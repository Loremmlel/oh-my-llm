import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 应用层仅知道 bytes 和安全失败，不耦合 cryptography 包。
abstract interface class SyncCrypto {
  List<int> randomBytes(int length);

  Future<List<int>> hmac({
    required List<int> secret,
    required List<int> message,
  });

  Future<bool> verifyHmac({
    required List<int> secret,
    required List<int> message,
    required List<int> proof,
  });

  Future<List<int>> hkdf({
    required List<int> secret,
    required List<int> salt,
    required List<int> info,
  });

  Future<List<int>> encrypt({
    required List<int> key,
    required List<int> nonce,
    required List<int> plaintext,
    required List<int> aad,
  });

  Future<List<int>?> decrypt({
    required List<int> key,
    required List<int> nonce,
    required List<int> ciphertext,
    required List<int> aad,
  });
}

final syncCryptoProvider = Provider<SyncCrypto>((ref) {
  throw StateError('SyncCrypto 尚未由应用组合层绑定');
});
