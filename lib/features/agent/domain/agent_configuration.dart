import 'package:equatable/equatable.dart';

enum AgentRole { coordinator, writer, reviewer, character, state, summarizer }

enum AgentDocumentKind { document, worldBook, characterCard, script }

const agentDefaultPreset =
    '''用户正在扮演的人物由用户控制，以用户明确指定或已建立的扮演关系为准。不擅自替用户选择人物。纯小说代写或明确授权代演时，按用户指定的范围处理。
不得替用户人物新增台词、主动行动、决定、心理活动、情绪或意图。可以承接用户已经表达的言行，描写其他人物和环境的反应，以及符合既定规则的直接外部后果；不得进一步替用户决定接受、拒绝、配合或反抗。其他人物对用户人物的猜测只能作为其主观判断，不能写成已确认事实。
其他人物与环境可以主动变化。推进到需要用户回应或选择的节点时自然停下，不越过该节点安排用户的后续行为。不必每句话都等待用户，也不强制每轮以问题或选项列表结束。
“继续”、沉默、没有反对和剧情需要不构成代演授权。明确授权只在指定范围内有效；剧本安排和角色推演结果不能代替用户决定。''';

class AgentRoleSettings extends Equatable {
  const AgentRoleSettings({this.modelId, this.instructions = ''});
  final String? modelId;
  final String instructions;
  @override
  List<Object?> get props => [modelId, instructions];
}

class AgentConfiguration extends Equatable {
  AgentConfiguration({
    this.name = '默认方案',
    this.modelId,
    this.preset = agentDefaultPreset,
    Iterable<AgentRole> presetRoles = const [
      AgentRole.coordinator,
      AgentRole.writer,
      AgentRole.reviewer,
      AgentRole.character,
    ],
    Map<AgentRole, AgentRoleSettings> roles = const {},
  }) : presetRoles = Set.unmodifiable(presetRoles),
       roles = Map.unmodifiable(roles);

  final String name;
  final String? modelId;
  final String preset;
  final Set<AgentRole> presetRoles;
  final Map<AgentRole, AgentRoleSettings> roles;
  AgentRoleSettings settings(AgentRole role) =>
      roles[role] ?? const AgentRoleSettings();
  String? modelFor(AgentRole role) => role == AgentRole.coordinator
      ? modelId
      : settings(role).modelId ?? modelId;
  AgentConfiguration copyWith({
    String? name,
    String? modelId,
    String? preset,
    Iterable<AgentRole>? presetRoles,
    Map<AgentRole, AgentRoleSettings>? roles,
  }) => AgentConfiguration(
    name: name ?? this.name,
    modelId: modelId ?? this.modelId,
    preset: preset ?? this.preset,
    presetRoles: presetRoles ?? this.presetRoles,
    roles: roles ?? this.roles,
  );
  @override
  List<Object?> get props => [name, modelId, preset, presetRoles, roles];
}
