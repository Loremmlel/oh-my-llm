import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/agent/application/agent_context.dart';
import 'package:oh_my_llm/features/agent/domain/agent_models.dart';

void main() {
  const card = AgentDocument(
    id: 'a',
    name: '阿弥',
    content: '作者秘密：她是继承人',
    kind: AgentDocumentKind.characterCard,
    revision: 1,
  );
  const world = AgentDocument(
    id: 'w',
    name: '港口',
    content: '每天日落关城门',
    kind: AgentDocumentKind.worldBook,
    revision: 1,
  );
  test('完整设定稳定排序并冻结版本，各职责共用设定且预设按职责应用', () {
    final initial = AgentWorkspace(
      id: 'n',
      title: '雾港',
      configuration: AgentConfiguration(
        preset: '克制文风',
        presetRoles: [AgentRole.writer],
      ),
    );
    final workspace = freezeAgentWorkspace(initial, [world, card]);
    final main = agentInputText(
      buildAgentInitialContext(workspace, AgentRole.coordinator),
    );
    expect(main, contains(card.content));
    expect(main, contains(world.content));
    expect(main.indexOf('ID=a'), lessThan(main.indexOf('ID=w')));
    expect(main, isNot(contains('克制文风')));
    final writer = agentInputText(
      buildAgentInitialContext(workspace, AgentRole.writer),
    );
    expect(writer, contains('克制文风'));
    final character = agentInputText(
      buildAgentInitialContext(workspace, AgentRole.character),
    );
    expect(character, contains(card.content));
    expect(character, contains(world.content));
    final updated = const AgentDocument(
      id: 'w',
      name: '港口',
      content: '城门全天开放',
      kind: AgentDocumentKind.worldBook,
      revision: 2,
    );
    expect(freezeAgentWorkspace(workspace, [updated, card]), workspace);
    expect(
      agentInputText(
        buildAgentInitialContext(
          freezeAgentWorkspace(initial, [updated, card]),
          AgentRole.coordinator,
        ),
      ),
      contains('城门全天开放'),
    );
  });
}
