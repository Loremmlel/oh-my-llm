import 'package:characters/characters.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/chat/domain/models/chat_conversation_summary.dart';

void main() {
  // ── 辅助工厂 ─────────────────────────────────────────────────

  ChatConversationSummary summary({
    String id = 'c1',
    String? title,
    String firstUserMessagePreview = '',
    String latestUserMessagePreview = '',
    DateTime? updatedAt,
  }) {
    return ChatConversationSummary(
      id: id,
      title: title,
      updatedAt: updatedAt ?? DateTime(2026, 6, 1),
      firstUserMessagePreview: firstUserMessagePreview,
      latestUserMessagePreview: latestUserMessagePreview,
    );
  }

  // ── hasCustomTitle ───────────────────────────────────────────

  group('hasCustomTitle', () {
    test('null 标题返回 false', () {
      expect(summary(title: null).hasCustomTitle, isFalse);
    });

    test('纯空白标题返回 false', () {
      expect(summary(title: '   ').hasCustomTitle, isFalse);
      expect(summary(title: '').hasCustomTitle, isFalse);
      expect(summary(title: '\t\n').hasCustomTitle, isFalse);
    });

    test('非空标题返回 true', () {
      expect(summary(title: '研发对话').hasCustomTitle, isTrue);
      expect(summary(title: ' a ').hasCustomTitle, isTrue);
    });
  });

  // ── resolvedTitle ─────────────────────────────────────────────

  group('resolvedTitle', () {
    test('有手动标题 → 返回 trim 后的标题', () {
      expect(summary(title: '  研发对话  ').resolvedTitle, '研发对话');
    });

    test('纯空白标题回退 firstUserMessagePreview', () {
      expect(
        summary(title: '   ', firstUserMessagePreview: '这是首条消息').resolvedTitle,
        '这是首条消息',
      );
    });

    test('null 标题 + 有 preview → 返回 preview', () {
      expect(
        summary(title: null, firstUserMessagePreview: '预览文本').resolvedTitle,
        '预览文本',
      );
    });

    test('无标题无 preview → 未命名对话', () {
      expect(summary(title: null, firstUserMessagePreview: '').resolvedTitle, '未命名对话');
      expect(summary(title: '  ', firstUserMessagePreview: '  ').resolvedTitle, '未命名对话');
    });

    test('超长 preview 按字符截断到 15 个', () {
      final longPreview = '这是一段超过十五个字符的预览文本内容';
      final result = summary(
        title: null,
        firstUserMessagePreview: longPreview,
      ).resolvedTitle;
      expect(result.characters.length, 15);
      expect(result, '这是一段超过十五个字符的预览文');
    });

    test('emoji 占多 code unit 时按字符而非 code unit 截断', () {
      // emoji 在 UTF-16 中占 2 个 code unit，characters 按字素簇截断
      final preview = '😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀'; // 16 个 emoji
      final result = summary(
        title: null,
        firstUserMessagePreview: preview,
      ).resolvedTitle;
      expect(result.characters.length, lessThanOrEqualTo(15));
    });
  });

  // ── previewText ───────────────────────────────────────────────

  group('previewText', () {
    test('优先 latestUserMessagePreview', () {
      expect(
        summary(
          firstUserMessagePreview: '首条',
          latestUserMessagePreview: '最新消息',
        ).previewText,
        '最新消息',
      );
    });

    test('latest 中的换行替换为空格', () {
      expect(
        summary(latestUserMessagePreview: '第一行\n第二行').previewText,
        '第一行 第二行',
      );
    });

    test('latest 为空白时回退 firstUserMessagePreview', () {
      expect(
        summary(
          firstUserMessagePreview: '首条消息',
          latestUserMessagePreview: '   ',
        ).previewText,
        '首条消息',
      );
    });

    test('latest 与 first 均空白时回退 resolvedTitle', () {
      expect(
        summary(
          title: '手动标题',
          firstUserMessagePreview: '',
          latestUserMessagePreview: '',
        ).previewText,
        '手动标题',
      );
    });

    test('无任何内容时回退未命名对话', () {
      expect(
        summary(
          title: null,
          firstUserMessagePreview: '',
          latestUserMessagePreview: '',
        ).previewText,
        '未命名对话',
      );
    });
  });

  // ── copyWith ─────────────────────────────────────────────────

  group('copyWith', () {
    test('单字段更新保留其他字段', () {
      final original = summary(
        title: '原标题',
        firstUserMessagePreview: '首条',
        latestUserMessagePreview: '最新',
      );
      final updated = original.copyWith(title: '新标题');

      expect(updated.title, '新标题');
      expect(updated.firstUserMessagePreview, '首条');
      expect(updated.latestUserMessagePreview, '最新');
      expect(updated.id, original.id);
      expect(updated.updatedAt, original.updatedAt);
    });

    test('Equatable 相等性', () {
      final a = summary(title: '测试', firstUserMessagePreview: '预览');
      final b = summary(title: '测试', firstUserMessagePreview: '预览');
      expect(a, equals(b));
    });
  });
}
