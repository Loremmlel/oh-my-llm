import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/agent/application/agent_context.dart';
import 'package:oh_my_llm/features/agent/domain/agent_models.dart';

void main() {
  const card = AgentDocument(
    id: 'a',
    name: '阿弥',
    content: '作者秘密：她是继承人',
    kind: AgentDocumentKind.characterCard,
  );
  const world = AgentDocument(
    id: 'w',
    name: '港口',
    content: '每天日落关城门',
    kind: AgentDocumentKind.worldBook,
  );
  test('完整设定稳定排序并采用当前内容，各职责共用设定且预设按职责应用', () {
    final initial = AgentWorkspace(
      id: 'n',
      title: '雾港',
      configuration: AgentConfiguration(
        preset: '克制文风',
        presetRoles: [AgentRole.writer],
        roles: const {
          AgentRole.writer: AgentRoleSettings(instructions: '保留我的写作规则'),
        },
      ),
    );
    final workspace = refreshAgentWorkspace(initial, [world, card]);
    final main = agentInputText(
      buildAgentInitialContext(workspace, AgentRole.coordinator),
    );
    expect(main, contains(card.content));
    expect(main, contains(world.content));
    expect(main.indexOf('ID=w'), lessThan(main.indexOf('ID=a')));
    expect(main, isNot(contains('克制文风')));
    final writer = agentInputText(
      buildAgentInitialContext(workspace, AgentRole.writer),
    );
    expect(writer, contains('克制文风'));
    expect(writer, contains('保留我的写作规则'));
    expect(writer, contains(card.content));
    expect(writer, contains(world.content));
    // 固定契约也适用于已保存的自定义规则，不能只更新新会话的默认提示词。
    expect(writer, contains('不要为阅读已注入的设定调用 list_documents 或 read_document'));
    final character = agentInputText(
      buildAgentInitialContext(
        workspace,
        AgentRole.character,
        characterCardId: card.id,
      ),
    );
    expect(character, contains(card.content));
    expect(character, contains(world.content));
    final updated = const AgentDocument(
      id: 'w',
      name: '港口',
      content: '城门全天开放',
      kind: AgentDocumentKind.worldBook,
    );
    expect(refreshAgentWorkspace(workspace, [updated, card]).references, [
      card,
      updated,
    ]);
    expect(
      agentInputText(
        buildAgentInitialContext(
          refreshAgentWorkspace(initial, [updated, card]),
          AgentRole.coordinator,
        ),
      ),
      contains('城门全天开放'),
    );
  });
}
