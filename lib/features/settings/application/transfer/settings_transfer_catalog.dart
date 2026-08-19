import 'package:equatable/equatable.dart';

import 'settings_transfer_participant.dart';
import 'settings_transfer_types.dart';

/// 已注册 Settings transfer 分组的只读描述。
final class SettingsTransferGroupDescriptor extends Equatable {
  const SettingsTransferGroupDescriptor({
    required this.group,
    required this.containsSensitive,
  });

  final SettingsTransferGroup group;
  final bool containsSensitive;

  String get wireKey => group.wireKey;
  String get label => group.label;
  int get order => group.order;

  @override
  List<Object?> get props => [group, containsSensitive];
}

/// Settings transfer 的显式 participant 注册表。
final class SettingsTransferCatalog {
  SettingsTransferCatalog(Iterable<Object> participants) {
    final boxes = <ErasedSettingsTransferParticipant>[];
    final boxesByKey = <String, ErasedSettingsTransferParticipant>{};
    final ordersByGroup = <SettingsTransferGroup, Set<int>>{};

    for (final candidate in participants) {
      final box = SettingsTransferParticipantBox.erase(candidate);
      final key = box.key.value;
      if (!_validKey.hasMatch(key)) {
        throw ArgumentError.value(
          key,
          'participant.key',
          '必须符合 ASCII lower-camel 规则 [a-z][A-Za-z0-9]*',
        );
      }
      if (box.label.trim().isEmpty) {
        throw ArgumentError.value(box.label, 'participant.label', '不能是空白字符串');
      }
      if (boxesByKey.containsKey(key)) {
        throw ArgumentError.value(
          key,
          'participant.key',
          'participant key 不能重复',
        );
      }

      final orders = ordersByGroup.putIfAbsent(box.group, () => <int>{});
      if (!orders.add(box.order)) {
        throw ArgumentError.value(
          box.order,
          'participant.order',
          '同一分组内 order 不能重复',
        );
      }

      boxes.add(box);
      boxesByKey[key] = box;
    }

    boxes.sort(_compareParticipants);
    _participants = List<ErasedSettingsTransferParticipant>.unmodifiable(boxes);
    _participantsByKey =
        Map<String, ErasedSettingsTransferParticipant>.unmodifiable(boxesByKey);
    _groups = List<SettingsTransferGroupDescriptor>.unmodifiable(
      _buildGroupDescriptors(boxes),
    );
  }

  late final List<ErasedSettingsTransferParticipant> _participants;
  late final Map<String, ErasedSettingsTransferParticipant> _participantsByKey;
  late final List<SettingsTransferGroupDescriptor> _groups;

  List<SettingsTransferGroupDescriptor> get groups => _groups;

  List<ErasedSettingsTransferParticipant> participantsForGroups(
    Set<SettingsTransferGroup> groups,
  ) {
    final selected = _participants
        .where((participant) => groups.contains(participant.group))
        .toList(growable: false);
    return List<ErasedSettingsTransferParticipant>.unmodifiable(selected);
  }

  SettingsTransferParticipant<T> participant<T>(SettingsTransferKey key) {
    final box = _participantsByKey[key.value];
    if (box == null) {
      throw StateError('未注册 Settings transfer participant：${key.value}');
    }
    return box.participantAs<T>();
  }

  SettingsTransferGroup groupForKey(SettingsTransferKey key) {
    final box = _participantsByKey[key.value];
    if (box == null) {
      throw StateError('未注册 Settings transfer participant：${key.value}');
    }
    return box.group;
  }

  static int _compareParticipants(
    ErasedSettingsTransferParticipant left,
    ErasedSettingsTransferParticipant right,
  ) {
    final groupOrder = left.group.order.compareTo(right.group.order);
    if (groupOrder != 0) return groupOrder;
    final participantOrder = left.order.compareTo(right.order);
    if (participantOrder != 0) return participantOrder;
    return left.key.value.compareTo(right.key.value);
  }

  static List<SettingsTransferGroupDescriptor> _buildGroupDescriptors(
    Iterable<ErasedSettingsTransferParticipant> participants,
  ) {
    final sensitivityByGroup = <SettingsTransferGroup, bool>{};
    for (final participant in participants) {
      final hasSensitive =
          participant.sensitivity ==
          SettingsTransferSensitivity.credentialBearing;
      sensitivityByGroup.update(
        participant.group,
        (current) => current || hasSensitive,
        ifAbsent: () => hasSensitive,
      );
    }

    final registeredGroups = sensitivityByGroup.keys.toList()
      ..sort((left, right) => left.order.compareTo(right.order));
    return [
      for (final group in registeredGroups)
        SettingsTransferGroupDescriptor(
          group: group,
          containsSensitive: sensitivityByGroup[group]!,
        ),
    ];
  }
}

final _validKey = RegExp(r'^[a-z][A-Za-z0-9]*$');
