import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oh_my_llm/core/constants/app_layout_tokens.dart';
import 'package:oh_my_llm/core/widgets/dialogs/app_confirm_dialog.dart';
import 'package:oh_my_llm/core/widgets/app_field_group.dart';

import '../application/agent_workspace_controller.dart';
import '../domain/agent_models.dart';
import '../domain/agent_script.dart';

const agentScriptExample = '''---
name: 秋季校园风波
description: 高一秋季加入文学社后相关，事件跨越两个月。
---

# 秋季校园风波

文学社收到匿名投稿，暂不揭露投稿人。

## 数周后
从收到投稿之日起数周后，筹备会上发生署名争议。
期间可以继续日常 RP，不需要直接跳过这些日子。

## 两个月后
校刊出版时，人物必须面对争议的后果。
''';

Future<void> showAgentDocumentEditor(
  BuildContext context, {
  AgentDocument? document,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _DocumentEditor(document: document),
);

class _DocumentEditor extends ConsumerStatefulWidget {
  const _DocumentEditor({this.document});
  final AgentDocument? document;
  @override
  ConsumerState<_DocumentEditor> createState() => _DocumentEditorState();
}

class _DocumentEditorState extends ConsumerState<_DocumentEditor> {
  late final _name = TextEditingController(text: widget.document?.name ?? '');
  late final _content = TextEditingController(
    text: widget.document?.content ?? '',
  );
  late AgentDocumentKind _kind =
      widget.document?.kind ?? AgentDocumentKind.document;
  bool _allowClose = false;
  bool get _dirty =>
      _name.text != (widget.document?.name ?? '') ||
      _content.text != (widget.document?.content ?? '') ||
      _kind != (widget.document?.kind ?? AgentDocumentKind.document);
  @override
  void dispose() {
    _name.dispose();
    _content.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    if (_dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (_) => const AppConfirmDialog(
          title: '放弃未保存的修改？',
          message: '已保存的文档不受影响。',
          confirmLabel: '放弃修改',
        ),
      );
      if (discard != true || !mounted) return;
    }
    if (mounted) {
      setState(() => _allowClose = true);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(agentWorkspaceProvider);
    final controller = ref.read(agentWorkspaceProvider.notifier);
    return PopScope<void>(
      canPop: _allowClose,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: AlertDialog(
        title: Text(widget.document == null ? '新建文档' : '编辑文档'),
        content: SizedBox(
          width: AppContentWidths.readable,
          height: 480,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppFieldGroup(
                children: [
                  if (_kind != AgentDocumentKind.script)
                    TextField(
                      controller: _name,
                      readOnly: widget.document != null,
                      decoration: const InputDecoration(labelText: '文档名'),
                    ),
                  DropdownButtonFormField<AgentDocumentKind>(
                    key: ValueKey('kind/$_kind'),
                    initialValue: _kind,
                    decoration: const InputDecoration(labelText: '资料类型'),
                    isExpanded: true,
                    borderRadius: BorderRadius.circular(AppRadii.sm),
                    items: [
                      for (final kind in AgentDocumentKind.values)
                        DropdownMenuItem(
                          value: kind,
                          child: Text(agentDocumentKindLabel(kind)),
                        ),
                    ],
                    onChanged: state.busy
                        ? null
                        : (kind) {
                            if (kind != null) setState(() => _kind = kind);
                          },
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              if (_kind == AgentDocumentKind.script)
                Row(
                  children: [
                    const Expanded(
                      child: Text('开头用 --- 包围 name、description；名称取自 name。'),
                    ),
                    TextButton(
                      onPressed: state.busy
                          ? null
                          : () => showDialog<void>(
                              context: context,
                              builder: (_) => AlertDialog(
                                title: const Text('剧本 Markdown 示例'),
                                content: const SingleChildScrollView(
                                  child: SelectableText(agentScriptExample),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(context).pop(),
                                    child: const Text('关闭'),
                                  ),
                                ],
                              ),
                            ),
                      child: const Text('查看示例'),
                    ),
                  ],
                ),
              if (_kind == AgentDocumentKind.script)
                const SizedBox(height: AppSpacing.sm),
              Expanded(
                child: TextField(
                  controller: _content,
                  expands: true,
                  minLines: null,
                  maxLines: null,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: InputDecoration(
                    labelText: _kind == AgentDocumentKind.characterCard
                        ? '作者设定'
                        : '正文',
                    alignLabelWithHint: true,
                  ),
                ),
              ),
              if (_kind != AgentDocumentKind.document)
                Text(
                  _kind == AgentDocumentKind.script
                      ? '元信息在下次主任务末尾追加，全文按需读取并保留。'
                      : '保存后覆盖当前内容，下次运行立即采用。',
                ),
              if (state.error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    state.error,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          if (_kind == AgentDocumentKind.script && widget.document != null)
            TextButton(
              onPressed: () {
                final progress = controller.scriptProgressFor(widget.document!);
                showDialog<void>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('本作品剧本备忘'),
                    content: SingleChildScrollView(
                      child: SelectableText(
                        progress == null
                            ? '当前内容尚无备忘。主 Agent 读取剧本后可记录时间起点、未兑现约定与完成依据；进度随作品保留，压缩后仍会提供有效备忘。'
                            : '${progress.status.label}\n\n${progress.notes}\n\n来源正文：${progress.sourceRoundIds.isEmpty ? '无（仅计划）' : progress.sourceRoundIds.join('、')}',
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('关闭'),
                      ),
                    ],
                  ),
                );
              },
              child: const Text('剧本备忘'),
            ),
          TextButton(onPressed: _close, child: const Text('取消')),
          FilledButton(
            onPressed: state.busy
                ? null
                : () {
                    controller.saveDocument(
                      _name.text.trim(),
                      _content.text,
                      kind: _kind,
                      documentId: widget.document?.id,
                    );
                    if (ref.read(agentWorkspaceProvider).error.isEmpty) {
                      setState(() => _allowClose = true);
                      Navigator.of(context).pop();
                    }
                  },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}

String agentDocumentKindLabel(AgentDocumentKind kind) => switch (kind) {
  AgentDocumentKind.document => '普通文档',
  AgentDocumentKind.worldBook => '世界书',
  AgentDocumentKind.characterCard => '人物卡',
  AgentDocumentKind.script => '剧本',
};
