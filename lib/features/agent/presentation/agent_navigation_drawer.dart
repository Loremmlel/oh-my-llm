import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oh_my_llm/core/constants/app_layout_tokens.dart';
import 'package:oh_my_llm/core/widgets/dialogs/rename_conversation_dialog.dart';

import '../application/agent_workspace_controller.dart';

class AgentNavigationDrawer extends ConsumerStatefulWidget {
  const AgentNavigationDrawer({super.key});
  @override
  ConsumerState<AgentNavigationDrawer> createState() =>
      _AgentNavigationDrawerState();
}

class _AgentNavigationDrawerState extends ConsumerState<AgentNavigationDrawer> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _rename(String id, String title) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => RenameConversationDialog(
        initialTitle: title,
        title: '重命名作品',
        labelText: '作品名称',
      ),
    );
    if (name != null && mounted) {
      ref.read(agentWorkspaceProvider.notifier).renameWorkspace(id, name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(agentWorkspaceProvider);
    final controller = ref.read(agentWorkspaceProvider.notifier);
    final query = _search.text.trim().toLowerCase();
    final entries = state.workspaces
        .where((w) => w.title.toLowerCase().contains(query))
        .toList();
    void select(void Function() action) {
      action();
      if (ref.read(agentWorkspaceProvider).error.isEmpty) {
        Scaffold.of(context).closeEndDrawer();
      }
    }

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '作品',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭侧栏',
                    onPressed: () => Scaffold.of(context).closeEndDrawer(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Column(
                children: [
                  TextField(
                    controller: _search,
                    focusNode: _searchFocus,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: '搜索作品',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: '清除搜索',
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                setState(_search.clear);
                                _searchFocus.requestFocus();
                              },
                            ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: state.busy
                        ? null
                        : () => select(controller.createWorkspace),
                    icon: const Icon(Icons.add),
                    label: const Text('新建作品'),
                  ),
                  if (state.busy) const Text('运行中，可浏览列表；停止后可切换或重命名。'),
                  if (state.error.isNotEmpty)
                    Text(
                      state.error,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: entries.isEmpty
                  ? Center(child: Text(query.isEmpty ? '新建作品后开始写作' : '没有匹配的作品'))
                  : ListView.builder(
                      itemCount: entries.length,
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        return ListTile(
                          selected: entry.id == state.workspace?.id,
                          enabled: !state.busy,
                          title: Tooltip(
                            message: entry.title,
                            child: Text(
                              entry.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          trailing: IconButton(
                            tooltip: '重命名作品「${entry.title}」',
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: state.busy
                                ? null
                                : () => _rename(entry.id, entry.title),
                          ),
                          onTap: () => select(
                            () => controller.selectWorkspace(entry.id),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
