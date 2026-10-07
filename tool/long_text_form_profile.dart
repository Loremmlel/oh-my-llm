import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:oh_my_llm/app/theme/app_theme.dart';
import 'package:oh_my_llm/core/widgets/long_text_editing_controller.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/fixed_prompt_sequence.dart';
import 'package:oh_my_llm/features/settings/presentation/widgets/prompts/forms/fixed_prompt_sequence_form_dialog.dart';

// 复用生产表单与主题，不启动 bootstrap，避免连接或改写用户数据库。
Future<void> main() async {
  if (!kProfileMode) throw StateError('必须以 profile 模式运行');
  WidgetsFlutterBinding.ensureInitialized();
  await (FontLoader(
    'Noto Sans SC',
  )..addFont(rootBundle.load('assets/fonts/NotoSansSC-VF.ttf'))).load();
  final source = await File(Platform.environment['LONG_TEXT_FIXTURE']!)
      .readAsString();
  runApp(
    MaterialApp(
      theme: AppTheme.lightTheme(),
      home: _Probe(source: source),
    ),
  );
}

class _Probe extends StatefulWidget {
  const _Probe({required this.source});
  final String source;
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  final _dialog = GlobalKey();
  final _frames = <FrameTiming>[];
  final _samples = <Map<String, Object>>[];
  final _errors = <String>[];

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_frames.addAll);
    FlutterError.onError = (details) => _errors.add(details.toString());
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  @override
  Widget build(BuildContext context) => const Scaffold();

  Future<void> _run() async {
    Size? size;
    try {
      unawaited(
        showDialog<void>(
          context: context,
          builder: (_) => FixedPromptSequenceFormDialog(
            key: _dialog,
            initialValue: FixedPromptSequence(
              id: 'profile',
              name: '长文本性能验证',
              steps: [
                FixedPromptSequenceStep(
                  id: 'step',
                  title: '正文',
                  content: widget.source,
                ),
              ],
              updatedAt: DateTime(2026, 10, 6),
            ),
            onSubmit: (_) async {},
          ),
        ),
      );
      await Future<void>.delayed(const Duration(seconds: 1));
      EditableTextState? editable;
      void findEditor(Element element, bool inContent) {
        inContent =
            inContent ||
            element.widget.key == const ValueKey('fixed-step-content-field');
        if (inContent &&
            element is StatefulElement &&
            element.state is EditableTextState) {
          editable = element.state as EditableTextState;
        }
        element.visitChildren((child) => findEditor(child, inContent));
      }

      findEditor(_dialog.currentContext! as Element, false);
      final state = editable!;
      final controller = state.widget.controller as LongTextEditingController;
      size = state.renderEditable.size;
      if (controller.text.contains('\r') ||
          controller.textForSave() != widget.source) {
        throw StateError('加载或原文保留契约失败');
      }
      for (final composing in [false, true]) {
        controller.loadText(widget.source);
        controller.selection = TextSelection.collapsed(
          offset: controller.text.length,
        );
        state.widget.focusNode.requestFocus();
        await Future<void>.delayed(const Duration(milliseconds: 300));
        state.bringIntoView(controller.selection.extent);
        await Future<void>.delayed(const Duration(milliseconds: 200));
        final startOffset = controller.text.length;
        for (var i = 0; i < 22; i++) {
          final expected = '${controller.text}a';
          final next = TextEditingValue(
            text: expected,
            selection: TextSelection.collapsed(offset: expected.length),
            composing: composing
                ? TextRange(start: startOffset, end: expected.length)
                : TextRange.empty,
          );
          final start = developer.Timeline.now;
          state.updateEditingValue(next);
          final returned = developer.Timeline.now;
          await WidgetsBinding.instance.endOfFrame;
          final end = developer.Timeline.now;
          if (controller.text != expected ||
              controller.selection.extentOffset != expected.length) {
            throw StateError('输入内容或光标校验失败');
          }
          if (i >= 2) {
            _samples.add({
              'composing': composing,
              'startUs': start,
              'endUs': end,
              'dispatchUs': returned - start,
              'throughFrameUs': end - start,
            });
          }
          await Future<void>.delayed(const Duration(milliseconds: 180));
        }
      }
    } catch (error, stack) {
      _errors.add('$error\n$stack');
    }
    await Future<void>.delayed(const Duration(seconds: 1));
    for (final sample in _samples) {
      sample['frames'] = _frames
          .where((frame) {
            final start = frame.timestampInMicroseconds(FramePhase.buildStart);
            return start >= (sample['startUs']! as int) &&
                start <= (sample['endUs']! as int);
          })
          .map(
            (frame) => {
              'buildUs': frame.buildDuration.inMicroseconds,
              'rasterUs': frame.rasterDuration.inMicroseconds,
            },
          )
          .toList();
    }
    await File(Platform.environment['LONG_TEXT_RESULT']!).writeAsString(
      jsonEncode({
        'sourceLength': widget.source.length,
        'crCount': '\r'.allMatches(widget.source).length,
        'fieldWidth': size?.width,
        'fieldHeight': size?.height,
        'input': '生产表单平台输入入口；不包含物理键盘或真实IME',
        'errors': _errors,
        'samples': _samples,
      }),
    );
    exit(_errors.isEmpty ? 0 : 1);
  }
}
