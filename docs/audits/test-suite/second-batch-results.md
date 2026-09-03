# 测试精简第二批结果

## 结论

第二批按 Chat generation / protocol 分层实施，修改 4 个测试文件；删除 1,570 行、增加 25 行，净减 1,545 行。运行节点从 1,970 个降至 1,933 个，减少 37 个（1.9%）；生产代码、依赖、协议 parser、generation lifecycle 和 race contract 均未修改。

相同覆盖率命令的墙钟时间从 173.172 秒降至 168.384 秒，减少 4.788 秒（2.8%）；reporter 时间从 2:44 降至 2:38。原始行覆盖率从 88.80% 降至 88.76%，只减少 8 个命中行（0.04 个百分点）。

日常全量的单次墙钟从 111.914 秒变为 113.222 秒，reporter 从 1:40 变为 1:43。两项均未改善，且变化量很小，应视为并发调度与 Flutter 编译噪声；这批主要移除同一已编译分片内的快测试，不能宣称日常全量提速。

## 前后对比

| 指标 | 删减前（第一批完成） | 删减后 | 变化 |
| --- | ---: | ---: | ---: |
| 测试 Dart 文件 | 247 | 247 | 0 |
| 显式 `test` / `testWidgets` 注册点 | 1,878 | 1,842 | -36（-1.9%） |
| 覆盖率口径运行节点 | 1,970 | 1,933 | -37（-1.9%） |
| 覆盖率口径墙钟时间 | 173.172 秒 | 168.384 秒 | -4.788 秒（-2.8%） |
| 覆盖率口径 reporter 时间 | 2:44 | 2:38 | -0:06（-3.7%） |
| Flutter 原始行覆盖率 | 16,812 / 18,933（88.80%） | 16,804 / 18,933（88.76%） | -8 命中行，-0.04 个百分点 |
| 日常全量运行节点 | 1,970 | 1,933 | -37（-1.9%） |
| 日常全量墙钟时间 | 111.914 秒 | 113.222 秒 | +1.308 秒（+1.2%） |
| 日常全量 reporter 时间 | 1:40 | 1:43 | +0:03（+3.0%） |

覆盖率口径前后均使用：

```powershell
flutter test --exclude-tags=udp --coverage --reporter compact
```

日常口径前后均使用 `flutter test --reporter compact`。两次删减之间没有测试文件或 LCOV source 集合变化，因此本批原始覆盖率的分子、分母可直接比较。

## 本批删减

- 三个 protocol client 删除对连接异常、SSE error、malformed JSON、空响应和 idle timeout 的重复验证。这些行为分别由 `llm_http_stream_transport_test.dart`、`sse_event_decoder_test.dart` 和三个协议 parser 测试完整持有。
- 每个 protocol client 继续保留协议专属 URL/header/body 编码、正常流式结果、reasoning/content 分离、finish reason / usage 归一化和一条非 2xx 异常映射。
- Chat Completions 保留超长原始 SSE 尾部截断的代表契约；Responses 保留 `response.completed` 主动结束与取消底层流；Anthropic 保留两阶段 usage、stop reason 映射和不支持 `tool_use` 的边界。
- sessions controller 的 stop 用例从 20 条收敛为 4 条跨层契约：部分回复停止并投影用户取消、底层 cancel 挂起、stop 落盘失败、Riverpod dispose 丢弃迟到事件。
- preparing / streaming / retry-waiting / finalizing、并发 stop、迟到 chunk、terminal snapshot 和 persistence failure 的完整状态矩阵继续由 `chat_generation_run_test.dart` 与 `chat_generation_race_contract_test.dart` 持有。

## 覆盖率取舍

本批未删除任何生产 source，LCOV 分母保持 18,933 行。命中行只减少 8 行，来自 controller 上层装配中不再重复经过的普通投影与清理分支；协议 client 的共享错误路径仍由底层 owner 触达。

保留项包括三协议 parser 的 malformed / error / event 边界、SSE UTF-8 与注释 keepalive、HTTP 连接/非 2xx/中断/idle/cancel、generation 各阶段 stop、durable save、并发与旧 token 隔离。数据库迁移、Sync 安全与 HTTP 信任域完全不在本批改动范围。

## 累计结果

从首次审计基线到第二批完成：

| 指标 | 初始基线 | 当前 | 累计变化 |
| --- | ---: | ---: | ---: |
| 测试代码 | 60,975 行 | 约 56,692 行 | 净减 4,283 行（7.0%） |
| 显式注册点 | 1,960 | 1,842 | -118（-6.0%） |
| 覆盖率运行节点 | 2,130 | 1,933 | -197（-9.2%） |
| 覆盖率墙钟时间 | 213.505 秒 | 168.384 秒 | -45.121 秒（-21.1%） |
| Flutter 原始行覆盖率 | 16,982 / 18,942（89.65%） | 16,804 / 18,933（88.76%） | -0.90 个百分点 |

累计测试代码按两批净删 2,738 行与 1,545 行计算；当前物理行是据此推算值。覆盖率分母累计少 9 行，是第一批删除专用测试后 `AppConstrainedContent` 不再进入 LCOV source 集合所致，本批分母没有继续变化。

## 验证

- `flutter test test/features/chat/data/generation/chat_completions/chat_completions_client_test.dart --reporter compact`：14 个测试通过。
- `flutter test test/features/chat/data/generation/responses/responses_client_test.dart --reporter compact`：17 个测试通过。
- `flutter test test/features/chat/data/generation/anthropic/anthropic_messages_client_test.dart --reporter compact`：16 个测试通过。
- `flutter test test/features/chat/application/sessions/chat_sessions_controller_test.dart --reporter compact`：93 个测试通过。
- `flutter test --reporter compact`：1,933 个测试通过，reporter 1:43，父进程墙钟 113.222 秒。
- `flutter test --exclude-tags=udp --coverage --reporter compact`：1,933 个测试通过，reporter 2:38，父进程墙钟 168.384 秒。
- `flutter analyze`：通过，无 issue。
- `dart run tool/check_import_boundaries.dart`：通过，检查 392 个文件，0 条违规。

## 后续

本批说明“删测试数量”与“节省日常时间”不是线性关系：协议/parser/controller 的纯 Dart 快路径能明显降维护面，却几乎不影响由编译和慢 Widget 分片主导的日常全量墙钟。下一批若以开发等待时间为目标，应转向媒体视频交互矩阵和剩余慢 Widget 入口；不应继续削减 parser、migration、安全或 lifecycle 纯函数测试来凑数量。
