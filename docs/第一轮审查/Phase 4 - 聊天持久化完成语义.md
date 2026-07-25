# Phase 4 - 聊天持久化完成语义

## Phase Name

聊天持久化完成语义、SQL 单一事实源与 core 去 feature 化。

## Why this Phase exists

本 Phase 聚合 TD-09、TD-20、TD-21。后台 writer 的 ACK/flush/close 需要传输 chat 写入命令，而当前命令、SQL 和 mapper 同时分散在 core 与 chat data；若只修 Future 语义，会继续固化 core→chat 反向依赖和双份 SQL。三项必须一起收敛，才能让“持久化完成”成为可信契约，并让 chat schema 只有一个 feature-owned 事实源。

## Included Technical Debts

- **TD-09（P3）**：`core/persistence/background_sqlite_writer.dart` 反向依赖 chat domain，并包含 chat 表写入。
- **TD-20（P0）**：后台 repository Future 只表示排队，无 ACK、flush、close、worker error/exit 完整生命周期。
- **TD-21（P0）**：前后台重复 UPSERT/mapper，且读取路径已经出现 `finish_reason` 漂移。

## Dependencies

- 前置 Phase：Phase 1。
- 后续依赖：Phase 9 的 chat generation 状态机依赖可信的持久化完成/失败语义；Phase 15 可在本 Phase 后删除后台测试的固定 delay；Phase 17 的 migration ownership 以本 Phase 已归还 chat mapper ownership 为基础。
- 顺序理由：先固化数据可靠性和失败语义，再拆上层异步工作流，避免状态机建立在错误 Future 契约上。

## Expected Benefits

- 调用方能区分排队完成与耐久落盘完成。
- 应用退出、测试 teardown 与 repository dispose 前可确认尾部写入已处理。
- worker error/exit 可观察并有明确降级，不再仅 print 或静默丢失。
- chat SQL、列集合、编码和解码由 chat feature 单一拥有，新增列不再要求同步修改两套实现。
- core persistence 恢复为 feature-neutral isolate/SQLite 基础设施。

## File Scope

- Core writer：`lib/core/persistence/background_sqlite_writer.dart`。
- Chat data：`lib/features/chat/data/background_chat_repository.dart`、`sqlite_chat_conversation_repository.dart`、`chat_conversation_repository.dart`，以及 `features/chat/data/` 下承载 chat-owned SQL/mapper/command contract 的文件。
- 数据库协调：`lib/core/persistence/app_database.dart`，仅限连接、worker 生命周期或现有 schema 契约所必需的变更。
- 测试：`test/core/persistence/background_sqlite_writer_test.dart`、`test/features/chat/data/background_chat_repository_test.dart`、`test/features/chat/chat_conversation_repository_test.dart`、chat persistence integration tests。

## Refactor Scope

- 明确后台写入“已排队”和“已耐久完成”的两类完成语义，并使 repository API 对调用者无歧义。
- 建立可确认的写入响应、flush、close、错误与 worker 退出生命周期。
- 将 chat-specific command、SQL、列映射和实体编解码归还 `features/chat/data`，前后台共用同一事实源。
- 修复所有 chat 加载路径对已持久化字段的契约一致性，包括报告指出的 `finish_reason`。
- 使测试基于可观察完成条件，而非假定 debounce 延迟后已落盘。

## Out Of Scope

- 不迁移全部 AppDatabase migration 到 feature registry；属于 Phase 17。
- 不重写 `ChatSessionsController`、流式逻辑或消息树；属于 Phase 9。
- 不改变 80ms 防抖存在的业务目标，除非完成语义要求明确区分排队与耐久。
- 不改变 SQLite 技术选型，也不引入 drift/sqflite。

## Risks

- ACK 与 debounce 合并的对应关系定义错误，可能让多个调用者收到错误完成信号。
- close/worker exit 竞态可能导致尾部命令丢失或 teardown 卡住。
- SQL 单一事实源迁移若漏掉任一加载路径，会造成兼容数据读取回归。
- core 与 chat data 同时修改，必须避免把 feature-neutral 通道重新绑定到另一种 chat 类型。

## Verification Requirements

- `flutter analyze` 必须通过。
- 全量测试按重定向规范执行并得到 `EXIT=0`。
- 测试覆盖 queued/durable 完成差异、debounce 合并、flush、close、worker error、worker exit 与尾部写入。
- 前台与后台 repository 的 round-trip 对所有当前列一致，特别是 `reasoning_content` 与 `finish_reason`。
- 依赖检查证明 `lib/core/` 不再 import chat feature。

## Completion Criteria

- Repository Future 的成功含义可由 API 和测试明确判断。
- 生命周期结束前存在可等待的 drain/close 契约，worker 故障不会静默。
- Chat SQL/mapper/command 只有一个 feature-owned 事实源，core 不认识 `ChatConversation`。
- 固定时间等待不再是后台持久化正确性的必要条件。

## Implement Context For Next Agent

当前 `BackgroundChatConversationRepository.save*` 的 Future 在命令进入 80ms debounce 队列后就完成；writer 无完整 ACK、flush、close、onError/onExit。`background_sqlite_writer.dart` 位于 core 却 import chat domain 并维护 chat SQL，前台 `sqlite_chat_conversation_repository.dart` 又有另一套 UPSERT/mapper；报告已观察到一个加载路径遗漏 `finish_reason`。本 Phase 必须同时解决完成语义和所有权，但保持 SQLite、后台 Isolate、防抖以及上层 repository 使用方式的渐进兼容。不要触碰 generation 状态机或全面 migration registry。
