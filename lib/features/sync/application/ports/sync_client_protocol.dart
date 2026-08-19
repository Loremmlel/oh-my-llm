import 'package:oh_my_llm/features/settings/domain/models/transfer/settings_transfer_document.dart';

import '../../domain/models/discovery/discovered_server.dart';
import '../../domain/models/protocol/sync_types.dart';

/// 客户端协议编排的应用层契约：controller 只依赖这些操作，不接触配对握手、
/// 加密或 wire 细节，便于用脚本化 fake 确定性测试状态转换。
abstract interface class SyncClientProtocol {
  Future<bool> isPaired(DiscoveredServer server);

  Future<void> pair({
    required DiscoveredServer server,
    required String code,
    required String displayName,
  });

  Future<SettingsTransferDocument> requestSettings({
    required DiscoveredServer server,
    required Set<SettingsSyncGroupId> groups,
    required bool confirmedSensitive,
  });

  Future<void> forgetPairing(DiscoveredServer server);

  void clearSessions();
}
