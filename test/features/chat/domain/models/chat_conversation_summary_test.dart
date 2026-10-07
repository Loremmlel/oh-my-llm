import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation_summary.dart';

ChatConversationSummary _summary({
  String? title,
  String first = '',
  String latest = '',
}) => ChatConversationSummary(
  id: 'conversation',
  title: title,
  firstUserMessagePreview: first,
  latestUserMessagePreview: latest,
  updatedAt: DateTime(2026, 6, 1),
);

void main() {
  test('手动标题只接受非空白内容', () {
    for (final (title, expected) in <(String?, bool)>[
      (null, false),
      ('   ', false),
      ('', false),
      ('\t\n', false),
      ('研发对话', true),
      (' a ', true),
    ]) {
      expect(_summary(title: title).hasCustomTitle, expected, reason: '$title');
    }
  });

  test('会话标题优先手动标题，否则首条消息按十五个字素截断或回退未命名', () {
    for (final (summary, expected) in [
      (_summary(title: '  研发对话  '), '研发对话'),
      (_summary(title: '   ', first: '这是首条消息'), '这是首条消息'),
      (_summary(first: '预览文本'), '预览文本'),
      (_summary(), '未命名对话'),
      (_summary(title: '  ', first: '  '), '未命名对话'),
      (_summary(first: '这是一段超过十五个字符的预览文本内容'), '这是一段超过十五个字符的预览文'),
      (_summary(first: '😀' * 16), '😀' * 15),
    ]) {
      expect(summary.resolvedTitle, expected, reason: '$summary');
    }
  });

  test('预览优先最新用户消息并清理换行，再回退首条消息和标题', () {
    for (final (summary, expected) in [
      (_summary(first: '首条', latest: '最新消息'), '最新消息'),
      (_summary(latest: '第一行\n第二行'), '第一行 第二行'),
      (_summary(first: '首条消息', latest: '   '), '首条消息'),
      (_summary(title: '手动标题'), '手动标题'),
      (_summary(), '未命名对话'),
    ]) {
      expect(summary.previewText, expected, reason: '$summary');
    }
  });
}
