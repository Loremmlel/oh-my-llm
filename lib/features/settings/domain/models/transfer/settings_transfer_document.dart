import 'dart:convert';

import 'package:equatable/equatable.dart';

/// Settings transfer 的 canonical v9 文档，只保存不可变的 JSON-safe section。
final class SettingsTransferDocument extends Equatable {
  SettingsTransferDocument({required Map<String, Object?> sections})
    : sections = _freezeJsonObject(sections);

  static const identifier = 'shikiyuzu-oh-my-llm';
  static const formatVersion = 9;

  final Map<String, Object?> sections;

  Map<String, Object?> toJson() => Map.unmodifiable({
    'identifier': identifier,
    'formatVersion': formatVersion,
    'sections': sections,
  });

  @override
  List<Object?> get props => [jsonEncode(toJson())];
}

Map<String, Object?> _freezeJsonObject(Map<String, Object?> source) {
  final ancestors = Set<Object>.identity();
  return _freezeJsonMap(source, ancestors, validateSectionKeys: true);
}

Object? _freezeJsonValue(Object? value, Set<Object> ancestors) {
  if (value == null || value is bool || value is String) return value;
  if (value is num) {
    if (value is double && !value.isFinite) {
      throw ArgumentError.value(value, 'value', '必须是有限 JSON 数字');
    }
    return value;
  }
  if (value is List) {
    if (!ancestors.add(value)) {
      throw ArgumentError.value(value, 'value', 'JSON 值不能包含循环引用');
    }
    try {
      final frozen = <Object?>[];
      for (final item in value) {
        frozen.add(_freezeJsonValue(item, ancestors));
      }
      return List<Object?>.unmodifiable(frozen);
    } finally {
      ancestors.remove(value);
    }
  }
  if (value is Map) {
    return _freezeJsonMap(value, ancestors);
  }
  throw ArgumentError.value(value, 'value', '不是 JSON-safe 值');
}

Map<String, Object?> _freezeJsonMap(
  Map source,
  Set<Object> ancestors, {
  bool validateSectionKeys = false,
}) {
  if (!ancestors.add(source)) {
    throw ArgumentError.value(source, 'value', 'JSON 值不能包含循环引用');
  }
  try {
    final frozen = <String, Object?>{};
    for (final entry in source.entries) {
      final key = entry.key;
      if (key is! String) {
        throw ArgumentError.value(key, 'key', 'JSON object 的 key 必须是字符串');
      }
      if (validateSectionKeys && !_isValidSectionKey(key)) {
        throw ArgumentError.value(key, 'key', 'section key 语法无效');
      }
      frozen[key] = _freezeJsonValue(entry.value, ancestors);
    }
    return Map<String, Object?>.unmodifiable(frozen);
  } finally {
    ancestors.remove(source);
  }
}

/// 稳定 wire key 固定采用 ASCII lower-camel 规则：正则为
/// `[a-z][A-Za-z0-9]*`，首字符必须是小写英文字母，后续只能是英文字母或数字。
/// 需要下划线、连字符或大写首字母时，必须先有显式规格并提升 formatVersion。
bool _isValidSectionKey(String key) =>
    RegExp(r'^[a-z][A-Za-z0-9]*$').hasMatch(key);
