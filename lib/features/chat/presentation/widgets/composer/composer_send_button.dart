import 'package:flutter/material.dart';

class ComposerSendButton extends StatelessWidget {
  const ComposerSendButton({
    required this.theme,
    required this.isBusy,
    required this.isStreaming,
    required this.isAutoRetryWaiting,
    required this.hasModels,
    required this.expandLabel,
    required this.onSendPressed,
    required this.onStopStreaming,
    super.key,
  });

  final ThemeData theme;
  final bool isBusy;
  final bool isStreaming;
  final bool isAutoRetryWaiting;
  final bool hasModels;
  final bool expandLabel;
  final Future<void> Function()? onSendPressed;
  final Future<void> Function()? onStopStreaming;

  @override
  Widget build(BuildContext context) {
    final isStopping = isStreaming || isAutoRetryWaiting;
    return FilledButton.icon(
      onPressed: isStopping
          ? () {
              onStopStreaming?.call();
            }
          : isBusy || !hasModels
          ? null
          : () {
              onSendPressed?.call();
            },
      style: FilledButton.styleFrom(
        minimumSize: Size(expandLabel ? 112 : 60, 40),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: isStopping ? theme.colorScheme.error : null,
        foregroundColor: isStopping ? theme.colorScheme.onError : null,
      ),
      icon: Icon(isStopping ? Icons.stop_rounded : Icons.send_rounded),
      label: Text(isStopping ? '终止回答' : '发送'),
    );
  }
}
