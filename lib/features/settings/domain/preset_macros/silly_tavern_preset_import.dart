import 'dart:convert';

import '../models/prompts/preset_prompt.dart';

typedef PresetOrderEntry = ({String identifier, bool enabled});
typedef PresetSourceOrder = ({String name, List<PresetOrderEntry> entries});

class PresetImportIssue {
  const PresetImportIssue(
    this.identifier,
    this.title,
    this.message, {
    this.needsPlacement = false,
  });
  final String identifier;
  final String title;
  final String message;
  final bool needsPlacement;
}

class PresetImportPlan {
  const PresetImportPlan(this.messages, this.issues, this.spareCount);
  final List<PromptMessage> messages;
  final List<PresetImportIssue> issues;
  final int spareCount;
  bool get canImport => !issues.any((issue) => issue.needsPlacement);
}

/// 只读取提示词与一个顺序表；其它宿主配置没有执行入口。
class SillyTavernPresetFile {
  SillyTavernPresetFile._(
    this.prompts,
    this.orders,
    this.hasExtensions,
    this.ignoredFields,
  );
  final Map<String, Map<String, dynamic>> prompts;
  final List<PresetSourceOrder> orders;
  final bool hasExtensions;
  final List<String> ignoredFields;

  static const _hostMarkers = {
    'chatHistory',
    'worldInfoBefore',
    'worldInfoAfter',
    'charDescription',
    'charPersonality',
    'personaDescription',
    'scenario',
    'dialogueExamples',
  };

  factory SillyTavernPresetFile.parse(String text) {
    if (text.length > 16 * 1024 * 1024) {
      throw const FormatException('预设文件超过 16 MiB');
    }
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, dynamic> ||
        decoded['prompts'] is! List ||
        decoded['prompt_order'] is! List) {
      throw const FormatException(
        '需要包含 prompts 和 prompt_order 的 SillyTavern JSON',
      );
    }
    final prompts = <String, Map<String, dynamic>>{};
    for (final raw in decoded['prompts'] as List) {
      if (raw is! Map<String, dynamic>) {
        throw const FormatException('prompts 中存在无效条目');
      }
      final id = raw['identifier'];
      if (id is! String || id.isEmpty || prompts.containsKey(id)) {
        throw const FormatException('条目标识缺失或重复');
      }
      for (final key in ['name', 'content', 'role']) {
        if (raw[key] != null && raw[key] is! String) {
          throw FormatException('$id 的 $key 必须为文本');
        }
      }
      if (raw['marker'] != null && raw['marker'] is! bool) {
        throw FormatException('$id 的 marker 必须为布尔值');
      }
      if (!const [
        'system',
        'user',
        'assistant',
        'model',
      ].contains(raw['role'] ?? 'system')) {
        throw FormatException('$id 的角色不受支持');
      }
      for (final key in [
        'injection_position',
        'injection_depth',
        'injection_order',
      ]) {
        if (raw[key] != null && raw[key] is! int) {
          throw FormatException('$id 的 $key 必须为整数');
        }
      }
      prompts[id] = Map.unmodifiable(raw);
    }
    if (prompts.length > 10000) throw const FormatException('预设条目超过 10000 条');
    final orders = <PresetSourceOrder>[];
    for (final raw in decoded['prompt_order'] as List) {
      if (raw is! Map || raw['order'] is! List) {
        throw const FormatException('无效的 prompt_order 顺序表');
      }
      final seen = <String>{};
      final entries = <PresetOrderEntry>[];
      for (final item in raw['order'] as List) {
        if (item is! Map || item['identifier'] is! String) {
          throw const FormatException('顺序表缺少条目标识');
        }
        final id = item['identifier'] as String;
        if (!prompts.containsKey(id) || !seen.add(id)) {
          throw FormatException('顺序表引用缺失或重复条目：$id');
        }
        if (item['enabled'] != null && item['enabled'] is! bool) {
          throw FormatException('$id 的 enabled 必须为布尔值');
        }
        entries.add((
          identifier: id,
          enabled: item['enabled'] as bool? ?? true,
        ));
      }
      if (entries.isNotEmpty) {
        orders.add((
          name: '${raw['character_id'] ?? orders.length + 1}',
          entries: List.unmodifiable(entries),
        ));
      }
    }
    if (orders.isEmpty) throw const FormatException('没有可用的顺序表');
    return SillyTavernPresetFile._(
      Map.unmodifiable(prompts),
      List.unmodifiable(orders),
      decoded['extensions'] != null,
      List.unmodifiable([
        for (final key in const [
          'assistant_prefill',
          'assistant_impersonation',
          'continue_prefill',
          'continue_nudge_prompt',
          'group_nudge_prompt',
          'impersonation_prompt',
          'new_chat_prompt',
          'new_example_chat_prompt',
          'new_group_chat_prompt',
          'personality_format',
          'scenario_format',
          'wi_format',
        ])
          if (decoded[key] != null &&
              decoded[key] != false &&
              decoded[key] != '')
            key,
      ]),
    );
  }

  int get preferredOrder {
    final index = orders.indexWhere((order) => order.name == '100001');
    return index < 0 ? 0 : index;
  }

  PresetImportPlan plan(
    int orderIndex, {
    Map<String, PromptMessagePlacement> placements = const {},
  }) {
    final order = orders[orderIndex].entries;
    final selected = order.map((entry) => entry.identifier).toSet();
    final spares = prompts.keys.where((id) => !selected.contains(id)).toList();
    final entries = [
      ...order,
      for (final id in spares) (identifier: id, enabled: false),
    ];
    final historyIndex = order.indexWhere(
      (entry) =>
          entry.identifier == 'chatHistory' &&
          prompts[entry.identifier]!['marker'] == true,
    );
    final messages = <PromptMessage>[];
    final issues = <PresetImportIssue>[];
    if (hasExtensions) {
      issues.add(const PresetImportIssue('', '', '扩展脚本、美化、正则和交互运行机制未导入。'));
    }
    if (ignoredFields.isNotEmpty) {
      issues.add(
        PresetImportIssue('', '', '未导入的宿主格式或预填充字段：${ignoredFields.join('、')}'),
      );
    }
    for (var index = 0; index < entries.length; index++) {
      final item = entries[index];
      final source = prompts[item.identifier]!;
      final title = source['name'] as String? ?? '';
      final content = source['content'] as String? ?? '';
      final marker = source['marker'] == true;
      final knownMarker = marker && _hostMarkers.contains(item.identifier);
      if (marker && content.isEmpty) {
        if (item.identifier == 'chatHistory' && knownMarker) {
          if (!item.enabled) {
            issues.add(
              PresetImportIssue(
                item.identifier,
                title,
                '来源关闭了历史；Chat 仍按本应用规则保留历史。',
              ),
            );
          }
        } else {
          issues.add(
            PresetImportIssue(
              item.identifier,
              title,
              knownMarker ? '未导入的动态来源' : '不支持的空动态槽位，未生成消息',
            ),
          );
        }
        continue;
      }
      final position = source['injection_position'] as int? ?? 0;
      final depth = source['injection_depth'] as int? ?? 4;
      PromptMessagePlacement? placement = placements[item.identifier];
      if (placement == null && !marker) {
        if (position == 0) {
          if (index >= order.length) {
            placement = PromptMessagePlacement.before;
          } else if (historyIndex >= 0) {
            placement = index < historyIndex
                ? PromptMessagePlacement.before
                : PromptMessagePlacement.after;
          }
        } else if (position == 1) {
          placement = switch (depth) {
            0 => PromptMessagePlacement.after,
            1 => PromptMessagePlacement.beforeLatestInput,
            _ => null,
          };
        }
      }
      if (placement == null) {
        issues.add(
          PresetImportIssue(
            item.identifier,
            title,
            marker
                ? '动态槽位含正文，请指定作为普通条目的注入位置'
                : '无法自动映射 position=$position、depth=$depth，请指定位置',
            needsPlacement: true,
          ),
        );
        continue;
      }
      if (source['injection_trigger'] case final List triggers
          when triggers.isNotEmpty) {
        issues.add(
          PresetImportIssue(
            item.identifier,
            title,
            '生成类型限制未导入，启用后使用 Chat 的发送规则',
          ),
        );
      }
      if (source['role'] == 'model') {
        issues.add(
          PresetImportIssue(
            item.identifier,
            title,
            '来源角色 model 已映射为 assistant；不导入模型预填充开关',
          ),
        );
      }
      messages.add(
        PromptMessage(
          id: item.identifier,
          sourceIdentifier: item.identifier,
          title: title,
          content: content,
          enabled: item.enabled,
          role: PromptMessageRole.fromApiValue(
            source['role'] == 'model'
                ? 'assistant'
                : source['role'] as String? ?? 'system',
          ),
          placement: placement,
        ),
      );
    }
    final originalIndices = {
      for (var i = 0; i < messages.length; i++) messages[i].id: i,
    };
    final ranks = <String, int>{};
    for (final placement in PromptMessagePlacement.values) {
      final placed = messages.where((m) => m.placement == placement).toList();
      bool isDepth(PromptMessage m) =>
          !placements.containsKey(m.id) &&
          prompts[m.id]!['injection_position'] == 1;
      placed.sort((a, b) {
        final aDepth = isDepth(a), bDepth = isDepth(b);
        if (aDepth != bDepth) return aDepth ? -1 : 1;
        if (aDepth) {
          // ST 先按 Order 降序、system/user/assistant 插入倒序历史，再整体反转。
          final priority = ((prompts[a.id]!['injection_order'] as int?) ?? 100)
              .compareTo((prompts[b.id]!['injection_order'] as int?) ?? 100);
          if (priority != 0) return priority;
          const roles = {
            PromptMessageRole.assistant: 0,
            PromptMessageRole.user: 1,
            PromptMessageRole.system: 2,
          };
          final roleOrder = roles[a.role]!.compareTo(roles[b.role]!);
          if (roleOrder != 0) return roleOrder;
        }
        return originalIndices[a.id]!.compareTo(originalIndices[b.id]!);
      });
      for (var index = 0; index < placed.length; index++) {
        ranks[placed[index].id] = index;
      }
    }
    return PresetImportPlan(
      List.unmodifiable(
        messages.map(
          (m) => PromptMessage(
            id: m.id,
            role: m.role,
            content: m.content,
            title: m.title,
            placement: m.placement,
            enabled: m.enabled,
            sourceIdentifier: m.sourceIdentifier,
            importInsertionOrder: ranks[m.id],
          ),
        ),
      ),
      List.unmodifiable(issues),
      messages.where((m) => spares.contains(m.id)).length,
    );
  }

  PresetPrompt createPreset(
    PresetImportPlan plan, {
    required String name,
    required String Function() newId,
  }) {
    if (!plan.canImport) throw const FormatException('请先指定未映射条目的位置');
    return PresetPrompt(
      id: newId(),
      name: name,
      updatedAt: DateTime.now(),
      syntax: PresetPromptSyntax.sillyTavernSubsetV1,
      messages: List.unmodifiable(
        plan.messages.map((message) => message.copyWith(id: newId())),
      ),
    );
  }
}
