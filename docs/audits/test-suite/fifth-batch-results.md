# 测试精简第五批结果

## 结论

第五批收敛 Favorites SQLite repository、日志缓冲、异步测试 helper 和共享分页组件，修改 8 个测试文件；删除 709 行、增加 213 行，测试代码净减 496 行。固定 8 文件基准从 93 个运行节点降至 56 个，墙钟从 28.457 秒降至 10.701 秒，减少 17.756 秒（62.4%）。

日常全量运行节点从 1,819 个降至 1,782 个，单次墙钟为 102.126 秒、reporter 1:35；该结果落在第四批删减后 97.703–113.640 秒的波动区间内，不能归因为全仓提速。覆盖率只减少 2 个命中行，从 88.4435% 降至 88.4329%。

## 前后对比

| 指标 | 删减前（第四批完成） | 删减后 | 变化 |
| --- | ---: | ---: | ---: |
| 测试 Dart 文件 | 247 | 247 | 0 |
| 测试代码物理行 | 53,962 | 53,466 | -496（-0.9%） |
| 显式 `test` / `testWidgets` 注册点 | 1,730 | 1,693 | -37（-2.1%） |
| 固定 repository / infrastructure 基准运行节点 | 93 | 56 | -37（-39.8%） |
| 固定 repository / infrastructure 基准墙钟时间 | 28.457 秒 | 10.701 秒 | -17.756 秒（-62.4%） |
| 固定 repository / infrastructure 基准 reporter 时间 | 0:12 | 0:04 | -0:08（-66.7%） |
| 日常全量运行节点 | 1,819 | 1,782 | -37（-2.0%） |
| 日常全量墙钟时间 | 98.436 秒（三次中位数） | 102.126 秒（单次） | +3.690 秒（+3.7%） |
| 日常全量 reporter 时间 | 1:31（三次中位数） | 1:35（单次） | +0:04（+4.4%） |
| 覆盖率口径运行节点 | 1,819 | 1,782 | -37（-2.0%） |
| 覆盖率口径墙钟时间 | 152.604 秒 | 160.522 秒 | +7.918 秒（+5.2%） |
| 覆盖率口径 reporter 时间 | 2:23 | 2:27 | +0:04（+2.8%） |
| Flutter 原始行覆盖率 | 16,745 / 18,933（88.4435%） | 16,743 / 18,933（88.4329%） | -2 命中行，-0.0106 个百分点 |

固定基准前后使用同一条命令，包含以下 8 个文件：

- `sqlite_favorites_repository_test.dart`
- `sqlite_collections_repository_test.dart`
- `app_log_store_test.dart`
- `sse_log_buffer_test.dart`
- `async_test_signals_test.dart`
- `app_pagination_state_test.dart`
- `app_pagination_bar_test.dart`
- `app_paginated_list_shell_test.dart`

全量覆盖率口径仍为：

```powershell
flutter test --exclude-tags=udp --coverage --reporter compact
```

## 本批删减

- Favorites repository 删除第二份完整 `loadById`、单条 delete/move、单条分页、51 条连续分页和重复内容查询；保留完整 nullable round-trip、REPLACE、归属时间、21 条分页边界、稳定 tie-break、collection 过滤、非法参数、批量 mutation 与外键拒绝。
- Collections repository 删除通用 save/delete 生命周期、第二份排序、第二份含收藏重命名和不存在 ID no-op；保留系统夹不可删除、UPSERT 不破坏归属、双 reader 同序、聚合时间、三种 typed delete、非法目标和事务回滚。
- 日志文件测试把批量写入与 clear 合并，把 response metadata/body、SSE JSON/text、request/response body-disabled 各自合并为一个文件回读契约；轮转、跨重启保留、错误堆栈截断继续独立。
- SSE buffer 把容量淘汰与 dropped marker 合并，删除空 flush 和较弱的自动 flush 重复；保留普通 flush、容量边界、drain 终止和在途自动写入等待。
- 异步测试 helper 删除完成后监听关闭和同步二次错误的内部时序装具；保留初始命中、后续命中、Provider 错误和超时描述四个外部契约。
- 分页状态的 16 个微测试收敛为 4 个表驱动契约；分页栏合并页码按钮与输入跳转，删除纯函数已经覆盖的空输入/越界/当前页细节；外壳合并 header 与固定分页栏并删除 bar 已持有的回调透传重复。

生产代码、依赖、数据库 schema 和迁移均未修改。

## 覆盖率取舍

本批 LCOV 分母保持 18,933 行，命中行只减少 2 行。主要生产 owner 当前行覆盖率如下：

| 生产 owner | 行覆盖率 |
| --- | ---: |
| `sqlite_favorites_repository.dart` | 83 / 83（100.00%） |
| `sqlite_collections_repository.dart` | 50 / 50（100.00%） |
| `app_paginated_list_shell.dart` | 43 / 43（100.00%） |
| `app_pagination_bar.dart` | 77 / 82（93.90%） |
| `app_pagination_state.dart` | 26 / 28（92.86%） |
| `app_log_store.dart` | 41 / 42（97.62%） |
| `app_network_logger.dart` | 43 / 50（86.00%） |
| `sse_log_buffer.dart` | 31 / 36（86.11%） |

日志脱敏与敏感 Header 测试不在本批范围。收藏外键、typed delete、事务回滚和稳定排序完整保留；分页 48px 命中区、busy 禁用、inline error、加载态与 `pageIdentity` 滚动语义也完整保留。

## 累计结果

从首次审计基线到第五批完成：

| 指标 | 初始基线 | 当前 | 累计变化 |
| --- | ---: | ---: | ---: |
| 测试代码 | 60,975 行 | 53,466 行 | 净减 7,509 行（12.3%） |
| 显式注册点 | 1,960 | 1,693 | -267（-13.6%） |
| 覆盖率运行节点 | 2,130 | 1,782 | -348（-16.3%） |
| 覆盖率墙钟时间 | 213.505 秒 | 160.522 秒 | -52.983 秒（-24.8%） |
| Flutter 原始行覆盖率 | 16,982 / 18,942（89.65%） | 16,743 / 18,933（88.43%） | -1.22 个百分点 |

覆盖率分母累计少 9 行，是第一批删除专用测试后 `AppConstrainedContent` 不再进入 LCOV source 集合所致；第二至第五批分母都没有继续变化。

## 验证

- 固定 8 文件基准：56 个测试通过，reporter 0:04，父进程墙钟 10.701 秒。
- `flutter test --reporter compact`：1,782 个测试通过，reporter 1:35，父进程墙钟 102.126 秒。
- `flutter test --exclude-tags=udp --coverage --reporter compact`：1,782 个测试通过，reporter 2:27，父进程墙钟 160.522 秒。
- `dart run tool/check_import_boundaries.dart`：通过，检查 392 个文件，0 条违规。
- `flutter analyze`：首次发现并删除一条随外壳断言一起失效的 import；清理后复验通过，无 issue。

## 停止建议

第五批后应停止按测试数量继续删减。固定集合继续显著变快，但日常全量和覆盖率运行已由未修改的慢 Widget / integration 分片及编译开销主导；剩余 migration、parser、安全、平台竞态和状态机测试的风险高于预期收益。后续只应根据新的分片计时处理具体慢点。
