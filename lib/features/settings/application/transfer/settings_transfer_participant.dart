import 'dart:convert';

import 'settings_transfer_types.dart';

/// 一种设置的类型化传输声明。
abstract interface class SettingsTransferParticipant<T> {
  SettingsTransferKey get key;
  SettingsTransferGroup get group;
  String get label;
  int get order;
  SettingsTransferSensitivity get sensitivity;

  T readLocal();
  bool shouldExport(T value);
  Object encode(T value);
  T decode(Object? payload);
  SettingsTransferChange<T>? prepareImport({
    required T local,
    required T incoming,
  });
  SettingsTransferSummaryItem summarizeExport(T value);
  Future<void> applyImport(T value);
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

/// erased export 边界一次读取后同时保留编码值和安全摘要。
final class SettingsTransferExportedValue {
  const SettingsTransferExportedValue({
    required this.encoded,
    required this.summary,
  });

  final Object encoded;
  final SettingsTransferSummaryItem summary;
}

/// 以完整值替换本地设置的通用 participant 策略。
///
/// 具体 participant 仍负责读取、编解码、等价判断和持久化；本类只统一
/// no-op、replace/clear 摘要和待写入指纹语义。
abstract class ReplacingValueParticipant<T>
    implements SettingsTransferParticipant<T> {
  const ReplacingValueParticipant({
    required this.key,
    required this.group,
    required this.label,
    required this.order,
    required this.sensitivity,
  });

  @override
  final SettingsTransferKey key;

  @override
  final SettingsTransferGroup group;

  @override
  final String label;

  @override
  final int order;

  @override
  final SettingsTransferSensitivity sensitivity;

  @override
  bool shouldExport(T value) => true;

  /// 比较完整的本地值和传入值，不应只比较用于显示的字段。
  bool isEquivalent(T existing, T incoming);

  /// 子类可将有效空值定义为 clear；默认只把 null 视为空值。
  bool isEmpty(T value) => value == null;

  /// 默认以编码后的完整写入值作为重校验指纹。
  String fingerprintFor(T value) => jsonEncode(encode(value));

  @override
  SettingsTransferChange<T>? prepareImport({
    required T local,
    required T incoming,
  }) {
    if (isEquivalent(local, incoming)) return null;

    return SettingsTransferChange<T>(
      incoming: incoming,
      writeValue: incoming,
      fingerprint: fingerprintFor(incoming),
      summary: summarizeExport(incoming),
    );
  }

  @override
  SettingsTransferSummaryItem summarizeExport(T value) {
    return SettingsTransferSummaryItem(
      key: key,
      label: label,
      action: isEmpty(value)
          ? SettingsTransferSummaryAction.clear
          : SettingsTransferSummaryAction.replace,
    );
  }
}

/// 将传入集合中未出现于本地集合的内容追加写入的通用 participant 策略。
///
/// 具体 participant 仍负责元素编解码、内容等价判断和持久化；本类只统一
/// 空集合省略、去重、add 摘要和新增项写入值。
abstract class MergingCollectionParticipant<T>
    implements SettingsTransferParticipant<List<T>> {
  const MergingCollectionParticipant({
    required this.key,
    required this.group,
    required this.label,
    required this.order,
    required this.sensitivity,
  });

  @override
  final SettingsTransferKey key;

  @override
  final SettingsTransferGroup group;

  @override
  final String label;

  @override
  final int order;

  @override
  final SettingsTransferSensitivity sensitivity;

  /// 比较集合元素的完整可传输内容。
  bool isEquivalent(T existing, T incoming);

  @override
  bool shouldExport(List<T> value) => value.isNotEmpty;

  /// 默认以编码后的完整写入集合作为重校验指纹。
  String fingerprintFor(List<T> value) => jsonEncode(encode(value));

  @override
  SettingsTransferChange<List<T>>? prepareImport({
    required List<T> local,
    required List<T> incoming,
  }) {
    if (incoming.isEmpty) return null;

    final additions = <T>[];
    for (final candidate in incoming) {
      final alreadyPresent = local.any(
        (existing) => isEquivalent(existing, candidate),
      );
      if (alreadyPresent) continue;

      final alreadyAdded = additions.any(
        (existing) => isEquivalent(existing, candidate),
      );
      if (!alreadyAdded) additions.add(candidate);
    }
    if (additions.isEmpty) return null;

    final writeValue = List<T>.unmodifiable(additions);
    final incomingValue = List<T>.unmodifiable(incoming);
    return SettingsTransferChange<List<T>>(
      incoming: incomingValue,
      writeValue: writeValue,
      fingerprint: fingerprintFor(writeValue),
      summary: SettingsTransferSummaryItem(
        key: key,
        label: label,
        action: SettingsTransferSummaryAction.add,
        count: additions.length,
      ),
    );
  }

  @override
  SettingsTransferSummaryItem summarizeExport(List<T> value) {
    if (value.isEmpty) {
      throw StateError('空合并集合不能生成 add 摘要');
    }
    return SettingsTransferSummaryItem(
      key: key,
      label: label,
      action: SettingsTransferSummaryAction.add,
      count: value.length,
    );
  }
}

/// Settings application 内部使用的非泛型 participant 视图。
sealed class ErasedSettingsTransferParticipant {
  SettingsTransferKey get key;
  SettingsTransferGroup get group;
  String get label;
  int get order;
  SettingsTransferSensitivity get sensitivity;

  SettingsTransferExportedValue? exportLocalIfExportable();
  Object? decodePayload(Object? payload);
  SettingsTransferChange<Object?>? prepareImport(Object? incoming);
  SettingsTransferChange<Object?>? reprepareImport(
    SettingsTransferChange<Object?> change,
  );
  Future<void> applyImport(SettingsTransferChange<Object?> change);

  SettingsTransferParticipant<T> participantAs<T>();
}

/// Settings application 内部唯一的 participant 类型擦除边界。
final class SettingsTransferParticipantBox<T>
    extends ErasedSettingsTransferParticipant {
  SettingsTransferParticipantBox(this.participant);

  static SettingsTransferParticipantBox<T> erase<T>(
    SettingsTransferParticipant<T> participant,
  ) {
    return SettingsTransferParticipantBox<T>(participant);
  }

  final SettingsTransferParticipant<T> participant;

  @override
  SettingsTransferKey get key => participant.key;

  @override
  SettingsTransferGroup get group => participant.group;

  @override
  String get label => participant.label;

  @override
  int get order => participant.order;

  @override
  SettingsTransferSensitivity get sensitivity => participant.sensitivity;

  @override
  SettingsTransferExportedValue? exportLocalIfExportable() {
    final value = participant.readLocal();
    _validateValue(value, 'local');
    if (!participant.shouldExport(value)) return null;
    return SettingsTransferExportedValue(
      encoded: participant.encode(value),
      summary: participant.summarizeExport(value),
    );
  }

  @override
  Object? decodePayload(Object? payload) {
    final decoded = participant.decode(payload);
    _validateValue(decoded, 'decoded');
    return decoded;
  }

  @override
  SettingsTransferChange<Object?>? prepareImport(Object? incoming) {
    _validateValue(incoming, 'incoming');
    final local = participant.readLocal();
    _validateValue(local, 'local');
    final change = participant.prepareImport(
      local: local,
      incoming: incoming as T,
    );
    return _eraseChange(change);
  }

  @override
  SettingsTransferChange<Object?>? reprepareImport(
    SettingsTransferChange<Object?> change,
  ) {
    _validateChange(change);
    final incoming = change.incoming;
    final local = participant.readLocal();
    _validateValue(local, 'local');
    final next = participant.prepareImport(
      local: local,
      incoming: incoming as T,
    );
    return _eraseChange(next);
  }

  @override
  Future<void> applyImport(SettingsTransferChange<Object?> change) async {
    _validateChange(change);
    await participant.applyImport(change.writeValue as T);
  }

  @override
  SettingsTransferParticipant<R> participantAs<R>() {
    if (T != R) {
      throw StateError(
        'participant ${key.value} 的值类型是 $T，'
        '不能按 $R 读取',
      );
    }
    return participant as SettingsTransferParticipant<R>;
  }

  void _validateValue(Object? value, String name) {
    if (value is T) return;
    throw StateError(
      'participant ${key.value} 收到错误的 $name 类型：'
      '${value.runtimeType}，期望 $T',
    );
  }

  void _validateChange(SettingsTransferChange<Object?> change) {
    _validateValue(change.incoming, 'incoming');
    _validateValue(change.writeValue, 'writeValue');
  }

  SettingsTransferChange<Object?>? _eraseChange(
    SettingsTransferChange<T>? change,
  ) {
    if (change == null) return null;
    _validateValue(change.incoming, 'incoming');
    _validateValue(change.writeValue, 'writeValue');
    return change as SettingsTransferChange<Object?>;
  }
}
