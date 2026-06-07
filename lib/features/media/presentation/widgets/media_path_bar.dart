import 'package:flutter/material.dart';

/// 可点击的面包屑路径导航栏。
///
/// 示例：`🏠 / sister / video / vlog`
/// - 🏠 点击跳转根目录
/// - 每级路径均可点击跳转
class MediaPathBar extends StatelessWidget {
  final String currentPath;
  final ValueChanged<String> onPathSelected;

  const MediaPathBar({
    super.key,
    required this.currentPath,
    required this.onPathSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final segments = _buildSegments();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // 🏠 根目录按钮
            _PathChip(
              label: '🏠',
              onTap: () => onPathSelected('/'),
              isActive: currentPath == '/' || currentPath.isEmpty,
              theme: theme,
            ),
            // 每级路径
            for (var i = 0; i < segments.length; i++)
              Row(children: [
                Text(' / ', style: theme.textTheme.bodySmall),
                _PathChip(
                  label: segments[i].name,
                  onTap: () => onPathSelected(segments[i].path),
                  isActive: segments[i].path == currentPath,
                  theme: theme,
                ),
              ]),
          ],
        ),
      ),
    );
  }

  List<_PathSegment> _buildSegments() {
    if (currentPath == '/' || currentPath.isEmpty) return [];

    final parts = currentPath
        .split('/')
        .where((s) => s.isNotEmpty)
        .toList();
    final segments = <_PathSegment>[];
    var accumulated = '';
    for (final part in parts) {
      accumulated += '/$part';
      segments.add(_PathSegment(name: part, path: accumulated));
    }
    return segments;
  }
}

class _PathSegment {
  final String name;
  final String path;
  const _PathSegment({required this.name, required this.path});
}

class _PathChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool isActive;
  final ThemeData theme;

  const _PathChip({
    required this.label,
    required this.onTap,
    required this.isActive,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          label,
          maxLines: 1,
          style: theme.textTheme.bodySmall?.copyWith(
            color: isActive
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurface,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
