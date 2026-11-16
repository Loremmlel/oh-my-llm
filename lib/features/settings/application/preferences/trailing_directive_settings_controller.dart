import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oh_my_llm/core/persistence/settings_key_value_store.dart';
import 'package:oh_my_llm/core/persistence/versioned_json_store.dart';

import '../../domain/models/preferences/trailing_directive_settings.dart';

const String trailingDirectiveSettingsStorageKey =
    'settings.trailing_directive';

final trailingDirectiveSettingsProvider =
    NotifierProvider<
      TrailingDirectiveSettingsController,
      TrailingDirectiveSettings
    >(TrailingDirectiveSettingsController.new);

final trailingDirectiveSettingsStoreProvider =
    Provider<VersionedJsonStore<TrailingDirectiveSettings>>((ref) {
      return VersionedJsonStore<TrailingDirectiveSettings>(
        storage: ref.watch(settingsKeyValueStoreProvider),
        key: trailingDirectiveSettingsStorageKey,
        subject: 'trailing directive settings',
        fallback: () => const TrailingDirectiveSettings(),
        fromJson: TrailingDirectiveSettings.fromJson,
        toJson: (settings) => settings.toJson(),
      );
    });

/// 末尾指令全局设置控制器。
class TrailingDirectiveSettingsController
    extends Notifier<TrailingDirectiveSettings> {
  late TrailingDirectiveSettings _lastPersisted;
  late TrailingDirectiveSettings _pending;
  int _revision = 0;
  final List<Completer<void>> _waiters = [];
  bool _isFlushing = false;
  bool _disposed = false;

  @override
  TrailingDirectiveSettings build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    final initial = ref.read(trailingDirectiveSettingsStoreProvider).load();
    _lastPersisted = initial;
    _pending = initial;
    return initial;
  }

  Future<void> save(TrailingDirectiveSettings settings) {
    return _enqueue(settings, optimisticState: false);
  }

  Future<void> updateContent(String content) {
    return _enqueue(_pending.copyWith(content: content), optimisticState: true);
  }

  Future<void> setAlternatingMode(bool alternatingMode) {
    return _enqueue(
      _pending.copyWith(alternatingMode: alternatingMode),
      optimisticState: true,
    );
  }

  Future<void> _enqueue(
    TrailingDirectiveSettings next, {
    required bool optimisticState,
  }) {
    _revision += 1;
    _pending = next;
    if (optimisticState) {
      state = next;
    }
    final store = ref.read(trailingDirectiveSettingsStoreProvider);
    final completer = Completer<void>();
    _waiters.add(completer);
    if (!_isFlushing) {
      _isFlushing = true;
      unawaited(_flushLoop(store));
    }
    return completer.future;
  }

  Future<void> _flushLoop(
    VersionedJsonStore<TrailingDirectiveSettings> store,
  ) async {
    try {
      while (_waiters.isNotEmpty) {
        final batchWaiters = List<Completer<void>>.of(_waiters);
        _waiters.clear();
        final target = _pending;
        final targetRevision = _revision;
        try {
          await store.save(target);
          _lastPersisted = target;
          if (!_disposed && _revision == targetRevision) {
            state = target;
          }
          for (final completer in batchWaiters) {
            completer.complete();
          }
        } catch (error, stackTrace) {
          if (!_disposed && _revision == targetRevision) {
            _pending = _lastPersisted;
            state = _lastPersisted;
          }
          for (final completer in batchWaiters) {
            completer.completeError(error, stackTrace);
          }
        }
      }
    } finally {
      _isFlushing = false;
    }
  }
}
