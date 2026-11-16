import 'package:flutter/material.dart';
import 'package:oh_my_llm/core/widgets/app_text_field.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oh_my_llm/core/widgets/app_field_group.dart';
import 'package:oh_my_llm/core/constants/app_layout_tokens.dart';

import '../../../application/preferences/auto_retry_settings_controller.dart';
import '../../../application/preferences/font_size_settings_controller.dart';
import '../../../application/preferences/trailing_directive_settings_controller.dart';
import '../../../domain/models/preferences/auto_retry_settings.dart';
import '../shared/settings_section_card.dart';

/// 自动重试分组内 Switch 项的统一形状：hover 高亮带圆角。
/// contentPadding 保持 EdgeInsets.zero，让 title 与上方
/// SegmentedButton / 数字输入框的左基线对齐。
const _switchTileShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.all(Radius.circular(AppRadii.md)),
);

/// 其它设置标签页，包含自动重试等杂项配置。
class OtherSettingsTab extends ConsumerWidget {
  const OtherSettingsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(autoRetrySettingsProvider);
    final fontSizeSettings = ref.watch(fontSizeSettingsProvider);
    final trailingSettings = ref.watch(trailingDirectiveSettingsProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SettingsSectionCard(
          title: '显示',
          maxWidth: AppContentWidths.readable,
          description: '调整正文字号。修改后全局生效，影响聊天消息、Markdown 渲染及所有使用 body 字体的界面文字。',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('正文字号'),
                  const Spacer(),
                  Text(
                    '${fontSizeSettings.bodyFontSize.toInt()}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
              Slider(
                value: fontSizeSettings.bodyFontSize,
                min: 12,
                max: 24,
                divisions: 12,
                label: '${fontSizeSettings.bodyFontSize.toInt()}',
                onChanged: (value) {
                  ref
                      .read(fontSizeSettingsProvider.notifier)
                      .updateLocal(
                        fontSizeSettings.copyWith(bodyFontSize: value),
                      );
                },
                onChangeEnd: (value) {
                  ref
                      .read(fontSizeSettingsProvider.notifier)
                      .save(fontSizeSettings.copyWith(bodyFontSize: value));
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SettingsSectionCard(
          title: '自动重试',
          maxWidth: AppContentWidths.readable,
          description:
              '当请求失败时自动重试的间隔与次数控制。'
              '每分钟窗口：每分钟在前 n 秒内随机一个毫秒发起重试；'
              '固定间隔：每 n 秒 + 随机 1000ms 抖动发起重试。'
              '最大次数设为 0 表示不限。\n\n'
              '异常 finish_reason 重试：当模型返回的 finish_reason 不是 stop 或 tool_calls 时自动重试。\n\n'
              '超时自动重试：当服务器在指定时间内没有响应时自动断开并重试。',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SegmentedButton<RetryMode>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment<RetryMode>(
                    value: RetryMode.perMinuteWindow,
                    label: Text('每分钟窗口'),
                  ),
                  ButtonSegment<RetryMode>(
                    value: RetryMode.fixedInterval,
                    label: Text('固定间隔'),
                  ),
                ],
                selected: {settings.retryMode},
                onSelectionChanged: (selected) {
                  ref
                      .read(autoRetrySettingsProvider.notifier)
                      .save(settings.copyWith(retryMode: selected.first));
                },
              ),
              const SizedBox(height: 16),
              AppFieldGroup(
                fieldWidth: 240,
                children: [
                  _AutoRetryNumberField(
                    key: const ValueKey('auto-retry-max-jitter-field'),
                    label: settings.retryMode == RetryMode.fixedInterval
                        ? '重试间隔（秒）'
                        : '最大重试间隔（秒）',
                    value: settings.maxJitterSeconds,
                    min: 0,
                    max: 60,
                    onChanged: (value) {
                      ref
                          .read(autoRetrySettingsProvider.notifier)
                          .save(settings.copyWith(maxJitterSeconds: value));
                    },
                  ),
                  _AutoRetryNumberField(
                    key: const ValueKey('auto-retry-max-count-field'),
                    label: '最大重试次数（0 不限）',
                    value: settings.maxRetryCount,
                    min: 0,
                    max: 100,
                    onChanged: (value) {
                      ref
                          .read(autoRetrySettingsProvider.notifier)
                          .save(settings.copyWith(maxRetryCount: value));
                    },
                  ),
                ],
              ),
              const Divider(height: 24),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                shape: _switchTileShape,
                title: const Text('异常 finish_reason 重试'),
                value: settings.retryOnAbnormalFinishReason,
                onChanged: (value) {
                  ref
                      .read(autoRetrySettingsProvider.notifier)
                      .save(
                        settings.copyWith(retryOnAbnormalFinishReason: value),
                      );
                },
              ),
              const Divider(height: 1),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                shape: _switchTileShape,
                title: const Text('超时自动重试'),
                value: settings.retryOnTimeout,
                onChanged: (value) {
                  ref
                      .read(autoRetrySettingsProvider.notifier)
                      .save(settings.copyWith(retryOnTimeout: value));
                },
              ),
              if (settings.retryOnTimeout) ...[
                const SizedBox(height: 16),
                _AutoRetryNumberField(
                  key: const ValueKey('auto-retry-timeout-seconds-field'),
                  label: '超时时间（秒）',
                  value: settings.timeoutSeconds,
                  min: 1,
                  max: 300,
                  onChanged: (value) {
                    ref
                        .read(autoRetrySettingsProvider.notifier)
                        .save(settings.copyWith(timeoutSeconds: value));
                  },
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        SettingsSectionCard(
          title: '末尾指令',
          maxWidth: AppContentWidths.readable,
          description:
              '在对话页开启「末尾指令」开关后，输入框内容将作为倒数第二条用户消息，这里配置的内容将作为最后一条用户消息发送（仅用于当次请求，不写入聊天记录）。\n\n'
              '普通模式：按「已有上下文 → 用户输入 → 末尾指令」顺序组装；若有预设后置条目，末尾指令放在其前面。\n\n'
              '轮替模式：在用户输入后拼接过渡提示「请输出"明白"，具体指令我接下来会给你。」，并插入助手消息「明白」，再发送末尾指令，以提高不同协议的兼容性。',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TrailingDirectiveContentField(
                content: trailingSettings.content,
                onChanged: (value) {
                  ref
                      .read(trailingDirectiveSettingsProvider.notifier)
                      .updateContent(value);
                },
              ),
              const Divider(height: 24),
              SwitchListTile(
                key: const ValueKey('trailing-directive-alternating-switch'),
                contentPadding: EdgeInsets.zero,
                shape: _switchTileShape,
                title: const Text('轮替模式'),
                value: trailingSettings.alternatingMode,
                onChanged: (value) {
                  ref
                      .read(trailingDirectiveSettingsProvider.notifier)
                      .setAlternatingMode(value);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TrailingDirectiveContentField extends StatefulWidget {
  const _TrailingDirectiveContentField({
    required this.content,
    required this.onChanged,
  });

  final String content;
  final ValueChanged<String> onChanged;

  @override
  State<_TrailingDirectiveContentField> createState() =>
      _TrailingDirectiveContentFieldState();
}

class _TrailingDirectiveContentFieldState
    extends State<_TrailingDirectiveContentField> {
  late final TextEditingController _controller;
  final List<String> _unacknowledgedLocalEdits = [];

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.content);
  }

  @override
  void didUpdateWidget(covariant _TrailingDirectiveContentField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.content == oldWidget.content) return;
    // 本地编辑回声（包括异步落后到达的中间快照）不回写控制器，避免抹掉后续键入与光标位置。
    final matchIndex = widget.content == _controller.text
        ? _unacknowledgedLocalEdits.lastIndexOf(widget.content)
        : _unacknowledgedLocalEdits.indexOf(widget.content);
    if (matchIndex != -1) {
      _unacknowledgedLocalEdits.removeRange(0, matchIndex + 1);
      return;
    }
    _unacknowledgedLocalEdits.clear();
    if (widget.content != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.content,
        selection: TextSelection.collapsed(offset: widget.content.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      key: const ValueKey('trailing-directive-content-field'),
      controller: _controller,
      minLines: 3,
      maxLines: 5,
      keyboardType: TextInputType.multiline,
      decoration: const InputDecoration(
        labelText: '指令内容',
        hintText: '例如：请根据上一条消息作答',
        border: OutlineInputBorder(),
      ),
      onChanged: (value) {
        _unacknowledgedLocalEdits.add(value);
        widget.onChanged(value);
      },
    );
  }
}

class _AutoRetryNumberField extends StatelessWidget {
  const _AutoRetryNumberField({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return AppTextField.form(
      initialValue: value.toString(),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onChanged: (text) {
        final parsed = int.tryParse(text);
        if (parsed != null) {
          onChanged(parsed.clamp(min, max));
        }
      },
    );
  }
}
