import 'package:equatable/equatable.dart';

enum AgentContextBatchStatus { active, restored, invalidated }

/// 正文仍保存在楼层中；批次只决定下次输入使用原文还是摘要。
class AgentContextBatch extends Equatable {
  AgentContextBatch({
    required this.id,
    required List<String> roundIds,
    this.summary = '',
    this.summaryRunId,
    this.status = AgentContextBatchStatus.active,
  }) : roundIds = List.unmodifiable(roundIds);

  final String id, summary;
  final List<String> roundIds;
  final String? summaryRunId;
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
  );

  Map<String, Object?> toJson() => {
    'version': 1,
    'id': id,
    'roundIds': roundIds,
    'summary': summary,
    'summaryRunId': summaryRunId,
    'status': status.name,
  };

  factory AgentContextBatch.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1) throw const FormatException('不支持的总结格式');
    return AgentContextBatch(
      id: json['id'] as String,
      roundIds: List<String>.from(json['roundIds'] as List),
      summary: json['summary'] as String,
      summaryRunId: json['summaryRunId'] as String?,
      status: AgentContextBatchStatus.values.byName(json['status'] as String),
    );
  }

  @override
  List<Object?> get props => [id, roundIds, summary, summaryRunId, status];
}
