import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/worldbooks/world_books_controller.dart';
import 'widgets/worldbooks/world_book_editor.dart';

class WorldBookEditorScreen extends ConsumerWidget {
  const WorldBookEditorScreen({this.worldBookId, super.key});
  final String? worldBookId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final book = resolveWorldBook(ref.watch(worldBooksProvider), worldBookId);
    if (worldBookId != null && book == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('世界书不存在')),
        body: const Center(child: Text('该世界书已被删除，请返回世界书列表。')),
      );
    }
    return WorldBookEditor(
      initialValue: book,
      onSubmit: ref.read(worldBooksProvider.notifier).upsert,
    );
  }
}
