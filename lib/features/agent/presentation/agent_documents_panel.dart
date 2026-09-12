import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oh_my_llm/core/constants/app_layout_tokens.dart';

import '../application/agent_workspace_controller.dart';
import 'agent_document_editor.dart';

class AgentDocumentsPanel extends ConsumerWidget {
  const AgentDocumentsPanel({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(agentWorkspaceProvider);
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
        if (state.busy) const Text('运行结束后可编辑文档。'),
        Expanded(
          child: state.documents.isEmpty
              ? const Center(child: Text('还没有文档。先添加世界设定、角色资料或草稿。'))
              : ListView.builder(
                  itemCount: state.documents.length,
                  itemBuilder: (context, index) {
                    final document = state.documents[index];
                    return ListTile(
                      title: Text(document.name),
                      subtitle: Text(
                        '版本 ${document.revision} · ${document.content.length} 字符',
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
