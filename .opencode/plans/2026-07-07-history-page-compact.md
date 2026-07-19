# 历史对话页面紧凑化 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 压缩历史对话页面顶部区域高度，使移动端列表可显示约 3 个卡片（当前仅 2 个）。

**Architecture:** 对现有布局做最小改动——删除冗余标题/描述、缩减 padding、将 PaginationBar 从两行压缩为单行。不改变数据层和交互逻辑。

**Tech Stack:** Flutter (Dart), Riverpod, 现有 widget 结构不变

## Global Constraints

- 不修改 HistoryToolbar、HistoryConversationTile、AppShellScaffold
- 不修改任何数据层 / controller 逻辑
- 所有改动仅涉及两个文件的 UI 层
- 注释使用简体中文

---

## File Structure

| 文件 | 操作 | 职责 |
|------|------|------|
| `lib/features/history/presentation/history_screen.dart` | Modify | 删除标题/描述、缩减 padding、缩减 tile 间距 |
| `lib/features/history/presentation/widgets/history_pagination_bar.dart` | Modify | 总数内联、按钮/控件缩小、间距缩减 |

---

### Task 1: 删除标题和描述文字

**Files:**
- Modify: `lib/features/history/presentation/history_screen.dart:89-96`

**Interfaces:**
- Consumes: 无外部依赖
- Produces: Column children 减少 3 个元素（标题 Text、SizedBox、描述 Text）及 1 个间距 SizedBox

- [ ] **Step 1: 删除标题、描述及间距**

在 `history_screen.dart` 的 `Column.children` 中，删除以下 4 个元素：

```dart
// 删除这 4 行（行 89-96）：
Text('历史对话',
    style: Theme.of(context).textTheme.headlineSmall),
const SizedBox(height: 8),
Text(
  '支持按标题和用户消息搜索、批量删除、重命名，并可跳回主页中的目标会话。',
  style: Theme.of(context).textTheme.bodyMedium,
),
const SizedBox(height: 20),
```

删除后，`Column.children` 直接从 `HistoryToolbar(...)` 开始。

- [ ] **Step 2: 运行 flutter analyze 确认无错误**

Run: `flutter analyze`
Expected: No issues found

- [ ] **Step 3: Commit**

```bash
git add lib/features/history/presentation/history_screen.dart
git commit -m "refactor: 移除历史页卡片内冗余标题和描述文字" -m "AppBar 已有页面标题，卡片内无需重复。节省约 68dp 垂直空间。" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: 缩减 Card 内外 Padding 和元素间距

**Files:**
- Modify: `lib/features/history/presentation/history_screen.dart`

**Interfaces:**
- Consumes: 无
- Produces: Card 区域上下各缩减 16dp（共 32dp），元素间距缩减

- [ ] **Step 1: 将外层 Padding 从 20 改为 12**

```dart
// 修改前
padding: const EdgeInsets.all(20),
// 修改后
padding: const EdgeInsets.all(12),
```

- [ ] **Step 2: 将内层 Padding 从 20 改为 12**

```dart
// 修改前
padding: const EdgeInsets.all(20),
// 修改后
padding: const EdgeInsets.all(12),
```

- [ ] **Step 3: 将 Toolbar 与 PaginationBar 之间的间距从 12 改为 8**

```dart
// HistoryToolbar 之后的 SizedBox
// 修改前
const SizedBox(height: 12),
// 修改后
const SizedBox(height: 8),
```

- [ ] **Step 4: 将 PaginationBar 与 Expanded 列表之间的间距从 12 改为 8**

```dart
// HistoryPaginationBar / LinearProgressIndicator 之后的 SizedBox
// 修改前
const SizedBox(height: 12),
// 修改后
const SizedBox(height: 8),
```

- [ ] **Step 5: 将 Tile 底部间距从 10 改为 6**

```dart
// _buildConversationList 方法中
// 修改前
padding: const EdgeInsets.only(bottom: 10),
// 修改后
padding: const EdgeInsets.only(bottom: 6),
```

- [ ] **Step 6: 运行 flutter analyze 确认无错误**

Run: `flutter analyze`
Expected: No issues found

- [ ] **Step 7: Commit**

```bash
git add lib/features/history/presentation/history_screen.dart
git commit -m "refactor: 缩减历史页 Card 内外 padding 和元素间距" -m "外层/内层 padding 20→12，toolbar/pagination/list 间距 12→8，tile 间距 10→6。" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: PaginationBar 单行化

**Files:**
- Modify: `lib/features/history/presentation/widgets/history_pagination_bar.dart`

**Interfaces:**
- Consumes: `historyPaginationProvider`（不变）
- Produces: 同样的分页功能，但视觉更紧凑

- [ ] **Step 1: 缩小页码按钮尺寸**

在 `_buildPageButton` 方法中，将 `minimumSize` 从 `Size(40, 40)` 改为 `Size(32, 32)`，并添加缩小字体：

```dart
Widget _buildPageButton(
  int pageNumber, {
  required bool isActive,
  required bool disabled,
}) {
  final onTap = disabled ? null : () => ref
      .read(historyPaginationProvider.notifier)
      .goToPage(pageNumber);
  if (isActive) {
    return FilledButton(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        minimumSize: const Size(32, 32),
        padding: EdgeInsets.zero,
        textStyle: const TextStyle(fontSize: 13),
      ),
      child: Text('$pageNumber'),
    );
  }
  return OutlinedButton(
    onPressed: onTap,
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(32, 32),
      padding: EdgeInsets.zero,
      textStyle: const TextStyle(fontSize: 13),
    ),
    child: Text('$pageNumber'),
  );
}
```

- [ ] **Step 2: 重构 build 方法——将总数行内联到 Wrap 中，删除独立 Column**

将整个 `build` 方法的返回值从 `Column` 改为单个 `Wrap`，总数信息作为 Wrap 的第一个子元素：

```dart
@override
Widget build(BuildContext context) {
  final state = ref.watch(historyPaginationProvider);
  final theme = Theme.of(context);
  final totalPages = state.totalPages;
  final disabled = state.isLoading;

  if (totalPages <= 0) return const SizedBox.shrink();

  final visiblePages = _visiblePageNumbers(totalPages, state.currentPage);

  return Wrap(
    spacing: 4,
    runSpacing: 4,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      // 总数信息内联
      Text(
        '共 ${state.totalItems} 条 · ${state.currentPage}/$totalPages 页',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(width: 8),
      // 上一页
      IconButton(
        tooltip: '上一页',
        icon: const Icon(Icons.chevron_left_rounded),
        visualDensity: VisualDensity.compact,
        onPressed:
            !disabled && state.hasPrevious
                ? () =>
                    ref
                        .read(historyPaginationProvider.notifier)
                        .prev()
                : null,
      ),
      // 页码按钮（含省略号）
      for (final item in visiblePages)
        if (item.isEllipsis)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text('…', style: theme.textTheme.bodySmall),
          )
        else
          _buildPageButton(
            item.page!,
            isActive: item.page == state.currentPage,
            disabled: disabled,
          ),
      // 下一页
      IconButton(
        tooltip: '下一页',
        icon: const Icon(Icons.chevron_right_rounded),
        visualDensity: VisualDensity.compact,
        onPressed:
            !disabled && state.hasNext
                ? () =>
                    ref
                        .read(historyPaginationProvider.notifier)
                        .next()
                : null,
      ),
      const SizedBox(width: 4),
      // 每页条数下拉
      SizedBox(
        width: 72,
        child: DropdownButtonFormField<int>(
          initialValue: state.pageSize,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: '每页',
            border: OutlineInputBorder(),
            isDense: true,
            contentPadding: EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 6,
            ),
          ),
          items: [
            for (final size in availablePageSizes)
              DropdownMenuItem<int>(value: size, child: Text('$size')),
          ],
          onChanged: disabled
              ? null
              : (value) {
                  if (value == null) return;
                  ref
                      .read(historyPaginationProvider.notifier)
                      .setPageSize(value);
                },
        ),
      ),
      // 跳转输入框 + 按钮
      SizedBox(
        width: 48,
        child: TextField(
          controller: _jumpController,
          enabled: !disabled,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13),
          decoration: const InputDecoration(
            labelText: '页码',
            border: OutlineInputBorder(),
            isDense: true,
            contentPadding: EdgeInsets.symmetric(
              horizontal: 4,
              vertical: 6,
            ),
          ),
          onSubmitted: (_) => _onJump(),
        ),
      ),
      TextButton(
        onPressed: disabled ? null : _onJump,
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        child: const Text('跳转', style: TextStyle(fontSize: 13)),
      ),
    ],
  );
}
```

关键变更点：
1. `Column` → `Wrap`，删除独立总数行和 `SizedBox(height: 8)`
2. 总数信息格式从 `"共 X 条 · 第 Y/Z 页"` 简化为 `"共 X 条 · Y/Z 页"`，作为 Wrap 第一个子元素
3. `Wrap` spacing 8→4，runSpacing 8→4
4. `IconButton` 添加 `visualDensity: VisualDensity.compact`（从 48dp 缩至约 40dp）
5. 省略号 padding horizontal 4→2，字体 bodyMedium→bodySmall
6. 每页下拉宽度 96→72，contentPadding 缩减
7. 跳转输入框宽度 64→48，添加 fontSize: 13，contentPadding 缩减
8. 跳转按钮添加 compact visualDensity 和缩小字体

- [ ] **Step 3: 运行 flutter analyze 确认无错误**

Run: `flutter analyze`
Expected: No issues found

- [ ] **Step 4: Commit**

```bash
git add lib/features/history/presentation/widgets/history_pagination_bar.dart
git commit -m "refactor: 历史页分页栏单行化" -m "总数信息内联到页码行，按钮/控件尺寸缩小，间距缩减。从两行压缩为单行布局。" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: 验证与测试

**Files:**
- 无新文件

- [ ] **Step 1: 运行全量测试**

Run: `flutter test --reporter compact 2>&1 > fltest.log; E=$?; echo "EXIT=$E"; tail -150 fltest.log`
Expected: EXIT=0

- [ ] **Step 2: 运行 flutter analyze**

Run: `flutter analyze`
Expected: No issues found

- [ ] **Step 3: 视觉验证（手动）**

Run: `flutter run -d windows`
在历史对话页确认：
- 标题和描述文字已移除
- Card 内外 padding 明显缩小
- 分页栏为单行布局，所有控件仍可正常交互
- 列表区域可显示更多卡片
