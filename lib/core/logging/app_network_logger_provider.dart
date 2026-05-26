import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'network_logger.dart';

/// 应用级网络日志记录器 Provider。
///
/// 类型为 [NetworkLogger] 接口（而非具体实现 `AppNetworkLogger`），
/// 允许测试通过 `NoopNetworkLogger` 注入空操作实现，避免测试中产生磁盘日志文件。
/// 生产环境由 [bootstrap] 函数通过 [AppNetworkLogger] 覆写。
final appNetworkLoggerProvider = Provider<NetworkLogger>((ref) {
  throw UnimplementedError('NetworkLogger must be overridden at bootstrap.');
});
