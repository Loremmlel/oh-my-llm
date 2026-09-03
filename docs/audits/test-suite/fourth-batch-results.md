# 测试精简第四批结果

## 结论

第四批按 Data、controller 与基础设施收口方案，修改 6 个测试文件；删除 1,208 行、增加 192 行，测试代码净减 1,016 行。固定 7 文件基准从 109 个运行节点降至 59 个，墙钟从 20.727 秒降至 12.601 秒，减少 8.126 秒（39.2%）。

日常全量运行节点从 1,869 个降至 1,819 个。删减后三次墙钟为 113.640、98.436、97.703 秒，中位数 98.436 秒；相较删减前单次基线 108.815 秒减少 10.379 秒（9.5%）。第一次删减后运行比基线慢 4.4%，说明全量并发调度存在约 15 秒波动，因此固定集合结果比单次全量更适合归因。

覆盖率命令单次墙钟从 145.772 秒变为 152.604 秒，增加 6.832 秒（4.7%），本批不能宣称覆盖率运行提速。原始行覆盖率从 88.4963% 降至 88.4435%，只减少 10 个命中行（0.0528 个百分点）。

## 前后对比

| 指标 | 删减前（第三批完成） | 删减后 | 变化 |
| --- | ---: | ---: | ---: |
| 测试 Dart 文件 | 247 | 247 | 0 |
| 测试代码物理行 | 54,978 | 53,962 | -1,016（-1.8%） |
| 显式 `test` / `testWidgets` 注册点 | 1,778 | 1,730 | -48（-2.7%） |
| 固定 Data / infrastructure 基准运行节点 | 109 | 59 | -50（-45.9%） |
| 固定 Data / infrastructure 基准墙钟时间 | 20.727 秒 | 12.601 秒 | -8.126 秒（-39.2%） |
| 固定 Data / infrastructure 基准 reporter 时间 | 0:12 | 0:05 | -0:07（-58.3%） |
| 日常全量运行节点 | 1,869 | 1,819 | -50（-2.7%） |
| 日常全量墙钟时间 | 108.815 秒（单次） | 98.436 秒（三次中位数） | -10.379 秒（-9.5%） |
| 日常全量 reporter 时间 | 1:40（单次） | 1:31（三次中位数） | -0:09（-9.0%） |
| 覆盖率口径运行节点 | 1,869 | 1,819 | -50（-2.7%） |
| 覆盖率口径墙钟时间 | 145.772 秒 | 152.604 秒 | +6.832 秒（+4.7%） |
| 覆盖率口径 reporter 时间 | 2:17 | 2:23 | +0:06（+4.4%） |
| Flutter 原始行覆盖率 | 16,755 / 18,933（88.4963%） | 16,745 / 18,933（88.4435%） | -10 命中行，-0.0528 个百分点 |

固定基准前后使用同一条命令，包含以下 7 个文件：

- `llm_model_configs_controller_test.dart`
- `settings_transfer_catalog_test.dart`
- `settings_transfer_catalog_contract_test.dart`
- `settings_transfer_coordinator_test.dart`
- `settings_sync_facade_test.dart`
- `persisted_settings_controllers_test.dart`
- `media_thumbnail_generator_test.dart`

全量覆盖率口径仍为：

```powershell
flutter test --exclude-tags=udp --coverage --reporter compact
```

## 本批删减

- LLM provider 测试从 921 行 / 30 条收敛到 384 行 / 10 条。`mergeImportedLlmProviders` 保留 ID 优先、归一化等价键、协议隔离和模型名去重四项完整规则；controller 只保留组合 CRUD、批量写入、一次导入接线、写失败不发布、模型 CRUD 和批量净增量。
- 持久化偏好 controller 从 343 行 / 21 条收敛到 142 行 / 5 条。四个薄包装不再各自重复 missing、corrupt、save/revive 和 rejected-write 模板；保留请求头索引操作、一个共享写失败契约、字体 `updateLocal`、输出规则持久化和自动重试旧裸 JSON 拒绝。
- Transfer facade 从 5 条收敛到 1 条，只证明新增 participant 能端到端进入导出、摘要和执行。生产 catalog 的顺序、类型、canonical v9 和 local-only 排除仍由 catalog contract 持有；未知分组、`allowedGroups`、敏感确认、stale、并发 writer、部分失败和一次性批次仍由 coordinator 持有。
- 删除 catalog contract 与 coordinator 中另外两条 fake participant 可扩展性重复，唯一 owner 是 facade 的端到端用例和 catalog 自身的 fake key 注册测试。
- 缩略图生成器从 16 个显式用例收敛到 10 个。保留图片格式成功、并发门控、损坏图片，以及视频短/长取帧、版本缓存、字节 stdout、启动失败、非法时长、提取失败和空输出；删除同阶段等价异常类别。

生产代码、依赖、SQLite fixture、迁移、协议 parser 和安全测试均未修改。

## 覆盖率取舍

本批 LCOV 分母保持 18,933 行，命中行只减少 10 行。被保留的核心 owner 当前行覆盖率如下：

| 生产 owner | 行覆盖率 |
| --- | ---: |
| `llm_provider_import_merger.dart` | 24 / 24（100.00%） |
| `llm_model_configs_controller.dart` | 83 / 83（100.00%） |
| `custom_headers_controller.dart` | 27 / 27（100.00%） |
| `font_size_settings_controller.dart` | 15 / 15（100.00%） |
| `output_processing_settings_controller.dart` | 13 / 13（100.00%） |
| `auto_retry_settings_controller.dart` | 13 / 13（100.00%） |
| `settings_transfer_catalog.dart` | 61 / 65（93.85%） |
| `settings_transfer_coordinator.dart` | 134 / 142（94.37%） |
| `settings_sync_facade.dart` | 56 / 61（91.80%） |
| `media_thumbnail_generator.dart` | 77 / 90（85.56%） |

Transfer 的敏感确认、分组白名单、canonical v9、事务失败和并发串行化全部保留。缩略图只放弃同一错误阶段的消息排列，不删除图片/视频成功脊柱、并发和缓存契约。

## 累计结果

从首次审计基线到第四批完成：

| 指标 | 初始基线 | 当前 | 累计变化 |
| --- | ---: | ---: | ---: |
| 测试代码 | 60,975 行 | 53,962 行 | 净减 7,013 行（11.5%） |
| 显式注册点 | 1,960 | 1,730 | -230（-11.7%） |
| 覆盖率运行节点 | 2,130 | 1,819 | -311（-14.6%） |
| 覆盖率墙钟时间 | 213.505 秒 | 152.604 秒 | -60.901 秒（-28.5%） |
| Flutter 原始行覆盖率 | 16,982 / 18,942（89.65%） | 16,745 / 18,933（88.44%） | -1.21 个百分点 |

覆盖率分母累计少 9 行，是第一批删除专用测试后 `AppConstrainedContent` 不再进入 LCOV source 集合所致；第二至第四批分母都没有继续变化。

## 验证

- 固定 7 文件基准：59 个测试通过，reporter 0:05，父进程墙钟 12.601 秒。
- `flutter test --reporter compact`：三次均为 1,819 个测试通过；墙钟 113.640、98.436、97.703 秒，中位数 98.436 秒；reporter 1:44、1:31、1:27，中位数 1:31。
- `flutter test --exclude-tags=udp --coverage --reporter compact`：1,819 个测试通过，reporter 2:23，父进程墙钟 152.604 秒。
- `dart run tool/check_import_boundaries.dart`：通过，检查 392 个文件，0 条违规。
- `flutter analyze`：首次发现并删除一条随 fake participant 一起失效的 import；清理后复验通过，无 issue。

## 后续

四批累计已净删 7,013 行，并让覆盖率墙钟相对初始基线下降 28.5%，超过实施方案的 20% 阶段目标。剩余候选主要位于 Favorites / History repository、日志 IO 与少量基础设施 helper；这些多为便宜的纯 Dart 测试，预期维护面收益大于全量时间收益。继续第五批前应重新按当前套件测量慢分片，不再按最初估算机械追求 9,963 行。
