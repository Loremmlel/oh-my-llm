import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/chat/application/checkpoint_request_context.dart';
import 'package:oh_my_llm/features/chat/application/chat_request_message_builder.dart';
import 'package:oh_my_llm/features/chat/application/request_message_filter.dart';
import 'package:oh_my_llm/features/chat/data/chat_completion_client.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_checkpoint.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';
import 'package:oh_my_llm/features/settings/domain/models/memory_prompt.dart';
import 'package:oh_my_llm/features/settings/domain/models/preset_prompt.dart';

void main() {
  // ── 辅助工厂 ───────────────────────────────────────────────────────────────

  ChatCheckpoint buildCheckpoint({
    String id = 'cp-1',
    String title = '检查点',
    String content = '检查点内容',
    String? parentCheckpointId,
    String? coveredUntilMessageId,
  }) => ChatCheckpoint(
    id: id,
    title: title,
    content: content,
    createdAt: DateTime(2026),
    parentCheckpointId: parentCheckpointId,
    coveredUntilMessageId: coveredUntilMessageId,
  );

  ChatMessage buildMessage({
    String id = 'msg-1',
    ChatMessageRole role = ChatMessageRole.user,
    String content = '消息内容',
  }) => ChatMessage(
    id: id,
    role: role,
    content: content,
    createdAt: DateTime(2026),
  );

  MemoryPrompt buildMemoryPrompt({
    String id = 'mp-1',
    String content = '请总结以下对话的要点',
  }) => MemoryPrompt(
    id: id,
    name: '默认记忆提示词',
    content: content,
    updatedAt: DateTime(2026),
  );

  PresetPrompt buildPresetPrompt({
    List<PromptMessage> messages = const [],
  }) => PresetPrompt(
    id: 'tpl-1',
    name: '测试模板',
    messages: messages,
    updatedAt: DateTime(2026),
  );

  PromptMessage buildPromptMessage({
    required PromptMessageRole role,
    required String content,
    PromptMessagePlacement placement = PromptMessagePlacement.before,
  }) => PromptMessage(
    id: 'pm-1',
    role: role,
    content: content,
    placement: placement,
  );

  // ── resolveCheckpointRequestContext ─────────────────────────────────────────

  group('resolveCheckpointRequestContext', () {
    test('selectedCheckpointId 为 null 时返回所有消息作为 tail，chain 为空', () {
      final messages = [
        buildMessage(id: 'm1', content: '第一条消息'),
        buildMessage(id: 'm2', content: '第二条消息'),
      ];

      final result = resolveCheckpointRequestContext(
        checkpoints: [buildCheckpoint(id: 'cp-1')],
        selectedCheckpointId: null,
        conversationMessages: messages,
      );

      expect(result.checkpointChain, isEmpty);
      expect(result.tailMessages, messages);
    });

    test('selectedCheckpointId 在 checkpoints 中不存在时返回空 chain 和所有消息', () {
      final messages = [
        buildMessage(id: 'm1', content: '消息'),
      ];

      final result = resolveCheckpointRequestContext(
        checkpoints: [buildCheckpoint(id: 'cp-1')],
        selectedCheckpointId: 'cp-nonexistent',
        conversationMessages: messages,
      );

      expect(result.checkpointChain, isEmpty);
      expect(result.tailMessages, messages);
    });

    test('有效 checkpoint + coveredUntilMessageId → chain + 覆盖点之后的消息', () {
      final messages = [
        buildMessage(id: 'm1', content: '第一条'),
        buildMessage(id: 'm2', content: '第二条'),
        buildMessage(id: 'm3', content: '第三条'),
      ];
      final checkpoint = buildCheckpoint(
        id: 'cp-1',
        coveredUntilMessageId: 'm1',
      );

      final result = resolveCheckpointRequestContext(
        checkpoints: [checkpoint],
        selectedCheckpointId: 'cp-1',
        conversationMessages: messages,
      );

      expect(result.checkpointChain, [checkpoint]);
      expect(result.tailMessages, hasLength(2));
      expect(result.tailMessages[0].id, 'm2');
      expect(result.tailMessages[1].id, 'm3');
    });

    test('有效 checkpoint 无 coveredUntilMessageId → chain + 所有消息', () {
      final messages = [
        buildMessage(id: 'm1', content: '消息'),
      ];
      final checkpoint = buildCheckpoint(id: 'cp-1');

      final result = resolveCheckpointRequestContext(
        checkpoints: [checkpoint],
        selectedCheckpointId: 'cp-1',
        conversationMessages: messages,
      );

      expect(result.checkpointChain, [checkpoint]);
      expect(result.tailMessages, messages);
    });

    test('coveredUntilMessageId 在 conversationMessages 中找不到 → chain + 所有消息', () {
      final messages = [
        buildMessage(id: 'm1', content: '消息'),
      ];
      final checkpoint = buildCheckpoint(
        id: 'cp-1',
        coveredUntilMessageId: 'm-not-found',
      );

      final result = resolveCheckpointRequestContext(
        checkpoints: [checkpoint],
        selectedCheckpointId: 'cp-1',
        conversationMessages: messages,
      );

      // 注意：coveredId 找不到时 chain 不返回
      expect(result.checkpointChain, isEmpty);
      expect(result.tailMessages, messages);
    });

    test('多级链：grandparent → parent → selected，tail 基于最深检查点的 coveredUntilMessageId', () {
      final messages = [
        buildMessage(id: 'm1', content: '第 1 条'),
        buildMessage(id: 'm2', content: '第 2 条'),
        buildMessage(id: 'm3', content: '第 3 条'),
        buildMessage(id: 'm4', content: '第 4 条'),
      ];
      final grandparent = buildCheckpoint(
        id: 'cp-grand',
        title: '祖检查点',
        coveredUntilMessageId: 'm1',
      );
      final parent = buildCheckpoint(
        id: 'cp-parent',
        title: '父检查点',
        parentCheckpointId: 'cp-grand',
        coveredUntilMessageId: 'm2',
      );
      final selected = buildCheckpoint(
        id: 'cp-selected',
        title: '选中检查点',
        parentCheckpointId: 'cp-parent',
        coveredUntilMessageId: 'm3',
      );

      final result = resolveCheckpointRequestContext(
        checkpoints: [grandparent, parent, selected],
        selectedCheckpointId: 'cp-selected',
        conversationMessages: messages,
      );

      // chain 应为祖先顺序
      expect(result.checkpointChain, [grandparent, parent, selected]);
      // tail 是 m3 之后的消息
      expect(result.tailMessages, hasLength(1));
      expect(result.tailMessages.single.id, 'm4');
    });
  });

  // ── resolveCheckpointChain ─────────────────────────────────────────────────

  group('resolveCheckpointChain', () {
    test('selectedCheckpointId 为 null 时返回空列表', () {
      final result = resolveCheckpointChain(
        checkpoints: [buildCheckpoint(id: 'cp-1')],
        selectedCheckpointId: null,
      );

      expect(result, isEmpty);
    });

    test('单个检查点（无父节点）→ 单元素链', () {
      final checkpoint = buildCheckpoint(id: 'cp-1', title: '唯一检查点');

      final result = resolveCheckpointChain(
        checkpoints: [checkpoint],
        selectedCheckpointId: 'cp-1',
      );

      expect(result, [checkpoint]);
    });

    test('3 个检查点链 → 返回祖先顺序（反转后从最旧到最新）', () {
      final cp1 = buildCheckpoint(id: 'cp-1', title: '第一');
      final cp2 = buildCheckpoint(
        id: 'cp-2',
        title: '第二',
        parentCheckpointId: 'cp-1',
      );
      final cp3 = buildCheckpoint(
        id: 'cp-3',
        title: '第三',
        parentCheckpointId: 'cp-2',
      );

      final result = resolveCheckpointChain(
        checkpoints: [cp1, cp2, cp3],
        selectedCheckpointId: 'cp-3',
      );

      expect(result, [cp1, cp2, cp3]);
    });

    test('循环引用保护：检查点引用自身 → break 并返回已遍历部分', () {
      final selfRef = buildCheckpoint(
        id: 'cp-self',
        title: '自引用',
        parentCheckpointId: 'cp-self',
      );

      final result = resolveCheckpointChain(
        checkpoints: [selfRef],
        selectedCheckpointId: 'cp-self',
      );

      // visitedIds 检测到重复后 break，返回反转后的单元素
      expect(result, [selfRef]);
    });

    test('孤儿父节点指针：父节点不在 checkpoints 中 → break 并返回已遍历部分', () {
      final cp1 = buildCheckpoint(id: 'cp-1', title: '第一');
      final cp2 = buildCheckpoint(
        id: 'cp-2',
        title: '第二',
        parentCheckpointId: 'cp-orphan-parent',
      );

      final result = resolveCheckpointChain(
        checkpoints: [cp1, cp2],
        selectedCheckpointId: 'cp-2',
      );

      // cp2 添加到 chain，然后 parent 查找失败 break，反转后只有 cp2
      expect(result, [cp2]);
    });
  });

  // ── buildCheckpointSummaryMessages ─────────────────────────────────────────

  group('buildCheckpointSummaryMessages', () {
    test('空 chain（根检查点）使用根检查点中文 system prompt', () {
      final memoryPrompt = buildMemoryPrompt();
      final conversationMessages = [
        buildMessage(id: 'm1', content: '对话消息'),
      ];

      final result = buildCheckpointSummaryMessages(
        memoryPrompt: memoryPrompt,
        conversationMessages: conversationMessages,
        checkpointChain: const [],
      );

      expect(result, isNotEmpty);
      // 第一条是 system 消息，包含根检查点提示
      expect(result.first.role, ChatMessageRole.system);
      expect(
        result.first.content,
        contains('你正在为当前对话创建根检查点'),
      );
    });

    test('非空 chain（后续检查点）使用链式检查点中文 system prompt', () {
      final memoryPrompt = buildMemoryPrompt();
      final chain = [
        buildCheckpoint(id: 'cp-1', title: '已有检查点', content: '已有内容'),
      ];
      final conversationMessages = [
        buildMessage(id: 'm1', content: '新对话消息'),
      ];

      final result = buildCheckpointSummaryMessages(
        memoryPrompt: memoryPrompt,
        conversationMessages: conversationMessages,
        checkpointChain: chain,
      );

      expect(result, isNotEmpty);
      expect(result.first.role, ChatMessageRole.system);
      expect(
        result.first.content,
        contains('你正在为当前对话创建新的链式检查点'),
      );
      // 不包含"根检查点"
      expect(
        result.first.content,
        isNot(contains('根检查点')),
      );
    });

    test('非空 chain 的消息中包含检查点记忆内容', () {
      final memoryPrompt = buildMemoryPrompt();
      final chain = [
        buildCheckpoint(id: 'cp-1', title: '检查点A', content: '内容A'),
        buildCheckpoint(
          id: 'cp-2',
          title: '检查点B',
          content: '内容B',
          parentCheckpointId: 'cp-1',
        ),
      ];
      final conversationMessages = <ChatMessage>[];

      final result = buildCheckpointSummaryMessages(
        memoryPrompt: memoryPrompt,
        conversationMessages: conversationMessages,
        checkpointChain: chain,
      );

      // 第一条是 system prompt
      // 第二条是检查点记忆消息
      expect(result.length, greaterThanOrEqualTo(3));
      expect(result[1].role, ChatMessageRole.system);
      expect(result[1].content, contains('检查点A'));
      expect(result[1].content, contains('检查点B'));
      expect(result[1].content, contains('内容A'));
      expect(result[1].content, contains('内容B'));
    });

    test('包含 filtered 对话消息', () {
      final memoryPrompt = buildMemoryPrompt();
      final conversationMessages = [
        buildMessage(id: 'm-keep', content: '保留消息'),
        buildMessage(id: 'm-exclude', content: '排除消息'),
      ];

      final result = buildCheckpointSummaryMessages(
        memoryPrompt: memoryPrompt,
        conversationMessages: conversationMessages,
        checkpointChain: const [],
        filter: const ExcludeByIdMessageFilter({'m-exclude'}),
      );

      // 在 system prompt + 对话消息 + 末尾指令中查找
      final userMessages = result.where(
        (m) => m.role == ChatMessageRole.user,
      );
      final contents = userMessages.map((m) => m.content).toList();
      expect(contents, contains('保留消息'));
      expect(contents, isNot(contains('排除消息')));
    });

    test('末尾包含记忆总结提示词指令', () {
      final memoryPrompt = buildMemoryPrompt(content: '请用简洁的语言总结');
      final conversationMessages = <ChatMessage>[];

      final result = buildCheckpointSummaryMessages(
        memoryPrompt: memoryPrompt,
        conversationMessages: conversationMessages,
        checkpointChain: const [],
      );

      // 最后一条 user 消息是记忆总结提示词
      final lastUser = result.lastWhere(
        (m) => m.role == ChatMessageRole.user,
      );
      expect(lastUser.content, contains('请用简洁的语言总结'));
      expect(lastUser.content, contains('记忆总结提示词'));
    });

    test('presetPrompt before/after placement 正确放置消息', () {
      final memoryPrompt = buildMemoryPrompt();
      final conversationMessages = [
        buildMessage(id: 'm1', content: '对话'),
      ];
      final presetPrompt = buildPresetPrompt(
        messages: [
          buildPromptMessage(
            role: PromptMessageRole.system,
            content: '前置系统消息',
            placement: PromptMessagePlacement.before,
          ),
          buildPromptMessage(
            role: PromptMessageRole.assistant,
            content: '后置助手消息',
            placement: PromptMessagePlacement.after,
          ),
        ],
      );

      final result = buildCheckpointSummaryMessages(
        memoryPrompt: memoryPrompt,
        conversationMessages: conversationMessages,
        checkpointChain: const [],
        presetPrompt: presetPrompt,
      );

      final rolesAndContents = result.map(
        (m) => '${m.role.apiValue}:${m.content}',
      ).toList();

      // 前置 system 消息应在对话消息之前
      final beforeSystemIndex = rolesAndContents.indexWhere(
        (rc) => rc == 'system:前置系统消息',
      );
      final dialogIndex = rolesAndContents.indexWhere(
        (rc) => rc == 'user:对话',
      );
      final afterAssistantIndex = rolesAndContents.indexWhere(
        (rc) => rc == 'assistant:后置助手消息',
      );

      expect(beforeSystemIndex, lessThan(dialogIndex));
      expect(dialogIndex, lessThan(afterAssistantIndex));
    });
  });
}
