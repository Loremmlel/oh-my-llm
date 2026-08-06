import '../domain/models/chat_conversation.dart';
import 'chat_generation_contract.dart';
import 'chat_generation_run.dart';
import 'ports/chat_completion_client.dart';

/// generation 时序的唯一 owner（不变量 1）。
///
/// 同一时刻只持有一个 [ChatGenerationRun]。新 generation command 由 controller
/// 的 busy guard 拒绝（不变量 5：旧 run terminal durable 完成前新 command 不开始），
/// 因此 coordinator 不需 supersede 路径；dispose 是唯一取消 current run 的途径。
///
/// coordinator 不操作 Riverpod、消息树或 repository--那些由 [ChatGenerationHost]
///（controller）负责。coordinator 只创建 run、转发 stop、在 dispose 时取消。
class ChatGenerationCoordinator {
  ChatGenerationCoordinator({required ChatCompletionClient client})
    : _client = client;

  final ChatCompletionClient _client;

  ChatGenerationRun? _currentRun;
  bool _disposed = false;
  int _nextGenerationId = 1;

  /// 启动新 run。调用方（controller）保证已通过 busy guard，无 active run。
  /// 返回 run 的 completion：terminal 完成时 complete（成功带最终会话，
  /// 取消/失败/persistenceFailed 为 null）。完成即 durable（不变量 4）。
  Future<ChatConversation?> start(
    ChatGenerationCommand command,
    ChatGenerationHost host,
  ) {
    if (_disposed) return Future.value(null);
    final currentRun = _currentRun;
    if (currentRun != null && !currentRun.isTerminal) {
      return currentRun.completion;
    }
    final run = ChatGenerationRun(
      generationId: _nextGenerationId++,
      client: _client,
      host: host,
      command: command,
    );
    _currentRun = run;
    run.start();
    return run.completion;
  }

  /// 用户停止 facade（不变量 6：幂等）。无 run 返回同步 null；有 run 记录停止
  /// 意图并返回同一 completion（第二次 stop 不重复入队、不重复保存）。
  Future<ChatConversation?> stop() {
    final run = _currentRun;
    if (run == null) return Future.value(null);
    run.requestStop();
    return run.completion;
  }

  /// 当前 run 的 completion；无 run 时为 null。stopStreaming 据此决定 await 或兜底。
  Future<ChatConversation?>? get currentCompletion => _currentRun?.completion;

  /// 当前是否有未 terminal 的 run。
  bool get hasActive => _currentRun != null && !_currentRun!.isTerminal;

  /// controller dispose 时调用：cancel 订阅/定时器，complete(null)。
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _currentRun?.dispose();
    _currentRun = null;
  }
}
