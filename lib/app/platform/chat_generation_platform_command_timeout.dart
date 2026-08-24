/// 单次平台命令等待原生 ACK 的固定上界（Android 与 Windows 共享）。
///
/// 原生侧未响应（无 handler、engine detach、宿主卡死等）时，通道调用以
/// [TimeoutException] 收束并按各域固定分类 fail-open，防止卡死通知串行 tail。
const chatGenerationPlatformCommandTimeout = Duration(seconds: 2);
