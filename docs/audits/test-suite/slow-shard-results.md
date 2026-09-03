# 实测慢分片处理结果

## 结论

第五批后不再按测试数量扫仓，而是用 JSON 事件计时对全量套件做三轮剖析。实测确认 `SyncWorkspaceScreen`、`app_router`和四个 Settings 表单 / CRUD 入口仍在重复验证下层已拥有的矩阵。

本次修改 10 个测试 / helper 文件，删除 1,394 行、增加 65 行，测试代码净减 1,329 行。六个目标入口的运行节点从 85 个收敛到 31 个；全量运行节点从 1,782 个降到 1,728 个。同命令三轮墙钟中位数从 95.822 秒降到 78.351 秒，减少 17.471 秒（18.2%）。

Flutter 原始行覆盖率从 88.4329% 降到 87.5297%，下降 0.9032 个百分点。数据库迁移、Sync 安全、协议解码、并发终态和核心用户流程未删。

## 测量口径

全量性能前后都使用同一命令，每轮产生独立 JSON 事件日志，取三轮中位数：

```powershell
flutter test --reporter compact --file-reporter json:logs/<profile>.json
```

覆盖率与第五批保持同一口径，单次运行：

```powershell
flutter test --exclude-tags=udp --coverage --reporter compact
```

逐分片「执行时长」是同一全量 profile 内该文件所有非 loading 测试的 `testDone.time - testStart.time` 之和，再取三轮中位数。分片会并行，该值只用于同文件前后对比，不与全量墙钟相加。

## 前后对比

| 指标 | 处理前（第五批后） | 处理后 | 变化 |
| --- | ---: | ---: | ---: |
| 测试 Dart 文件 | 247 | 247 | 0 |
| 测试代码物理行 | 53,466 | 52,137 | -1,329（-2.5%） |
| 显式 `test` / `testWidgets` 注册点 | 1,693 | 1,641 | -52（-3.1%） |
| 目标六分片运行节点 | 85 | 31 | -54（-63.5%） |
| 目标六分片执行时长中位数之和 | 45.193 秒 | 21.646 秒 | -23.547 秒（-52.1%） |
| 日常全量运行节点 | 1,782 | 1,728 | -54（-3.0%） |
| 日常全量墙钟中位数 | 95.822 秒 | 78.351 秒 | -17.471 秒（-18.2%） |
| 日常全量 reporter 中位数 | 88.198 秒 | 67.089 秒 | -21.109 秒（-23.9%） |
| 覆盖率墙钟时间 | 160.522 秒 | 134.285 秒 | -26.237 秒（-16.3%） |
| Flutter 原始行覆盖率 | 16,743 / 18,933（88.4329%） | 16,572 / 18,933（87.5297%） | -171 命中行，-0.9032 个百分点 |

全量墙钟原始数据：

- 处理前：119.123 / 91.815 / 95.822 秒，中位数 95.822 秒。
- 处理后：79.932 / 75.092 / 78.351 秒，中位数 78.351 秒。

## 逐分片结果

| 入口 | 处理前执行时长 | 处理后 | 减少 |
| --- | ---: | ---: | ---: |
| `sync_workspace_screen_test.dart` | 11.586 秒 | 3.931 秒 | 66.1% |
| `app_router_test.dart` | 9.145 秒 | 4.189 秒 | 54.2% |
| `template_prompt_form_dialog_test.dart` | 6.881 秒 | 3.440 秒 | 50.0% |
| `model_config_form_dialog_test.dart` | 6.361 秒 | 3.482 秒 | 45.3% |
| `model_provider_form_dialog_test.dart` | 5.847 秒 | 3.497 秒 | 40.2% |
| `output_processing_tab_test.dart` | 5.373 秒 | 3.107 秒 | 42.2% |

另外对四个最慢整页 Widget 分片做了单变量探针：把有限动画的 `pumpAndSettle` 步进从 50ms 恢复为 Flutter 默认 100ms，避免额外渲染中间帧。固定 172 节点三轮墙钟中位数从 50.968 秒降到 46.524 秒，减少 8.7%；不删测试或断言。

## 本次删减

- App router 删除收藏列表点击 / 返回、image / video 对称路由、Chat query 生命周期和 History 分页深链的重复整树装配；保留收藏 canonical 详情、已删除恢复、旧 URL 重定向、收藏夹深链、一条媒体路由、缺参恢复、Chat 深链和 History 搜索深链。
- Sync composition 删除静态文案、分组选择、媒体会话生命周期、密度选择和返回链的重复矩阵；保留 Android 远程来源、Windows 本地来源、目录返回、紧凑 / 宽壳层边界、敏感确认与导入 busy 保护。
- Template prompt 表单不再重演 compiler / evaluator 的语法矩阵；保留展开 smoke、合法 select 提交、带行列诊断不提交和短暂无效后恢复输入。
- Model 表单不再分别重演 client / workflow 的 loading / success / existing 矩阵和每个协议；保留手动提交、Anthropic 协议传递、失败重试、勾选提交和保存 busy 保护。
- Output processing Tab 删除空态 / 卡片静态渲染、空表达式、编辑和取消 Dialog 默认行为；保留无效正则、新增、启停 + 重排和确认删除。

生产代码、依赖、SQLite schema 和迁移均未修改。

## 覆盖率取舍

LCOV 分母保持 18,933 行，减少的 171 个命中行来自被移除的 UI 对称分支和文案分支。相关生产 owner 的处理后行覆盖率为：

| 生产 owner | 行覆盖率 |
| --- | ---: |
| `app_router.dart` | 52 / 57（91.23%） |
| `sync_workspace_screen.dart` | 83 / 115（72.17%） |
| `output_processing_tab.dart` | 141 / 150（94.00%） |
| `template_prompt_form_dialog.dart` | 182 / 206（88.35%） |
| `model_config_form_dialog.dart` | 85 / 86（98.84%） |
| `model_provider_form_dialog.dart` | 53 / 53（100.00%） |

Sync composition 的低一层协议、安全、controller 和媒体会话 owner 仍由各自专用测试完整覆盖；72.17% 是顶层组装页主动不再遍历所有 UI 分支的结果。

## 验证

- 六个目标入口定向回归：31 个节点连续三次通过，墙钟 15.286 / 15.199 / 15.097 秒。
- `flutter test --reporter compact --file-reporter json:...`：三轮均 1,728 个节点通过，墙钟中位数 78.351 秒。
- `flutter test --exclude-tags=udp --coverage --reporter compact`：1,728 个节点通过，墙钟 134.285 秒，覆盖率 87.5297%。
- `flutter analyze`：通过，无 issue。
- `dart run tool/check_import_boundaries.dart`：通过，检查 392 个文件，0 条违规。
- `git diff --check`：通过。

## 累计结果与停止条件

从首次审计基线到本次慢分片处理完成：

| 指标 | 初始基线 | 当前 | 累计变化 |
| --- | ---: | ---: | ---: |
| 测试代码 | 60,975 行 | 52,137 行 | 净减 8,838 行（14.5%） |
| 显式注册点 | 1,960 | 1,641 | -319（-16.3%） |
| 覆盖率运行节点 | 2,130 | 1,728 | -402（-18.9%） |
| 覆盖率墙钟时间 | 213.505 秒 | 134.285 秒 | -79.220 秒（-37.1%） |
| Flutter 原始行覆盖率 | 16,982 / 18,942（89.65%） | 16,572 / 18,933（87.53%） | -2.12 个百分点 |

本次已处理所有「实测较慢 + 原审计已判定重复」的剩余入口。当前慢榜前列的 Chat / Favorites / History / Settings 整页测试承载消息树、搜索规则、分页回退、提示词顺序和持久化等明确核心契约，不应因为排名靠前继续机械删减。后续只在新的三轮 profile 同时证明「真慢」与「有重复 owner」时再处理。
