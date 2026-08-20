import 'package:equatable/equatable.dart';

/// Sync v4 wire payload 使用的稳定设置分组 ID。
final class SettingsSyncGroupId extends Equatable {
  const SettingsSyncGroupId(this.value);

  final String value;

  @override
  List<Object?> get props => [value];
}
