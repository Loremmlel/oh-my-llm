import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:re_editor/re_editor.dart';

int loadedFontBytes = 0;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final font = await rootBundle.load('assets/fonts/NotoSansSC-VF.ttf');
  loadedFontBytes = font.lengthInBytes;
  // 使用独立 family 明确加载成功，防止静默回退系统字体后误报实测条件。
  await (FontLoader('BenchmarkNoto')..addFont(Future.value(font))).load();
  runApp(const MaterialApp(home: Benchmark()));
}

// 在独立原生窗口里测试真实字体、软换行及布局，不以 widget test 的假字体计时。
class Benchmark extends StatefulWidget {
  const Benchmark({super.key});
  @override
  State<Benchmark> createState() => _BenchmarkState();
}

class _BenchmarkState extends State<Benchmark> {
  final _frames = <FrameTiming>[];
  final _results = <Map<String, Object?>>[];
  final _errors = <String>[];
  TextEditingController? _text;
  CodeLineEditingController? _code;
  final _focus = FocusNode();
  double _width = 720;
  int _generation = 0;
  String _label = '准备长文本编辑性能对照';

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_frames.addAll);
    FlutterError.onError = (details) {
      _errors.add(details.toString());
      FlutterError.presentError(details);
    };
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: SizedBox(
        width: _width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_label),
            const SizedBox(height: 12),
            SizedBox(
              height: 320,
              child: _code != null
                  ? CodeEditor(
                      key: ValueKey(_generation),
                      controller: _code,
                      focusNode: _focus,
                      wordWrap: true,
                      autocompleteSymbols: false,
                      // 禁止以截断长行换取虚假的性能优势。
                      maxLengthSingleLineRendering: 1000000,
                      chunkAnalyzer: const NonCodeChunkAnalyzer(),
                      padding: EdgeInsets.zero,
                      style: const CodeEditorStyle(
                        fontFamily: 'BenchmarkNoto',
                        fontSize: 16,
                        fontHeight: 1.5,
                      ),
                    )
                  : _text != null
                  ? TextField(
                      key: ValueKey(_generation),
                      controller: _text,
                      focusNode: _focus,
                      expands: true,
                      minLines: null,
                      maxLines: null,
                      style: const TextStyle(
                        fontFamily: 'BenchmarkNoto',
                        fontSize: 16,
                        height: 1.5,
                      ),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        isCollapsed: true,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    ),
  );

  String _fixture(int length, bool paragraphs) {
    const sentence =
        '这是用于验证长文本编辑性能的中文段落，包含标点与 English 123。请保留原始内容并检查光标附近的插入与删除。';
    final unit = paragraphs ? '${sentence * 3}\n' : sentence;
    return (unit * (length ~/ unit.length + 1)).substring(0, length);
  }

  Future<void> _mount(String editor, String source, double width) async {
    final previousText = _text;
    final previousCode = _code;
    setState(() {
      _width = width;
      _generation++;
      _text = editor == 'TextField'
          ? TextEditingController(text: source)
          : null;
      _code = editor == 're_editor'
          ? CodeLineEditingController.fromText(source)
          : null;
    });
    await WidgetsBinding.instance.endOfFrame;
    previousText?.dispose();
    previousCode?.dispose();
    _focus.requestFocus();
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }

  String get _current => _text?.text ?? _code!.text;

  void _select(String source, int start, int end) {
    if (_text != null) {
      _text!.selection = TextSelection(baseOffset: start, extentOffset: end);
    } else {
      final beforeStart = source.substring(0, start);
      final beforeEnd = source.substring(0, end);
      _code!.selection = CodeLineSelection(
        baseIndex: '\n'.allMatches(beforeStart).length,
        baseOffset: start - beforeStart.lastIndexOf('\n') - 1,
        extentIndex: '\n'.allMatches(beforeEnd).length,
        extentOffset: end - beforeEnd.lastIndexOf('\n') - 1,
      );
      _code!.makeCursorVisible();
    }
  }

  void _replace(String value) {
    if (_text != null) {
      final old = _text!.value;
      _text!.value = TextEditingValue(
        text: old.text.replaceRange(
          old.selection.start,
          old.selection.end,
          value,
        ),
        selection: TextSelection.collapsed(
          offset: old.selection.start + value.length,
        ),
      );
    } else {
      _code!.replaceSelection(value);
      _code!.makeCursorVisible();
    }
  }

  Future<void> _case(
    String editor,
    String source,
    String shape,
    String operation,
    double width,
    int round,
  ) async {
    _label =
        '$editor / ${source.length} / $shape / $operation / $width / $round';
    await _mount(editor, source, width);
    final offset = operation == 'tail' ? source.length : source.length ~/ 2;
    final payload = operation == 'bulk' ? _fixture(4096, true) : '测';
    final windows = <Map<String, Object>>[];
    for (var i = 0; i < 26; i++) {
      final insert = i.isEven;
      final current = _current;
      _select(current, offset, insert ? offset : offset + payload.length);
      await WidgetsBinding.instance.endOfFrame;
      // 选择映射和准备工作在计时窗口外；正文替换及其下一帧单独计时。
      final start = developer.Timeline.now;
      final update = Stopwatch()..start();
      _replace(insert ? payload : '');
      update.stop();
      final updated = developer.Timeline.now;
      await WidgetsBinding.instance.endOfFrame;
      final end = developer.Timeline.now;
      final expected = insert
          ? source.replaceRange(offset, offset, payload)
          : source;
      if (_current != expected) {
        throw StateError('正文不一致：$_label / $i');
      }
      if (i >= 6) {
        windows.add({
          'action': insert ? 'insert' : 'delete',
          'startUs': start,
          'endUs': end,
          'updateUs': update.elapsedMicroseconds,
          'throughFrameUs': end - start,
          'updatedUs': updated,
        });
      }
    }
    // FrameTiming 批量回传；按 buildStart 时间归属样本，不将延迟回调归到下一场景。
    await Future<void>.delayed(const Duration(milliseconds: 250));
    for (final sample in windows) {
      final selected = _frames.where((frame) {
        final start = frame.timestampInMicroseconds(FramePhase.buildStart);
        return start >= (sample['startUs']! as int) &&
            start <= (sample['endUs']! as int);
      }).toList();
      sample['frames'] = selected
          .map(
            (frame) => {
              'buildUs': frame.buildDuration.inMicroseconds,
              'rasterUs': frame.rasterDuration.inMicroseconds,
              'totalUs': frame.totalSpan.inMicroseconds,
            },
          )
          .toList();
    }
    _results.add({
      'editor': editor,
      'lengthUtf16': source.length,
      'shape': shape,
      'operation': operation,
      'width': width,
      'round': round,
      'sourceChecksum': _checksum(source),
      'finalChecksum': _checksum(_current),
      'rssBytes': ProcessInfo.currentRss,
      'samples': windows,
    });
    _frames.clear();
    await _save(false);
    stdout.writeln('DONE $_label');
  }

  int _checksum(String text) {
    var hash = 2166136261;
    for (final code in text.codeUnits) {
      hash = ((hash ^ code) * 16777619) & 0xffffffff;
    }
    return hash;
  }

  Future<void> _run() async {
    try {
      if (!kProfileMode) throw StateError('必须使用 profile 构建');
      for (var round = 0; round < 2; round++) {
        for (final width in [720.0, 360.0]) {
          for (final length in [5000, 10000, 50000]) {
            for (final paragraphs in [true, false]) {
              final source = _fixture(length, paragraphs);
              for (final operation in ['middle', 'tail', 'bulk']) {
                final editors = round.isEven
                    ? ['TextField', 're_editor']
                    : ['re_editor', 'TextField'];
                for (final editor in editors) {
                  await _case(
                    editor,
                    source,
                    paragraphs ? 'paragraphs' : 'single',
                    operation,
                    width,
                    round,
                  );
                }
              }
            }
          }
        }
      }
      await _save(true);
      exit(_errors.isEmpty ? 0 : 1);
    } catch (error, stack) {
      _errors.add('$error\n$stack');
      await _save(false);
      stderr.writeln(error);
      exit(1);
    }
  }

  Future<void> _save(bool complete) async {
    final output = Platform.environment['LONG_TEXT_RESULT']!;
    await File(output).writeAsString(
      jsonEncode({
        'complete': complete,
        'mode': 'profile',
        'platform': Platform.operatingSystemVersion,
        'dart': Platform.version,
        'font': 'Noto Sans SC, 16px, height 1.5',
        'loadedFontBytes': loadedFontBytes,
        'viewportHeight': 320,
        'wordWrap': true,
        'reEditorVersion': '0.10.0',
        'reEditorMaxLengthSingleLineRendering': 1000000,
        'inputPath': 'controller replacement, not physical IME',
        'errors': _errors,
        'results': _results,
      }),
    );
  }
}
