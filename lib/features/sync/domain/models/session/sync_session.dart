import 'package:equatable/equatable.dart';

/// 内存 session，token 和 key 不会持久化或投影到 Riverpod state。
final class SyncSession extends Equatable {
  const SyncSession({
    required this.id,
    required this.peerId,
    required this.token,
    required this.key,
    required this.createdAt,
    required this.lastActivityAt,
  });

  final String id;
  final String peerId;
  final List<int> token;
  final List<int> key;
  final DateTime createdAt;
  final DateTime lastActivityAt;

  SyncSession touch(DateTime time) => SyncSession(
    id: id,
    peerId: peerId,
    token: token,
    key: key,
    createdAt: createdAt,
    lastActivityAt: time,
  );

  @override
  List<Object?> get props => [id, peerId, createdAt, lastActivityAt];
}
