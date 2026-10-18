import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:oh_my_llm/app/theme/app_theme.dart';
import 'package:oh_my_llm/core/llm/llm_usage.dart';
import 'package:oh_my_llm/core/llm/llm_usage_summary.dart';
import 'package:oh_my_llm/core/widgets/llm_usage_widgets.dart';
import 'package:oh_my_llm/features/agent/domain/agent_models.dart';
import 'package:oh_my_llm/features/agent/presentation/agent_transcript.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';
import 'package:oh_my_llm/features/chat/presentation/widgets/messages/bubble/chat_message_bubble.dart';

void main() => runApp(usageMetricsPreview());

@Preview(name: '回复速度与对话总量 · 桌面', group: '用量', size: Size(900, 800))
@Preview(name: '回复速度与对话总量 · 手机', group: '用量', size: Size(390, 844))
Widget usageMetricsPreview() => const _UsageMetricsPreview();

class _UsageMetricsPreview extends StatefulWidget {
  const _UsageMetricsPreview();

  @override
  State<_UsageMetricsPreview> createState() => _UsageMetricsPreviewState();
}

class _UsageMetricsPreviewState extends State<_UsageMetricsPreview> {
  bool dark = false;

  static const usage = LlmUsage(
    inputTokens: 12400,
    cachedInputTokens: 9600,
    cacheWriteInputTokens: 1200,
    outputTokens: 840,
    outputDuration: Duration(seconds: 12),
  );

  @override
  Widget build(BuildContext context) {
    final run = AgentRunRecord(
      id: 'preview-run',
      workspaceId: 'preview',
      prompt: '继续写下一段。',
      startedAt: DateTime(2026),
      status: AgentRunStatus.completed,
      content: '林知夏把蓝色素材本放到窗边，等雨停了再出门。',
      usage: const AgentRunUsage(modelCalls: 1, tokens: usage),
      steps: const [
        AgentStep(
          label: '模型回复 1',
          content: '林知夏把蓝色素材本放到窗边，等雨停了再出门。',
          usage: usage,
        ),
      ],
    );
    return MaterialApp(
      theme: AppTheme.lightTheme(),
      darkTheme: AppTheme.darkTheme(),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      home: Scaffold(
        appBar: AppBar(
          title: const Text('对话用量预览'),
          actions: [
            IconButton(
              tooltip: '切换主题',
              onPressed: () => setState(() => dark = !dark),
              icon: const Icon(Icons.brightness_6_outlined),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Chat'),
            ConversationTokenUsage(
              summary: LlmUsageSummary.fromUsages([usage, usage]),
            ),
            ChatMessageBubble(
              message: ChatMessage(
                id: 'preview-reply',
                role: ChatMessageRole.assistant,
                content: '先把今天的小事记下来，明天再一起接着写。',
                createdAt: DateTime(2026),
                assistantModelDisplayName: '写作模型',
                tokenUsage: usage,
              ),
            ),
            const Divider(),
            const Text('Agent'),
            ConversationTokenUsage(
              summary: LlmUsageSummary.fromUsages([usage]),
            ),
            SizedBox(
              height: 320,
              child: AgentTranscript(records: [run], allRuns: [run]),
            ),
            const Divider(),
            const Text('空对话与部分用量'),
            const ConversationTokenUsage(summary: LlmUsageSummary()),
            ConversationTokenUsage(
              summary: LlmUsageSummary.fromUsages([usage, null]),
            ),
          ],
        ),
      ),
    );
  }
}
