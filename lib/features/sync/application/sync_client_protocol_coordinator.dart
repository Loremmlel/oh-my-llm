import 'dart:convert';

import 'package:oh_my_llm/features/settings/domain/models/settings_export_data.dart';
import '../domain/models/discovered_server.dart';
import '../domain/models/sync_pairing.dart';
import '../domain/models/sync_protocol_failure.dart';
import '../domain/models/sync_protocol_message.dart';
import '../domain/models/sync_session.dart';
import '../domain/models/sync_types.dart';
import 'ports/sync_clock.dart';
import 'ports/sync_client_protocol.dart';
import 'ports/sync_client_transport.dart';
import 'ports/sync_crypto.dart';
import 'ports/sync_pairing_repository.dart';

/// 客户端的配对、session 与加密编排；controller 不处理密钥或 wire Map。
final class SyncClientProtocolCoordinator implements SyncClientProtocol {
  SyncClientProtocolCoordinator({
    required SyncClientTransport transport,
    required SyncPairingRepository pairingRepository,
    required SyncCrypto crypto,
    required SyncClock clock,
  }) : _transport = transport,
       _pairingRepository = pairingRepository,
       _crypto = crypto,
       _clock = clock;

  final SyncClientTransport _transport;
  final SyncPairingRepository _pairingRepository;
  final SyncCrypto _crypto;
  final SyncClock _clock;
  final Map<String, SyncSession> _sessions = {};

  @override
  Future<bool> isPaired(DiscoveredServer server) async {
    if (server.serverId.isEmpty) return false;
    return (await _pairingRepository.load(server.serverId)) != null;
  }

  @override
  Future<void> forgetPairing(DiscoveredServer server) async {
    _sessions.remove(server.serverId);
    if (server.serverId.isNotEmpty) {
      await _pairingRepository.revoke(server.serverId);
    }
  }

  @override
  Future<void> pair({
    required DiscoveredServer server,
    required String code,
    required String displayName,
  }) async {
    _checkCompatible(server);
    final normalizedCode = code.trim().toUpperCase();
    final local = await _pairingRepository.ensureLocalIdentity(
      _crypto.randomBytes(16),
    );
    final challengeRequest = PairingChallengeRequest(
      requestId: _randomId(16),
      clientIdentity: local.id,
    );
    final challengeResult = await _transport.send(
      server: server,
      request: challengeRequest,
    );
    final challenge = _expect<PairingChallengeResponse>(challengeResult);
    if (challenge.serverIdentity != server.serverId &&
        server.serverId.isNotEmpty) {
      throw const SyncProtocolFailure(SyncProtocolErrorCode.pairingRejected);
    }
    final clientNonce = _crypto.randomBytes(16);
    final transcript = SyncPairingTranscript(
      serverIdentity: challenge.serverIdentity,
      pairingId: challenge.pairingId,
      challengeNonce: challenge.challengeNonce,
      clientIdentity: local.id,
      clientNonce: base64Encode(clientNonce),
    );
    final proof = await _crypto.hmac(
      secret: utf8.encode(normalizedCode),
      message: transcript.canonicalBytes,
    );
    final proofRequest = PairingProofRequest(
      requestId: _randomId(16),
      pairingId: challenge.pairingId,
      clientIdentity: local.id,
      clientDisplayName: displayName.trim().isEmpty
          ? local.displayName
          : displayName.trim(),
      clientNonce: base64Encode(clientNonce),
      proof: base64Encode(proof),
    );
    final proofResult = await _transport.send(
      server: server,
      request: proofRequest,
    );
    final response = _expect<PairingProofResponse>(proofResult);
    final secret = await _crypto.hkdf(
      secret: utf8.encode(normalizedCode),
      salt: transcript.canonicalBytes,
      info: utf8.encode('oh-my-llm-sync-v3-pairing'),
    );
    final expectedProof = await _crypto.hmac(
      secret: secret,
      message: utf8.encode(
        'pairing-response:${base64Encode(transcript.canonicalBytes)}',
      ),
    );
    if (!_constantTimeEquals(expectedProof, base64Decode(response.proof))) {
      throw const SyncProtocolFailure(SyncProtocolErrorCode.pairingRejected);
    }
    final now = _clock.now();
    await _pairingRepository.save(
      record: SyncPairingRecord(
        peer: SyncPeerIdentity(
          id: response.serverIdentity,
          displayName: server.deviceName,
        ),
        createdAt: now,
        lastUsedAt: now,
      ),
      secret: secret,
    );
  }

  @override
  Future<SettingsExportData> requestSettings({
    required DiscoveredServer server,
    required Set<SyncCategory> categories,
    required bool confirmedSensitive,
  }) async {
    _checkCompatible(server);
    if (categories.isEmpty) {
      throw const SyncProtocolFailure(SyncProtocolErrorCode.malformedMessage);
    }
    if (categories.any((item) => item.isCredentialBearing) &&
        !confirmedSensitive) {
      throw const SyncProtocolFailure(
        SyncProtocolErrorCode.sensitiveConfirmationRequired,
      );
    }
    return _requestSettings(
      server: server,
      categories: categories,
      confirmedSensitive: confirmedSensitive,
      reopen: true,
    );
  }

  Future<SettingsExportData> _requestSettings({
    required DiscoveredServer server,
    required Set<SyncCategory> categories,
    required bool confirmedSensitive,
    required bool reopen,
  }) async {
    final session = await _sessionFor(server);
    final nonce = _crypto.randomBytes(12);
    final request = EncryptedSyncRequest(
      requestId: _randomId(16),
      sessionId: session.id,
      sessionToken: base64Encode(session.token),
      issuedAtMs: _clock.now().millisecondsSinceEpoch,
      nonce: base64Encode(nonce),
      ciphertext: '',
    );
    final ciphertext = await _crypto.encrypt(
      key: session.key,
      nonce: nonce,
      plaintext: utf8.encode(
        SyncProtocolCodec.encodePayload(
          SettingsSyncRequestPayload(
            categories,
            confirmedSensitive: confirmedSensitive,
          ),
        ),
      ),
      aad: utf8.encode(SyncProtocolCodec.canonicalAad(request)),
    );
    final encryptedRequest = EncryptedSyncRequest(
      requestId: request.requestId,
      sessionId: request.sessionId,
      sessionToken: request.sessionToken,
      issuedAtMs: request.issuedAtMs,
      nonce: request.nonce,
      ciphertext: base64Encode(ciphertext),
    );
    try {
      final result = await _transport.send(
        server: server,
        request: encryptedRequest,
      );
      final response = _expect<EncryptedSyncResponse>(result);
      if (response.requestId != encryptedRequest.requestId ||
          response.sessionId != session.id ||
          response.sessionToken != encryptedRequest.sessionToken) {
        throw const SyncProtocolFailure(SyncProtocolErrorCode.replayRejected);
      }
      final plain = await _crypto.decrypt(
        key: session.key,
        nonce: base64Decode(response.nonce),
        ciphertext: base64Decode(response.ciphertext),
        aad: utf8.encode(SyncProtocolCodec.canonicalAad(response)),
      );
      final payload = plain == null
          ? null
          : SyncProtocolCodec.tryDecodePayload(
              utf8.decode(plain, allowMalformed: false),
            );
      if (payload is! SettingsSyncResponsePayload) {
        throw const SyncProtocolFailure(SyncProtocolErrorCode.replayRejected);
      }
      return payload.snapshot.data;
    } on SyncProtocolFailure catch (failure) {
      if (reopen &&
          (failure.code == SyncProtocolErrorCode.sessionExpired ||
              failure.code == SyncProtocolErrorCode.sessionInvalid ||
              failure.code == SyncProtocolErrorCode.replayRejected)) {
        _sessions.remove(server.serverId);
        return _requestSettings(
          server: server,
          categories: categories,
          confirmedSensitive: confirmedSensitive,
          reopen: false,
        );
      }
      rethrow;
    }
  }

  Future<SyncSession> _sessionFor(DiscoveredServer server) async {
    final existing = _sessions[server.serverId];
    if (existing != null) return existing;
    final record = await _pairingRepository.load(server.serverId);
    final secret = record == null
        ? null
        : await _pairingRepository.loadSecret(server.serverId);
    if (secret == null) {
      throw const SyncProtocolFailure(SyncProtocolErrorCode.pairingRequired);
    }
    final clientNonce = _crypto.randomBytes(16);
    final localIdentity = await _pairingRepository.localIdentity();
    final proof = await _crypto.hmac(
      secret: secret,
      message: utf8.encode(
        'session-open:${localIdentity.id}:${base64Encode(clientNonce)}',
      ),
    );
    final request = SessionOpenRequest(
      requestId: _randomId(16),
      peerId: localIdentity.id,
      clientNonce: base64Encode(clientNonce),
      proof: base64Encode(proof),
    );
    final response = _expect<SessionOpenResponse>(
      await _transport.send(server: server, request: request),
    );
    final expectedProof = await _crypto.hmac(
      secret: secret,
      message: utf8.encode(
        'session-open-response:${response.sessionId}:${response.sessionToken}:${response.serverNonce}',
      ),
    );
    if (!_constantTimeEquals(expectedProof, base64Decode(response.proof))) {
      throw const SyncProtocolFailure(SyncProtocolErrorCode.sessionInvalid);
    }
    final key = await _crypto.hkdf(
      secret: secret,
      salt: [...clientNonce, ...base64Decode(response.serverNonce)],
      info: utf8.encode('oh-my-llm-sync-v3-session'),
    );
    final now = _clock.now();
    final session = SyncSession(
      id: response.sessionId,
      peerId: server.serverId,
      token: base64Decode(response.sessionToken),
      key: key,
      createdAt: now,
      lastActivityAt: now,
    );
    _sessions[server.serverId] = session;
    return session;
  }

  @override
  void clearSessions() => _sessions.clear();

  void _checkCompatible(DiscoveredServer server) {
    if (server.serverId.isEmpty || !server.isProtocolCompatible) {
      throw const SyncProtocolFailure(
        SyncProtocolErrorCode.unsupportedProtocol,
      );
    }
  }

  T _expect<T extends SyncProtocolMessage>(SyncProtocolMessage message) {
    if (message case SyncProtocolError(:final failure)) throw failure;
    if (message is! T) {
      throw const SyncProtocolFailure(SyncProtocolErrorCode.malformedMessage);
    }
    return message;
  }

  String _randomId(int bytes) =>
      base64UrlEncode(_crypto.randomBytes(bytes)).replaceAll('=', '');

  bool _constantTimeEquals(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    var difference = 0;
    for (var index = 0; index < left.length; index++) {
      difference |= left[index] ^ right[index];
    }
    return difference == 0;
  }
}
