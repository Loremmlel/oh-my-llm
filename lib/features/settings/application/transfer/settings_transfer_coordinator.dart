import 'dart:async';

import '../../domain/models/transfer/settings_transfer_document.dart';
import '../../domain/models/transfer/settings_transfer_document_codec.dart';
import '../../domain/models/prompts/preset_prompt.dart';

import 'settings_transfer_section.dart';
import 'settings_transfer_types.dart';

/// 导出准备的 sealed 结果。
sealed class SettingsExportPreparation {
  const SettingsExportPreparation();
}

/// 当前选择的分组没有任何可导出的 section 内容。
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
}

/// 导入准备的 sealed 结果。
sealed class SettingsImportPreparation {
  const SettingsImportPreparation();
}

final class SettingsImportMalformed extends SettingsImportPreparation {
  const SettingsImportMalformed();

  String get label => '导入内容无效';
}

final class SettingsImportUnsupportedVersion extends SettingsImportPreparation {
  const SettingsImportUnsupportedVersion([this.version]);

  final int? version;

  String get label => '不支持的设置传输版本';
}

final class SettingsImportUnknownSection extends SettingsImportPreparation {
  const SettingsImportUnknownSection(this.sectionKey);

  final String sectionKey;

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
}

final class SettingsImportInvalidSectionPayload
    extends SettingsImportPreparation {
  const SettingsImportInvalidSectionPayload({
    required this.sectionKey,
    required this.label,
  });

  final String sectionKey;
  final String label;
}

final class SettingsImportNoChanges extends SettingsImportPreparation {
  const SettingsImportNoChanges();

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

/// 固定设置项的导出、准备、重校验和执行协调器。
final class SettingsTransferCoordinator {
  SettingsTransferCoordinator({
    required Iterable<SettingsTransferSection> sections,
  }) {
    final ordered = sections.toList(growable: false)
      ..sort((left, right) {
        final byGroup = left.group.order.compareTo(right.group.order);
        if (byGroup != 0) return byGroup;
        final byOrder = left.order.compareTo(right.order);
        if (byOrder != 0) return byOrder;
        return left.key.compareTo(right.key);
      });
    final byKey = <String, SettingsTransferSection>{};
    for (final section in ordered) {
      if (byKey.containsKey(section.key)) {
        throw ArgumentError.value(section.key, 'sections', '设置项 key 不能重复');
      }
      byKey[section.key] = section;
    }
    _sections = List<SettingsTransferSection>.unmodifiable(ordered);
    _sectionsByKey = Map<String, SettingsTransferSection>.unmodifiable(byKey);
    groups = List<SettingsTransferGroupDescriptor>.unmodifiable(
      SettingsTransferGroup.values
          .where((group) => ordered.any((section) => section.group == group))
          .map((group) {
            final groupSections = ordered.where(
              (section) => section.group == group,
            );
            return SettingsTransferGroupDescriptor(
              group: group,
              containsSensitive: groupSections.any(
                (section) =>
                    section.sensitivity ==
                    SettingsTransferSensitivity.credentialBearing,
              ),
            );
          }),
    );
  }

  late final List<SettingsTransferSection> _sections;
  late final Map<String, SettingsTransferSection> _sectionsByKey;
  late final List<SettingsTransferGroupDescriptor> groups;
  Future<void> _executionTail = Future<void>.value();

  // ── Public operations ────────────────────────────────────────────────

  SettingsExportPreparation exportGroups(Set<SettingsTransferGroup> groups) {
    final sections = <String, Object?>{};
    final summaries = <SettingsTransferSummaryItem>[];
    var containsSensitive = false;

    for (final section in _sections.where(
      (section) => groups.contains(section.group),
    )) {
      final exported = section.exportLocalIfExportable();
      if (exported == null) continue;

      sections[section.key] = exported.encoded;
      summaries.add(exported.summary);
      containsSensitive =
          containsSensitive ||
          section.sensitivity == SettingsTransferSensitivity.credentialBearing;
    }

    if (sections.isEmpty) return const SettingsExportNoContent();
    return SettingsExportBatch(
      document: SettingsTransferDocument(sections: sections),
      summaryItems: summaries,
      containsSensitive: containsSensitive,
    );
  }

  SettingsExportPreparation exportPreset(PresetPrompt preset) {
    final section = _sectionsByKey['presetPrompts'];
    if (section == null) {
      throw StateError('固定设置项 presetPrompts 未注册');
    }
    final exported = section.exportValueIfExportable(<PresetPrompt>[preset]);
    if (exported == null) return const SettingsExportNoContent();

    return SettingsExportBatch(
      document: SettingsTransferDocument(
        sections: <String, Object?>{section.key: exported.encoded},
      ),
      summaryItems: <SettingsTransferSummaryItem>[exported.summary],
      containsSensitive:
          section.sensitivity == SettingsTransferSensitivity.credentialBearing,
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
    // 先完成 key 和 group 门禁，防止未请求 section 触发 payload decode。
    for (final key in document.sections.keys) {
      final section = _sectionsByKey[key];
      if (section == null) {
        return SettingsImportUnknownSection(key);
      }
      if (allowedGroups != null && !allowedGroups.contains(section.group)) {
        return SettingsImportSectionOutsideAllowedGroups(
          sectionKey: key,
          label: section.label,
        );
      }
    }

    final decodedValues = <String, Object?>{};
    String? invalidSectionKey;
    String? invalidSectionLabel;
    for (final entry in document.sections.entries) {
      final section = _sectionsByKey[entry.key]!;
      try {
        decodedValues[entry.key] = section.decodePayload(entry.value);
      } catch (_) {
        invalidSectionKey ??= entry.key;
        invalidSectionLabel ??= section.label;
      }
    }
    if (invalidSectionKey != null && invalidSectionLabel != null) {
      return SettingsImportInvalidSectionPayload(
        sectionKey: invalidSectionKey,
        label: invalidSectionLabel,
      );
    }

    final changes = <_PreparedSettingsTransferChange>[];
    String? preparationFailureKey;
    String? preparationFailureLabel;
    for (final section in _sections) {
      final key = section.key;
      if (!decodedValues.containsKey(key)) continue;
      try {
        final change = section.prepareImport(decodedValues[key]);
        if (change != null) {
          changes.add(
            _PreparedSettingsTransferChange(section: section, change: change),
          );
        }
      } catch (_) {
        preparationFailureKey ??= key;
        preparationFailureLabel ??= section.label;
      }
    }
    if (preparationFailureKey != null && preparationFailureLabel != null) {
      return SettingsImportInvalidSectionPayload(
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

  Future<SettingsImportExecutionResult> _execute(SettingsImportBatch batch) {
    return _enqueue(() async {
      final revalidated = <_PreparedSettingsTransferChange>[];
      var stale = false;

      for (final prepared in batch._changes) {
        SettingsTransferChange<Object?>? next;
        try {
          next = prepared.section.reprepareImport(prepared.change);
        } catch (_) {
          return _failure(prepared.change.summary.label);
        }

        if (next == null || !_samePreparedChange(prepared.change, next)) {
          stale = true;
        }
        if (next != null) {
          revalidated.add(
            _PreparedSettingsTransferChange(
              section: prepared.section,
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
          await prepared.section.applyImport(prepared.change);
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
    final previous = _executionTail;
    final gate = Completer<void>();
    _executionTail = gate.future;

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
    required this._coordinator,
    required List<_PreparedSettingsTransferChange> changes,
    required Set<SettingsTransferGroup>? allowedGroups,
  }) : _changes = List<_PreparedSettingsTransferChange>.unmodifiable(changes),
       _allowedGroups = allowedGroups == null
           ? null
           : Set<SettingsTransferGroup>.unmodifiable(allowedGroups),
       summaryItems = List<SettingsTransferSummaryItem>.unmodifiable(
         changes.map((item) => item.change.summary),
       ),
       containsSensitive = changes.any(
         (item) =>
             item.section.sensitivity ==
             SettingsTransferSensitivity.credentialBearing,
       );

  final SettingsTransferCoordinator _coordinator;
  final List<_PreparedSettingsTransferChange> _changes;
  final Set<SettingsTransferGroup>? _allowedGroups;
  final List<SettingsTransferSummaryItem> summaryItems;
  final bool containsSensitive;
  bool _consumed = false;

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
    required this.section,
    required this.change,
  });

  final SettingsTransferSection section;
  final SettingsTransferChange<Object?> change;
}

const _safeWriteFailureReason = '写入未完成，请检查本地存储后重试';
