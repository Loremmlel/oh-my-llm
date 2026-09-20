import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:oh_my_llm/core/constants/app_layout_tokens.dart';

import '../../../application/ports/chat_image_store.dart';
import '../../../domain/models/chat_image_attachment.dart';

/// 草稿与历史使用同一缩略图，文件只在实际显示时读取。
class ChatImageStrip extends StatelessWidget {
  const ChatImageStrip({super.key, required this.images, this.onRemove});
  final List<ChatImageAttachment> images;
  final ValueChanged<String>? onRemove;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 112,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: images.length,
      separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.xs),
      itemBuilder: (context, index) =>
          _ChatImageThumbnail(image: images[index], onRemove: onRemove),
    ),
  );
}

class _ChatImageThumbnail extends StatefulWidget {
  const _ChatImageThumbnail({required this.image, this.onRemove});
  final ChatImageAttachment image;
  final ValueChanged<String>? onRemove;
  @override
  State<_ChatImageThumbnail> createState() => _ChatImageThumbnailState();
}

class _ChatImageThumbnailState extends State<_ChatImageThumbnail> {
  bool _hovered = false;
  bool _focused = false;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: 112,
      child: Material(
        color: colors.surfaceContainerHighest,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.sm),
          side: BorderSide(
            color: _focused ? colors.primary : colors.outlineVariant,
            width: _focused ? 2 : 1,
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: ChatImageContent(id: widget.image.id, thumbnail: true),
            ),
            Positioned.fill(
              child: Tooltip(
                message: '预览图片：${widget.image.name}',
                child: InkWell(
                  onHover: (value) => setState(() => _hovered = value),
                  onFocusChange: (value) => setState(() => _focused = value),
                  onTap: () => context.push('/chat/images/${widget.image.id}'),
                  child: ColoredBox(
                    color: _hovered || _focused
                        ? colors.scrim.withValues(alpha: 0.45)
                        : Colors.transparent,
                    child: _hovered || _focused
                        ? const Center(
                            child: Icon(Icons.zoom_in, color: Colors.white),
                          )
                        : null,
                  ),
                ),
              ),
            ),
            if (widget.onRemove != null)
              Positioned(
                top: 0,
                right: 0,
                child: IconButton.filledTonal(
                  tooltip: '移除图片：${widget.image.name}',
                  onPressed: () => widget.onRemove!(widget.image.id),
                  icon: const Icon(Icons.close, size: 18),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class ChatImageContent extends ConsumerWidget {
  const ChatImageContent({super.key, required this.id, this.thumbnail = false});
  final String id;
  final bool thumbnail;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget failure() => Center(
      child: thumbnail
          ? const Tooltip(
              message: '图片无法读取',
              child: Icon(Icons.broken_image_outlined),
            )
          : const Text('图片文件已丢失或损坏，请重新添加图片。'),
    );
    return ref
        .watch(chatImageBytesProvider(id))
        .when(
          loading: () => const Center(
            child: SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(),
            ),
          ),
          error: (_, _) => failure(),
          data: (bytes) => Image.memory(
            bytes,
            fit: thumbnail ? BoxFit.cover : BoxFit.contain,
            cacheWidth: thumbnail ? 224 : null,
            excludeFromSemantics: thumbnail,
            semanticLabel: thumbnail ? null : '预览图片',
            errorBuilder: (_, _, _) => failure(),
          ),
        );
  }
}
