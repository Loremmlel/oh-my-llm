import 'dart:async';
import 'dart:convert';

import 'package:oh_my_llm/core/utils/id_generator.dart';
import 'package:oh_my_llm/core/llm/llm_call_control.dart';
import 'package:oh_my_llm/core/llm/llm_client.dart';
import 'package:oh_my_llm/core/llm/llm_content.dart';
import 'package:oh_my_llm/core/llm/llm_event.dart';
import 'package:oh_my_llm/core/llm/llm_request.dart';
import 'package:oh_my_llm/core/llm/llm_usage.dart';

import '../domain/agent_models.dart';
import 'agent_harness.dart';
import 'ports/agent_store.dart';

class AgentLimits {
  const AgentLimits({
    this.totalModelCalls = 24,
    this.mainRounds = 12,
    this.childRounds = 6,
    this.totalToolCalls = 64,
    this.children = 6,
    this.concurrentChildren = 2,
    this.duration = const Duration(minutes: 10),
  });
  final int totalModelCalls,
      mainRounds,
      childRounds,
      totalToolCalls,
      children,
      concurrentChildren;
  final Duration duration;
}

/// 一次用户任务及其子任务的 owner：循环、预算、取消与检查点集中在这里。
class AgentRuntime {
  static const streamRefreshInterval = Duration(milliseconds: 60);
  AgentRuntime({
    required this.client,
    required this.store,
    required this.workspace,
    required this.target,
    this.options = const LlmGenerationOptions(
      maxOutputTokens: 8192,
      responseHeaderTimeout: Duration(seconds: 60),
      streamIdleTimeout: Duration(seconds: 60),
    ),
    this.limits = const AgentLimits(),
    required this.onUpdate,
  });
  final LlmClient client;
  final AgentStore store;
  AgentWorkspace workspace;
  final LlmRequestTarget target;
  final LlmGenerationOptions options;
  final AgentLimits limits;
  final void Function(AgentRunRecord) onUpdate;
  final _controls = <LlmCallControl>{};
  final _children = <String, _Child>{};
  final _unsavedRecords = <String, AgentRunRecord>{};
  List<AgentRunRecord> get unsavedRecords =>
      List.unmodifiable(_unsavedRecords.values);
  final _cancelled = Completer<void>();
  int _modelCalls = 0, _toolCalls = 0;
  bool _started = false, _timedOut = false;
  bool get isCancelled => _cancelled.isCompleted;

  void cancel() {
    if (isCancelled) return;
    _cancelled.complete();
    for (final control in _controls.toList()) {
      control.cancel();
    }
  }

  Future<AgentRunRecord> run(String prompt) async {
    if (_started) throw StateError('运行器不能复用');
    _validateText(prompt, '任务');
    _started = true;
    final timer = Timer(limits.duration, () {
      _timedOut = true;
      cancel();
    });
    try {
      final history = workspace.history.isEmpty
          ? <LlmInputItem>[
              LlmTextMessage(
                role: LlmRole.system,
                text:
                    agentMainInstructions +
                    (workspace.instructions.isEmpty
                        ? ''
                        : '\n\n用户的写作规则：\n${workspace.instructions}'),
              ),
            ]
          : [...workspace.history];
      history.add(LlmTextMessage(role: LlmRole.user, text: prompt));
      return await _execute(_newRecord(prompt, AgentRole.coordinator), history);
    } finally {
      timer.cancel();
      cancel();
      // 子任务必须回到终态，主任务结束后不能遗留后台调用。
      await Future.wait(_children.values.map((child) => child.future));
    }
  }

  AgentRunRecord _newRecord(
    String prompt,
    AgentRole role, {
    String? parentId,
  }) => AgentRunRecord(
    id: generateEntityId(),
    workspaceId: workspace.id,
    prompt: prompt,
    role: role,
    parentId: parentId,
    startedAt: DateTime.now(),
  );

  Future<AgentRunRecord> _execute(
    AgentRunRecord record,
    List<LlmInputItem> history,
  ) async {
    final main = record.parentId == null;
    void publish() {
      if (main) workspace = workspace.copyWith(history: history, draft: '');
      store.checkpoint(record, workspace: main ? workspace : null);
      _unsavedRecords.remove(record.id);
      onUpdate(record);
    }

    try {
      publish();
      final rounds = main ? limits.mainRounds : limits.childRounds;
      for (var round = 0; round < rounds; round++) {
        _checkCancelled();
        if (_modelCalls >= limits.totalModelCalls) {
          throw const _Limit('主任务与子任务合计模型调用次数已达上限。');
        }
        if (_historyBytes(history) > 4 * 1024 * 1024) {
          throw const _Limit('上下文超过 4 MiB，请新建工作区并按需迁入文档。');
        }
        _modelCalls++;
        record = record.copyWith(
          modelCalls: record.modelCalls + 1,
          content: '',
          steps: [
            ...record.steps,
            AgentStep(label: '模型回复 ${record.modelCalls + 1}', isRunning: true),
          ],
        );
        publish();
        final result = await _request(
          LlmRequest(
            target: target,
            input: history,
            tools: main ? agentMainTools : agentReadTools,
            options: options,
          ),
          (text, reasoning) {
            record = record.copyWith(
              content: text,
              steps: [
                ...record.steps.take(record.steps.length - 1),
                record.steps.last.copyWith(content: text, reasoning: reasoning),
              ],
            );
            onUpdate(record);
          },
        );
        _checkCancelled();
        record = record.copyWith(
          content: result.content,
          usage: _addUsage(record.usage, result.usage),
          steps: [
            ...record.steps.take(record.steps.length - 1),
            AgentStep(
              label: '模型回复 ${record.modelCalls}',
              content: result.content,
              reasoning: result.reasoningContent,
            ),
          ],
        );
        if (result.stopKind != LlmStopKind.completed &&
            result.stopKind != LlmStopKind.toolCalls) {
          throw AgentWorkspaceException(
            '模型未正常完成（${result.finishReason ?? result.stopKind.name}），未执行未完成的工具。',
          );
        }
        final turn = result.assistantTurn;
        if (turn == null) {
          throw const AgentWorkspaceException('服务商未返回可可靠续接的原生内容，已停止。');
        }
        if (utf8.encode(jsonEncode(turn.replay.items)).length >
            4 * 1024 * 1024) {
          throw const _Limit('原生模型回复超过 4 MiB，未执行工具。');
        }
        history.add(turn);
        publish();
        if (result.stopKind == LlmStopKind.toolCalls) {
          if (turn.toolCalls.isEmpty) {
            throw const AgentWorkspaceException('工具终态没有完整工具调用。');
          }
          for (final call in turn.toolCalls) {
            _checkCancelled();
            if (_toolCalls >= limits.totalToolCalls) {
              throw const _Limit('工具调用次数已达上限。');
            }
            _toolCalls++;
            record = record.copyWith(
              steps: [
                ...record.steps,
                AgentStep(
                  label: call.name,
                  kind: AgentStepKind.tool,
                  isRunning: true,
                  content: jsonEncode({'arguments': call.arguments}),
                ),
              ],
            );
            publish();
            final toolResult = await _tool(call, record);
            history.add(toolResult);
            record = record.copyWith(
              steps: [
                ...record.steps.take(record.steps.length - 1),
                AgentStep(
                  label: call.name,
                  kind: AgentStepKind.tool,
                  content: jsonEncode({
                    'arguments': call.arguments,
                    'result': toolResult.output,
                  }),
                  isError: toolResult.isError,
                ),
              ],
            );
            publish();
          }
          continue;
        }
        if (turn.toolCalls.isNotEmpty) {
          throw const AgentWorkspaceException('完成终态仍包含待处理工具调用。');
        }
        if (main) {
          final uncollected = _children.values
              .where((c) => !c.collected)
              .toList();
          if (uncollected.isNotEmpty) {
            final results = <Object?>[];
            for (final child in uncollected) {
              final finished = await child.future;
              _checkCancelled();
              child.collected = true;
              results.add(_childResult(finished));
            }
            // spawn 已返回 task_id；完成通知是新的上下文，不能伪造第二份同 ID 工具结果。
            history.add(
              LlmTextMessage(
                role: LlmRole.user,
                text: '应用收到了尚未收取的子任务结果，请评估后完成本次任务：\n${jsonEncode(results)}',
              ),
            );
            publish();
            continue;
          }
        }
        if (result.content.trim().isEmpty) {
          throw const AgentWorkspaceException('模型返回空的完成结果，请检查模型与任务。');
        }
        record = record.copyWith(status: AgentRunStatus.completed);
        publish();
        return record;
      }
      throw const _Limit('模型循环轮数已达上限，已停止继续调用。');
    } catch (error) {
      final cancelled = isCancelled;
      record = record.copyWith(
        steps: [
          for (final step in record.steps)
            step.isRunning
                ? step.copyWith(isRunning: false, isError: true)
                : step,
        ],
        status: _timedOut || error is _Limit
            ? AgentRunStatus.limitReached
            : cancelled
            ? AgentRunStatus.cancelled
            : AgentRunStatus.failed,
        error: _timedOut
            ? '运行时间已达上限。'
            : cancelled
            ? '已停止，已保存的文档版本仍保留。'
            : error is AgentWorkspaceException
            ? error.message
            : error is _Limit
            ? error.message
            : error is LlmException
            ? '模型调用失败：${error.message}'
            : '运行或保存失败，请检查存储空间与服务配置。',
      );
      history = closePendingAgentTools(history);
      if (main) {
        history.add(
          LlmTextMessage(
            role: LlmRole.user,
            text:
                '应用记录：上次任务${record.status.name}。${record.error}后续任务请先核实文档当前版本。',
          ),
        );
        cancel();
      }
      try {
        publish();
      } catch (_) {
        record = record.copyWith(
          status: AgentRunStatus.failed,
          error: '${record.error}\n执行记录未能保存，当前显示的结果可能尚未持久化。',
        );
        _unsavedRecords[record.id] = record;
        onUpdate(record);
      }
      return record;
    }
  }

  Future<LlmResult> _request(
    LlmRequest request,
    void Function(String, String) onText,
  ) async {
    final control = LlmCallControl();
    _controls.add(control);
    final done = Completer<LlmResult>();
    final text = StringBuffer(), reasoning = StringBuffer();
    LlmResult? result;
    StreamSubscription<LlmEvent>? subscription;
    Timer? refresh;
    var bytes = 0;
    void fail(Object error, [StackTrace? stack]) {
      if (!done.isCompleted) done.completeError(error, stack);
    }

    final remove = control.onCancel(() {
      // 共享流正常关闭也释放句柄；只有整树取消才应打断当前等待。
      if (isCancelled) {
        fail(const LlmException('调用已取消', kind: LlmFailureKind.cancelled));
      }
    });
    try {
      _checkCancelled();
      subscription = client
          .streamCompletion(request, control: control)
          .listen(
            (event) {
              if (done.isCompleted) return;
              if (event is LlmCompleted) {
                result = event.result;
                return;
              }
              bytes +=
                  utf8.encode(event.contentDelta).length +
                  utf8.encode(event.reasoningDelta).length;
              if (bytes > 512 * 1024) {
                fail(const _Limit('单次输出超过 512 KiB。'));
                return;
              }
              text.write(event.contentDelta);
              reasoning.write(event.reasoningDelta);
              refresh ??= Timer(streamRefreshInterval, () {
                refresh = null;
                if (!done.isCompleted) {
                  onText(text.toString(), reasoning.toString());
                }
              });
            },
            onError: fail,
            onDone: () {
              if (done.isCompleted) return;
              if (result == null) {
                fail(const AgentWorkspaceException('模型流结束但没有权威终态。'));
              } else if (utf8.encode(result!.content).length +
                      utf8.encode(result!.reasoningContent).length >
                  512 * 1024) {
                fail(const _Limit('单次输出超过 512 KiB。'));
              } else {
                done.complete(result!);
              }
            },
          );
      return await done.future;
    } finally {
      refresh?.cancel();
      if (text.isNotEmpty || reasoning.isNotEmpty) {
        onText(text.toString(), reasoning.toString());
      }
      remove();
      _controls.remove(control);
      control.cancel();
      if (subscription != null) {
        unawaited(subscription.cancel().catchError((Object _) {}));
      }
    }
  }

  Future<LlmToolResult> _tool(LlmToolCall call, AgentRunRecord owner) async {
    try {
      final allowed = owner.parentId == null ? agentMainTools : agentReadTools;
      final definition = allowed
          .where((tool) => tool.name == call.name)
          .firstOrNull;
      if (definition == null) {
        throw const AgentWorkspaceException('该工具不存在或当前 Agent 无权调用。');
      }
      final properties = definition.parameters['properties']! as Map;
      if (call.arguments.length != properties.length ||
          !properties.keys.every(call.arguments.containsKey)) {
        throw const AgentWorkspaceException('工具参数字段不匹配，拒绝缺失或额外字段。');
      }
      final args = call.arguments;
      String string(String key) {
        final value = args[key];
        if (value is! String) throw AgentWorkspaceException('$key 必须是字符串。');
        return value;
      }

      bool boolean(String key) {
        final value = args[key];
        if (value is! bool) throw AgentWorkspaceException('$key 必须是布尔值。');
        return value;
      }

      Object? output;
      switch (call.name) {
        case 'list_documents':
          output = [
            for (final doc in store.listDocuments(workspace.id))
              {'name': doc.name, 'revision': doc.revision},
          ];
        case 'read_document':
          final document = store.readDocument(workspace.id, string('name'));
          if (document == null) throw const AgentWorkspaceException('文档不存在。');
          output = {
            'name': document.name,
            'revision': document.revision,
            'content': document.content,
          };
        case 'write_document':
          final revision = args['expected_revision'];
          if (revision is! int || revision < 0) {
            throw const AgentWorkspaceException('expected_revision 必须是非负整数。');
          }
          _checkCancelled();
          final document = store.writeDocument(
            workspace.id,
            string('name'),
            string('content'),
            expectedRevision: revision,
          );
          output = {
            'name': document.name,
            'revision': document.revision,
            'saved': true,
          };
        case 'spawn_subagent':
          final roleName = string('role'), task = string('task');
          final background = boolean('background');
          final role = AgentRole.values
              .where((r) => r.name == roleName && r != AgentRole.coordinator)
              .firstOrNull;
          if (role == null) {
            throw const AgentWorkspaceException('不支持该子 Agent 角色。');
          }
          _validateText(task, '子任务');
          if (_children.length >= limits.children ||
              _children.values
                      .where((c) => c.record.status == AgentRunStatus.running)
                      .length >=
                  limits.concurrentChildren) {
            throw const AgentWorkspaceException('子 Agent 总数或并发数已达上限，请先收取已有任务。');
          }
          _checkCancelled();
          final record = _newRecord(task, role, parentId: owner.id);
          final child = _Child(record);
          _children[record.id] = child;
          child.future =
              _execute(record, [
                LlmTextMessage(
                  role: LlmRole.system,
                  text:
                      '${agentInstructions(role)}\n\n用户的写作规则：\n${workspace.instructions}',
                ),
                LlmTextMessage(role: LlmRole.user, text: task),
              ]).then((value) {
                child.record = value;
                return value;
              });
          if (background) {
            output = {'task_id': record.id, 'status': 'running'};
          } else {
            child.collected = true;
            output = _childResult(await child.future);
          }
        case 'collect_subagent':
          final child = _children[string('task_id')];
          final wait = boolean('wait');
          if (child == null) {
            throw const AgentWorkspaceException('子任务不属于本次主任务。');
          }
          if (wait) await child.future;
          if (child.record.status != AgentRunStatus.running) {
            child.collected = true;
          }
          output = _childResult(child.record);
      }
      return LlmToolResult(
        callId: call.callId,
        name: call.name,
        output: jsonEncode(output),
      );
    } on AgentWorkspaceException catch (error) {
      return LlmToolResult(
        callId: call.callId,
        name: call.name,
        output: jsonEncode({'error': error.message}),
        isError: true,
      );
    }
  }

  Map<String, Object?> _childResult(AgentRunRecord record) => {
    'task_id': record.id,
    'status': record.status.name,
    'content': record.content,
    'error': record.error,
  };
  void _checkCancelled() {
    if (isCancelled) {
      throw const LlmException('运行已取消', kind: LlmFailureKind.cancelled);
    }
  }

  void _validateText(String text, String label) {
    if (text.trim().isEmpty || utf8.encode(text).length > 64 * 1024) {
      throw AgentWorkspaceException('$label不能为空且不能超过 64 KiB。');
    }
  }
}

class _Child {
  _Child(this.record);
  AgentRunRecord record;
  late Future<AgentRunRecord> future;
  bool collected = false;
}

class _Limit implements Exception {
  const _Limit(this.message);
  final String message;
}

int _historyBytes(List<LlmInputItem> items) => items.fold(
  0,
  (size, item) =>
      size +
      utf8.encode(switch (item) {
        LlmTextMessage() => item.text,
        LlmToolResult() => item.output,
        LlmAssistantTurn() => jsonEncode(item.replay.items),
      }).length,
);
LlmUsage? _addUsage(LlmUsage? a, LlmUsage? b) {
  if (b == null) return a;
  int? sum(int? x, int? y) =>
      x == null && y == null ? null : (x ?? 0) + (y ?? 0);
  return LlmUsage(
    inputTokens: sum(a?.inputTokens, b.inputTokens),
    outputTokens: sum(a?.outputTokens, b.outputTokens),
    reasoningTokens: sum(a?.reasoningTokens, b.reasoningTokens),
    cachedInputTokens: sum(a?.cachedInputTokens, b.cachedInputTokens),
    cacheWriteInputTokens: sum(
      a?.cacheWriteInputTokens,
      b.cacheWriteInputTokens,
    ),
  );
}
