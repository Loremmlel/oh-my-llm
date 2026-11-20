import 'package:material_ui/material_ui.dart';
import 'package:oh_my_llm/core/constants/app_layout_tokens.dart';
import 'package:oh_my_llm/core/widgets/app_text_field.dart';

import '../../../../application/providers/model_catalog_workflow.dart';
import '../../../../domain/models/providers/model_catalog_entry.dart';
import '../../../../domain/models/providers/llm_provider_config.dart';
import '../model_capability_chips.dart';

/// 拉取模式中单个模型的选择状态。
class ModelSelectionEntry {
  ModelSelectionEntry({
    required this.remoteModel,
    this.alreadyExists = false,
    this.supportsReasoning = false,
    this.supportsImageInput = false,
  }) : displayName = remoteModel.id;

  final ModelCatalogEntry remoteModel;

  String displayName;
  bool selected = false;

  final bool alreadyExists;

  bool supportsReasoning;
  bool supportsImageInput;
}

/// 拉取模式的 UI 区块。
///
/// 负责发起 /models 请求、展示返回的模型列表、管理勾选和显示名输入。
class ModelFetchSection extends StatefulWidget {
  const ModelFetchSection({
    required this.visible,
    required this.provider,
    required this.fetchModels,
    this.onSelectionChanged,
    super.key,
  });

  final bool visible;
  final LlmProviderConfig provider;

  final Future<List<ModelCatalogEntry>> Function(ModelCatalogRequest request)
  fetchModels;

  /// 当勾选状态或显示名称的有效性变化时通知父级刷新提交按钮。
  final void Function()? onSelectionChanged;

  @override
  State<ModelFetchSection> createState() => ModelFetchSectionState();
}

enum _FetchStatus { idle, loading, loaded, error }

class ModelFetchSectionState extends State<ModelFetchSection> {
  _FetchStatus _status = _FetchStatus.idle;
  String? _errorMessage;
  final _searchController = TextEditingController();
  List<ModelSelectionEntry> _entries = const [];
  List<ModelSelectionEntry> _filteredEntries = const [];
  String _editedUrl = '';
  bool _isUrlEdited = false;
  bool _showAdvanced = false;

  Iterable<ModelSelectionEntry> get selectedEntries =>
      _entries.where((entry) => entry.selected);

  String get _derivedUrl => resolveModelsUrl(
    ModelCatalogRequest(
      apiUrl: widget.provider.apiUrl,
      apiKey: widget.provider.apiKey,
      apiProtocol: widget.provider.apiProtocol,
    ),
  );

  String get _effectiveUrl => _isUrlEdited ? _editedUrl : _derivedUrl;

  @override
  void initState() {
    super.initState();
    _editedUrl = _derivedUrl;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    if (_status == _FetchStatus.loading) return;
    setState(() {
      _status = _FetchStatus.loading;
      _errorMessage = null;
      _entries = const [];
      _filteredEntries = const [];
      _searchController.clear();
    });
    widget.onSelectionChanged?.call();

    try {
      final models = await widget.fetchModels(
        ModelCatalogRequest(
          apiUrl: widget.provider.apiUrl,
          apiKey: widget.provider.apiKey,
          apiProtocol: widget.provider.apiProtocol,
          modelsUrlOverride: _isUrlEdited ? _editedUrl : null,
        ),
      );

      if (!mounted) return;
      final existingModelNames = widget.provider.models
          .map((m) => m.modelName)
          .toSet();

      setState(() {
        _entries = models
            .map(
              (m) => ModelSelectionEntry(
                remoteModel: m,
                alreadyExists: existingModelNames.contains(m.id),
              ),
            )
            .toList();
        _filteredEntries = _entries;
        _status = _FetchStatus.loaded;
      });
    } on ModelCatalogFailure catch (e) {
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
    // 切换到手动输入时保留目录与草稿，移除列表子树。
    if (!widget.visible) return const SliverToBoxAdapter();
    final theme = Theme.of(context);
    final provider = widget.provider;

    if (provider.apiUrl.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: Text(
              '请先在服务商配置中填写 API URL。',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      );
    }

    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildAdvancedSection(theme),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const ValueKey('model-fetch-button'),
                onPressed: _status == _FetchStatus.loading ? null : _fetch,
                icon: _status == _FetchStatus.loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download_rounded),
                label: Text(
                  _status == _FetchStatus.loading ? '正在拉取...' : '拉取模型',
                ),
              ),
              const SizedBox(height: 12),
              _buildStatusArea(theme),
            ],
          ),
        ),
        if (_filteredEntries.isNotEmpty)
          SliverList.builder(
            itemCount: _filteredEntries.length,
            itemBuilder: (context, index) =>
                _buildModelRow(theme, _filteredEntries[index]),
          ),
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
        AppTextField.form(
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
        if (_entries.isEmpty) {
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
        return _buildSearchField();
    }
  }

  void _updateSearch(String value) {
    final query = value.trim().toLowerCase();
    setState(() {
      _filteredEntries = query.isEmpty
          ? _entries
          : _entries
                .where(
                  (entry) => entry.remoteModel.id.toLowerCase().contains(query),
                )
                .toList();
    });
  }

  Widget _buildSearchField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(
          controller: _searchController,
          textInputAction: TextInputAction.search,
          autocorrect: false,
          enableSuggestions: false,
          onChanged: _updateSearch,
          decoration: InputDecoration(
            labelText: '搜索模型 ID',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _searchController.text.isEmpty
                ? null
                : IconButton(
                    tooltip: '清除搜索',
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      _updateSearch('');
                    },
                  ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (_filteredEntries.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('没有匹配的模型')),
          ),
      ],
    );
  }

  Widget _buildModelRow(ThemeData theme, ModelSelectionEntry entry) {
    return Padding(
      key: ObjectKey(entry),
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            key: ValueKey('model-fetch-checkbox-${entry.remoteModel.id}'),
            semanticLabel: entry.remoteModel.id,
            value: entry.selected,
            onChanged: entry.alreadyExists
                ? null
                : (value) {
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
                          borderRadius: BorderRadius.circular(AppRadii.sm),
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
                AppTextField.form(
                  key: ValueKey(
                    'model-fetch-display-name-${entry.remoteModel.id}',
                  ),
                  initialValue: entry.displayName,
                  enabled: entry.selected && !entry.alreadyExists,
                  decoration: const InputDecoration(
                    labelText: '显示名称',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    final wasEmpty = entry.displayName.trim().isEmpty;
                    entry.displayName = value;
                    if (wasEmpty != value.trim().isEmpty) {
                      widget.onSelectionChanged?.call();
                    }
                  },
                ),
                ModelCapabilityChips(
                  supportsReasoning: entry.supportsReasoning,
                  supportsImageInput: entry.supportsImageInput,
                  onReasoningChanged: entry.selected && !entry.alreadyExists
                      ? (value) =>
                            setState(() => entry.supportsReasoning = value)
                      : null,
                  onImageInputChanged: entry.selected && !entry.alreadyExists
                      ? (value) =>
                            setState(() => entry.supportsImageInput = value)
                      : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
