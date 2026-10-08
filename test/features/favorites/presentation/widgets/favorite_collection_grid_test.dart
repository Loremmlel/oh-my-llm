import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/core/constants/app_reserved_entities.dart';
import 'package:oh_my_llm/core/utils/date_formatting.dart';
import 'package:oh_my_llm/features/favorites/domain/models/collection.dart';
import 'package:oh_my_llm/features/favorites/domain/models/favorite_collection_summary.dart';
import 'package:oh_my_llm/features/favorites/presentation/widgets/favorite_collection_grid.dart';

void main() {
  testWidgets('重复布局复用文字测量，内容与字号变化后重新测量', (tester) async {
    final date = DateTime(2026, 10, 8);
    var summaries = List.generate(
      1000,
      (index) => FavoriteCollectionSummary(
        collection: FavoriteCollection(
          id: 'collection-$index',
          name: '收藏夹$index',
          createdAt: date,
        ),
        itemCount: 1,
        recentAssignedAt: date,
      ),
    );
    var measurementCalls = 0;
    var scaler = _CountingTextScaler(1.5, () => measurementCalls++);
    var height = 600.0;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return MediaQuery(
                data: MediaQuery.of(context).copyWith(textScaler: scaler),
                child: SizedBox(
                  width: 320,
                  height: height,
                  child: FavoriteCollectionGrid(
                    summaries: summaries,
                    onOpen: (_) {},
                    onRename: (_) {},
                    onDelete: (_) {},
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    expect(measurementCalls, greaterThan(1000));
    measurementCalls = 0;
    update(() {
      height = 590;
      summaries = List.of(summaries);
    });
    await tester.pump();
    expect(measurementCalls, lessThan(1000));

    update(
      () => summaries = [
        ...summaries,
        FavoriteCollectionSummary(
          collection: FavoriteCollection(
            id: 'new',
            name: '新收藏夹',
            createdAt: date,
          ),
          itemCount: 1,
          recentAssignedAt: date,
        ),
      ],
    );
    await tester.pump();
    expect(measurementCalls, greaterThan(1000));
    measurementCalls = 0;
    update(() => scaler = _CountingTextScaler(2, () => measurementCalls++));
    await tester.pump();
    expect(measurementCalls, greaterThan(1000));
    expect(tester.takeException(), isNull);
  });

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
      expect(find.text(formatDateOnly(date)).hitTestable(), findsOneWidget);
      await tester.tap(find.text(entry.value));
      await tester.pump();
      expect(opened, isTrue);
    });
  }
}

class _CountingTextScaler extends TextScaler {
  const _CountingTextScaler(this.factor, this.onScale);

  final double factor;
  final VoidCallback onScale;

  @override
  double scale(double fontSize) {
    onScale();
    return fontSize * factor;
  }

  @override
  double get textScaleFactor => factor;
}
