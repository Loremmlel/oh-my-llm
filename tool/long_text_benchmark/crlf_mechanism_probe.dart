import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// 直接测 Paragraph.layout，剥离 TextField、IME、业务监听与绘制。
Future<void> main() async {
  if (!kProfileMode) throw StateError('必须使用 profile 构建');
  WidgetsFlutterBinding.ensureInitialized();
  final directory = Platform.environment['CONTROL_FONT_DIR']!;
  for (final name in ['original', 'cr', 'lf', 'both']) {
    final bytes = await File('$directory/$name.ttf').readAsBytes();
    await (FontLoader(
      'Probe-$name',
    )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
  }
  runApp(const MaterialApp(home: Scaffold()));
  await WidgetsBinding.instance.endOfFrame;
  final actual = await File(Platform.environment['INPUT_PROBE_FIXTURE']!)
      .readAsString();
  const line = '这是用于定位换行开销的中文文本，包含 English 和数字123。';
  final cases = <({String name, String font, String text})>[];
  for (final ending in {
    'LF': '\n',
    'CRLF': '\r\n',
    'CR': '\r',
    'LFCR': '\n\r',
    'CR-space-LF': '\r \n',
    'space-LF': ' \n',
    'double-LF': '\n\n',
  }.entries) {
    cases.add((
      name: ending.key,
      font: 'original',
      text: '$line${ending.value}' * 427,
    ));
  }
  for (final count in [1, 10, 50, 100, 200]) {
    cases.add((
      name: 'CRLF-count-$count',
      font: 'original',
      text: List.generate(
        427,
        (i) => '$line${i < count ? '\r\n' : '\n'}',
      ).join(),
    ));
  }
  for (final font in ['original', 'cr', 'lf', 'both']) {
    cases.add((name: 'actual-CRLF', font: font, text: actual));
    cases.add((
      name: 'actual-LF',
      font: font,
      text: actual.replaceAll('\r\n', '\n'),
    ));
  }
  final results = <Map<String, Object?>>[];
  for (var round = 0; round < 2; round++) {
    for (final entry in round == 0 ? cases : cases.reversed) {
      for (var i = 0; i < 7; i++) {
        final text = '${entry.text} $round/$i/${entry.name}';
        final builder = ui.ParagraphBuilder(
          ui.ParagraphStyle(
            textDirection: ui.TextDirection.ltr,
            fontFamily: 'Probe-${entry.font}',
            fontSize: 16,
          ),
        )..addText(text);
        final paragraph = builder.build();
        final timer = Stopwatch()..start();
        paragraph.layout(const ui.ParagraphConstraints(width: 680));
        timer.stop();
        if (i >= 2) {
          results.add({
            'case': entry.name,
            'font': entry.font,
            'round': round,
            'length': text.length,
            'crCount': '\r'.allMatches(text).length,
            'layoutUs': timer.elapsedMicroseconds,
            'lineCount': paragraph.computeLineMetrics().length,
            'height': paragraph.height,
          });
        }
        paragraph.dispose();
      }
    }
  }
  await File(Platform.environment['LONG_TEXT_RESULT']!)
      .writeAsString(jsonEncode({'complete': true, 'samples': results}));
  exit(0);
}
