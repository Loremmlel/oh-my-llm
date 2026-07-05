/// 表示实体具有 [id] 和 [updatedAt] 字段的 mixin。
///
/// 用于 [SettingsEntityController] 的泛型约束，保证编译期类型安全。
mixin HasIdAndUpdatedAt {
  String get id;
  DateTime get updatedAt;
}
