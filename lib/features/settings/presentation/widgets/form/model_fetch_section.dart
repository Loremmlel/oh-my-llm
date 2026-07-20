import 'package:flutter/material.dart';

import '../../../data/model_list_client.dart';
import '../../../data/model_list_url.dart';
import '../../../domain/models/llm_provider_config.dart';

/// 拉取模式中单个模型的选择状态。
class ModelSelectionEntry {
  ModelSelectionEntry({
    required this.remoteModel,
    required this.controller,
    this.alreadyExists = false,
  });

  final RemoteModelInfo remoteModel;

  final TextEditingController controller;

  bool selected = false;

  final bool alreadyExists;

  void dispose() {
    controller.dispose();
  }
}

/// 拉取模式的 UI 区块。
///
/// 负责发起 /models 请求、展示返回的模型列表、管理勾选和显示名输入。
class ModelFetchSection extends StatefulWidget {
  const ModelFetchSection({
    required this.provider,
    required this.fetchModels,
    this.onSelectionChanged,
    super.key,
  });

  final LlmProviderConfig provider;

  final Future<List<RemoteModelInfo>> Function({
    required String modelsUrl,
    required String apiKey,
  }) fetchModels;

  /// 当勾选状态或显示名变化时通知父级刷新。
  final void Function()? onSelectionChanged;

  @override
  State<ModelFetchSection> createState() => ModelFetchSectionState();
}

enum _FetchStatus { idle, loading, loaded, error }

class ModelFetchSectionState extends State<ModelFetchSection> {
  _FetchStatus _status = _FetchStatus.idle;
  String? _errorMessage;
  List<ModelSelectionEntry> entries = [];
  String _editedUrl = '';
  bool _isUrlEdited = false;
  bool _showAdvanced = false;

  String get _derivedUrl => deriveModelsUrl(widget.provider.apiUrl);

  String get _effectiveUrl => _isUrlEdited ? _editedUrl : _derivedUrl;

  @override
  void initState() {
    super.initState();
    _editedUrl = _derivedUrl;
  }

  @override
  void dispose() {
    for (final entry in entries) {
      entry.dispose();
    }
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() {
      _status = _FetchStatus.loading;
      _errorMessage = null;
    });

    for (final entry in entries) {
      entry.dispose();
    }

    try {
      final models = await widget.fetchModels(
        modelsUrl: _effectiveUrl,
        apiKey: widget.provider.apiKey,
      );

      final existingModelNames = widget.provider.models
          .map((m) => m.modelName)
          .toSet();

      if (!mounted) return;
      setState(() {
        entries = models
            .map((m) => ModelSelectionEntry(
                  remoteModel: m,
                  controller: TextEditingController(text: m.id),
                  alreadyExists:
                      existingModelNames.contains(m.id),
                ))
            .toList();
        _status = _FetchStatus.loaded;
      });
      widget.onSelectionChanged?.call();
    } on ModelListException catch (e) {
      if (!mounted) return;
      setState(() {
        _status = _FetchStatus.error;
        _errorMessage = e.message;
        if (e.responseBody != null) {
          _errorMessage = '${e.message}\n${e.responseBody}';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = _FetchStatus.error;
        _errorMessage = '未知错误：$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = widget.provider;

    if (provider.apiUrl.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            '请先在服务商配置中填写 API URL。',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildAdvancedSection(theme),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          key: const ValueKey('model-fetch-button'),
          onPressed: _status == _FetchStatus.loading ? null : _fetch,
          icon: _status == _FetchStatus.loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.download_rounded),
          label: Text(_status == _FetchStatus.loading ? '正在拉取...' : '拉取模型'),
        ),
        const SizedBox(height: 12),
        _buildStatusArea(theme),
      ],
    );
  }

  Widget _buildAdvancedSection(ThemeData theme) {
    if (!_showAdvanced) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: const ValueKey('model-fetch-advanced-toggle'),
          onPressed: () => setState(() => _showAdvanced = true),
          icon: const Icon(Icons.tune_rounded, size: 18),
          label: Text(
            _effectiveUrl,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          key: const ValueKey('model-fetch-url-field'),
          initialValue: _editedUrl,
          decoration: const InputDecoration(
            labelText: 'Models 端点 URL',
            isDense: true,
          ),
          onChanged: (value) {
            _editedUrl = value;
            _isUrlEdited = true;
          },
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => setState(() => _showAdvanced = false),
            child: const Text('收起'),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusArea(ThemeData theme) {
    switch (_status) {
      case _FetchStatus.idle:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: Text(
              '点击上方按钮从服务器拉取可用模型列表。',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        );
      case _FetchStatus.loading:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: Text(
              '正在拉取模型列表...',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        );
      case _FetchStatus.error:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _errorMessage ?? '拉取失败',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const ValueKey('model-fetch-retry'),
                  onPressed: _fetch,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('重试'),
                ),
              ),
            ],
          ),
        );
      case _FetchStatus.loaded:
        if (entries.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                '服务器未返回任何模型。',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          );
        }
        return _buildModelList(theme);
    }
  }

  Widget _buildModelList(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in entries) _buildModelRow(theme, entry),
      ],
    );
  }

  Widget _buildModelRow(ThemeData theme, ModelSelectionEntry entry) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            key: ValueKey('model-fetch-checkbox-${entry.remoteModel.id}'),
            value: entry.selected,
            onChanged: (value) {
              setState(() {
                entry.selected = value ?? false;
              });
              widget.onSelectionChanged?.call();
            },
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Tooltip(
                        message: entry.remoteModel.id,
                        child: Text(
                          entry.remoteModel.id,
                          style: theme.textTheme.bodyMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    if (entry.alreadyExists) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '已存在',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                TextFormField(
                  key: ValueKey(
                    'model-fetch-display-name-${entry.remoteModel.id}',
                  ),
                  controller: entry.controller,
                  enabled: entry.selected,
                  decoration: const InputDecoration(
                    labelText: '显示名称',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) {
                    setState(() {});
                    widget.onSelectionChanged?.call();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
