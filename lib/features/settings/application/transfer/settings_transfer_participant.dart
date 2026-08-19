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
    required this.participant,
    required this.incoming,
    required this.writeValue,
    required this.fingerprint,
    required this.summary,
  });

  final SettingsTransferParticipant<T> participant;
  final T incoming;
  final T writeValue;
  final String fingerprint;
  final SettingsTransferSummaryItem summary;

  /// 供 application-internal 类型擦除适配器校验 change 的泛型参数。
  Type get valueType => T;
}

/// Settings application 内部的运行时类型校验能力，不属于 participant 公共契约。
abstract interface class SettingsTransferParticipantRuntime {
  Type get valueType;

  bool acceptsValue(Object? value);
}

/// 以完整值替换本地设置的通用 participant 策略。
///
/// 具体 participant 仍负责读取、编解码、等价判断和持久化；本类只统一
/// no-op、replace/clear 摘要和待写入指纹语义。
abstract class ReplacingValueParticipant<T>
    implements
        SettingsTransferParticipant<T>,
        SettingsTransferParticipantRuntime {
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
  Type get valueType => T;

  @override
  bool acceptsValue(Object? value) => value is T;

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
      participant: this,
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
    implements
        SettingsTransferParticipant<List<T>>,
        SettingsTransferParticipantRuntime {
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

  @override
  Type get valueType => List<T>;

  @override
  bool acceptsValue(Object? value) => value is List<T>;

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
      participant: this,
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
///
/// 该类型只允许出现在 Settings application transfer 边界内；presentation
/// 与 Sync 不应依赖它，也不应自行执行类型转换。
abstract interface class ErasedSettingsTransferParticipant {
  SettingsTransferKey get key;
  SettingsTransferGroup get group;
  String get label;
  int get order;
  SettingsTransferSensitivity get sensitivity;

  Object? encodeLocalIfExportable();
  Object? decodePayload(Object? payload);
  SettingsTransferChange<Object?>? prepareImport(Object? incoming);
  SettingsTransferChange<Object?>? reprepareImport(
    SettingsTransferChange<Object?> change,
  );
  Future<void> applyImport(SettingsTransferChange<Object?> change);

  SettingsTransferParticipant<T> participantAs<T>();
}

/// Settings application 内部唯一允许执行 participant 类型擦除/恢复的 box。
///
/// [T] 在 catalog 的统一遍历中通常被擦除为 dynamic；真实值类型仍由底层
/// participant 的 [SettingsTransferParticipant.valueType] 和 [acceptsValue]
/// 在每次边界操作前校验。
final class SettingsTransferParticipantBox<T>
    implements ErasedSettingsTransferParticipant {
  SettingsTransferParticipantBox(this.participant);

  /// 将直接 participant 或已构造的 erased box 绑定到 application 边界。
  ///
  /// 该入口故意位于 box 内，使 catalog 不需要执行任何 participant payload
  /// 或 change 的类型转换。
  static ErasedSettingsTransferParticipant erase(Object candidate) {
    if (candidate is ErasedSettingsTransferParticipant) return candidate;
    if (candidate is! SettingsTransferParticipant<dynamic>) {
      throw ArgumentError.value(
        candidate,
        'participant',
        '必须是 SettingsTransferParticipant 或 erased participant box',
      );
    }
    return SettingsTransferParticipantBox<dynamic>(candidate);
  }

  final SettingsTransferParticipant<T> participant;

  Type? get _registeredValueType {
    final candidate = participant;
    if (candidate is SettingsTransferParticipantRuntime) {
      final runtimeParticipant =
          candidate as SettingsTransferParticipantRuntime;
      return runtimeParticipant.valueType;
    }
    return null;
  }

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
  Object? encodeLocalIfExportable() {
    final value = participant.readLocal();
    if (!participant.shouldExport(value)) return null;
    final encoded = participant.encode(value);
    return encoded;
  }

  @override
  Object? decodePayload(Object? payload) => participant.decode(payload);

  @override
  SettingsTransferChange<Object?>? prepareImport(Object? incoming) {
    _validateValue(incoming, 'incoming');
    final local = participant.readLocal();
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
    _validateValue(incoming, 'incoming');
    final next = participant.prepareImport(
      local: participant.readLocal(),
      incoming: incoming as T,
    );
    return _eraseChange(next);
  }

  @override
  Future<void> applyImport(SettingsTransferChange<Object?> change) async {
    _validateChange(change);
    _validateValue(change.writeValue, 'writeValue');
    await participant.applyImport(change.writeValue as T);
  }

  @override
  SettingsTransferParticipant<R> participantAs<R>() {
    final registeredValueType = _registeredValueType;
    if (registeredValueType != null && registeredValueType != R) {
      throw StateError(
        'participant ${key.value} 的值类型是 $registeredValueType，'
        '不能按 $R 读取',
      );
    }
    try {
      return participant as SettingsTransferParticipant<R>;
    } catch (_) {
      throw StateError('participant ${key.value} 的值类型与请求的 $R 不匹配');
    }
  }

  void _validateValue(Object? value, String name) {
    final candidate = participant;
    if (candidate is! SettingsTransferParticipantRuntime) {
      return;
    }
    final runtimeParticipant = candidate as SettingsTransferParticipantRuntime;
    if (runtimeParticipant.acceptsValue(value)) return;
    final registeredValueType = _registeredValueType;
    if (registeredValueType != null) {
      throw StateError(
        'participant ${key.value} 收到错误的 $name 类型：'
        '${value.runtimeType}，期望 $registeredValueType',
      );
    }
  }

  void _validateChange(SettingsTransferChange<Object?> change) {
    if (!identical(change.participant, participant)) {
      throw StateError('participant ${key.value} 的 change 来源不匹配');
    }
    final registeredValueType = _registeredValueType;
    if (registeredValueType != null &&
        change.valueType != registeredValueType) {
      throw StateError(
        'participant ${key.value} 的 change 类型是 ${change.valueType}，'
        '期望 $registeredValueType',
      );
    }
  }

  SettingsTransferChange<Object?>? _eraseChange(
    SettingsTransferChange<T>? change,
  ) {
    if (change == null) return null;
    return change as SettingsTransferChange<Object?>;
  }
}
