import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/chat/application/composer_draft_controller.dart';

/// 让派生 Provider 的监听通知落定（Riverpod 3 对派生 provider 的 notify 是
/// 异步微任务，不 flush 时同步断言会过早读到 0）。
Future<void> _flushMicrotasks() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('ComposerDraftController per-conversation aggregate', () {
    late ProviderContainer container;
    late ComposerDraftController controller;

    setUp(() {
      container = ProviderContainer();
      controller = container.read(composerDraftProvider.notifier);
    });

    tearDown(() => container.dispose());

    test('A/B 会话 body 与同名模板变量互不覆盖，切回 A 读到 A 的完整 draft', () {
      controller.setBody('conv-a', 'A 正文');
      controller.setBody('conv-b', 'B 正文');
      controller.setTemplateVariable('conv-a', 'tpl-1', 'title', '甲');
      controller.setTemplateVariable('conv-b', 'tpl-1', 'title', '乙');

      final a = controller.draftFor('conv-a');
      final b = controller.draftFor('conv-b');
      expect(a.body, 'A 正文');
      expect(b.body, 'B 正文');
      expect(a.templateVariableValuesByTemplateId['tpl-1']?['title'], '甲');
      expect(b.templateVariableValuesByTemplateId['tpl-1']?['title'], '乙');
    });

    test('selection 是 conversation-scoped', () {
      controller.selectTemplate('conv-a', 'tpl-a');
      expect(controller.draftFor('conv-b').selectedTemplatePromptId, isNull);
      controller.selectTemplate('conv-b', 'tpl-b');
      expect(controller.draftFor('conv-a').selectedTemplatePromptId, 'tpl-a');
      expect(controller.draftFor('conv-b').selectedTemplatePromptId, 'tpl-b');
    });

    test('暴露的外层/内层 Map 不可变，旧 state 不受 mutation 影响', () {
      controller.setBody('conv-a', '正文');
      controller.setTemplateVariable('conv-a', 'tpl-1', 'title', '甲');
      final stateBefore = container.read(composerDraftProvider);

      expect(
        () =>
            stateBefore
                    .draftsByConversationId['conv-a']!
                    .templateVariableValuesByTemplateId['tpl-1']!['title'] =
                '改',
        throwsUnsupportedError,
      );
      expect(stateBefore.draftsByConversationId['conv-a']!.body, '正文');
    });

    test('只监听 select 的 derived family：正文/变量写入不触发 selection listener', () async {
      var selectionChanges = 0;
      container.listen(
        composerTemplateSelectionProvider('conv-a'),
        (_, _) => selectionChanges++,
      );
      controller.setBody('conv-a', '正文');
      controller.setTemplateVariable('conv-a', 'tpl-1', 'title', '甲');
      await _flushMicrotasks();
      expect(selectionChanges, 0);

      controller.selectTemplate('conv-a', 'tpl-a');
      await _flushMicrotasks();
      expect(selectionChanges, 1);

      controller.selectTemplate('conv-b', 'tpl-b'); // 不同会话
      await _flushMicrotasks();
      expect(selectionChanges, 1);
    });

    test('dispose 后新建 provider container，draft 为空（证明非 App 持久态）', () {
      controller.setBody('conv-a', '正文');
      container.dispose();

      final fresh = ProviderContainer();
      addTearDown(fresh.dispose);
      expect(
        fresh.read(composerDraftProvider.notifier).draftFor('conv-a'),
        ComposerDraft.empty,
      );
    });

    test('clearBody 保留模板选择与变量，clearDraft 整体清空', () {
      controller.setBody('conv-a', '正文');
      controller.selectTemplate('conv-a', 'tpl-a');
      controller.setTemplateVariable('conv-a', 'tpl-a', 'title', '甲');
      controller.clearBody('conv-a');
      var draft = controller.draftFor('conv-a');
      expect(draft.body, '');
      expect(draft.selectedTemplatePromptId, 'tpl-a');
      expect(draft.templateVariableValuesByTemplateId['tpl-a'], isNotEmpty);

      controller.clearDraft('conv-a');
      draft = controller.draftFor('conv-a');
      expect(draft, ComposerDraft.empty);
    });

    test('replaceDraft 存入 state 后，外部对原 draft 内层 map 的修改不可见', () {
      final notifier = container.read(composerDraftProvider.notifier);
      final mutableInner = <String, String>{'title': '甲'};
      final draft = ComposerDraft(
        body: '正文',
        templateVariableValuesByTemplateId: {'tp-1': mutableInner},
      );
      notifier.replaceDraft('conv-a', draft);

      // 修改外部 map：state 内的 draft 不得受影响。
      mutableInner['title'] = '乙';
      final stored = notifier.draftFor('conv-a');
      expect(stored.templateVariableValuesByTemplateId['tp-1']?['title'], '甲');
      // 且 state 内的内层 map 不可变。
      expect(
        () => stored.templateVariableValuesByTemplateId['tp-1']!['title'] = '丙',
        throwsUnsupportedError,
      );
    });
  });
}
