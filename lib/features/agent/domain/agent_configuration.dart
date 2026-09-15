import 'package:equatable/equatable.dart';

enum AgentRole { coordinator, writer, reviewer, character, state }

enum AgentDocumentKind { document, worldBook, characterCard }

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
    this.preset = '',
    Iterable<AgentRole> presetRoles = AgentRole.values,
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
