/// 已退休的 Sync v1 动态信封。
///
/// 历史测试可保留导入该文件的编译兼容性，但 app/transport 不再包含构造器或
/// decoder，因此无法重新创建匿名 v1 请求。
@Deprecated('Sync v1 已退休；请使用 sync_protocol_message.dart。')
abstract final class SyncMessage {
  const SyncMessage._();
}
