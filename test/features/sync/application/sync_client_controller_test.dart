import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/sync/application/sync_client_controller.dart';
import 'package:oh_my_llm/features/sync/domain/models/discovered_server.dart';
import 'package:oh_my_llm/features/sync/domain/models/sync_protocol_version.dart';
import 'package:oh_my_llm/features/sync/domain/models/sync_types.dart';

void main() {
  test('客户端安全状态不会包含 pairing code 或 session secret', () {
    final state = SyncClientState(
      phase: SyncPhase.connected,
      server: const DiscoveredServer(
        deviceName: '服务器',
        ip: '192.168.1.2',
        httpPort: 8080,
        serverId: 'stable-server',
        protocolRange: SyncProtocolRange.local,
      ),
      selectedCategories: {SyncCategory.presets},
      isPaired: true,
    );

    expect(state.isPaired, isTrue);
    expect(state.selectedCategories, {SyncCategory.presets});
    expect(state.props.join(), isNot(contains('token')));
    expect(state.props.join(), isNot(contains('secret')));
  });

  test('分类变更会清除仅本次的敏感接收确认', () {
    final state = SyncClientState(
      selectedCategories: {SyncCategory.providers},
      sensitiveRequestConfirmed: true,
    );

    final changed = state.copyWith(
      selectedCategories: {SyncCategory.presets},
      sensitiveRequestConfirmed: false,
    );

    expect(changed.sensitiveRequestConfirmed, isFalse);
  });
}
