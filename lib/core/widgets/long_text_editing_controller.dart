import 'package:flutter/widgets.dart';

/// 编辑时使用 LF，避免 CRLF 在原生段落布局中产生额外开销。
String normalizeEditorLineEndings(String text) => text.contains('\r')
    ? text.replaceAll('\r\n', '\n').replaceAll('\r', '\n')
    : text;

/// 统一长文本的加载、粘贴和程序赋值入口，保留未改动正文的原始换行。
///
/// 活跃的输入法组合区由平台拥有，等提交后再转换，避免打断候选输入。
class LongTextEditingController extends TextEditingController {
  LongTextEditingController({String text = ''})
    : _original = text,
      _normalizedOriginal = normalizeEditorLineEndings(text),
      super(text: normalizeEditorLineEndings(text));

  String _original;
  String _normalizedOriginal;

  /// 切换文档或恢复草稿时建立新的原文基线；普通赋值仍视为编辑。
  void loadText(String text) {
    _original = text;
    _normalizedOriginal = normalizeEditorLineEndings(text);
    this.text = text;
  }

  /// 未改动或撤销回原文时保持原字符串；改动后的正文使用 LF。
  String textForSave({bool trim = false}) {
    final normalized = normalizeEditorLineEndings(text);
    final edited = trim ? normalized.trim() : normalized;
    final initial = trim ? _normalizedOriginal.trim() : _normalizedOriginal;
    return edited == initial ? _original : edited;
  }

  bool get hasTextChanges =>
      normalizeEditorLineEndings(text) != _normalizedOriginal;

  @override
  set value(TextEditingValue newValue) {
    if (!newValue.text.contains('\r') ||
        (newValue.isComposingRangeValid && !newValue.composing.isCollapsed)) {
      super.value = newValue;
      return;
    }

    // 只有 CRLF 删除了一个 UTF-16 单元；单独 CR 替换成 LF 不改变偏移。
    final removed = <int>[];
    for (var i = 0; i + 1 < newValue.text.length; i++) {
      if (newValue.text.codeUnitAt(i) == 13 &&
          newValue.text.codeUnitAt(i + 1) == 10) {
        removed.add(i);
      }
    }
    int mapOffset(int offset) {
      if (offset < 0) return offset;
      var count = 0;
      for (final index in removed) {
        if (index >= offset) break;
        count++;
      }
      return offset - count;
    }

    super.value = newValue.copyWith(
      text: normalizeEditorLineEndings(newValue.text),
      selection: newValue.selection.copyWith(
        baseOffset: mapOffset(newValue.selection.baseOffset),
        extentOffset: mapOffset(newValue.selection.extentOffset),
      ),
      composing: newValue.composing.isValid
          ? TextRange(
              start: mapOffset(newValue.composing.start),
              end: mapOffset(newValue.composing.end),
            )
          : TextRange.empty,
    );
  }
}
