import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/core/constants/app_reserved_entities.dart';
import 'package:oh_my_llm/features/favorites/domain/models/collection.dart';
import 'package:oh_my_llm/features/favorites/domain/models/favorite_collection_summary.dart';
import 'package:oh_my_llm/features/favorites/presentation/widgets/favorite_collection_grid.dart';

void main() {
  for (final entry in {
    AppReservedEntities.uncategorizedFavoriteCollectionId: '未分类',
    'ordinary': '保留人物关系和长篇情节的写作参考收藏夹',
  }.entries) {
    testWidgets('大字号下${entry.value}卡片仍可阅读和打开', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final date = DateTime(2026, 10, 8);
      var opened = false;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(1.5)),
            child: child!,
          ),
          home: Scaffold(
            body: FavoriteCollectionGrid(
              summaries: [
                FavoriteCollectionSummary(
                  collection: FavoriteCollection(
                    id: entry.key,
                    name: entry.value,
                    createdAt: date,
                  ),
                  itemCount: 1,
                  recentAssignedAt: date,
                ),
              ],
              onOpen: (_) => opened = true,
              onRename: (_) {},
              onDelete: (_) {},
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('1 项收藏'), findsOneWidget);
      await tester.tap(find.text(entry.value));
      await tester.pump();
      expect(opened, isTrue);
    });
  }
}
