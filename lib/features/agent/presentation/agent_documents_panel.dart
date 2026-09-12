import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oh_my_llm/core/constants/app_layout_tokens.dart';

import '../application/agent_workspace_controller.dart';
import 'agent_document_editor.dart';
import '../domain/agent_models.dart';

class AgentDocumentsPanel extends ConsumerStatefulWidget {
  const AgentDocumentsPanel({super.key});
  @override
  ConsumerState<AgentDocumentsPanel> createState() =>
      _AgentDocumentsPanelState();
}

class _AgentDocumentsPanelState extends ConsumerState<AgentDocumentsPanel> {
  AgentDocumentKind? _kind;
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(agentWorkspaceProvider);
    final documents = state.documents
        .where((d) => _kind == null || d.kind == _kind)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('每次保存保留旧版本，正文可以直接修改。'),
              OutlinedButton.icon(
                onPressed: state.busy
                    ? null
                    : () => showAgentDocumentEditor(context),
                icon: const Icon(Icons.note_add_outlined),
                label: const Text('新建文档'),
              ),
            ],
          ),
        ),
        Wrap(
          spacing: AppSpacing.xs,
          children: [
            ChoiceChip(
              label: Text('全部 ${state.documents.length}'),
              selected: _kind == null,
              onSelected: (_) => setState(() => _kind = null),
            ),
            for (final kind in AgentDocumentKind.values)
              ChoiceChip(
                label: Text(
                  '${agentDocumentKindLabel(kind)} ${state.documents.where((d) => d.kind == kind).length}',
                ),
                selected: _kind == kind,
                onSelected: (_) => setState(() => _kind = kind),
              ),
          ],
        ),
        if (state.busy) const Text('运行结束后可编辑文档。'),
        Expanded(
          child: documents.isEmpty
              ? const Center(child: Text('此分类还没有资料。新建文档时可以选择世界书、人物卡或普通文档。'))
              : ListView.builder(
                  itemCount: documents.length,
                  itemBuilder: (context, index) {
                    final document = documents[index];
                    return ListTile(
                      title: Text(document.name),
                      subtitle: Text(
                        '${agentDocumentKindLabel(document.kind)} · 版本 ${document.revision} · ${document.content.length} 字符',
                      ),
                      trailing: const Icon(Icons.edit_outlined),
                      enabled: !state.busy,
                      onTap: () =>
                          showAgentDocumentEditor(context, document: document),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
