import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:oh_my_llm/core/persistence/has_id_and_updated_at.dart';

class WorldBookEntry extends Equatable {
  const WorldBookEntry({
    required this.id,
    required this.title,
    required this.content,
    this.enabled = true,
  });

  final String id;
  final String title;
  final String content;
  final bool enabled;

  WorldBookEntry copyWith({String? title, String? content, bool? enabled}) =>
      WorldBookEntry(
        id: id,
        title: title ?? this.title,
        content: content ?? this.content,
        enabled: enabled ?? this.enabled,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'content': content,
    'enabled': enabled,
  };

  factory WorldBookEntry.fromJson(Map<String, dynamic> json) => WorldBookEntry(
    id: json['id'] as String,
    title: json['title'] as String,
    content: json['content'] as String,
    enabled: json['enabled'] as bool? ?? true,
  );

  @override
  List<Object> get props => [id, title, content, enabled];
}

/// 条目数组顺序就是注入顺序；请求只读取启用条目，不进行动态匹配。
class WorldBook extends Equatable with HasIdAndUpdatedAt {
  WorldBook({
    required this.id,
    required this.name,
    required List<WorldBookEntry> entries,
    required this.updatedAt,
  }) : entries = List.unmodifiable(entries);

  @override
  final String id;
  final String name;
  final List<WorldBookEntry> entries;
  @override
  final DateTime updatedAt;

  WorldBook copyWith({
    String? name,
    List<WorldBookEntry>? entries,
    DateTime? updatedAt,
  }) => WorldBook(
    id: id,
    name: name ?? this.name,
    entries: entries ?? this.entries,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'entries': entries.map((entry) => entry.toJson()).toList(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory WorldBook.fromJson(Map<String, dynamic> json) => WorldBook(
    id: json['id'] as String,
    name: json['name'] as String,
    entries: (json['entries'] as List)
        .map(
          (entry) =>
              WorldBookEntry.fromJson(Map<String, dynamic>.from(entry as Map)),
        )
        .toList(),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
  );

  /// 只使用已保存的标题、正文与顺序，避免每轮引入变化破坏缓存前缀。
  String get promptContent {
    final active = entries.where(
      (entry) => entry.enabled && entry.content.trim().isNotEmpty,
    );
    if (active.isEmpty) return '';
    const escape = HtmlEscape(HtmlEscapeMode.attribute);
    return '<world_book name="${escape.convert(name)}">\n'
        '${active.map((entry) => '<entry title="${escape.convert(entry.title)}">\n${entry.content}\n</entry>').join('\n')}\n'
        '</world_book>';
  }

  @override
  List<Object> get props => [id, name, entries, updatedAt];
}
