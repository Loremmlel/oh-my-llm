import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oh_my_llm/core/constants/app_layout_tokens.dart';
import 'package:oh_my_llm/core/widgets/dialogs/app_confirm_dialog.dart';

import '../application/agent_workspace_controller.dart';
import '../domain/agent_models.dart';

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
  late int _revision = widget.document?.revision ?? 0;
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
          message: '已保存的文档版本不受影响。',
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
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _name,
                  readOnly: widget.document != null,
                  decoration: const InputDecoration(labelText: '文档名'),
                ),
                const SizedBox(height: AppSpacing.sm),
                DropdownButtonFormField<AgentDocumentKind>(
                  key: ValueKey('kind/$_kind'),
                  initialValue: _kind,
                  decoration: const InputDecoration(labelText: '资料类型'),
                  isExpanded: true,
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
                const SizedBox(height: AppSpacing.sm),
                if (widget.document != null)
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '正在查看版本 $_revision / ${widget.document!.revision}',
                        ),
                      ),
                      IconButton(
                        tooltip: '上一版本',
                        onPressed: _revision > 1
                            ? () => _loadVersion(_revision - 1)
                            : null,
                        icon: const Icon(Icons.chevron_left),
                      ),
                      IconButton(
                        tooltip: '下一版本',
                        onPressed: _revision < widget.document!.revision
                            ? () => _loadVersion(_revision + 1)
                            : null,
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                TextField(
                  controller: _content,
                  minLines: 10,
                  maxLines: 20,
                  decoration: InputDecoration(
                    labelText: _kind == AgentDocumentKind.characterCard
                        ? '作者设定'
                        : '正文',
                    alignLabelWithHint: true,
                  ),
                ),
                if (_kind != AgentDocumentKind.document)
                  const Text('世界书和人物卡在新会话开始时采用最新版本；已有会话继续使用原版本。'),
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
        ),
        actions: [
          TextButton(onPressed: _close, child: const Text('取消')),
          FilledButton(
            onPressed: state.busy
                ? null
                : () {
                    controller.saveDocument(
                      _name.text.trim(),
                      _content.text,
                      widget.document?.revision ?? 0,
                      kind: _kind,
                    );
                    if (ref.read(agentWorkspaceProvider).error.isEmpty) {
                      setState(() => _allowClose = true);
                      Navigator.of(context).pop();
                    }
                  },
            child: const Text('保存新版本'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadVersion(int revision) async {
    // 查看历史可能覆盖编辑框，先保护尚未保存的输入。
    final current = ref
        .read(agentWorkspaceProvider.notifier)
        .readRevision(_name.text, _revision);
    if (current != null &&
        (_content.text != current.content || _kind != current.kind)) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (_) => const AppConfirmDialog(
          title: '放弃编辑后查看历史？',
          message: '编辑框中未保存的内容将被历史版本替换。',
          confirmLabel: '查看历史',
        ),
      );
      if (discard != true || !mounted) return;
    }
    final document = ref
        .read(agentWorkspaceProvider.notifier)
        .readRevision(_name.text, revision);
    if (document != null) {
      setState(() {
        _revision = revision;
        _content.text = document.content;
        _kind = document.kind;
      });
    }
  }
}

String agentDocumentKindLabel(AgentDocumentKind kind) => switch (kind) {
  AgentDocumentKind.document => '普通文档',
  AgentDocumentKind.worldBook => '世界书',
  AgentDocumentKind.characterCard => '人物卡',
};
