import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oh_my_llm/features/settings/domain/models/transfer/settings_transfer_document.dart';

import '../../domain/models/protocol/sync_types.dart';

/// Sync application 从 Settings catalog 获得的稳定分组描述。
final class SettingsSyncGroupDescriptor extends Equatable {
  const SettingsSyncGroupDescriptor({
    required this.id,
    required this.label,
    required this.order,
    required this.sensitivity,
  });

  final SettingsSyncGroupId id;
  final String label;
  final int order;
  final SettingsSyncSensitivity sensitivity;

  @override
  List<Object?> get props => [id, label, order, sensitivity];
}

enum SettingsSyncSensitivity { standard, credentialBearing }

/// 跨 feature 传递的安全摘要，不携带原始设置值。
final class SettingsSyncSummaryItem extends Equatable {
  const SettingsSyncSummaryItem({
    required this.label,
    required this.trailingText,
  });

  final String label;
  final String trailingText;

  @override
  List<Object?> get props => [label, trailingText];
}

/// Settings application 已完成校验、可由 Sync presentation 执行的一次性导入。
abstract interface class SettingsSyncPreparedImport {
  List<SettingsSyncSummaryItem> get summaries;

  bool get containsSensitive;

  Future<SettingsSyncImportExecutionResult> execute({
    required bool confirmedSensitive,
  });
}

sealed class SettingsSyncImportExecutionResult {
  const SettingsSyncImportExecutionResult();
}

final class SettingsSyncImportSuccess
    extends SettingsSyncImportExecutionResult {
  const SettingsSyncImportSuccess();
}

final class SettingsSyncImportSensitiveConfirmationRequired
    extends SettingsSyncImportExecutionResult {
  const SettingsSyncImportSensitiveConfirmationRequired();
}

final class SettingsSyncImportStalePreview
    extends SettingsSyncImportExecutionResult {
  const SettingsSyncImportStalePreview(this.refreshedImport);

  final SettingsSyncPreparedImport refreshedImport;
}

final class SettingsSyncImportFailure
    extends SettingsSyncImportExecutionResult {
  const SettingsSyncImportFailure({
    required this.failedLabel,
    required this.safeReason,
  });

  final String failedLabel;
  final String safeReason;
}

final class SettingsSyncImportPartialFailure
    extends SettingsSyncImportExecutionResult {
  const SettingsSyncImportPartialFailure({
    required this.completed,
    required this.failedLabel,
    required this.notAttempted,
    required this.safeReason,
  });

  final List<SettingsSyncSummaryItem> completed;
  final String failedLabel;
  final List<SettingsSyncSummaryItem> notAttempted;
  final String safeReason;
}

final class SettingsSyncImportAlreadyConsumed
    extends SettingsSyncImportExecutionResult {
  const SettingsSyncImportAlreadyConsumed();
}

/// prepareIncoming 失败时的安全、可展示异常；不携带文档或 participant payload。
class SettingsSyncPreparationException implements Exception {
  const SettingsSyncPreparationException(this.safeMessage);

  final String safeMessage;

  @override
  String toString() => safeMessage;
}

final class SettingsSyncNoNewDataException
    extends SettingsSyncPreparationException {
  const SettingsSyncNoNewDataException() : super('远端配置与本机完全一致，无需导入');
}

/// Sync 对 Settings transfer 的唯一聚合边界。
abstract interface class SettingsSyncFacade {
  List<SettingsSyncGroupDescriptor> get availableGroups;

  SettingsTransferDocument exportGroups(Set<SettingsSyncGroupId> groups);

  SettingsSyncPreparedImport prepareIncoming(
    SettingsTransferDocument document, {
    required Set<SettingsSyncGroupId> requestedGroups,
  });
}

/// 必须由 app composition 或测试显式绑定的 Settings 同步实现。
final settingsSyncFacadeProvider = Provider<SettingsSyncFacade>((ref) {
  throw StateError('SettingsSyncFacade 尚未由应用组合层绑定');
});
