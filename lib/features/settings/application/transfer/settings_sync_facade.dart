import 'package:oh_my_llm/features/settings/domain/models/transfer/settings_transfer_document.dart';
import 'package:oh_my_llm/features/sync/application/ports/settings_sync_facade.dart';
import 'package:oh_my_llm/features/sync/domain/models/protocol/sync_types.dart';

import 'settings_transfer_catalog.dart';
import 'settings_transfer_coordinator.dart';
import 'settings_transfer_types.dart';

/// 将 Settings transfer catalog 投影到 Sync-owned port 的唯一实现。
///
/// 这里仅负责稳定 ID、摘要和结果类型的机械适配；participant 的具体字段、
/// 去重和持久化 ACK 仍由 Settings transfer coordinator 负责。
final class RiverpodSettingsSyncFacade implements SettingsSyncFacade {
  RiverpodSettingsSyncFacade({required this.catalog, required this.coordinator})
    : availableGroups = _projectGroups(catalog);

  final SettingsTransferCatalog catalog;
  final SettingsTransferCoordinator coordinator;

  @override
  final List<SettingsSyncGroupDescriptor> availableGroups;

  @override
  SettingsTransferDocument exportGroups(Set<SettingsSyncGroupId> groups) {
    final resolved = _resolveGroups(groups);
    final preparation = coordinator.exportGroups(resolved);
    return switch (preparation) {
      SettingsExportNoContent() => SettingsTransferDocument(sections: const {}),
      SettingsExportBatch(:final document) => document,
    };
  }

  @override
  SettingsSyncPreparedImport prepareIncoming(
    SettingsTransferDocument document, {
    required Set<SettingsSyncGroupId> requestedGroups,
  }) {
    final allowedGroups = _resolveGroups(requestedGroups);
    final preparation = coordinator.prepareDocument(
      document,
      allowedGroups: allowedGroups,
    );
    return switch (preparation) {
      SettingsImportNoChanges() => throw const SettingsSyncNoNewDataException(),
      SettingsImportReady(:final batch) => _PreparedImport(batch),
      SettingsImportMalformed() => throw const SettingsSyncPreparationException(
        '导入内容无效',
      ),
      SettingsImportUnsupportedVersion() =>
        throw const SettingsSyncPreparationException('不支持的设置传输版本'),
      SettingsImportUnknownSection() =>
        throw const SettingsSyncPreparationException('同步内容包含未知设置项'),
      SettingsImportSectionOutsideAllowedGroups() =>
        throw const SettingsSyncPreparationException('同步内容包含未请求的配置项'),
      SettingsImportInvalidParticipantPayload(:final label) =>
        throw SettingsSyncPreparationException('$label 的导入内容无效'),
    };
  }

  Set<SettingsTransferGroup> _resolveGroups(Set<SettingsSyncGroupId> groupIds) {
    final groupsByWireKey = <String, SettingsTransferGroup>{
      for (final group in SettingsTransferGroup.values) group.wireKey: group,
    };
    final resolved = <SettingsTransferGroup>{};
    for (final id in groupIds) {
      final group = groupsByWireKey[id.value];
      if (group == null ||
          !catalog.groups.any((descriptor) => descriptor.group == group)) {
        throw const SettingsSyncPreparationException('同步分组无效');
      }
      resolved.add(group);
    }
    return resolved;
  }
}

List<SettingsSyncGroupDescriptor> _projectGroups(
  SettingsTransferCatalog catalog,
) => List<SettingsSyncGroupDescriptor>.unmodifiable([
  for (final descriptor in catalog.groups)
    SettingsSyncGroupDescriptor(
      id: SettingsSyncGroupId(descriptor.wireKey),
      label: descriptor.label,
      order: descriptor.order,
      sensitivity: descriptor.containsSensitive
          ? SettingsSyncSensitivity.credentialBearing
          : SettingsSyncSensitivity.standard,
    ),
]);

final class _PreparedImport implements SettingsSyncPreparedImport {
  _PreparedImport(this._batch)
    : summaries = List<SettingsSyncSummaryItem>.unmodifiable([
        for (final item in _batch.summaries)
          SettingsSyncSummaryItem(
            label: item.label,
            trailingText: item.trailingText,
          ),
      ]),
      containsSensitive = _batch.containsSensitive;

  final SettingsImportBatch _batch;

  @override
  final List<SettingsSyncSummaryItem> summaries;

  @override
  final bool containsSensitive;

  @override
  Future<SettingsSyncImportExecutionResult> execute({
    required bool confirmedSensitive,
  }) async {
    final result = await _batch.execute(confirmedSensitive: confirmedSensitive);
    return switch (result) {
      SettingsImportSuccess() => const SettingsSyncImportSuccess(),
      SettingsImportSensitiveConfirmationRequired() =>
        const SettingsSyncImportSensitiveConfirmationRequired(),
      SettingsImportStalePreview(:final refreshedBatch) =>
        SettingsSyncImportStalePreview(_PreparedImport(refreshedBatch)),
      SettingsImportFailure(:final failedLabel, :final safeReason) =>
        SettingsSyncImportFailure(
          failedLabel: failedLabel,
          safeReason: safeReason,
        ),
      SettingsImportPartialFailure(
        :final completed,
        :final failedLabel,
        :final notAttempted,
        :final safeReason,
      ) =>
        SettingsSyncImportPartialFailure(
          completed: _summaryItems(completed),
          failedLabel: failedLabel,
          notAttempted: _summaryItems(notAttempted),
          safeReason: safeReason,
        ),
      SettingsImportAlreadyConsumed() =>
        const SettingsSyncImportAlreadyConsumed(),
    };
  }
}

List<SettingsSyncSummaryItem> _summaryItems(
  Iterable<SettingsTransferSummaryItem> items,
) => [
  for (final item in items)
    SettingsSyncSummaryItem(label: item.label, trailingText: item.trailingText),
];
