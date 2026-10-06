import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await (FontLoader(
    'ProbeNoto',
  )..addFont(rootBundle.load('assets/fonts/NotoSansSC-VF.ttf'))).load();
  runApp(const MaterialApp(home: InputProbe()));
}

class InputProbe extends StatefulWidget {
  const InputProbe({super.key});
  @override
  State<InputProbe> createState() => _InputProbeState();
}

class _InputProbeState extends State<InputProbe> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  final _field = GlobalKey();
  final _frames = <FrameTiming>[];
  final _results = <Map<String, Object?>>[];
  int _changedAt = 0;
  String _label = '输入链路定位';
  static const _native = MethodChannel('probe/input');

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_frames.addAll);
    _controller.addListener(() => _changedAt = developer.Timeline.now);
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: SizedBox(
        width: 680,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_label),
            SizedBox(
              height: 270,
              child: TextField(
                key: _field,
                controller: _controller,
                focusNode: _focus,
                expands: true,
                minLines: null,
                maxLines: null,
                style: const TextStyle(fontFamily: 'ProbeNoto', fontSize: 16),
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  EditableTextState get _editable {
    EditableTextState? result;
    void visit(Element element) {
      if (element is StatefulElement && element.state is EditableTextState) {
        result = element.state as EditableTextState;
      } else {
        element.visitChildren(visit);
      }
    }

    (_field.currentContext! as Element).visitChildren(visit);
    return result!;
  }

  Future<void> _run() async {
    final errors = <String>[];
    WebSocket? profiler;
    Stream<dynamic>? replies;
    var requestId = 0;
    final isolateId = developer.Service.getIsolateId(Isolate.current)!;
    Future<dynamic> rpc(String method, Map<String, Object> params) async {
      final id = ++requestId;
      final response = replies!
          .map((message) => jsonDecode(message as String))
          .firstWhere((message) => message['id'] == id);
      profiler!.add(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': id,
          'method': method,
          'params': params,
        }),
      );
      return response;
    }

    try {
      if (Platform.environment['INPUT_PROBE_CPU'] == '1') {
        final service = await developer.Service.controlWebServer(enable: true);
        final uri = service.serverUri!;
        profiler = await WebSocket.connect(
          uri.replace(scheme: 'ws', path: '${uri.path}ws').toString(),
        );
        replies = profiler.asBroadcastStream();
        final enabled = await rpc('setFlag', {
          'name': 'profiler',
          'value': 'true',
        });
        if ((enabled as Map).containsKey('error')) {
          throw StateError('无法启用 CPU 采样：$enabled');
        }
        await rpc('clearCpuSamples', {'isolateId': isolateId});
      }
      final fixturePath = Platform.environment['INPUT_PROBE_FIXTURE'];
      final actual = fixturePath == null
          ? null
          : await File(fixturePath).readAsString();
      for (final length
          in actual == null ? [100, 10000, 50000] : [actual.length]) {
        for (final path in [
          'controller',
          'framework-ascii',
          'framework-composing',
          'native-char',
        ]) {
          const unit = '这是用于排查中文长文本输入延迟的段落，包含 English 和数字123。\n';
          final source =
              actual ??
              (unit * (length ~/ unit.length + 1)).substring(0, length);
          setState(() => _label = '$path / $length');
          _controller.value = TextEditingValue(
            text: '$source\n',
            selection: TextSelection.collapsed(offset: length + 1),
          );
          _focus.requestFocus();
          await Future<void>.delayed(const Duration(milliseconds: 400));
          _editable.bringIntoView(_controller.selection.extent);
          await Future<void>.delayed(const Duration(milliseconds: 200));
          for (var i = 0; i < 12; i++) {
            final old = _controller.value;
            final updated = TextEditingValue(
              text: '${old.text}a',
              selection: TextSelection.collapsed(offset: old.text.length + 1),
              composing: path == 'framework-composing'
                  ? TextRange(start: length + 1, end: old.text.length + 1)
                  : TextRange.empty,
            );
            final start = developer.Timeline.now;
            int? nativeUs;
            if (path == 'native-char') {
              nativeUs = await _native.invokeMethod<int>('char', 97);
            } else if (path == 'controller') {
              _controller.value = updated;
            } else {
              _editable.updateEditingValue(updated);
            }
            final returned = developer.Timeline.now;
            await WidgetsBinding.instance.endOfFrame;
            final end = developer.Timeline.now;
            if (_controller.text != updated.text) {
              throw StateError('输入未到达：$path');
            }
            await Future<void>.delayed(const Duration(milliseconds: 180));
            if (i >= 2) {
              _results.add({
                'length': length,
                'path': path,
                'index': i,
                'dispatchUs': returned - start,
                'listenerUs': _changedAt - start,
                'throughFrameUs': end - start,
                'nativeHandlerUs': nativeUs,
                'startUs': start,
                'endUs': end,
              });
            }
          }
          stdout.writeln('DONE $path $length');
        }
      }
    } catch (error, stack) {
      errors.add('$error\n$stack');
    }
    await Future<void>.delayed(const Duration(seconds: 1));
    if (profiler != null) {
      final cpu = await rpc('getCpuSamples', {
        'isolateId': isolateId,
        'timeOriginMicros': 0,
        'timeExtentMicros': developer.Timeline.now,
      });
      await File('${Platform.environment['LONG_TEXT_RESULT']}.cpu.json')
          .writeAsString(jsonEncode(cpu));
      await profiler.close();
    }
    for (final result in _results) {
      final start = result['startUs']! as int;
      final end = result['endUs']! as int;
      result['frames'] = _frames
          .where((f) {
            final time = f.timestampInMicroseconds(FramePhase.buildStart);
            return time >= start && time <= end;
          })
          .map(
            (f) => {
              'buildUs': f.buildDuration.inMicroseconds,
              'rasterUs': f.rasterDuration.inMicroseconds,
            },
          )
          .toList();
    }
    await File(Platform.environment['LONG_TEXT_RESULT']!).writeAsString(
      jsonEncode({
        'errors': errors,
        'results': _results,
        'note': 'framework 调用平台入口；native-char 为 WM_CHAR，不包含真实 IME。',
      }),
    );
    exit(errors.isEmpty ? 0 : 1);
  }
}
