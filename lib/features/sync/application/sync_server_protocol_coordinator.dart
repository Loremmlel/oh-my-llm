import 'dart:convert';

import '../../settings/domain/models/settings_export_data.dart';
import '../domain/models/sync_pairing.dart';
import '../domain/models/sync_protocol_failure.dart';
import '../domain/models/sync_protocol_message.dart';
import '../domain/models/sync_session.dart';
import '../domain/models/sync_types.dart';
import 'ports/settings_sync_facade.dart';
import 'ports/sync_clock.dart';
import 'ports/sync_crypto.dart';
import 'ports/sync_pairing_repository.dart';
import 'sync_session_registry.dart';

/// server protocol 的业务安全闸门；HTTP handler 仅负责编解码和 status 映射。
final class SyncServerProtocolCoordinator {
  SyncServerProtocolCoordinator({
    required SyncPairingRepository pairingRepository,
    required SyncCrypto crypto,
    required SyncClock clock,
    required SettingsSyncFacade settingsFacade,
    SyncSessionRegistry? sessions,
  }) : _pairingRepository = pairingRepository,
       _crypto = crypto,
       _clock = clock,
       _settingsFacade = settingsFacade,
       _sessions = sessions ?? SyncSessionRegistry(clock);

  static const pairingCodeLifetime = Duration(minutes: 5);
  static const _maxPairingAttempts = 5;

  final SyncPairingRepository _pairingRepository;
  final SyncCrypto _crypto;
  final SyncClock _clock;
  final SettingsSyncFacade _settingsFacade;
  final SyncSessionRegistry _sessions;
  _PendingPairingCode? _pendingCode;
  final Map<String, _PairingChallenge> _challenges = {};

  /// 本地 UI 获取一次性 code。它只存在内存并由调用处本地展示。
  Future<String> generatePairingCode() async {
    final code = base64UrlEncode(_crypto.randomBytes(20)).replaceAll('=', '');
    _pendingCode = _PendingPairingCode(
      code: code,
      expiresAt: _clock.now().add(pairingCodeLifetime),
    );
    _challenges.clear();
    return code;
  }

  Future<SyncServerProtocolResult> handle(SyncProtocolMessage request) async {
    try {
      return switch (request) {
        PairingChallengeRequest() => _challenge(request),
        PairingProofRequest() => _proof(request),
        SessionOpenRequest() => _openSession(request),
        EncryptedSyncRequest() => _sync(request),
        _ => _failure(
          request.requestId,
          SyncProtocolErrorCode.malformedMessage,
        ),
      };
    } catch (_) {
      return _failure(request.requestId, SyncProtocolErrorCode.serverBusy);
    }
  }

  void invalidateAllSessions() => _sessions.clear();

  Future<void> grant({
    required String peerId,
    required Set<SyncCategory> categories,
    required bool confirmedSensitive,
  }) async {
    if (categories.any((item) => item.isCredentialBearing) &&
        !confirmedSensitive) {
      throw const SyncProtocolFailure(
        SyncProtocolErrorCode.sensitiveConfirmationRequired,
      );
    }
    final record = await _pairingRepository.load(peerId);
    if (record == null) {
      throw const SyncProtocolFailure(SyncProtocolErrorCode.pairingRequired);
    }
    await _pairingRepository.updateGrants(peerId, {
      ...record.grantedCategories,
      ...categories,
    });
  }

  Future<void> revoke(String peerId) async {
    await _pairingRepository.revoke(peerId);
    _sessions.invalidatePeer(peerId);
  }

  Future<SyncServerProtocolResult> _challenge(
    PairingChallengeRequest request,
  ) async {
    final pending = _pendingCode;
    if (pending == null || _clock.now().isAfter(pending.expiresAt)) {
      return _failure(request.requestId, SyncProtocolErrorCode.pairingRequired);
    }
    final server = await _localIdentity();
    final pairingId = _randomId(16);
    final nonce = _crypto.randomBytes(16);
    _challenges[pairingId] = _PairingChallenge(
      clientId: request.clientIdentity,
      challengeNonce: nonce,
      createdAt: _clock.now(),
    );
    return SyncServerProtocolResult(
      PairingChallengeResponse(
        requestId: request.requestId,
        pairingId: pairingId,
        challengeNonce: base64Encode(nonce),
        serverIdentity: server.id,
      ),
    );
  }

  Future<SyncServerProtocolResult> _proof(PairingProofRequest request) async {
    final pending = _pendingCode;
    final challenge = _challenges.remove(request.pairingId);
    if (pending == null ||
        challenge == null ||
        _clock.now().isAfter(pending.expiresAt) ||
        pending.attempts >= _maxPairingAttempts ||
        challenge.clientId != request.clientIdentity) {
      return _pairingRejected(request.requestId);
    }
    final server = await _localIdentity();
    final transcript = SyncPairingTranscript(
      serverIdentity: server.id,
      pairingId: request.pairingId,
      challengeNonce: base64Encode(challenge.challengeNonce),
      clientIdentity: request.clientIdentity,
      clientNonce: request.clientNonce,
    );
    final valid = await _crypto.verifyHmac(
      secret: utf8.encode(pending.code),
      message: transcript.canonicalBytes,
      proof: base64Decode(request.proof),
    );
    if (!valid) {
      pending.attempts++;
      return _pairingRejected(request.requestId);
    }
    final secret = await _crypto.hkdf(
      secret: utf8.encode(pending.code),
      salt: transcript.canonicalBytes,
      info: utf8.encode('oh-my-llm-sync-v2-pairing'),
    );
    final now = _clock.now();
    await _pairingRepository.save(
      record: SyncPairingRecord(
        peer: SyncPeerIdentity(
          id: request.clientIdentity,
          displayName: request.clientDisplayName,
        ),
        grantedCategories: const {},
        createdAt: now,
        lastUsedAt: now,
      ),
      secret: secret,
    );
    _pendingCode = null;
    _challenges.clear();
    final responseProof = await _crypto.hmac(
      secret: secret,
      message: utf8.encode(
        'pairing-response:${base64Encode(transcript.canonicalBytes)}',
      ),
    );
    return SyncServerProtocolResult(
      PairingProofResponse(
        requestId: request.requestId,
        serverIdentity: server.id,
        proof: base64Encode(responseProof),
      ),
    );
  }

  Future<SyncServerProtocolResult> _openSession(
    SessionOpenRequest request,
  ) async {
    final record = await _pairingRepository.load(request.peerId);
    final secret = record == null
        ? null
        : await _pairingRepository.loadSecret(request.peerId);
    if (secret == null) {
      return _failure(request.requestId, SyncProtocolErrorCode.pairingRequired);
    }
    final message = utf8.encode(
      'session-open:${request.peerId}:${request.clientNonce}',
    );
    if (!await _crypto.verifyHmac(
      secret: secret,
      message: message,
      proof: base64Decode(request.proof),
    )) {
      return _failure(request.requestId, SyncProtocolErrorCode.pairingRejected);
    }
    final serverNonce = _crypto.randomBytes(16);
    final sessionId = _randomId(16);
    final token = _crypto.randomBytes(32);
    final key = await _crypto.hkdf(
      secret: secret,
      salt: [...base64Decode(request.clientNonce), ...serverNonce],
      info: utf8.encode('oh-my-llm-sync-v2-session'),
    );
    final now = _clock.now();
    _sessions.open(
      SyncSession(
        id: sessionId,
        peerId: request.peerId,
        token: token,
        key: key,
        createdAt: now,
        lastActivityAt: now,
      ),
    );
    final proof = await _crypto.hmac(
      secret: secret,
      message: utf8.encode(
        'session-open-response:$sessionId:${base64Encode(token)}:${base64Encode(serverNonce)}',
      ),
    );
    return SyncServerProtocolResult(
      SessionOpenResponse(
        requestId: request.requestId,
        sessionId: sessionId,
        sessionToken: base64Encode(token),
        serverNonce: base64Encode(serverNonce),
        proof: base64Encode(proof),
      ),
    );
  }

  Future<SyncServerProtocolResult> _sync(EncryptedSyncRequest request) async {
    final session = _sessions.lookup(
      sessionId: request.sessionId,
      token: base64Decode(request.sessionToken),
    );
    if (session == null) {
      return _failure(request.requestId, SyncProtocolErrorCode.sessionInvalid);
    }
    final nonce = base64Decode(request.nonce);
    if (!_sessions.isFresh(request.issuedAtMs) ||
        !_sessions.consumeNonce(sessionId: session.id, nonce: nonce)) {
      return _failure(request.requestId, SyncProtocolErrorCode.replayRejected);
    }
    final plain = await _crypto.decrypt(
      key: session.key,
      nonce: nonce,
      ciphertext: base64Decode(request.ciphertext),
      aad: utf8.encode(SyncProtocolCodec.canonicalAad(request)),
    );
    final payload = plain == null
        ? null
        : SyncProtocolCodec.tryDecodePayload(
            utf8.decode(plain, allowMalformed: false),
          );
    if (payload is! SettingsSyncRequestPayload) {
      return _failure(request.requestId, SyncProtocolErrorCode.replayRejected);
    }
    final record = await _pairingRepository.load(session.peerId);
    if (record == null) {
      _sessions.invalidatePeer(session.peerId);
      return _failure(request.requestId, SyncProtocolErrorCode.pairingRequired);
    }
    if (!record.grantedCategories.containsAll(payload.categories)) {
      return _failure(
        request.requestId,
        SyncProtocolErrorCode.authorizationRequired,
      );
    }
    final export = _settingsFacade.exportSelected(
      _selection(payload.categories),
    );
    return _encryptedSnapshot(request, session, export);
  }

  Future<SyncServerProtocolResult> _encryptedSnapshot(
    EncryptedSyncRequest request,
    SyncSession session,
    SettingsExportData data,
  ) async {
    final nonce = _crypto.randomBytes(12);
    final response = EncryptedSyncResponse(
      requestId: request.requestId,
      sessionId: session.id,
      sessionToken: base64Encode(session.token),
      issuedAtMs: _clock.now().millisecondsSinceEpoch,
      nonce: base64Encode(nonce),
      ciphertext: '',
    );
    final payload = SettingsSyncResponsePayload(
      SettingsSnapshotPayload(
        formatVersion: SettingsExportData.formatVersion,
        data: data,
      ),
    );
    final ciphertext = await _crypto.encrypt(
      key: session.key,
      nonce: nonce,
      plaintext: utf8.encode(SyncProtocolCodec.encodePayload(payload)),
      aad: utf8.encode(SyncProtocolCodec.canonicalAad(response)),
    );
    return SyncServerProtocolResult(
      EncryptedSyncResponse(
        requestId: response.requestId,
        sessionId: response.sessionId,
        sessionToken: response.sessionToken,
        issuedAtMs: response.issuedAtMs,
        nonce: response.nonce,
        ciphertext: base64Encode(ciphertext),
      ),
      servedSnapshot: true,
    );
  }

  Future<SyncPeerIdentity> _localIdentity() =>
      _pairingRepository.ensureLocalIdentity(_crypto.randomBytes(16));

  SyncServerProtocolResult _pairingRejected(String requestId) =>
      _failure(requestId, SyncProtocolErrorCode.pairingRejected);

  SyncServerProtocolResult _failure(
    String requestId,
    SyncProtocolErrorCode code,
  ) => SyncServerProtocolResult(
    SyncProtocolError(requestId: requestId, failure: SyncProtocolFailure(code)),
  );

  String _randomId(int bytes) =>
      base64UrlEncode(_crypto.randomBytes(bytes)).replaceAll('=', '');

  SettingsSyncSelection _selection(Set<SyncCategory> categories) =>
      SettingsSyncSelection(
        providers: categories.contains(SyncCategory.providers),
        presets: categories.contains(SyncCategory.presets),
        prompts: categories.contains(SyncCategory.prompts),
        other: categories.contains(SyncCategory.other),
      );
}

final class SyncServerProtocolResult {
  const SyncServerProtocolResult(this.message, {this.servedSnapshot = false});

  final SyncProtocolMessage message;
  final bool servedSnapshot;
}

final class _PendingPairingCode {
  _PendingPairingCode({required this.code, required this.expiresAt});
  final String code;
  final DateTime expiresAt;
  var attempts = 0;
}

final class _PairingChallenge {
  const _PairingChallenge({
    required this.clientId,
    required this.challengeNonce,
    required this.createdAt,
  });
  final String clientId;
  final List<int> challengeNonce;
  final DateTime createdAt;
}
