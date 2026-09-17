import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/agent/application/agent_workspace_controller.dart';
import 'package:oh_my_llm/features/agent/domain/agent_models.dart';
import 'package:oh_my_llm/features/agent/domain/agent_story_state.dart';
import 'package:oh_my_llm/features/agent/presentation/agent_story_panel.dart';

import '../../../helpers/async/widget_test_animation.dart';

void main() {
  testWidgets('数百楼正文按需读取，滚动后可展开原文和继续浏览轮次历史', (tester) async {
    var reads = 0;
    final workspace = AgentWorkspace(id: 'novel', title: '长篇');
    final state = AgentWorkspaceState(
      workspace: workspace,
      storyRounds: [
        for (var i = 299; i >= 0; i--)
          AgentStoryRound(
            id: 'round-$i',
            beforeWorkspace: workspace,
            document: _ObservedDocument('第 $i 楼', () => reads++),
            beforeState: AgentStoryState(),
            stateAgentId: 'state-$i',
            status: AgentStoryRoundStatus.committed,
          ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          agentWorkspaceProvider.overrideWith(() => _SeededController(state)),
        ],
        child: const MaterialApp(home: Scaffold(body: AgentStoryPanel())),
      ),
    );
    await tester.pump();
    expect(reads, lessThan(20), reason: '屏幕外的正文不应为了创建折叠条目而全部读取');
    await tester.scrollUntilVisible(find.text('第 299 楼'), 500, maxScrolls: 100);
    await tester.tap(find.widgetWithText(ExpansionTile, '第 299 楼'));
    await settleAnimatedWidgetTransition(tester);
    expect(
      find.textContaining('这是第 299 楼的原文', findRichText: true),
      findsWidgets,
    );
    await tester.scrollUntilVisible(find.text('轮次历史'), 300);
    await tester.tap(find.text('轮次历史'));
    await settleAnimatedWidgetTransition(tester);
    await tester.scrollUntilVisible(find.text('加载更多轮次').hitTestable(), 300);
    await tester.pump();
    await tester.tap(find.text('加载更多轮次'));
    await tester.pump();
    expect(find.text('第 260 楼'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.widgetWithText(ListTile, '第 260 楼').hitTestable(),
      300,
    );
    expect(find.widgetWithText(ListTile, '第 260 楼'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _ObservedDocument extends AgentDocument {
  const _ObservedDocument(String name, this.onRead)
    : super(name: name, content: '');
  final VoidCallback onRead;
  @override
  String get content {
    onRead();
    return '这是$name的原文';
  }
}

class _SeededController extends AgentWorkspaceController {
  _SeededController(this.initial);
  final AgentWorkspaceState initial;
  @override
  AgentWorkspaceState build() => initial;
}
