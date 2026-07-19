import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_checkpoint.dart';

void main() {
  final now = DateTime(2026, 7, 1, 12, 0);

  ChatCheckpoint _checkpoint({
    String id = 'cp-1',
    String title = '阶段总结',
    String content = '本次对话讨论了架构设计。',
    DateTime? createdAt,
    String? parentCheckpointId,
    String? coveredUntilMessageId,
    String sourceMemoryPromptName = '研发总结',
  }) {
    return ChatCheckpoint(
      id: id,
      title: title,
      content: content,
      createdAt: createdAt ?? now,
      parentCheckpointId: parentCheckpointId,
      coveredUntilMessageId: coveredUntilMessageId,
      sourceMemoryPromptName: sourceMemoryPromptName,
    );
  }

  group('ChatCheckpoint', () {
    test('toJson → fromJson round-trip 保留全部字段', () {
      final original = _checkpoint(
        parentCheckpointId: 'cp-0',
        coveredUntilMessageId: 'msg-10',
        sourceMemoryPromptName: '研发总结',
      );
      final restored = ChatCheckpoint.fromJson(original.toJson());

      expect(restored.id, original.id);
      expect(restored.title, original.title);
      expect(restored.content, original.content);
      expect(restored.createdAt, original.createdAt);
      expect(restored.parentCheckpointId, original.parentCheckpointId);
      expect(restored.coveredUntilMessageId, original.coveredUntilMessageId);
      expect(restored.sourceMemoryPromptName, original.sourceMemoryPromptName);
    });

    test('fromJson 缺失可选字段时使用默认值', () {
      final json = {
        'id': 'cp-2',
        'title': '检查点',
        'content': '内容',
        'createdAt': now.toIso8601String(),
      };
      final result = ChatCheckpoint.fromJson(json);

      expect(result.parentCheckpointId, isNull);
      expect(result.coveredUntilMessageId, isNull);
      expect(result.sourceMemoryPromptName, '');
    });

    test('copyWith 部分覆盖', () {
      final original = _checkpoint();
      final updated = original.copyWith(title: '新标题', content: '新内容');

      expect(updated.title, '新标题');
      expect(updated.content, '新内容');
      expect(updated.id, original.id);
      expect(updated.createdAt, original.createdAt);
      expect(updated.parentCheckpointId, original.parentCheckpointId);
    });

    test('summary 正常文本截断', () {
      final longContent = 'A' * 50;
      final checkpoint = _checkpoint(content: longContent);
      expect(checkpoint.summary.length, lessThanOrEqualTo(45));
      expect(checkpoint.summary, contains('...'));
    });

    test('summary 短文本不截断', () {
      final checkpoint = _checkpoint(content: '短文本');
      expect(checkpoint.summary, '短文本');
    });

    test('summary 空内容返回占位文本', () {
      for (final empty in ['', '   ', '  \n  ']) {
        final checkpoint = _checkpoint(content: empty);
        expect(checkpoint.summary, '该检查点为空。');
      }
    });

    test('Equatable 相等性', () {
      final a = _checkpoint(id: 'cp-x', title: '相同');
      final b = _checkpoint(id: 'cp-x', title: '相同');
      final c = _checkpoint(id: 'cp-x', title: '不同');

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('toString 返回可解析的 JSON', () {
      final checkpoint = _checkpoint();
      final parsed = jsonDecode(checkpoint.toString()) as Map<String, dynamic>;

      expect(parsed['id'], checkpoint.id);
      expect(parsed['title'], checkpoint.title);
      expect(parsed, equals(checkpoint.toJson()));
    });
  });
}
