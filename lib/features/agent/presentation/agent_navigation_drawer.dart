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
  bool _showWorks = true;

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _selectTab(bool works) => setState(() {
    _showWorks = works;
    _search.clear();
  });

  Future<void> _rename(String id, String title) async {
    final works = _showWorks;
    final name = await showDialog<String>(
      context: context,
      builder: (_) => RenameConversationDialog(
        initialTitle: title,
        title: works ? '重命名作品' : '重命名会话',
        labelText: works ? '作品名称' : '会话标题',
      ),
    );
    if (name == null || !mounted) return;
    final controller = ref.read(agentWorkspaceProvider.notifier);
    if (works) {
      controller.renameWorkspace(id, name);
    } else {
      controller.renameSession(id, name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(agentWorkspaceProvider);
    final controller = ref.read(agentWorkspaceProvider.notifier);
    final workspace = state.workspace;
    final query = _search.text.trim().toLowerCase();
    final entries =
        (_showWorks
                ? state.workspaces.map((w) => (id: w.id, title: w.title))
                : controller.sessions)
            .where((e) => e.title.toLowerCase().contains(query))
            .toList();
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.xs,
                AppSpacing.xs,
                0,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '作品与会话',
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
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<bool>(
                    segments: [
                      const ButtonSegment(value: true, label: Text('作品')),
                      ButtonSegment(
                        value: false,
                        label: const Text('会话'),
                        enabled: workspace != null,
                      ),
                    ],
                    selected: {_showWorks},
                    onSelectionChanged: (value) => _selectTab(value.single),
                  ),
                  if (!_showWorks && workspace != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      workspace.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: _search,
                    focusNode: _searchFocus,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: _showWorks ? '搜索作品' : '搜索会话',
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
                  const SizedBox(height: AppSpacing.sm),
                  TextButton.icon(
                    onPressed: state.busy
                        ? null
                        : () {
                            if (_showWorks) {
                              controller.createWorkspace();
                              if (ref
                                  .read(agentWorkspaceProvider)
                                  .error
                                  .isEmpty) {
                                _selectTab(false);
                              }
                            } else {
                              controller.createSession();
                              if (ref
                                  .read(agentWorkspaceProvider)
                                  .error
                                  .isEmpty) {
                                Scaffold.of(context).closeEndDrawer();
                              }
                            }
                          },
                    icon: const Icon(Icons.add),
                    label: Text(_showWorks ? '新建作品' : '新建会话'),
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
                  ? Center(
                      child: Text(
                        query.isNotEmpty
                            ? '没有匹配的${_showWorks ? '作品' : '会话'}'
                            : '新建作品后开始写作',
                      ),
                    )
                  : ListView.builder(
                      itemCount: entries.length,
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        return ListTile(
                          selected:
                              entry.id ==
                              (_showWorks
                                  ? workspace?.id
                                  : workspace?.sessionId),
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
                            tooltip:
                                '重命名${_showWorks ? '作品' : '会话'}「${entry.title}」',
                            onPressed: state.busy
                                ? null
                                : () => _rename(entry.id, entry.title),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                          onTap: () {
                            if (_showWorks) {
                              controller.selectWorkspace(entry.id);
                              if (ref
                                  .read(agentWorkspaceProvider)
                                  .error
                                  .isEmpty) {
                                _selectTab(false);
                              }
                            } else {
                              controller.selectSession(entry.id);
                              if (ref
                                  .read(agentWorkspaceProvider)
                                  .error
                                  .isEmpty) {
                                Scaffold.of(context).closeEndDrawer();
                              }
                            }
                          },
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
