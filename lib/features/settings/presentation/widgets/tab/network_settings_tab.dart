import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/custom_headers_controller.dart';
import '../../../domain/models/custom_headers_config.dart';
import '../settings_helpers.dart';
import '../settings_section_card.dart';
import 'header_form_dialog.dart';

/// 网络设置标签页，包含自定义请求头规则等网络层配置。
class NetworkSettingsTab extends ConsumerWidget {
  const NetworkSettingsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(customHeadersProvider);
    final controller = ref.read(customHeadersProvider.notifier);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SettingsSectionCard(
          title: '请求头定义',
          description: '自定义 HTTP 请求头，会附加到所有发出的请求中。'
              '同名请求头会覆盖应用的默认值。'
              '注意：Host 请求头可能被系统底层覆盖，不一定生效。',
          action: FilledButton.icon(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => const HeaderFormDialog(),
            ),
            icon: const Icon(Icons.add_rounded),
            label: const Text('新增请求头'),
          ),
          child: config.headers.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      '暂无自定义请求头，点击上方按钮添加',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                )
              : Column(
                  children: [
                    for (var i = 0; i < config.headers.length; i++)
                      _HeaderEntryTile(
                        index: i,
                        entry: config.headers[i],
                        onEdit: () => showDialog(
                          context: context,
                          builder: (_) => HeaderFormDialog(
                            index: i,
                            initialKey: config.headers[i].key,
                            initialValue: config.headers[i].value,
                          ),
                        ),
                        onDelete: () => _confirmDelete(
                          context,
                          controller,
                          i,
                          config.headers[i].key,
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    CustomHeadersController controller,
    int index,
    String key,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('确认删除'),
          content: Text('确定要删除请求头「$key」吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error,
              ),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await controller.removeHeader(index);
      if (context.mounted) {
        showSettingsSnackbar(context, '请求头已删除');
      }
    }
  }
}

class _HeaderEntryTile extends StatelessWidget {
  const _HeaderEntryTile({
    required this.index,
    required this.entry,
    required this.onEdit,
    required this.onDelete,
  });

  final int index;
  final CustomHeaderEntry entry;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(top: index > 0 ? 8 : 0),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.key,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      entry.value,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withAlpha(179),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined),
                tooltip: '编辑',
              ),
              IconButton(
                onPressed: onDelete,
                icon: Icon(
                  Icons.delete_outline,
                  color: theme.colorScheme.error,
                ),
                tooltip: '删除',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
