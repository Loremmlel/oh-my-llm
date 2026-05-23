import 'package:flutter/material.dart';

class ComposerSendButton extends StatelessWidget {
  const ComposerSendButton({
    required this.theme,
    required this.isBusy,
    required this.isStreaming,
    required this.hasModels,
    required this.expandLabel,
    required this.onSendPressed,
    required this.onStopStreaming,
    super.key,
  });

  final ThemeData theme;
  final bool isBusy;
  final bool isStreaming;
  final bool hasModels;
  final bool expandLabel;
  final Future<void> Function()? onSendPressed;
  final Future<void> Function()? onStopStreaming;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: isStreaming
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
        backgroundColor: isStreaming ? theme.colorScheme.error : null,
        foregroundColor: isStreaming ? theme.colorScheme.onError : null,
      ),
      icon: Icon(isStreaming ? Icons.stop_rounded : Icons.send_rounded),
      label: Text(isStreaming ? '终止回答' : '发送'),
    );
  }
}
