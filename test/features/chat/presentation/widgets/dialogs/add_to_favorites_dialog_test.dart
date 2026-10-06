import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/chat/application/favorites/chat_favorites_facade.dart';
import 'package:oh_my_llm/features/chat/presentation/widgets/dialogs/add_to_favorites_dialog.dart';

import '../../../../../helpers/async/widget_test_animation.dart';

void main() {
  testWidgets('手机键盘弹出后新建收藏夹可触摸滚动且取消始终可达', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 640);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<String>(
                context: context,
                builder: (_) => AddToFavoritesDialog(
                  collections: [
                    for (var i = 1; i <= 12; i++)
                      ChatFavoriteCollectionOption(id: 'col-$i', name: '收藏夹$i'),
                  ],
                  initialCollectionId: 'col-1',
                  onCreateCollection: (_) => 'new-collection',
                ),
              ),
              child: const Text('打开收藏'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开收藏'));
    await settleOverlayTransition(tester);
    await tester.ensureVisible(find.text('新建收藏夹'));
    await tester.tap(find.text('新建收藏夹'));
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await settleOverlayTransition(tester);
    expect(tester.takeException(), isNull);
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -600),
    );
    await settleScrollMotion(tester);
    expect(find.byType(TextField).hitTestable(), findsOneWidget);
    await tester.enterText(find.byType(TextField), '新收藏夹');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.text('收藏到'), findsOneWidget);
    expect(find.text('取消').hitTestable(), findsOneWidget);
    await tester.tap(find.text('取消'));
    await settleOverlayTransition(tester);
    expect(find.text('收藏到'), findsNothing);
  });
}
