import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/sync/domain/models/sync_protocol_version.dart';

void main() {
  group('SyncProtocolVersionPolicy', () {
    test('只接受 v2，拒绝缺失、旧版本和未来版本', () {
      expect(SyncProtocolVersionPolicy.check(2).isSupported, isTrue);
      expect(SyncProtocolVersionPolicy.check(null).isSupported, isFalse);
      expect(
        SyncProtocolVersionPolicy.check(1).direction,
        SyncProtocolVersionDirection.tooOld,
      );
      expect(
        SyncProtocolVersionPolicy.check(3).direction,
        SyncProtocolVersionDirection.tooNew,
      );
    });

    test('discovery 只有支持区间重叠时才兼容', () {
      expect(
        SyncProtocolRange.local.overlaps(
          const SyncProtocolRange(minimum: 2, maximum: 2),
        ),
        isTrue,
      );
      expect(
        SyncProtocolRange.local.overlaps(
          const SyncProtocolRange(minimum: 3, maximum: 3),
        ),
        isFalse,
      );
    });
  });
}
