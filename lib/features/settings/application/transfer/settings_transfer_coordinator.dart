import 'dart:async';

import 'package:oh_my_llm/features/settings/domain/models/transfer/settings_transfer_document.dart';
import 'package:oh_my_llm/features/settings/domain/models/transfer/settings_transfer_document_codec.dart';

import 'settings_transfer_catalog.dart';
import 'settings_transfer_participant.dart';
import 'settings_transfer_types.dart';

/// 导出准备的 sealed 结果。
sealed class SettingsExportPreparation {
  const SettingsExportPreparation();
}

/// 当前选择的分组没有任何可导出的 participant 内容。
final class SettingsExportNoContent extends SettingsExportPreparation {
  const SettingsExportNoContent();
}

/// 已完成导出编码、但尚未把文本交给外部系统的批次。
final class SettingsExportBatch extends SettingsExportPreparation {
  SettingsExportBatch({
    required this.document,
    required Iterable<SettingsTransferSummaryItem> summaryItems,
    required this.containsSensitive,
  }) : summaryItems = List<SettingsTransferSummaryItem>.unmodifiable(
         summaryItems,
       );

  final SettingsTransferDocument document;
  final List<SettingsTransferSummaryItem> summaryItems;
  final bool containsSensitive;

  /// 供 Sync/application consumer 使用的同义只读视图。
  List<SettingsTransferSummaryItem> get summaries => summaryItems;

  /// 只有确认敏感内容后，才允许把完整文档序列化为可外传文本。
  SettingsExportExposureResult exposeJson({required bool confirmedSensitive}) {
    if (containsSensitive && !confirmedSensitive) {
      return const SettingsExportSensitiveConfirmationRequired();
    }
    return SettingsExportJsonExposed(
      SettingsTransferDocumentCodec.encodeJson(document),
    );
  }
}

/// 导出文本暴露给外部 adapter 前的确认结果。
sealed class SettingsExportExposureResult {
  const SettingsExportExposureResult();
}

final class SettingsExportSensitiveConfirmationRequired
    extends SettingsExportExposureResult {
  const SettingsExportSensitiveConfirmationRequired();
}

final class SettingsExportJsonExposed extends SettingsExportExposureResult {
  const SettingsExportJsonExposed(this.text);

  final String text;

  String get json => text;
}

/// 导入准备的 sealed 结果。
sealed class SettingsImportPreparation {
  const SettingsImportPreparation();
}

final class SettingsImportMalformed extends SettingsImportPreparation {
  const SettingsImportMalformed();

  String get code => 'malformed';
  String get label => '导入内容无效';
}

final class SettingsImportUnsupportedVersion extends SettingsImportPreparation {
  const SettingsImportUnsupportedVersion([this.version]);

  final int? version;

  String get code => 'unsupportedVersion';
  String get label => '不支持的设置传输版本';
}

final class SettingsImportUnknownSection extends SettingsImportPreparation {
  const SettingsImportUnknownSection(this.sectionKey);

  final String sectionKey;

  String get code => 'unknownSection';
  String get label => '未知设置项';
}

final class SettingsImportSectionOutsideAllowedGroups
    extends SettingsImportPreparation {
  const SettingsImportSectionOutsideAllowedGroups({
    required this.sectionKey,
    required this.label,
  });

  final String sectionKey;
  final String label;

  String get code => 'sectionOutsideAllowedGroups';
}

final class SettingsImportInvalidParticipantPayload
    extends SettingsImportPreparation {
  const SettingsImportInvalidParticipantPayload({
    required this.sectionKey,
    required this.label,
  });

  final String sectionKey;
  final String label;

  String get code => 'invalidParticipantPayload';
}

final class SettingsImportNoChanges extends SettingsImportPreparation {
  const SettingsImportNoChanges();

  String get code => 'noChanges';
  String get label => '没有可导入的变化';
}

final class SettingsImportReady extends SettingsImportPreparation {
  const SettingsImportReady(this.batch);

  final SettingsImportBatch batch;
}

/// 已接受的导入执行结果。
sealed class SettingsImportExecutionResult {
  const SettingsImportExecutionResult();
}

final class SettingsImportSuccess extends SettingsImportExecutionResult {
  const SettingsImportSuccess();
}

final class SettingsImportSensitiveConfirmationRequired
    extends SettingsImportExecutionResult {
  const SettingsImportSensitiveConfirmationRequired();
}

final class SettingsImportStalePreview extends SettingsImportExecutionResult {
  const SettingsImportStalePreview(this.refreshedBatch);

  final SettingsImportBatch refreshedBatch;
}

final class SettingsImportFailure extends SettingsImportExecutionResult {
  const SettingsImportFailure({
    required this.failedLabel,
    required this.safeReason,
  });

  final String failedLabel;
  final String safeReason;
}

final class SettingsImportPartialFailure extends SettingsImportExecutionResult {
  const SettingsImportPartialFailure({
    required this.completed,
    required this.failedLabel,
    required this.notAttempted,
    required this.safeReason,
  });

  final List<SettingsTransferSummaryItem> completed;
  final String failedLabel;
  final List<SettingsTransferSummaryItem> notAttempted;
  final String safeReason;
}

final class SettingsImportAlreadyConsumed
    extends SettingsImportExecutionResult {
  const SettingsImportAlreadyConsumed();
}

/// 由 catalog 驱动设置传输的导出、准备、重校验和执行协调器。
final class SettingsTransferCoordinator {
  const SettingsTransferCoordinator({required this.catalog});

  final SettingsTransferCatalog catalog;

  static final Expando<_SettingsTransferExecutionState> _executionStates =
      Expando<_SettingsTransferExecutionState>();

  _SettingsTransferExecutionState get _executionState {
    final existing = _executionStates[this];
    if (existing != null) return existing;
    final created = _SettingsTransferExecutionState();
    _executionStates[this] = created;
    return created;
  }

  // ── Public operations ────────────────────────────────────────────────

  SettingsExportPreparation exportGroups(Set<SettingsTransferGroup> groups) {
    final sections = <String, Object?>{};
    final summaries = <SettingsTransferSummaryItem>[];
    var containsSensitive = false;

    for (final participant in catalog.participantsForGroups(groups)) {
      final exported = participant.exportLocalIfExportable();
      if (exported == null) continue;

      sections[participant.key.value] = exported.encoded;
      summaries.add(exported.summary);
      containsSensitive =
          containsSensitive ||
          participant.sensitivity ==
              SettingsTransferSensitivity.credentialBearing;
    }

    if (sections.isEmpty) return const SettingsExportNoContent();
    return SettingsExportBatch(
      document: SettingsTransferDocument(sections: sections),
      summaryItems: summaries,
      containsSensitive: containsSensitive,
    );
  }

  SettingsExportPreparation exportValue<T>(
    SettingsTransferParticipant<T> participant,
    T value,
  ) {
    if (!participant.shouldExport(value)) {
      return const SettingsExportNoContent();
    }

    return SettingsExportBatch(
      document: SettingsTransferDocument(
        sections: <String, Object?>{
          participant.key.value: participant.encode(value),
        },
      ),
      summaryItems: <SettingsTransferSummaryItem>[
        participant.summarizeExport(value),
      ],
      containsSensitive:
          participant.sensitivity ==
          SettingsTransferSensitivity.credentialBearing,
    );
  }

  SettingsImportPreparation prepareJson(
    String? text, {
    Set<SettingsTransferGroup>? allowedGroups,
  }) {
    final decoded = SettingsTransferDocumentCodec.decodeJson(text);
    if (decoded is SettingsTransferDocumentMalformed) {
      return const SettingsImportMalformed();
    }
    if (decoded is SettingsTransferDocumentUnsupportedVersion) {
      return SettingsImportUnsupportedVersion(decoded.version);
    }
    return prepareDocument(
      (decoded as SettingsTransferDocumentDecodeSuccess).document,
      allowedGroups: allowedGroups,
    );
  }

  SettingsImportPreparation prepareDocument(
    SettingsTransferDocument document, {
    Set<SettingsTransferGroup>? allowedGroups,
  }) {
    final participants = _allParticipants();
    final participantsByKey = <String, ErasedSettingsTransferParticipant>{
      for (final participant in participants)
        participant.key.value: participant,
    };

    // 先完成 key 和 group 门禁，防止未请求 section 触发 participant decode。
    for (final key in document.sections.keys) {
      final participant = participantsByKey[key];
      if (participant == null) {
        return SettingsImportUnknownSection(key);
      }
      if (allowedGroups != null && !allowedGroups.contains(participant.group)) {
        return SettingsImportSectionOutsideAllowedGroups(
          sectionKey: key,
          label: participant.label,
        );
      }
    }

    final decodedValues = <String, Object?>{};
    String? invalidSectionKey;
    String? invalidSectionLabel;
    for (final entry in document.sections.entries) {
      final participant = participantsByKey[entry.key]!;
      try {
        decodedValues[entry.key] = participant.decodePayload(entry.value);
      } catch (_) {
        invalidSectionKey ??= entry.key;
        invalidSectionLabel ??= participant.label;
      }
    }
    if (invalidSectionKey != null && invalidSectionLabel != null) {
      return SettingsImportInvalidParticipantPayload(
        sectionKey: invalidSectionKey,
        label: invalidSectionLabel,
      );
    }

    final changes = <_PreparedSettingsTransferChange>[];
    String? preparationFailureKey;
    String? preparationFailureLabel;
    for (final participant in participants) {
      final key = participant.key.value;
      if (!decodedValues.containsKey(key)) continue;
      try {
        final change = participant.prepareImport(decodedValues[key]);
        if (change != null) {
          changes.add(
            _PreparedSettingsTransferChange(
              participant: participant,
              change: change,
            ),
          );
        }
      } catch (_) {
        preparationFailureKey ??= key;
        preparationFailureLabel ??= participant.label;
      }
    }
    if (preparationFailureKey != null && preparationFailureLabel != null) {
      return SettingsImportInvalidParticipantPayload(
        sectionKey: preparationFailureKey,
        label: preparationFailureLabel,
      );
    }
    if (changes.isEmpty) return const SettingsImportNoChanges();

    return SettingsImportReady(
      SettingsImportBatch._(
        coordinator: this,
        changes: changes,
        allowedGroups: allowedGroups,
      ),
    );
  }

  // ── Internal execution ──────────────────────────────────────────────

  List<ErasedSettingsTransferParticipant> _allParticipants() =>
      catalog.participantsForGroups(SettingsTransferGroup.values.toSet());

  Future<SettingsImportExecutionResult> _execute(SettingsImportBatch batch) {
    return _enqueue(() async {
      final revalidated = <_PreparedSettingsTransferChange>[];
      var stale = false;

      for (final prepared in batch._changes) {
        SettingsTransferChange<Object?>? next;
        try {
          next = prepared.participant.reprepareImport(prepared.change);
        } catch (_) {
          return _failure(prepared.change.summary.label);
        }

        if (next == null || !_samePreparedChange(prepared.change, next)) {
          stale = true;
        }
        if (next != null) {
          revalidated.add(
            _PreparedSettingsTransferChange(
              participant: prepared.participant,
              change: next,
            ),
          );
        }
      }

      if (stale) {
        final refreshedBatch = SettingsImportBatch._(
          coordinator: this,
          changes: revalidated,
          allowedGroups: batch._allowedGroups,
        );
        return SettingsImportStalePreview(refreshedBatch);
      }

      final completed = <SettingsTransferSummaryItem>[];
      for (var index = 0; index < revalidated.length; index += 1) {
        final prepared = revalidated[index];
        try {
          await prepared.participant.applyImport(prepared.change);
        } catch (_) {
          final failedLabel = prepared.change.summary.label;
          final safeReason = _safeWriteFailureReason;
          if (completed.isEmpty) {
            return SettingsImportFailure(
              failedLabel: failedLabel,
              safeReason: safeReason,
            );
          }
          return SettingsImportPartialFailure(
            completed: List<SettingsTransferSummaryItem>.unmodifiable(
              completed,
            ),
            failedLabel: failedLabel,
            notAttempted: List<SettingsTransferSummaryItem>.unmodifiable(
              revalidated.skip(index + 1).map((item) => item.change.summary),
            ),
            safeReason: safeReason,
          );
        }
        completed.add(prepared.change.summary);
      }

      return const SettingsImportSuccess();
    });
  }

  Future<SettingsImportExecutionResult> _enqueue(
    Future<SettingsImportExecutionResult> Function() action,
  ) {
    final previous = _executionState.tail;
    final gate = Completer<void>();
    _executionState.tail = gate.future;

    return () async {
      try {
        await previous;
        return await action();
      } finally {
        if (!gate.isCompleted) gate.complete();
      }
    }();
  }

  static bool _samePreparedChange(
    SettingsTransferChange<Object?> previous,
    SettingsTransferChange<Object?> next,
  ) =>
      previous.fingerprint == next.fingerprint &&
      previous.summary == next.summary;

  static SettingsImportFailure _failure(String label) => SettingsImportFailure(
    failedLabel: label,
    safeReason: _safeWriteFailureReason,
  );
}

final class SettingsImportBatch {
  SettingsImportBatch._({
    required SettingsTransferCoordinator coordinator,
    required List<_PreparedSettingsTransferChange> changes,
    required Set<SettingsTransferGroup>? allowedGroups,
  }) : _coordinator = coordinator,
       _changes = List<_PreparedSettingsTransferChange>.unmodifiable(changes),
       _allowedGroups = allowedGroups == null
           ? null
           : Set<SettingsTransferGroup>.unmodifiable(allowedGroups),
       summaryItems = List<SettingsTransferSummaryItem>.unmodifiable(
         changes.map((item) => item.change.summary),
       ),
       containsSensitive = changes.any(
         (item) =>
             item.participant.sensitivity ==
             SettingsTransferSensitivity.credentialBearing,
       );

  final SettingsTransferCoordinator _coordinator;
  final List<_PreparedSettingsTransferChange> _changes;
  final Set<SettingsTransferGroup>? _allowedGroups;
  final List<SettingsTransferSummaryItem> summaryItems;
  final bool containsSensitive;
  bool _consumed = false;

  List<SettingsTransferSummaryItem> get summaries => summaryItems;

  Future<SettingsImportExecutionResult> execute({
    required bool confirmedSensitive,
  }) {
    if (_consumed) return Future.value(const SettingsImportAlreadyConsumed());
    if (containsSensitive && !confirmedSensitive) {
      return Future.value(const SettingsImportSensitiveConfirmationRequired());
    }

    _consumed = true;
    return _coordinator._execute(this);
  }
}

final class _PreparedSettingsTransferChange {
  const _PreparedSettingsTransferChange({
    required this.participant,
    required this.change,
  });

  final ErasedSettingsTransferParticipant participant;
  final SettingsTransferChange<Object?> change;
}

final class _SettingsTransferExecutionState {
  Future<void> tail = Future<void>.value();
}

const _safeWriteFailureReason = '写入未完成，请检查本地存储后重试';

// 让测试和后续 application adapter 可以使用更具语义的别名，而不增加
// 第二套结果层级或可绕过 sealed contract 的实现。
typedef SettingsExportEmpty = SettingsExportNoContent;
typedef SettingsExportJson = SettingsExportJsonExposed;
typedef SettingsImportInvalidPayload = SettingsImportInvalidParticipantPayload;
typedef SettingsImportSectionNotAllowed =
    SettingsImportSectionOutsideAllowedGroups;
typedef SettingsImportNoChange = SettingsImportNoChanges;
typedef SettingsImportReadyBatch = SettingsImportReady;
