import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oh_my_llm/core/widgets/notification_bubble/notification_bubble_context_ext.dart';

import '../../../application/preferences/auto_retry_settings_controller.dart';
import '../../../application/preferences/font_size_settings_controller.dart';
import '../../../application/ports/system_notification_settings.dart';
import '../../../application/system_notifications/system_notification_status_controller.dart';
import '../../../domain/models/preferences/auto_retry_settings.dart';
import '../shared/settings_section_card.dart';

/// 自动重试卡片内 Switch 项的统一形状：hover 高亮带圆角。
/// contentPadding 保持 EdgeInsets.zero，让 title 与上方
/// SegmentedButton / 数字输入框的左基线对齐。
const _switchTileShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.all(Radius.circular(12)),
);

/// 其它设置标签页，包含显示、系统通知与自动重试等配置。
class OtherSettingsTab extends ConsumerStatefulWidget {
  const OtherSettingsTab({super.key});

  @override
  ConsumerState<OtherSettingsTab> createState() => _OtherSettingsTabState();
}

class _OtherSettingsTabState extends ConsumerState<OtherSettingsTab> {
  AppLifecycleListener? _lifecycleListener;

  @override
  void initState() {
    super.initState();
    // 用户可能跳去系统设置改通知开关后返回应用；resume 时重新查询一次，
    // 卡片才能反映当前系统事实而不是进页时的旧值。
    _lifecycleListener = AppLifecycleListener(
      onResume: () => unawaited(
        ref.read(systemNotificationStatusProvider.notifier).refresh(),
      ),
    );
  }

  @override
  void dispose() {
    _lifecycleListener?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(autoRetrySettingsProvider);
    final fontSizeSettings = ref.watch(fontSizeSettingsProvider);
    final notificationStatus = ref.watch(systemNotificationStatusProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SettingsSectionCard(
          title: '显示',
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
          title: '系统通知',
          description: '生成完成或失败时由系统显示通知；声音、横幅和权限由系统管理。',
          child: _buildSystemNotificationContent(notificationStatus),
        ),
        const SizedBox(height: 16),
        SettingsSectionCard(
          title: '自动重试',
          description:
              '当请求失败时自动重试的间隔与次数控制。'
              '每分钟窗口：每分钟在前 n 秒内随机一个毫秒发起重试；'
              '固定间隔：每 n 秒 + 随机 1000ms 抖动发起重试。'
              '最大次数设为 0 表示不限。',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SegmentedButton<RetryMode>(
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
              const SizedBox(height: 16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                shape: _switchTileShape,
                title: const Text('异常 finish_reason 重试'),
                subtitle: const Text(
                  '当模型返回的 finish_reason 不是 stop 或 tool_calls 时自动重试',
                ),
                value: settings.retryOnAbnormalFinishReason,
                onChanged: (value) {
                  ref
                      .read(autoRetrySettingsProvider.notifier)
                      .save(
                        settings.copyWith(retryOnAbnormalFinishReason: value),
                      );
                },
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                shape: _switchTileShape,
                title: const Text('超时自动重试'),
                subtitle: const Text('当服务器在指定时间内没有响应时自动断开并重试'),
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
      ],
    );
  }

  // ── 系统通知卡片 ────────────────────────────────────────────

  /// 查询期间保留流畅加载动画，数据返回后再渲染具体状态；入口按钮只在
  /// 状态落地且平台可用时可点，避免对不可用平台发起无意义的打开请求。
  Widget _buildSystemNotificationContent(
    AsyncValue<SystemNotificationStatus> status,
  ) {
    final Widget statusChild;
    if (status.isLoading) {
      statusChild = const Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 12),
          Text('正在读取系统通知状态'),
        ],
      );
    } else {
      // controller 已把查询异常映射为 unavailable，value 为 null 只剩
      // 理论路径，同样按不可用渲染兜底。
      statusChild = Text(switch (status.value ??
          SystemNotificationStatus.unavailable) {
        SystemNotificationStatus.enabled => '系统通知已开启',
        SystemNotificationStatus.disabled => '系统通知已关闭',
        SystemNotificationStatus.available => '系统通知功能可用，具体横幅和声音由 Windows 管理',
        SystemNotificationStatus.unavailable => '当前平台无法使用系统通知',
      });
    }

    final canOpen =
        !status.isLoading &&
        status.value != SystemNotificationStatus.unavailable;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        statusChild,
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: canOpen
              ? () => unawaited(_openSystemNotificationSettings(context))
              : null,
          child: const Text('打开系统通知设置'),
        ),
      ],
    );
  }

  /// 打开系统设置的失败用非阻塞气泡提示，不打断页面浏览。
  Future<void> _openSystemNotificationSettings(BuildContext context) async {
    final opened = await ref
        .read(systemNotificationStatusProvider.notifier)
        .openSettings();
    if (!opened && context.mounted) {
      context.showErrorBubble('无法打开系统通知设置');
    }
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
      onChanged: (text) {
        final parsed = int.tryParse(text);
        if (parsed != null) {
          onChanged(parsed.clamp(min, max));
        }
      },
    );
  }
}
