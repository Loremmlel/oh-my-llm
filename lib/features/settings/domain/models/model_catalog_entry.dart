import 'package:equatable/equatable.dart';

/// 可供设置页展示和选择的远程模型目录项。
final class ModelCatalogEntry extends Equatable {
  const ModelCatalogEntry({required this.id, this.ownedBy});

  final String id;
  final String? ownedBy;

  @override
  List<Object?> get props => [id, ownedBy];
}
