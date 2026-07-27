import 'dart:math';

import 'package:cryptography/cryptography.dart';

import '../application/ports/sync_crypto.dart';

/// 以 AES-GCM / HMAC-SHA256 / HKDF-SHA256 实现 Sync 的纯数据层加密端口。
final class CryptographySyncCrypto implements SyncCrypto {
  CryptographySyncCrypto({Random? random})
    : _random = random ?? Random.secure();

  final Random _random;
  final _hmac = Hmac.sha256();
  final _aesGcm = AesGcm.with256bits();
  final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  @override
  List<int> randomBytes(int length) =>
      List<int>.generate(length, (_) => _random.nextInt(256), growable: false);

  @override
  Future<List<int>> hmac({
    required List<int> secret,
    required List<int> message,
  }) async {
    final mac = await _hmac.calculateMac(message, secretKey: SecretKey(secret));
    return mac.bytes;
  }

  @override
  Future<bool> verifyHmac({
    required List<int> secret,
    required List<int> message,
    required List<int> proof,
  }) async =>
      _constantTimeEquals(await hmac(secret: secret, message: message), proof);

  @override
  Future<List<int>> hkdf({
    required List<int> secret,
    required List<int> salt,
    required List<int> info,
  }) async {
    final derived = await _hkdf.deriveKey(
      secretKey: SecretKey(secret),
      nonce: salt,
      info: info,
    );
    return derived.extractBytes();
  }

  @override
  Future<List<int>> encrypt({
    required List<int> key,
    required List<int> nonce,
    required List<int> plaintext,
    required List<int> aad,
  }) async {
    final box = await _aesGcm.encrypt(
      plaintext,
      secretKey: SecretKey(key),
      nonce: nonce,
      aad: aad,
    );
    return [...box.cipherText, ...box.mac.bytes];
  }

  @override
  Future<List<int>?> decrypt({
    required List<int> key,
    required List<int> nonce,
    required List<int> ciphertext,
    required List<int> aad,
  }) async {
    if (ciphertext.length < 16) return null;
    try {
      return await _aesGcm.decrypt(
        SecretBox(
          ciphertext.sublist(0, ciphertext.length - 16),
          nonce: nonce,
          mac: Mac(ciphertext.sublist(ciphertext.length - 16)),
        ),
        secretKey: SecretKey(key),
        aad: aad,
      );
    } on SecretBoxAuthenticationError {
      return null;
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
