import 'dart:convert';

import 'settings_transfer_payload.dart';
import 'settings_transfer_types.dart';

/// 一项固定设置的传输描述。
///
/// 泛型只存在于构造阶段；运行时由本类集中完成类型检查和擦除。
final class SettingsTransferSection {
  SettingsTransferSection._({
    required this.key,
    required this.group,
    required this.label,
    required this.order,
    required this.sensitivity,
    required this._readLocal,
    required this._shouldExport,
    required this._encode,
    required this._decode,
    required this._prepareImport,
    required this._summarizeExport,
    required this._write,
  }) {
    if (!_validKey.hasMatch(key)) {
      throw ArgumentError.value(
        key,
        'key',
        '必须符合 ASCII lower-camel 规则 [a-z][A-Za-z0-9]*',
      );
    }
    if (label.trim().isEmpty) {
      throw ArgumentError.value(label, 'label', '不能是空白字符串');
    }
  }

  /// 构造整体替换型 section。
  static SettingsTransferSection replacing<T>({
    required String key,
    required SettingsTransferGroup group,
    required String label,
    required int order,
    required SettingsTransferSensitivity sensitivity,
    required T Function() readLocal,
    required Future<void> Function(T) write,
    required Object Function(T) encode,
    required T Function(Map<String, dynamic>) decode,
    bool Function(T)? isEmpty,
    bool Function(T, T)? isEquivalent,
  }) {
    final equivalent = isEquivalent ?? (T left, T right) => left == right;
    final empty = isEmpty ?? (T value) => value == null;
    return custom<T>(
      key: key,
      group: group,
      label: label,
      order: order,
      sensitivity: sensitivity,
      readLocal: readLocal,
      write: write,
      shouldExport: (_) => true,
      encode: encode,
      decode: (payload) => decode(decodeTransferObject(payload, label)),
      prepareImport: (local, incoming) {
        if (equivalent(local, incoming)) return null;
        return SettingsTransferChange<T>(
          incoming: incoming,
          writeValue: incoming,
          fingerprint: jsonEncode(encode(incoming)),
          summary: SettingsTransferSummaryItem(
            key: key,
            label: label,
            action: empty(incoming)
                ? SettingsTransferSummaryAction.clear
                : SettingsTransferSummaryAction.replace,
          ),
        );
      },
      summarizeExport: (value) => SettingsTransferSummaryItem(
        key: key,
        label: label,
        action: empty(value)
            ? SettingsTransferSummaryAction.clear
            : SettingsTransferSummaryAction.replace,
      ),
    );
  }

  /// 构造只追加远端新增项的集合型 section。
  static SettingsTransferSection merging<T>({
    required String key,
    required SettingsTransferGroup group,
    required String label,
    required int order,
    required SettingsTransferSensitivity sensitivity,
    required List<T> Function() readLocal,
    required Future<void> Function(List<T>) write,
    required Object Function(T) encodeItem,
    required T Function(Map<String, dynamic>) decodeItem,
    required bool Function(T, T) isEquivalent,
    void Function(T)? validateItem,
  }) {
    Object encodeItems(List<T> values) =>
        values.map(encodeItem).toList(growable: false);

    return custom<List<T>>(
      key: key,
      group: group,
      label: label,
      order: order,
      sensitivity: sensitivity,
      readLocal: readLocal,
      write: write,
      shouldExport: (value) => value.isNotEmpty,
      encode: encodeItems,
      decode: (payload) {
        final values = decodeTransferObjectList(
          payload,
          label,
        ).map(decodeItem).toList(growable: false);
        if (validateItem != null) {
          for (final value in values) {
            validateItem(value);
          }
        }
        return values;
      },
      prepareImport: (local, incoming) {
        if (incoming.isEmpty) return null;
        final additions = <T>[];
        for (final candidate in incoming) {
          if (local.any((item) => isEquivalent(item, candidate))) continue;
          if (!additions.any((item) => isEquivalent(item, candidate))) {
            additions.add(candidate);
          }
        }
        if (additions.isEmpty) return null;

        final writeValue = List<T>.unmodifiable(additions);
        return SettingsTransferChange<List<T>>(
          incoming: List<T>.unmodifiable(incoming),
          writeValue: writeValue,
          fingerprint: jsonEncode(encodeItems(writeValue)),
          summary: SettingsTransferSummaryItem(
            key: key,
            label: label,
            action: SettingsTransferSummaryAction.add,
            count: additions.length,
          ),
        );
      },
      summarizeExport: (value) {
        if (value.isEmpty) {
          throw StateError('空合并集合不能生成 add 摘要');
        }
        return SettingsTransferSummaryItem(
          key: key,
          label: label,
          action: SettingsTransferSummaryAction.add,
          count: value.length,
        );
      },
    );
  }

  /// 构造需要自定义导入合并策略的 section。
  static SettingsTransferSection custom<T>({
    required String key,
    required SettingsTransferGroup group,
    required String label,
    required int order,
    required SettingsTransferSensitivity sensitivity,
    required T Function() readLocal,
    required Future<void> Function(T) write,
    required bool Function(T) shouldExport,
    required Object Function(T) encode,
    required T Function(Object?) decode,
    required SettingsTransferChange<T>? Function(T, T) prepareImport,
    required SettingsTransferSummaryItem Function(T) summarizeExport,
  }) {
    return SettingsTransferSection._(
      key: key,
      group: group,
      label: label,
      order: order,
      sensitivity: sensitivity,
      readLocal: readLocal,
      shouldExport: (value) => shouldExport(value as T),
      encode: (value) => encode(value as T),
      decode: decode,
      prepareImport: (local, incoming) =>
          _eraseChange(prepareImport(local as T, incoming as T)),
      summarizeExport: (value) => summarizeExport(value as T),
      write: (value) => write(value as T),
    );
  }

  final String key;
  final SettingsTransferGroup group;
  final String label;
  final int order;
  final SettingsTransferSensitivity sensitivity;

  final Object? Function() _readLocal;
  final bool Function(Object?) _shouldExport;
  final Object Function(Object?) _encode;
  final Object? Function(Object?) _decode;
  final SettingsTransferChange<Object?>? Function(Object?, Object?)
  _prepareImport;
  final SettingsTransferSummaryItem Function(Object?) _summarizeExport;
  final Future<void> Function(Object?) _write;

  SettingsTransferExportedValue? exportLocalIfExportable() {
    final value = _readLocal();
    if (!_shouldExport(value)) return null;
    return _export(value);
  }

  SettingsTransferExportedValue? exportValueIfExportable(Object? value) {
    if (!_shouldExport(value)) return null;
    return _export(value);
  }

  Object? decodePayload(Object? payload) => _decode(payload);

  SettingsTransferChange<Object?>? prepareImport(Object? incoming) {
    return _prepareImport(_readLocal(), incoming);
  }

  SettingsTransferChange<Object?>? reprepareImport(
    SettingsTransferChange<Object?> change,
  ) {
    return _prepareImport(_readLocal(), change.incoming);
  }

  Future<void> applyImport(SettingsTransferChange<Object?> change) =>
      _write(change.writeValue);

  SettingsTransferExportedValue _export(Object? value) {
    return SettingsTransferExportedValue(
      encoded: _encode(value),
      summary: _summarizeExport(value),
    );
  }
}

final class SettingsTransferChange<T> {
  const SettingsTransferChange({
    required this.incoming,
    required this.writeValue,
    required this.fingerprint,
    required this.summary,
  });

  final T incoming;
  final T writeValue;
  final String fingerprint;
  final SettingsTransferSummaryItem summary;
}

final class SettingsTransferExportedValue {
  const SettingsTransferExportedValue({
    required this.encoded,
    required this.summary,
  });

  final Object encoded;
  final SettingsTransferSummaryItem summary;
}

SettingsTransferChange<Object?>? _eraseChange<T>(
  SettingsTransferChange<T>? change,
) {
  if (change == null) return null;
  return SettingsTransferChange<Object?>(
    incoming: change.incoming,
    writeValue: change.writeValue,
    fingerprint: change.fingerprint,
    summary: change.summary,
  );
}

final _validKey = RegExp(r'^[a-z][A-Za-z0-9]*$');
