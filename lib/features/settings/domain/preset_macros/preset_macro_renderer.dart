import 'package:equatable/equatable.dart';

import '../models/prompts/preset_prompt.dart';

class PresetMacroDiagnostic extends Equatable {
  const PresetMacroDiagnostic({
    required this.entryId,
    required this.title,
    required this.expression,
    required this.message,
    this.isError = false,
  });

  final String entryId;
  final String title;
  final String expression;
  final String message;
  final bool isError;

  @override
  List<Object> get props => [entryId, title, expression, message, isError];
}

class PresetRenderResult {
  PresetRenderResult(
    Iterable<PromptMessage> messages,
    Iterable<PresetMacroDiagnostic> diagnostics,
  ) : messages = List.unmodifiable(messages),
      diagnostics = List.unmodifiable(diagnostics);

  final List<PromptMessage> messages;
  final List<PresetMacroDiagnostic> diagnostics;
  bool get hasErrors => diagnostics.any((item) => item.isError);
}

/// 变量仅属于这一次求值，正文和开关始终以原始预设为准。
PresetRenderResult renderPresetPrompt(
  PresetPrompt? preset, {
  String lastUserMessage = '',
}) {
  if (preset == null) return PresetRenderResult(const [], const []);
  if (preset.syntax == PresetPromptSyntax.plain) {
    return PresetRenderResult(
      preset.messages.where((item) => item.enabled),
      const [],
    );
  }
  return _PresetRenderer(lastUserMessage).render(preset);
}

class _PresetRenderer {
  _PresetRenderer(this.lastUserMessage);

  // 高于当前写作样本的需要，同时限制递归和反复复制大变量的成本。
  static const maxDepth = 32;
  static const maxOperations = 50000;
  static const maxCharacters = 8 * 1024 * 1024;
  static final _trailingNewlines = RegExp(r'[\r\n]+$');
  final String lastUserMessage;
  final variables = <String, String>{};
  final diagnostics = <PresetMacroDiagnostic>{};
  late PromptMessage entry;
  int operations = 0;
  int characters = 0;

  PresetRenderResult render(PresetPrompt preset) {
    final messages = <PromptMessage>[];
    for (final item in preset.messages.where((item) => item.enabled)) {
      entry = item;
      try {
        _charge(item.content.length);
        final content = _expand(item.content, 0);
        messages.add(item.copyWith(content: content));
        if (content.trim().isEmpty && item.content.isNotEmpty) {
          _report('', '展开后为空，未生成消息');
        }
      } on FormatException catch (error) {
        _report('', error.message, isError: true);
        // 有错误时调用方不得发送已展开的部分结果。
        break;
      }
    }
    return PresetRenderResult(messages, diagnostics);
  }

  void _charge(int length) {
    characters += length;
    if (characters > maxCharacters) {
      throw const FormatException('预设展开超过 8 MiB 字符预算');
    }
  }

  void _report(String expression, String message, {bool isError = false}) {
    diagnostics.add(
      PresetMacroDiagnostic(
        entryId: entry.id,
        title: entry.title,
        expression: expression,
        message: message,
        isError: isError,
      ),
    );
  }

  String _expand(String source, int depth) {
    if (depth > maxDepth) throw const FormatException('宏嵌套超过 32 层');
    final chunks = <String>[];
    var cursor = 0;
    while (cursor < source.length) {
      final start = source.indexOf('{{', cursor);
      if (start < 0) {
        chunks.add(source.substring(cursor));
        break;
      }
      chunks.add(source.substring(cursor, start));
      final end = _closingIndex(source, start);
      if (++operations > maxOperations) {
        throw const FormatException('宏调用超过 50000 次');
      }
      final body = source.substring(start + 2, end);
      final expression = source.substring(start, end + 2);
      cursor = end + 2;
      if (body.trim().toLowerCase() == 'trim') {
        while (chunks.isNotEmpty) {
          final last = chunks.removeLast().replaceFirst(_trailingNewlines, '');
          if (last.isNotEmpty) {
            chunks.add(last);
            break;
          }
        }
        while (cursor < source.length &&
            (source[cursor] == '\r' || source[cursor] == '\n')) {
          cursor++;
        }
      } else {
        final value = _evaluate(body, expression, depth);
        _charge(value.length);
        chunks.add(value);
      }
    }
    return chunks.join();
  }

  int _closingIndex(String source, int start) {
    var nesting = 1;
    for (var index = start + 2; index < source.length - 1; index++) {
      if (source.startsWith('{{', index)) {
        nesting++;
        if (nesting > maxDepth) throw const FormatException('宏嵌套超过 32 层');
        index++;
      } else if (source.startsWith('}}', index)) {
        if (--nesting == 0) return index;
        index++;
      }
    }
    throw const FormatException('宏缺少配对的 }}');
  }

  String _evaluate(String body, String expression, int depth) {
    if (body.trimLeft().startsWith('//')) return '';
    final separator = body.indexOf('::');
    final name = (separator < 0 ? body : body.substring(0, separator))
        .trim()
        .toLowerCase();
    if (!const {
      'setvar',
      'getvar',
      'addvar',
      'user',
      'lastusermessage',
    }.contains(name)) {
      _report(expression, '不支持此宏，保留原文');
      return expression;
    }
    if (name == 'user' || name == 'lastusermessage') {
      if (separator >= 0) throw FormatException('$name 不接受参数');
      return name == 'user' ? 'user' : lastUserMessage;
    }
    if (separator < 0) throw FormatException('$name 缺少 :: 参数');
    final arguments = body.substring(separator + 2);
    final valueSeparator = _argumentSeparator(arguments);
    final writes = name != 'getvar';
    if (writes && valueSeparator < 0) throw FormatException('$name 缺少值参数');
    if (!writes && valueSeparator >= 0) throw FormatException('$name 只接受变量名');
    final keySource = writes
        ? arguments.substring(0, valueSeparator)
        : arguments;
    final key = _expand(keySource, depth + 1).trim();
    if (key.isEmpty) throw FormatException('$name 的变量名不能为空');
    if (!writes) {
      if (!variables.containsKey(key)) _report(expression, '变量 $key 未定义，展开为空');
      return variables[key] ?? '';
    }
    final value = _expand(arguments.substring(valueSeparator + 2), depth + 1);
    if (name == 'setvar') {
      variables[key] = value;
    } else {
      final old = variables[key] ?? '';
      if ((old.isEmpty || num.tryParse(old) != null) &&
          num.tryParse(value) != null) {
        _report(expression, '不支持数值 addvar，保留原文且不修改变量');
        return expression;
      }
      _charge(old.length + value.length);
      variables[key] = old + value;
    }
    return '';
  }

  int _argumentSeparator(String source) {
    for (var index = 0; index < source.length - 1; index++) {
      if (source.startsWith('{{', index)) {
        index = _closingIndex(source, index) + 1;
      } else if (source.startsWith('::', index)) {
        return index;
      }
    }
    return -1;
  }
}
