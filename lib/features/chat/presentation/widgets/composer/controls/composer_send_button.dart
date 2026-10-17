import 'package:flutter/material.dart';
import 'package:oh_my_llm/core/constants/app_layout_tokens.dart';

class ComposerSendButton extends StatelessWidget {
  const ComposerSendButton({
    required this.theme,
    required this.isBusy,
    required this.isStreaming,
    required this.isAutoRetryWaiting,
    required this.hasModels,
    required this.onSendPressed,
    required this.onStopStreaming,
    super.key,
  });

  final ThemeData theme;
  final bool isBusy;
  final bool isStreaming;
  final bool isAutoRetryWaiting;
  final bool hasModels;
  final Future<void> Function()? onSendPressed;
  final Future<void> Function()? onStopStreaming;

  @override
  Widget build(BuildContext context) {
    final isStopping = isStreaming || isAutoRetryWaiting;
    return IconButton.filled(
      tooltip: isStopping ? '终止回答' : '发送',
      onPressed: isStopping
          ? () {
              onStopStreaming?.call();
            }
          : isBusy || !hasModels || onSendPressed == null
          ? null
          : () {
              onSendPressed?.call();
            },
      style: IconButton.styleFrom(
        fixedSize: const Size.square(AppInteractionSizes.standardVisualControl),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.sm),
        ),
        tapTargetSize: MaterialTapTargetSize.padded,
        backgroundColor: isStopping
            ? theme.colorScheme.onSurface
            : theme.colorScheme.primary,
        foregroundColor: isStopping
            ? theme.colorScheme.surface
            : theme.colorScheme.onPrimary,
      ),
      icon: Icon(
        isStopping ? Icons.stop_rounded : Icons.arrow_upward_rounded,
        size: 18,
      ),
    );
  }
}
