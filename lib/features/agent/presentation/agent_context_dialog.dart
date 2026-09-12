import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oh_my_llm/core/constants/app_layout_tokens.dart';

import '../application/agent_context.dart';
import '../application/agent_harness.dart';
import '../application/agent_workspace_controller.dart';
import '../domain/agent_models.dart';

Future<void> showAgentContext(
  BuildContext context, {
  AgentRunRecord? record,
  AgentStep? step,
}) => showDialog<void>(
  context: context,
  builder: (_) => _ContextDialog(record: record, step: step),
);

class _ContextDialog extends ConsumerWidget {
  const _ContextDialog({this.record, this.step});
  final AgentRunRecord? record;
  final AgentStep? step;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(agentWorkspaceProvider.notifier);
    String text;
    final tools = record?.tools ?? agentMainTools;
    try {
      final input = record == null
          ? controller.previewInput()
          : controller.runInput(record!, step!);
      text = input == null ? '此旧记录没有保存输入边界，无法重建实际输入。' : agentInputText(input);
    } catch (_) {
      text = '无法读取上下文，请检查本地存储后重试。';
    }
    return AlertDialog(
      title: Text(record == null ? '下一次输入预览' : '${step!.label}的实际输入'),
      content: SizedBox(
        width: AppContentWidths.readable,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (record != null)
                Text(
                  record!.modelLabel.isEmpty
                      ? '旧记录未保存模型名称'
                      : record!.modelLabel,
                ),
              Text('可读内容 ${text.length} 字符 · ${utf8.encode(text).length} 字节'),
              const Text('显示实际输入的可读部分；不展示协议签名等私有字段。字符数不是 Token 用量。'),
              const SizedBox(height: AppSpacing.sm),
              SelectableText(text),
              ExpansionTile(
                title: const Text('工具定义'),
                children: [
                  SelectableText(
                    const JsonEncoder.withIndent('  ').convert([
                      for (final tool in tools)
                        {
                          'name': tool.name,
                          'description': tool.description,
                          'parameters': tool.parameters,
                        },
                    ]),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}
