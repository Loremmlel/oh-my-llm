import 'dart:convert';

import '../domain/models/session/sync_session.dart';
import 'ports/sync_clock.dart';

/// session 和 replay nonce 都只保存在内存中。
final class SyncSessionRegistry {
  SyncSessionRegistry(this._clock);

  static const idleLifetime = Duration(minutes: 10);
  static const absoluteLifetime = Duration(minutes: 30);
  static const freshnessWindow = Duration(minutes: 1);
  static const _maxNoncesPerSession = 256;

  final SyncClock _clock;
  final Map<String, SyncSession> _sessions = {};
  final Map<String, Map<String, DateTime>> _usedNonces = {};

  void open(SyncSession session) {
    _sessions[session.id] = session;
    _usedNonces[session.id] = {};
  }

  SyncSession? lookup({required String sessionId, required List<int> token}) {
    purgeExpired();
    final session = _sessions[sessionId];
    if (session == null || !_constantTimeEquals(session.token, token)) {
      return null;
    }
    final now = _clock.now();
    final touched = session.touch(now);
    _sessions[sessionId] = touched;
    return touched;
  }

  bool isFresh(int issuedAtMs) {
    final issuedAt = DateTime.fromMillisecondsSinceEpoch(issuedAtMs);
    return (_clock.now().difference(issuedAt)).abs() <= freshnessWindow;
  }

  bool consumeNonce({required String sessionId, required List<int> nonce}) {
    purgeExpired();
    final values = _usedNonces[sessionId];
    if (values == null) return false;
    final key = base64Encode(nonce);
    if (values.containsKey(key)) return false;
    values[key] = _clock.now();
    if (values.length > _maxNoncesPerSession) {
      final oldest = values.entries.reduce(
        (current, next) => current.value.isBefore(next.value) ? current : next,
      );
      values.remove(oldest.key);
    }
    return true;
  }

  void invalidatePeer(String peerId) {
    final ids = _sessions.values
        .where((session) => session.peerId == peerId)
        .map((session) => session.id)
        .toList(growable: false);
    for (final id in ids) {
      _sessions.remove(id);
      _usedNonces.remove(id);
    }
  }

  void clear() {
    _sessions.clear();
    _usedNonces.clear();
  }

  void purgeExpired() {
    final now = _clock.now();
    final expired = _sessions.values
        .where((session) {
          return now.difference(session.createdAt) > absoluteLifetime ||
              now.difference(session.lastActivityAt) > idleLifetime;
        })
        .map((session) => session.id)
        .toList(growable: false);
    for (final id in expired) {
      _sessions.remove(id);
      _usedNonces.remove(id);
    }
  }

  bool _constantTimeEquals(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    var difference = 0;
    for (var index = 0; index < left.length; index++) {
      difference |= left[index] ^ right[index];
    }
    return difference == 0;
  }
}
