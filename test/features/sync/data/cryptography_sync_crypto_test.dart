import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/sync/data/cryptography_sync_crypto.dart';

void main() {
  test('AES-GCM 拒绝 AAD 和密文篡改，不返回明文', () async {
    final crypto = CryptographySyncCrypto();
    final key = crypto.randomBytes(32);
    final nonce = crypto.randomBytes(12);
    final ciphertext = await crypto.encrypt(
      key: key,
      nonce: nonce,
      plaintext: utf8.encode('sk-test-key'),
      aad: utf8.encode('header'),
    );

    expect(
      await crypto.decrypt(
        key: key,
        nonce: nonce,
        ciphertext: ciphertext,
        aad: utf8.encode('different-header'),
      ),
      isNull,
    );
    ciphertext[0] ^= 1;
    expect(
      await crypto.decrypt(
        key: key,
        nonce: nonce,
        ciphertext: ciphertext,
        aad: utf8.encode('header'),
      ),
      isNull,
    );
  });
}
