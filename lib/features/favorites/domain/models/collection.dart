import 'package:equatable/equatable.dart';

/// 收藏夹，用于对收藏条目进行分类。
class FavoriteCollection extends Equatable {
  const FavoriteCollection({
    required this.id,
    required this.name,
    required this.createdAt,
  });

  final String id;
  final String name;
  final DateTime createdAt;

  /// 复制收藏夹，并允许覆盖单个字段。
  FavoriteCollection copyWith({String? id, String? name, DateTime? createdAt}) {
    return FavoriteCollection(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  List<Object> get props => [id, name, createdAt];
}
