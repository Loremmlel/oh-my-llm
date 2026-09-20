import 'dart:async';
import 'dart:convert';

import 'package:oh_my_llm/core/utils/id_generator.dart';
import 'package:oh_my_llm/core/llm/llm_call_control.dart';
import 'package:oh_my_llm/core/llm/llm_client.dart';
import 'package:oh_my_llm/core/llm/llm_content.dart';
import 'package:oh_my_llm/core/llm/llm_event.dart';
import 'package:oh_my_llm/core/llm/llm_request.dart';
import 'package:oh_my_llm/core/llm/llm_history_conversion.dart';

import '../domain/agent_models.dart';
import '../domain/agent_context_batch.dart';
import '../domain/agent_story_state.dart';
import 'agent_harness.dart';
import 'agent_context.dart';
import 'agent_model.dart';
import 'agent_script_context.dart';
import 'ports/agent_store.dart';

class AgentLimits {
  const AgentLimits({
    this.totalModelCalls = 24,
    this.mainRounds = 12,
    this.childRounds = 12,
    this.totalToolCalls = 64,
    this.children = 10,
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
  // UTF-8 字节保护独立于服务商 token 预算，必须给长推理及正文留出空间。
  static const _maxOutputBytes = 2 * 1024 * 1024;
  AgentRuntime({
    required this.client,
    required this.store,
    required this.workspace,
    required this.roleModels,
    this.limits = const AgentLimits(),
    required this.onUpdate,
  });
  final LlmClient client;
  final AgentStore store;
  AgentWorkspace workspace;
  final AgentLimits limits;
  final Map<AgentRole, AgentModel> roleModels;
  final void Function(AgentRunRecord) onUpdate;
  final _controls = <LlmCallControl>{};
  final _children = <String, _Child>{};
  final _unsavedRecords = <String, AgentRunRecord>{};
  List<AgentRunRecord> get unsavedRecords =>
      List.unmodifiable(_unsavedRecords.values);
  final _cancelled = Completer<void>();
  int _modelCalls = 0, _toolCalls = 0;
  bool _started = false, _timedOut = false;
  late AgentWorkspace _beforeRound;
  List<LlmInputItem> _canonicalHistory = [];
  int _appendStart = 0;
  String? _rootId;
  String _preservedDraft = '';
  final _waiting = <String>{};
  final _reviewDocuments = <String, AgentDocument>{};
  final _reviewResults = <String, ({bool approved, String feedback})>{};
  final _approvedDocuments = <String, AgentDocument>{};
  final _characterCards = <String, String>{};
  final _characterStates = <String, AgentStoryState>{};
  final _stateBindings = <String, AgentStoryRound>{};
  bool get isCancelled => _cancelled.isCompleted;

  void cancel() {
    if (isCancelled) return;
    _cancelled.complete();
    for (final control in _controls.toList()) {
      control.cancel();
    }
  }

  Future<AgentRunRecord> run(String prompt, {AgentRunRecord? retryRun}) async {
    if (_started) throw StateError('运行器不能复用');
    _validateText(prompt, '任务');
    if (store.latestStoryRound(workspace.id)?.status ==
        AgentStoryRoundStatus.pending) {
      throw const AgentWorkspaceException('请先重试状态更新或放弃未完成轮次。');
    }
    _started = true;
    _preservedDraft = retryRun == null ? '' : workspace.draft;
    final timer = Timer(limits.duration, () {
      _timedOut = true;
      cancel();
    });
    try {
      workspace = refreshAgentWorkspace(
        workspace,
        store.listDocuments(workspace.id),
      );
      workspace = workspace.copyWith(
        history: convertLlmHistory(
          workspace.history,
          _model(AgentRole.coordinator).target,
        ),
      );
      _beforeRound = workspace.copyWith(draft: prompt);
      _canonicalHistory = workspace.history;
      final batch = _batch;
      final history = buildAgentMainContext(workspace, batch: batch);
      _appendStart = history.length;
      final documents = store.listDocuments(workspace.id);
      history.addAll(
        agentScriptUpdates(workspace, documents, full: batch?.active ?? false),
      );
      final catalog = agentScriptCatalog(documents);
      workspace = workspace.copyWith(
        knownScripts: catalog,
        scriptProgress: {
          for (final entry in workspace.scriptProgress.entries)
            if (catalog[entry.key] == entry.value.fingerprint)
              entry.key: entry.value,
        },
      );
      history.add(agentStateMessage(store.readStoryState(workspace.id)));
      history.add(LlmTextMessage(role: LlmRole.user, text: prompt));
      final record = (retryRun ?? _newRecord(prompt, AgentRole.coordinator))
          .copyWith(
            status: AgentRunStatus.running,
            error: '',
            recovery: AgentRunRecovery(
              beforeWorkspace: _beforeRound,
              historyEnd: retryRun?.recovery.historyEnd,
            ),
            request: AgentRunRequestSnapshot(
              modelId: _model(AgentRole.coordinator).id,
              modelLabel: _model(AgentRole.coordinator).label,
              tools: agentToolsFor(AgentRole.coordinator),
              inputHistory: retryRun?.request.inputHistory,
            ),
          );
      _rootId = record.id;
      return await _execute(record, history);
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
    AgentContextBatch? summaryBatch,
  }) => AgentRunRecord(
    id: generateEntityId(),
    workspaceId: workspace.id,
    request: AgentRunRequestSnapshot(
      modelId: _model(role).id,
      modelLabel: _model(role).label,
      tools: agentToolsFor(role),
    ),
    prompt: prompt,
    role: role,
    parentId: parentId,
    summaryBatch: summaryBatch,
    rootRunId: parentId == null ? null : _rootId,
    startedAt: DateTime.now(),
  );

  Future<AgentRunRecord> _execute(
    AgentRunRecord record,
    List<LlmInputItem> history,
  ) async {
    final main =
        record.role == AgentRole.coordinator && record.parentId == null;
    void publish() {
      if (main) {
        workspace = workspace.copyWith(
          history: [..._canonicalHistory, ...history.skip(_appendStart)],
          draft: _preservedDraft,
        );
        record = record.copyWith(
          request: record.request.copyWith(inputHistory: history),
          recovery: record.recovery.copyWith(
            historyEnd: workspace.history.length,
          ),
        );
      } else {
        record = record.copyWith(childHistory: history);
      }
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
          throw const _Limit('上下文超过 4 MiB，请先压缩较早的正文轮次。');
        }
        _modelCalls++;
        record = record.copyWith(
          usage: record.usage.startCall(),
          content: '',
          steps: [
            ...record.steps,
            AgentStep(
              label: '模型回复 ${record.usage.modelCalls + 1}',
              isRunning: true,
              inputItemCount: history.length,
            ),
          ],
        );
        publish();
        final result = await _request(
          LlmRequest(
            target: _model(record.role).target,
            input: history,
            tools: agentToolsFor(record.role),
            options: _model(record.role).options,
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
          usage: record.usage.addResponse(result.usage),
          steps: [
            ...record.steps.take(record.steps.length - 1),
            AgentStep(
              label: '模型回复 ${record.usage.modelCalls}',
              content: result.content,
              reasoning: result.reasoningContent,
              inputItemCount: history.length,
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
        final replay = turn?.replay;
        if (turn == null || replay == null) {
          throw const AgentWorkspaceException('服务商未返回可可靠续接的原生内容，已停止。');
        }
        if (utf8.encode(jsonEncode(replay.items)).length > 4 * 1024 * 1024) {
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
          final adopted = main || record.role == AgentRole.writer
              ? store.readStoryRound(workspace.id, record.roundRunId)
              : null;
          if (adopted?.status == AgentStoryRoundStatus.committed) {
            // 先闭合本层工具往返，再追加可独立选择的正式正文。
            if (main) history.add(agentProseMessage(adopted!));
            record = record.copyWith(
              status: AgentRunStatus.completed,
              content: adopted!.document.content,
            );
            publish();
            return record;
          }
          if (record.role == AgentRole.state &&
              store.readStoryRound(workspace.id, record.roundRunId)?.status ==
                  AgentStoryRoundStatus.committed) {
            record = record.copyWith(
              status: AgentRunStatus.completed,
              content: '剧情状态已保存。',
            );
            publish();
            return record;
          }
          if (_reviewResults.containsKey(record.id)) {
            record = record.copyWith(
              status: AgentRunStatus.completed,
              content: _reviewResults[record.id]!.feedback,
            );
            publish();
            return record;
          }
          continue;
        }
        if (turn.toolCalls.isNotEmpty) {
          throw const AgentWorkspaceException('完成终态仍包含待处理工具调用。');
        }
        if (main) {
          final uncollected = _children.values
              .where((c) => c.record.parentId == record.id && !c.collected)
              .toList();
          if (uncollected.isNotEmpty) {
            final results = <Object?>[];
            for (final child in uncollected) {
              final finished = await _waitFor(record.id, child);
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
            final adopted = store.readStoryRound(workspace.id, record.id);
            if (adopted?.status == AgentStoryRoundStatus.committed) {
              history.add(agentProseMessage(adopted!));
              record = record.copyWith(
                status: AgentRunStatus.completed,
                content: adopted.document.content,
              );
              publish();
              return record;
            }
            publish();
            continue;
          }
        }
        if (result.content.trim().isEmpty) {
          throw const AgentWorkspaceException('模型返回空的完成结果，请检查模型与任务。');
        }
        if (_reviewDocuments.containsKey(record.id)) {
          throw const AgentWorkspaceException('审查 Agent 未提交明确结论。');
        }
        if (record.role == AgentRole.writer &&
            store.readStoryRound(workspace.id, record.roundRunId)?.status !=
                AgentStoryRoundStatus.committed) {
          throw const AgentWorkspaceException('写作任务尚未完成审查与交付，候选稿已保留。');
        }
        if (record.role == AgentRole.state) {
          throw const AgentWorkspaceException('状态 Agent 没有提交状态，本轮尚未完成。');
        }
        if (main &&
            store.readStoryRound(workspace.id, record.id)?.status ==
                AgentStoryRoundStatus.pending) {
          throw const AgentWorkspaceException('正文已保留，状态尚未保存。请重试状态更新或放弃本轮。');
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
            ? '已停止，已保存的文档仍保留。'
            : error is AgentWorkspaceException
            ? error.message
            : error is _Limit
            ? error.message
            : error is LlmException
            ? '模型调用失败：${error.message}'
            : '运行或保存失败，请检查存储空间与服务配置。',
      );
      history = closePendingAgentTools(history);
      final committed = (main || record.role == AgentRole.writer)
          ? store.readStoryRound(workspace.id, record.roundRunId)
          : null;
      if (committed?.status == AgentStoryRoundStatus.committed) {
        record = record.copyWith(
          status: AgentRunStatus.completed,
          error: '',
          content: committed!.document.content,
        );
        if (main &&
            !history.whereType<LlmTextMessage>().any(
              (m) => m.text == agentProseMessage(committed).text,
            )) {
          history.add(agentProseMessage(committed));
        }
        try {
          publish();
        } catch (_) {
          _unsavedRecords[record.id] = record;
          onUpdate(record);
        }
        return record;
      }
      if (main) {
        history.add(
          LlmTextMessage(
            role: LlmRole.user,
            text:
                '应用记录：上次任务${record.status.name}。${record.error}后续任务请先核实文档当前内容。',
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
              if (bytes > _maxOutputBytes) {
                fail(const _Limit('单次输出超过 2 MiB。'));
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
                  _maxOutputBytes) {
                fail(const _Limit('单次输出超过 2 MiB。'));
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
      final allowed = agentToolsFor(owner.role);
      final definition = allowed
          .where((tool) => tool.name == call.name)
          .firstOrNull;
      if (definition == null) {
        throw const AgentWorkspaceException('该工具不存在或当前 Agent 无权调用。');
      }
      final properties = definition.parameters['properties']! as Map;
      if (!call.arguments.keys.every(properties.containsKey) ||
          !(definition.parameters['required']! as List).every(
            call.arguments.containsKey,
          )) {
        throw const AgentWorkspaceException('工具参数字段不匹配，拒绝缺失或额外字段。');
      }
      final adoptedRound = store.readStoryRound(workspace.id, owner.roundRunId);
      if (adoptedRound?.status == AgentStoryRoundStatus.committed &&
          call.name != 'collect_subagent') {
        throw const AgentWorkspaceException('本轮已交付，后续工具不再执行。');
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
        case 'read_script':
          final script = _script(string('script_id'));
          output = {
            'script_id': script.id,
            'name': script.name,
            'fingerprint': agentScriptFingerprint(script),
            'content': script.content,
          };
        case 'record_script_progress':
          final script = _script(string('script_id'));
          final fingerprint = agentScriptFingerprint(script);
          final hasRead = workspace.history.whereType<LlmToolResult>().any((
            item,
          ) {
            if (item.name != 'read_script' || item.isError) return false;
            final value = jsonDecode(item.output);
            return value is Map &&
                value['script_id'] == script.id &&
                value['fingerprint'] == fingerprint;
          });
          if (!hasRead) {
            throw const AgentWorkspaceException('请先读取当前剧本全文，再记录备忘。');
          }
          final progress = validateAgentScriptProgress(
            document: script,
            status: string('status'),
            notes: string('notes'),
            sourceRoundIds: args['source_round_ids'],
            rounds: _rounds,
          );
          workspace = workspace.copyWith(
            scriptProgress: {...workspace.scriptProgress, script.id: progress},
          );
          output = {
            'script_id': script.id,
            ...progress.toJson(),
            'saved': true,
          };
        case 'read_story_state':
          output =
              (owner.role == AgentRole.state
                      ? _stateBindings[owner.id]!.beforeState
                      : _characterStates[owner.id] ??
                            store.readStoryState(workspace.id))
                  .toolData;
        case 'update_story_state':
          final document = store.readDocument(workspace.id, string('name'));
          if (document == null || document.kind != AgentDocumentKind.document) {
            throw const AgentWorkspaceException('请先保存审查通过的普通正文，再提供文档名。');
          }
          if (_approvedDocuments[owner.id] != document) {
            throw const AgentWorkspaceException(
              '当前稿件尚未通过审查，请先调用 review_document；修改后需重新审查。',
            );
          }
          final existing = store.readStoryRound(workspace.id, owner.roundRunId);
          if (existing != null &&
              existing.writerRunId !=
                  (owner.role == AgentRole.writer ? owner.id : null)) {
            throw const AgentWorkspaceException('该轮正文已由另一任务绑定，请重试原状态任务或放弃本轮。');
          }
          final selected =
              existing ??
              AgentStoryRound(
                id: owner.roundRunId,
                writerRunId: owner.role == AgentRole.writer ? owner.id : null,
                beforeWorkspace: _beforeRound,
                document: document,
                beforeState: store.readStoryState(workspace.id),
                stateAgentId: '',
              );
          if (selected.document != document) {
            throw const AgentWorkspaceException('本轮已绑定正文，请先放弃本轮再重新写作。');
          }
          // 先保存待更新轮次，模型不可用或预算耗尽时仍可单独重试。
          if (existing == null) store.prepareStoryRound(selected);
          output = await _updateStory(selected, owner);
        case 'commit_story_state':
          final operations = args['operations'];
          if (operations is! List) {
            throw const AgentWorkspaceException('operations 必须是数组。');
          }
          final binding = _stateBindings[owner.id];
          if (binding == null || binding.id != owner.roundRunId) {
            throw const AgentWorkspaceException('状态任务没有绑定正文。');
          }
          _checkCancelled();
          final saved = store.commitStoryRound(
            workspace.id,
            binding.id,
            owner.id,
            operations.map(AgentStateOperation.fromJson).toList(),
          );
          output = _storyResult(saved);
        case 'list_documents':
          output = [
            for (final doc in _workspaceDocuments(owner))
              {'id': doc.id, 'name': doc.name, 'kind': doc.kind.name},
          ];
        case 'read_document':
          final document = _workspaceDocuments(owner)
              .where((d) => d.name == string('name'))
              .firstOrNull;
          if (document == null) {
            throw const AgentWorkspaceException('当前作品中找不到这份资料。');
          }
          output = {'name': document.name, 'content': document.content};
        case 'write_document':
          final adopted = store.readStoryRound(workspace.id, owner.roundRunId);
          if (adopted != null && adopted.document.name == string('name')) {
            throw const AgentWorkspaceException(
              '本轮正文已选定，不能在状态更新后继续改写。需要重写时先撤回或放弃本轮。',
            );
          }
          final currentDocument = store.readDocument(
            workspace.id,
            string('name'),
          );
          if (currentDocument != null &&
                  currentDocument.kind != AgentDocumentKind.document ||
              workspace.references.any((d) => d.name == string('name'))) {
            throw const AgentWorkspaceException(
              '世界书、人物卡和剧本只能由用户编辑；请将修改建议保存为普通文档。',
            );
          }
          _checkCancelled();
          final document = store.writeDocument(
            workspace.id,
            string('name'),
            string('content'),
            sourceRunId: owner.id,
          );
          output = {'name': document.name, 'saved': true};
        case 'review_document':
          final document = store.readDocument(workspace.id, string('name'));
          if (document == null || document.kind != AgentDocumentKind.document) {
            throw const AgentWorkspaceException('找不到待审查的普通文档。');
          }
          final task = string('task');
          _approvedDocuments.remove(owner.id);
          _checkChildBudget();
          final reviewer = _newRecord(
            task,
            AgentRole.reviewer,
            parentId: owner.id,
          );
          _reviewDocuments[reviewer.id] = document;
          final child = _launch(reviewer, [
            ..._childContext(AgentRole.reviewer),
            LlmTextMessage(
              role: LlmRole.user,
              text:
                  '审查要求：$task\n当前待审稿：\n${agentDocumentText(document)}\n必须调用 submit_review 提交结论。',
            ),
          ]);
          final finished = await _waitFor(owner.id, child);
          final verdict = _reviewResults[reviewer.id];
          if (finished.status != AgentRunStatus.completed || verdict == null) {
            throw AgentWorkspaceException('审查未完成：${finished.error}');
          }
          if (verdict.approved) {
            _approvedDocuments[owner.id] = document;
          } else {
            _approvedDocuments.remove(owner.id);
          }
          output = {
            'task_id': reviewer.id,
            'approved': verdict.approved,
            'feedback': verdict.feedback,
          };
        case 'submit_review':
          if (!_reviewDocuments.containsKey(owner.id)) {
            throw const AgentWorkspaceException('没有绑定待审稿件。');
          }
          _reviewResults[owner.id] = (
            approved: boolean('approved'),
            feedback: string('feedback'),
          );
          output = {'submitted': true};
        case 'spawn_subagent':
        case 'spawn_character':
          final character = call.name == 'spawn_character';
          final role = character
              ? AgentRole.character
              : switch (string('role')) {
                  'writer' => AgentRole.writer,
                  'reviewer' => AgentRole.reviewer,
                  _ => throw const AgentWorkspaceException(
                    '不支持该子 Agent 角色；角色推演使用 spawn_character。',
                  ),
                };
          final task = string('task');
          _validateText(task, '子任务');
          _checkChildBudget();
          _checkCancelled();
          final record = _newRecord(task, role, parentId: owner.id);
          String? cardId;
          AgentStoryState? scopedState;
          if (character) {
            cardId = string('card_id');
            if (cardId.isNotEmpty &&
                !workspace.references.any(
                  (d) =>
                      d.id == cardId &&
                      d.kind == AgentDocumentKind.characterCard,
                )) {
              throw const AgentWorkspaceException('请选择当前作品的人物卡 ID。');
            }
            final ids = args['state_row_ids'];
            final current = store.readStoryState(workspace.id);
            if (ids is! List ||
                ids.any(
                  (id) => id is! String || !current.rows.any((r) => r.id == id),
                )) {
              throw const AgentWorkspaceException('状态行范围不合法。');
            }
            if (cardId.isEmpty &&
                !current.rows.any(
                  (r) =>
                      r.table == AgentStateTable.characters &&
                      ids.contains(r.id),
                )) {
              throw const AgentWorkspaceException('没有人物卡时需绑定新人物的状态行。');
            }
            scopedState = AgentStoryState(
              revision: current.revision,
              rows: current.rows.where((r) => ids.contains(r.id)).toList(),
            );
            _characterCards[record.id] = cardId;
            _characterStates[record.id] = scopedState;
          }
          final child = _launch(record, [
            ..._childContext(role, cardId: cardId, state: scopedState),
            LlmTextMessage(role: LlmRole.user, text: task),
          ]);
          output = boolean('background')
              ? {'task_id': record.id, 'status': 'running'}
              : _childResult(await _waitFor(owner.id, child));
        case 'collect_subagent':
          final child = _children[string('task_id')];
          final wait = boolean('wait');
          if (child == null || child.record.parentId != owner.id) {
            throw const AgentWorkspaceException('子任务不属于本次主任务。');
          }
          if (wait) await _waitFor(owner.id, child);
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

  Map<String, Object?> _storyResult(AgentStoryRound round) => {
    'saved': true,
    'round_id': round.id,
    'name': round.document.name,
    'state_revision': round.afterState!.revision,
    'changes': round.operations.map((op) => op.toJson()).toList(),
  };

  Future<Map<String, Object?>> _updateStory(
    AgentStoryRound selected,
    AgentRunRecord owner,
  ) async {
    _checkChildBudget();
    _checkCancelled();
    final record = _newRecord(
      '根据「${selected.document.name}」更新剧情状态',
      AgentRole.state,
      parentId: owner.id,
    );
    final binding = store.prepareStoryRound(
      selected.copyWith(stateAgentId: record.id),
    );
    _stateBindings[record.id] = binding;
    final child = _launch(record, [
      ...buildAgentInitialContext(workspace, AgentRole.state),
      LlmTextMessage(
        role: LlmRole.user,
        text: jsonEncode({
          'round_id': binding.id,
          'state': binding.beforeState.toolData,
          'opening_or_instruction': binding.beforeWorkspace.draft,
          'approved_document': {
            'name': binding.document.name,
            'content': binding.document.content,
          },
        }),
      ),
    ])..collected = true;
    final finished = await _waitFor(owner.id, child);
    final saved = store.readStoryRound(workspace.id, selected.id)!;
    // 提交后停止或通知失败不能抹掉已经完成的事务。
    if (saved.status == AgentStoryRoundStatus.committed) {
      return _storyResult(saved);
    }
    throw AgentWorkspaceException('状态更新未保存：${finished.error} 正文已保留，可重试状态更新。');
  }

  Future<AgentRunRecord> retryStory(AgentStoryRound round) async {
    if (_started) throw StateError('运行器不能复用');
    _started = true;
    if (round.status != AgentStoryRoundStatus.pending ||
        round.beforeWorkspace.id != workspace.id) {
      throw const AgentWorkspaceException('没有本作品可重试的状态更新。');
    }
    _beforeRound = round.beforeWorkspace;
    _rootId = round.id;
    var record = store.loadRun(workspace.id, round.id)!;
    final timer = Timer(limits.duration, () {
      _timedOut = true;
      cancel();
    });
    final history = [...workspace.history];
    try {
      record = record.copyWith(status: AgentRunStatus.running, error: '');
      store.checkpoint(record);
      onUpdate(record);
      final writer = round.writerRunId == null
          ? record
          : store.loadRun(workspace.id, round.writerRunId!)!;
      final result = await _updateStory(round, writer);
      history.add(
        LlmTextMessage(
          role: LlmRole.user,
          text: '应用已重试状态更新，采用的正式正文及状态版本如下：${jsonEncode(result)}',
        ),
      );
      history.add(agentProseMessage(round));
      if (writer.id != record.id) {
        store.checkpoint(
          writer.copyWith(
            status: AgentRunStatus.completed,
            content: round.document.content,
            error: '',
          ),
        );
      }
      record = record.copyWith(
        status: AgentRunStatus.completed,
        error: '',
        content: round.document.content,
      );
    } catch (error) {
      record = record.copyWith(
        status: isCancelled ? AgentRunStatus.cancelled : AgentRunStatus.failed,
        error: error is AgentWorkspaceException
            ? error.message
            : '状态更新失败，正文已保留，请重试或放弃本轮。',
      );
    } finally {
      timer.cancel();
      cancel();
      await Future.wait(_children.values.map((c) => c.future));
    }
    workspace = workspace.copyWith(history: history);
    record = record.copyWith(
      // 重试没有调用主模型，保留其原实际输入，不能用当前上下文投影覆盖。
      recovery: record.recovery.copyWith(historyEnd: history.length),
      steps: [
        ...record.steps,
        AgentStep(
          label: '重试状态更新',
          kind: AgentStepKind.tool,
          isError: record.status != AgentRunStatus.completed,
          content: jsonEncode({
            'arguments': {'name': round.document.name},
            'result': record.error.isEmpty ? record.content : record.error,
          }),
        ),
      ],
    );
    try {
      store.checkpoint(record, workspace: workspace);
    } catch (_) {
      _unsavedRecords[record.id] = record;
      record = record.copyWith(error: '${record.error}\n执行记录未能保存，请修复存储后重试保存。');
    }
    onUpdate(record);
    return record;
  }

  AgentModel _model(AgentRole role) =>
      roleModels[role] ??
      (throw const AgentWorkspaceException('此职责的模型已不可用，请在模型与规则中应用可用模型。'));

  AgentContextBatch? get _batch => store.readContextBatch(workspace.id);
  List<AgentStoryRound> get _rounds =>
      store.listStoryRounds(workspace.id, includeHistory: false);

  List<LlmInputItem> _childContext(
    AgentRole role, {
    String? cardId,
    AgentStoryState? state,
  }) => buildAgentChildContext(
    workspace,
    role,
    state: state ?? store.readStoryState(workspace.id),
    batch: _batch,
    rounds: _rounds,
    characterCardId: cardId,
  );

  List<AgentDocument> _workspaceDocuments(AgentRunRecord owner) =>
      store
          .listDocuments(workspace.id)
          .where(
            (d) =>
                d.kind != AgentDocumentKind.script &&
                (owner.role != AgentRole.character ||
                    d.kind == AgentDocumentKind.worldBook ||
                    d.id == _characterCards[owner.id]),
          )
          .toList()
        ..sort((a, b) => a.id.compareTo(b.id));

  AgentDocument _script(String id) =>
      store
          .listDocuments(workspace.id)
          .where((d) => d.id == id && d.kind == AgentDocumentKind.script)
          .firstOrNull ??
      (throw const AgentWorkspaceException('当前作品没有该剧本，请使用目录中的 script_id。'));

  void _checkChildBudget() {
    if (_children.length >= limits.children ||
        _children.values
                .where(
                  (c) =>
                      c.record.status == AgentRunStatus.running &&
                      !_waiting.contains(c.record.id),
                )
                .length >=
            limits.concurrentChildren) {
      throw const AgentWorkspaceException('子任务数量或并发已达上限，请先收取任务。');
    }
  }

  _Child _launch(AgentRunRecord record, List<LlmInputItem> history) {
    final child = _Child(record);
    _children[record.id] = child;
    child.future = _execute(record, history).then((value) {
      child.record = value;
      return value;
    });
    return child;
  }

  Future<AgentRunRecord> _waitFor(String ownerId, _Child child) async {
    _waiting.add(ownerId);
    try {
      return await child.future;
    } finally {
      _waiting.remove(ownerId);
      child.collected = true;
    }
  }

  Map<String, Object?> _childResult(AgentRunRecord record) => {
    'task_id': record.id,
    'status': record.status.name,
    if (record.role == AgentRole.writer &&
        record.status == AgentRunStatus.completed)
      'delivered_round_id': record.roundRunId
    else
      'content': record.content,
    'error': record.error,
  };

  Future<AgentRunRecord> summarize(AgentContextBatch batch) async {
    if (_started) throw StateError('运行器不能复用');
    _started = true;
    final committed = _rounds.reversed
        .where((r) => r.status == AgentStoryRoundStatus.committed)
        .toList();
    final current = _batch;
    final previous = current != null && current.active && current.id != batch.id
        ? current
        : null;
    final covered = previous?.roundIds.length ?? 0;
    if (batch.roundIds.isEmpty ||
        batch.roundIds.length > committed.length ||
        Iterable<int>.generate(batch.roundIds.length)
            .any((i) => committed[i].id != batch.roundIds[i]) ||
        (previous != null &&
            (covered >= batch.roundIds.length ||
                Iterable<int>.generate(covered)
                    .any((i) => previous.roundIds[i] != batch.roundIds[i]))) ||
        (current?.id == batch.id &&
            current?.status == AgentContextBatchStatus.invalidated)) {
      throw const AgentWorkspaceException('累计压缩来源已失效，请重新选择。');
    }
    if (batch.historyEnd <= 0 ||
        batch.historyEnd > workspace.history.length ||
        store.loadRun(workspace.id, batch.roundIds.last)?.recovery.historyEnd !=
            batch.historyEnd) {
      throw const AgentWorkspaceException('压缩任务边界已失效，请重新选择。');
    }
    final rounds = committed.take(batch.roundIds.length).skip(covered).toList();
    workspace = refreshAgentWorkspace(
      workspace,
      store.listDocuments(workspace.id),
    );
    final timer = Timer(limits.duration, () {
      _timedOut = true;
      cancel();
    });
    try {
      var record = await _execute(
        _newRecord(
          '累计压缩 ${batch.roundIds.length} 楼正文（新增 ${rounds.length} 楼）',
          AgentRole.summarizer,
          summaryBatch: batch,
        ),
        [
          ...buildAgentInitialContext(workspace, AgentRole.summarizer),
          const LlmTextMessage(
            role: LlmRole.user,
            text: '请将已有累计摘要与本次新增正文及写作指令合并为一份完整累计摘要。保留仍有效的事实、时间线、人物关系、未解决事项和写作约束，不要只总结新增部分。',
          ),
          ...agentSummaryMessages(previous),
          for (final round in rounds) ...[
            LlmTextMessage(
              role: LlmRole.user,
              text: '该楼写作输入：${round.beforeWorkspace.draft}',
            ),
            agentProseMessage(round),
          ],
        ],
      );
      if (record.status == AgentRunStatus.completed) {
        try {
          _checkCancelled();
          store.saveContextBatch(
            workspace.id,
            batch.copyWith(
              summary: record.content,
              summaryRunId: record.id,
              status: AgentContextBatchStatus.active,
            ),
          );
        } catch (_) {
          record = record.copyWith(
            status: isCancelled
                ? AgentRunStatus.cancelled
                : AgentRunStatus.failed,
            error: '摘要尚未应用，原输入范围与摘要保持不变。请重试总结。',
          );
          try {
            store.checkpoint(record);
          } catch (_) {
            _unsavedRecords[record.id] = record;
          }
          onUpdate(record);
        }
      }
      return record;
    } finally {
      timer.cancel();
      cancel();
    }
  }

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
        LlmUserMessage() => throw UnsupportedError('Agent 尚未启用多模态输入'),
        LlmTextMessage() => item.text,
        LlmToolResult() => item.output,
        LlmAssistantTurn() => jsonEncode(
          item.replay?.items ??
              {
                'text': item.text,
                'calls': [
                  for (final call in item.toolCalls)
                    {
                      'id': call.callId,
                      'name': call.name,
                      'arguments': call.argumentsJson,
                    },
                ],
              },
        ),
      }).length,
);
