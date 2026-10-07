import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oh_my_llm/core/constants/app_layout_tokens.dart';
import 'package:oh_my_llm/core/utils/id_generator.dart';

import '../../../../application/ports/preset_import_source.dart';
import '../../../../application/prompts/preset_prompts_controller.dart';
import '../../../../domain/models/prompts/preset_prompt.dart';
import '../../../../domain/preset_macros/preset_macro_renderer.dart';
import '../../../../domain/preset_macros/silly_tavern_preset_import.dart';
import '../../shared/settings_form_dialog_scaffold.dart';

class SillyTavernImportDialog extends ConsumerStatefulWidget {
  const SillyTavernImportDialog({super.key});
  @override
  ConsumerState<SillyTavernImportDialog> createState() =>
      _SillyTavernImportDialogState();
}

class _SillyTavernImportDialogState
    extends ConsumerState<SillyTavernImportDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _placements = <String, PromptMessagePlacement>{};
  SillyTavernPresetFile? _source;
  int _order = 0;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final file = await ref.read(presetImportSourceProvider)();
      if (!mounted || file == null) return;
      final source = SillyTavernPresetFile.parse(file.text);
      setState(() {
        _source = source;
        _order = source.preferredOrder;
        _placements.clear();
        _name.text = file.name.replaceFirst(
          RegExp(r'\.json$', caseSensitive: false),
          '',
        );
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final source = _source;
    if (source == null) return;
    final plan = source.plan(_order, placements: _placements);
    if (!plan.canImport) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final preset = source.createPreset(
        plan,
        name: _name.text.trim(),
        newId: generateEntityId,
      );
      await ref.read(presetPromptsProvider.notifier).upsert(preset);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final source = _source;
    final plan = source?.plan(_order, placements: _placements);
    final placementIssues = source
        ?.plan(_order)
        .issues
        .where((issue) => issue.needsPlacement);
    final macroDiagnostics = plan == null
        ? const <PresetMacroDiagnostic>[]
        : renderPresetPrompt(
            PresetPrompt(
              id: 'import-preview',
              name: _name.text,
              messages: plan.messages,
              syntax: PresetPromptSyntax.sillyTavernSubsetV1,
              updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
            ),
          ).diagnostics;
    return SettingsFormDialogScaffold(
      title: '导入 SillyTavern 预设',
      formKey: _formKey,
      isSaving: _busy,
      onSubmit: _save,
      submitLabel: '导入',
      submitEnabled: plan?.canImport == true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OutlinedButton.icon(
            onPressed: _busy ? null : _pick,
            icon: const Icon(Icons.file_open_outlined),
            label: const Text('选择 JSON 文件'),
          ),
          const SizedBox(height: AppSpacing.md),
          const Text('保留标题、正文、顺序和开关。仅适配 Chat 写作所需的有限宏；前端美化、正则、脚本及外部记忆不会运行。'),
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: LinearProgressIndicator(),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: SelectableText(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (source != null && plan != null) ...[
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: '预设名称'),
              validator: (value) =>
                  value?.trim().isEmpty != false ? '请填写名称' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            if (source.orders.length > 1)
              DropdownButtonFormField<int>(
                initialValue: _order,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '使用哪个顺序表'),
                items: [
                  for (var i = 0; i < source.orders.length; i++)
                    DropdownMenuItem(
                      value: i,
                      child: Text(
                        '${source.orders[i].name} · ${source.orders[i].entries.length} 条',
                      ),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() {
                            _order = value;
                            _placements.clear();
                          });
                        }
                      },
              ),
            const SizedBox(height: AppSpacing.md),
            Text(
              '导入 ${plan.messages.length} 条，其中 ${plan.spareCount} 条为默认关闭的备用条目。',
            ),
            const Text('备用 Relative 条目默认前置。标题不决定互斥、启停或功能。{{user}} 固定为 user。'),
            for (final issue in placementIssues!)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.md),
                child: DropdownButtonFormField<PromptMessagePlacement>(
                  key: ValueKey('placement-${issue.identifier}'),
                  initialValue: _placements[issue.identifier],
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: issue.title.isEmpty
                        ? issue.identifier
                        : issue.title,
                    helperText: issue.message,
                    helperMaxLines: 3,
                  ),
                  items: [
                    for (final placement in PromptMessagePlacement.values)
                      DropdownMenuItem(
                        value: placement,
                        child: Text(placement.label),
                      ),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(
                              () => _placements[issue.identifier] = value,
                            );
                          }
                        },
                ),
              ),
            ExpansionTile(
              title: Text(
                '结构说明（${plan.issues.where((i) => !i.needsPlacement).length}）',
              ),
              children: [
                for (final issue in plan.issues.where(
                  (issue) => !issue.needsPlacement,
                ))
                  ListTile(
                    title: Text(
                      issue.title.isEmpty ? issue.identifier : issue.title,
                    ),
                    subtitle: Text(issue.message),
                  ),
              ],
            ),
            ExpansionTile(
              title: Text('宏诊断（${macroDiagnostics.length}）'),
              children: [
                const ListTile(
                  subtitle: Text(
                    '这里尚未提供用户输入；导入后可在 Chat 的“查看当前上下文”中检查实际展开。未知宏保留原文，解析错误需修正后才能发送。',
                  ),
                ),
                for (final diagnostic in macroDiagnostics)
                  ListTile(
                    title: Text(
                      diagnostic.title.isEmpty ? '无标题条目' : diagnostic.title,
                    ),
                    subtitle: SelectableText(
                      '${diagnostic.message}\n${diagnostic.expression}',
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
