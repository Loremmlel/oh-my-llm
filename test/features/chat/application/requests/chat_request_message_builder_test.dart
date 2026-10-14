import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/chat/application/requests/chat_request_message_builder.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_checkpoint.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/preset_prompt.dart';
import 'package:oh_my_llm/features/settings/domain/models/worldbooks/world_book.dart';

import '../../../../helpers/fixtures.dart';

void main() {
  test('世界书只注入启用非空条目且顺序稳定，固定在预设前置和历史之间', () {
    final book = TestFixtures.worldBook(
      name: '城市 & 群岛',
      entries: const [
        WorldBookEntry(id: 'b', title: '人物 "乙"', content: '角色乙\n{{char}}'),
        WorldBookEntry(
          id: 'disabled',
          title: '停用',
          content: '不应注入',
          enabled: false,
        ),
        WorldBookEntry(id: 'empty', title: '空条目', content: '  '),
        WorldBookEntry(id: 'a', title: '世界', content: '世界规则'),
      ],
    );
    final preset = TestFixtures.presetPrompt(
      id: 'preset',
      messages: [
        TestFixtures.promptMessage(id: 'before', content: '前置'),
        TestFixtures.promptMessage(
          id: 'tail',
          content: '后置',
          placement: PromptMessagePlacement.after,
        ),
      ],
    );
    final history = [TestFixtures.userMessage(id: 'input', content: '无关关键词')];
    final prepared = buildRequestMessages(
      presetPrompt: preset,
      worldBook: book,
      conversationMessages: history,
    );
    expect(prepared.map((m) => m.content), [
      '前置',
      '<world_book name="城市 &amp; 群岛">\n<entry title="人物 &quot;乙&quot;">\n角色乙\n{{char}}\n</entry>\n<entry title="世界">\n世界规则\n</entry>\n</world_book>',
      '无关关键词',
      '后置',
    ]);
    expect(prepared[1].role, ChatMessageRole.system);
    expect(prepared[1].sourceLabel, '世界书 · 城市 & 群岛');
    expect(
      buildRequestMessages(
        presetPrompt: null,
        worldBook: book,
        conversationMessages: [],
      ).single.content,
      prepared[1].content,
    );
    expect(
      buildRequestMessages(
        presetPrompt: null,
        worldBook: book.copyWith(entries: []),
        conversationMessages: [],
      ),
      isEmpty,
    );
    final single = buildRequestMessages(
      presetPrompt: preset.copyWith(singleSystemPrompt: true),
      worldBook: book,
      conversationMessages: history,
    );
    expect(single.map((m) => m.content), prepared.map((m) => m.content));
    expect(single[1].role, ChatMessageRole.user);
  });
  ChatMessage message(String id, ChatMessageRole role, String content) =>
      ChatMessage(
        id: id,
        role: role,
        content: content,
        createdAt: DateTime(2026),
      );

  PromptMessage promptMessage(
    String id,
    PromptMessageRole role,
    String content, {
    PromptMessagePlacement placement = PromptMessagePlacement.before,
    bool enabled = true,
  }) => PromptMessage(
    id: id,
    role: role,
    content: content,
    placement: placement,
    enabled: enabled,
  );

  PresetPrompt template(
    List<PromptMessage> messages, {
    bool singleSystemPrompt = false,
  }) => PresetPrompt(
    id: 'template',
    name: '测试模板',
    messages: messages,
    singleSystemPrompt: singleSystemPrompt,
    updatedAt: DateTime(2026),
  );

  test('无模板时按原角色和内容透传会话消息，空输入仍为空', () {
    final result = buildRequestMessages(
      presetPrompt: null,
      conversationMessages: [
        message('u1', ChatMessageRole.user, '你好\n！'),
        message('a1', ChatMessageRole.assistant, '你好！'),
      ],
    );

    expect(result.map((item) => item.role), [
      ChatMessageRole.user,
      ChatMessageRole.assistant,
    ]);
    expect(result.map((item) => item.content), ['你好\n！', '你好！']);
    expect(
      buildRequestMessages(presetPrompt: null, conversationMessages: const []),
      isEmpty,
    );
  });

  test('三种模板位置保持各自顺序并正确转换全部角色', () {
    final result = buildRequestMessages(
      presetPrompt: template([
        promptMessage('before-user', PromptMessageRole.user, '前置用户'),
        promptMessage(
          'latest-system',
          PromptMessageRole.system,
          '最新输入前系统',
          placement: PromptMessagePlacement.beforeLatestInput,
        ),
        promptMessage(
          'after-assistant',
          PromptMessageRole.assistant,
          '后置助手',
          placement: PromptMessagePlacement.after,
        ),
        promptMessage('before-assistant', PromptMessageRole.assistant, '前置助手'),
        promptMessage(
          'latest-user',
          PromptMessageRole.user,
          '最新输入前用户',
          placement: PromptMessagePlacement.beforeLatestInput,
        ),
      ]),
      conversationMessages: [message('u1', ChatMessageRole.user, '真实问题')],
      latestInputMessageId: 'u1',
    );

    expect(result.map((item) => item.content), [
      '前置用户',
      '前置助手',
      '最新输入前系统',
      '最新输入前用户',
      '真实问题',
      '后置助手',
    ]);
    expect(result.map((item) => item.role), [
      ChatMessageRole.user,
      ChatMessageRole.assistant,
      ChatMessageRole.system,
      ChatMessageRole.user,
      ChatMessageRole.user,
      ChatMessageRole.assistant,
    ]);
  });

  test('禁用或纯空白模板消息不会进入请求', () {
    final result = buildRequestMessages(
      presetPrompt: template([
        promptMessage(
          'disabled',
          PromptMessageRole.system,
          '禁用',
          enabled: false,
        ),
        promptMessage('blank', PromptMessageRole.system, '   '),
        promptMessage('enabled', PromptMessageRole.system, '保留'),
      ]),
      conversationMessages: const [],
    );

    expect(result.map((item) => item.content), ['保留']);
  });

  test('filter 只过滤会话消息，不过滤模板消息', () {
    final result = buildRequestMessages(
      presetPrompt: template([
        promptMessage('template', PromptMessageRole.system, '模板前置'),
      ]),
      filter: const ExcludeByIdMessageFilter({'a1'}),
      conversationMessages: [
        message('u1', ChatMessageRole.user, '真实问题'),
        message('a1', ChatMessageRole.assistant, '被排除回复'),
      ],
    );

    expect(result.map((item) => item.content), ['模板前置', '真实问题']);
  });

  test('检查点记忆在模板和会话之前，且不受会话 filter 影响', () {
    final result = buildRequestMessages(
      presetPrompt: template([
        promptMessage('template', PromptMessageRole.system, '模板前置'),
      ]),
      checkpointChain: [
        ChatCheckpoint(
          id: 'checkpoint',
          title: '检查点 1',
          content: '已确认记忆',
          createdAt: DateTime(2026),
        ),
      ],
      filter: const ExcludeByIdMessageFilter({'a1'}),
      conversationMessages: [
        message('u1', ChatMessageRole.user, '新的问题'),
        message('a1', ChatMessageRole.assistant, '旧回复'),
      ],
    );

    expect(result.map((item) => item.role), [
      ChatMessageRole.system,
      ChatMessageRole.system,
      ChatMessageRole.user,
    ]);
    expect(result.first.content, contains('检查点 1'));
    expect(result.map((item) => item.content).skip(1), ['模板前置', '新的问题']);
  });

  test('单 System 模式合并检查点和连续前置条目，后续 System 转 User', () {
    final result = buildRequestMessages(
      presetPrompt: template([
        promptMessage('leading-1', PromptMessageRole.system, '规则一'),
        promptMessage('disabled', PromptMessageRole.user, '禁用', enabled: false),
        promptMessage('leading-2', PromptMessageRole.system, '规则二'),
        promptMessage('break', PromptMessageRole.user, '前置问题'),
        promptMessage('late', PromptMessageRole.system, '后续规则'),
        promptMessage(
          'before-latest',
          PromptMessageRole.system,
          '输入前规则',
          placement: PromptMessagePlacement.beforeLatestInput,
        ),
        promptMessage(
          'after',
          PromptMessageRole.system,
          '后置规则',
          placement: PromptMessagePlacement.after,
        ),
      ], singleSystemPrompt: true),
      checkpointChain: [
        ChatCheckpoint(
          id: 'checkpoint',
          title: '检查点',
          content: '记忆',
          createdAt: DateTime(2026),
        ),
      ],
      conversationMessages: [message('u1', ChatMessageRole.user, '真实问题')],
      latestInputMessageId: 'u1',
    );

    expect(result.map((item) => item.role), [
      ChatMessageRole.system,
      ChatMessageRole.user,
      ChatMessageRole.user,
      ChatMessageRole.user,
      ChatMessageRole.user,
      ChatMessageRole.user,
    ]);
    expect(result.first.content, contains('检查点'));
    expect(result.first.content, endsWith('\n规则一\n规则二'));
    expect(result.map((item) => item.content).skip(1), [
      '前置问题',
      '后续规则',
      '输入前规则',
      '真实问题',
      '后置规则',
    ]);
  });

  test('单 System 模式没有开头 System 时将后续 System 转为 User', () {
    final result = buildRequestMessages(
      presetPrompt: template([
        promptMessage('user', PromptMessageRole.user, '前置用户'),
        promptMessage('system', PromptMessageRole.system, '中间系统'),
      ], singleSystemPrompt: true),
      conversationMessages: const [],
    );
    expect(result.map((item) => item.role), [
      ChatMessageRole.user,
      ChatMessageRole.user,
    ]);
  });
}
