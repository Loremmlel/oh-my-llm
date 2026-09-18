import 'package:equatable/equatable.dart';

enum AgentContextBatchStatus { active, restored, invalidated }

/// 一部作品只保存一份当前累计摘要；原始楼层仍供查看与恢复。
class AgentContextBatch extends Equatable {
  AgentContextBatch({
    required this.id,
    required List<String> roundIds,
    this.summary = '',
    this.summaryRunId,
    this.historyEnd = 0,
    this.status = AgentContextBatchStatus.active,
  }) : roundIds = List.unmodifiable(roundIds);

  final String id, summary;
  final List<String> roundIds;
  final String? summaryRunId;

  /// 原始历史的排他结束位置，覆盖完整任务及其工具往返。
  final int historyEnd;
  final AgentContextBatchStatus status;
  bool get active => status == AgentContextBatchStatus.active;

  AgentContextBatch copyWith({
    String? summary,
    String? summaryRunId,
    AgentContextBatchStatus? status,
  }) => AgentContextBatch(
    id: id,
    roundIds: roundIds,
    summary: summary ?? this.summary,
    summaryRunId: summaryRunId ?? this.summaryRunId,
    status: status ?? this.status,
    historyEnd: historyEnd,
  );

  Map<String, Object?> toJson() => {
    'version': 2,
    'id': id,
    'roundIds': roundIds,
    'summary': summary,
    'summaryRunId': summaryRunId,
    'status': status.name,
    'historyEnd': historyEnd,
  };

  factory AgentContextBatch.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 2) throw const FormatException('不支持的总结格式');
    return AgentContextBatch(
      id: json['id'] as String,
      historyEnd: json['historyEnd'] as int,
      roundIds: List<String>.from(json['roundIds'] as List),
      summary: json['summary'] as String,
      summaryRunId: json['summaryRunId'] as String?,
      status: AgentContextBatchStatus.values.byName(json['status'] as String),
    );
  }

  @override
  List<Object?> get props => [
    id,
    roundIds,
    summary,
    summaryRunId,
    status,
    historyEnd,
  ];
}
