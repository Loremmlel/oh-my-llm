import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/auto_retry_settings_controller.dart';
import '../../../application/font_size_settings_controller.dart';
import '../settings_section_card.dart';

/// 其它设置标签页，包含自动重试等杂项配置。
class OtherSettingsTab extends ConsumerWidget {
  const OtherSettingsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(autoRetrySettingsProvider);
    final fontSizeSettings = ref.watch(fontSizeSettingsProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SettingsSectionCard(
          title: '显示',
          description:
              '调整正文字号。修改后全局生效，影响聊天消息、Markdown 渲染及所有使用 body 字体的界面文字。',
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
                  ref.read(fontSizeSettingsProvider.notifier).updateLocal(
                    fontSizeSettings.copyWith(bodyFontSize: value),
                  );
                },
                onChangeEnd: (value) {
                  ref.read(fontSizeSettingsProvider.notifier).save(
                    fontSizeSettings.copyWith(bodyFontSize: value),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SettingsSectionCard(
          title: '自动重试',
          description: '当请求失败时自动重试的间隔与次数控制。'
              '最大重试间隔对应每分钟内的随机抖动上限；'
              '最大次数设为 0 表示不限。',
          child: Column(
            children: [
              _AutoRetryNumberField(
                key: const ValueKey('auto-retry-max-jitter-field'),
                label: '最大重试间隔（秒）',
                value: settings.maxJitterSeconds,
                min: 0,
                max: 60,
                onChanged: (value) {
                  ref
                      .read(autoRetrySettingsProvider.notifier)
                      .save(settings.copyWith(maxJitterSeconds: value));
                },
              ),
              const SizedBox(height: 16),
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
        ),
      ],
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
    return TextFormField(
      initialValue: value.toString(),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onFieldSubmitted: (text) {
        final parsed = int.tryParse(text);
        if (parsed != null) {
          onChanged(parsed.clamp(min, max));
        }
      },
    );
  }
}
