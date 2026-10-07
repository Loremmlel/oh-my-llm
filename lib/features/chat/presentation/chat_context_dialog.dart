import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:oh_my_llm/core/constants/app_breakpoints.dart';
import 'package:oh_my_llm/core/constants/app_layout_tokens.dart';
import 'package:oh_my_llm/features/settings/domain/preset_macros/preset_macro_renderer.dart';

import '../application/ports/chat_generation_client.dart';

/// 只接收打开时的不可变结果，不监听正在流入的回复。
class ChatContextDialog extends StatefulWidget {
  const ChatContextDialog({
    required this.conversationTitle,
    required this.presetName,
    required this.status,
    this.messages = const [],
    this.diagnostics = const [],
    this.error,
    this.note,
    super.key,
  });
  final String conversationTitle;
  final String presetName;
  final String status;
  final List<ChatRequestMessage> messages;
  final List<PresetMacroDiagnostic> diagnostics;
  final String? error;
  final String? note;

  @override
  State<ChatContextDialog> createState() => _ChatContextDialogState();
}

class _ChatContextDialogState extends State<ChatContextDialog> {
  String? _copyStatus;
  String _text(ChatRequestMessage message, int index) => [
    '${index + 1}. ${message.role.apiValue} · ${message.sourceLabel}',
    message.content,
    for (final image in message.images)
      '[图片：${image.name} · ${image.mimeType}]',
  ].join('\n');

  Future<void> _copy(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) setState(() => _copyStatus = '已复制');
    } catch (error) {
      if (mounted) setState(() => _copyStatus = '复制失败：$error');
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = AppBreakpoints.useCompactShell(constraints.maxWidth);
      final content = SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '当前上下文',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: compact ? '返回对话' : '关闭上下文',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(compact ? Icons.arrow_back : Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SelectionArea(
                child: ListView(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  children: [
                    Text(
                      widget.status,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '${widget.conversationTitle}\n预设：${widget.presetName.isEmpty ? '无' : widget.presetName}',
                    ),
                    Text(
                      '${widget.messages.length} 条消息 · ${widget.messages.fold<int>(0, (sum, m) => sum + m.content.characters.length)} 个文本字符（非 Token）',
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    const Text(
                      '显示进入生成适配器的有序消息。协议层可能合并角色或编码图片；这里不是原始 HTTP 报文。关闭后重开可刷新。',
                    ),
                    if (widget.note != null) Text(widget.note!),
                    if (widget.error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.md,
                        ),
                        child: Text(
                          widget.error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    if (widget.diagnostics.isNotEmpty)
                      ExpansionTile(
                        title: Text('预设诊断（${widget.diagnostics.length}）'),
                        children: [
                          for (final diagnostic in widget.diagnostics)
                            ListTile(
                              title: Text(
                                diagnostic.title.isEmpty
                                    ? '无标题条目'
                                    : diagnostic.title,
                              ),
                              subtitle: Text(
                                '${diagnostic.message}${diagnostic.expression.isEmpty ? '' : '\n${diagnostic.expression}'}',
                              ),
                            ),
                        ],
                      ),
                    for (var i = 0; i < widget.messages.length; i++) ...[
                      const Divider(height: AppSpacing.xl),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${i + 1}. ${widget.messages[i].role.apiValue} · ${widget.messages[i].sourceLabel}',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                          IconButton(
                            tooltip: '复制第 ${i + 1} 条',
                            onPressed: () =>
                                _copy(_text(widget.messages[i], i)),
                            icon: const Icon(Icons.copy_outlined),
                          ),
                        ],
                      ),
                      Text(widget.messages[i].content),
                      for (final image in widget.messages[i].images)
                        Text('[图片：${image.name} · ${image.mimeType}]'),
                    ],
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Wrap(
                spacing: AppSpacing.md,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: widget.messages.isEmpty
                        ? null
                        : () => _copy(
                            [
                              for (var i = 0; i < widget.messages.length; i++)
                                _text(widget.messages[i], i),
                            ].join('\n\n'),
                          ),
                    icon: const Icon(Icons.copy_all_outlined),
                    label: const Text('复制全部文本'),
                  ),
                  if (_copyStatus != null)
                    Semantics(liveRegion: true, child: Text(_copyStatus!)),
                ],
              ),
            ),
          ],
        ),
      );
      if (compact) return Dialog.fullscreen(child: content);
      return Dialog(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: AppContentWidths.readable,
            maxHeight: constraints.maxHeight * 0.9,
          ),
          child: SizedBox(width: AppContentWidths.readable, child: content),
        ),
      );
    },
  );
}
