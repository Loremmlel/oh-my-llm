import 'package:equatable/equatable.dart';

enum AgentScriptStatus { planned, active, completed }

extension AgentScriptStatusLabel on AgentScriptStatus {
  String get label => switch (this) {
    AgentScriptStatus.planned => '尚未开始',
    AgentScriptStatus.active => '正在推进',
    AgentScriptStatus.completed => '已完成',
  };
}

/// 备忘绑定实际正文来源，随主会话检查点与撤回快照一起保存。
class AgentScriptProgress extends Equatable {
  AgentScriptProgress({
    required this.fingerprint,
    required this.status,
    required this.notes,
    required List<String> sourceRoundIds,
  }) : sourceRoundIds = List.unmodifiable(sourceRoundIds);

  final String fingerprint, notes;
  final AgentScriptStatus status;
  final List<String> sourceRoundIds;

  Map<String, Object?> toJson() => {
    'fingerprint': fingerprint,
    'status': status.name,
    'notes': notes,
    'source_round_ids': sourceRoundIds,
  };

  factory AgentScriptProgress.fromJson(Map<String, dynamic> json) =>
      AgentScriptProgress(
        fingerprint: json['fingerprint'] as String,
        status: AgentScriptStatus.values.byName(json['status'] as String),
        notes: json['notes'] as String,
        sourceRoundIds: List<String>.from(json['source_round_ids'] as List),
      );

  @override
  List<Object?> get props => [fingerprint, status, notes, sourceRoundIds];
}
