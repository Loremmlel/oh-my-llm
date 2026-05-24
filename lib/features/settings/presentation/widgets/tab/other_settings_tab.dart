import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/auto_retry_settings_controller.dart';
import '../settings_section_card.dart';

/// 其它设置标签页，包含自动重试等杂项配置。
class OtherSettingsTab extends ConsumerWidget {
  const OtherSettingsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(autoRetrySettingsProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
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
