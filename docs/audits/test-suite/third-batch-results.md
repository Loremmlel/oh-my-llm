# 测试精简第三批结果

## 结论

第三批收敛媒体视频 controller、移动/桌面页面、无障碍和路由恢复矩阵，修改 5 个测试文件；删除 2,386 行、增加 672 行，测试代码净减 1,714 行。固定媒体基准从 145 个运行节点降至 81 个，墙钟从 33.612 秒降至 16.383 秒，减少 17.229 秒（51.3%）。

全量覆盖率命令从 168.384 秒降至 145.772 秒，减少 22.612 秒（13.4%）；reporter 从 2:38 降至 2:17。原始行覆盖率从 88.76% 降至 88.50%，减少 49 个命中行（0.26 个百分点）。

## 前后对比

| 指标 | 删减前（第二批完成） | 删减后 | 变化 |
| --- | ---: | ---: | ---: |
| 测试 Dart 文件 | 247 | 247 | 0 |
| 测试代码物理行 | 56,692 | 54,978 | -1,714（-3.0%） |
| 显式 `test` / `testWidgets` 注册点 | 1,842 | 1,778 | -64（-3.5%） |
| 固定媒体基准运行节点 | 145 | 81 | -64（-44.1%） |
| 固定媒体基准墙钟时间 | 33.612 秒 | 16.383 秒 | -17.229 秒（-51.3%） |
| 固定媒体基准 reporter 时间 | 0:24 | 0:08 | -0:16（-66.7%） |
| 日常全量运行节点 | 1,933 | 1,869 | -64（-3.3%） |
| 日常全量墙钟时间 | 113.222 秒 | 108.815 秒 | -4.407 秒（-3.9%） |
| 日常全量 reporter 时间 | 1:43 | 1:40 | -0:03（-2.9%） |
| 覆盖率口径运行节点 | 1,933 | 1,869 | -64（-3.3%） |
| 覆盖率口径墙钟时间 | 168.384 秒 | 145.772 秒 | -22.612 秒（-13.4%） |
| 覆盖率口径 reporter 时间 | 2:38 | 2:17 | -0:21（-13.3%） |
| Flutter 原始行覆盖率 | 16,804 / 18,933（88.76%） | 16,755 / 18,933（88.50%） | -49 命中行，-0.26 个百分点 |

固定媒体基准前后使用同一条命令，包含以下 7 个文件：

- `desktop_video_interaction_controller_test.dart`
- `video_player_desktop_test.dart`
- `mobile_video_interaction_controller_test.dart`
- `video_player_page_test.dart`
- `video_playback_controller_test.dart`
- `video_player_accessibility_test.dart`
- `media_route_pages_test.dart`

全量覆盖率口径仍为：

```powershell
flutter test --exclude-tags=udp --coverage --reporter compact
```

## 本批删减

- Desktop controller 从 45 条收敛到 20 条：保留右键短按/长按互斥、暂停 guard、失焦收口、主要快捷键、全屏成功/失败、Escape、自动隐藏 hold、滚轮方向/节流和 dispose 后迟到结果。
- Desktop 页面从 23 条收敛到 11 条：每类输入只保留一条 wiring，继续验证焦点、弹层 Escape、全屏/返回、触摸双击策略、滚轮与应用失焦；controller 已覆盖的 repeat、clamp 和多种取消来源不再在页面重复。
- Mobile 页面从 18 条收敛到 8 条：保留初始化失败重试、双击、长按、横拖、关闭释放与系统 UI、系统手势边缘、非宽屏布局和平台快捷键隔离。
- 无障碍从 24 个显式注册点收敛到 13 个：保留两个极端 viewport、播放/加载/错误语义、一个键盘等价操作、单一 live region、进度 enabled/disabled、焦点可达和桌面帮助/失败反馈。
- 路由恢复从 14 条收敛到 8 条：保留合法图片/视频、无效链接、会话失效、解析失败不创建 bindings、独立视频会话，以及嵌套 pop / 顶层 go 两种返回栈。
- 将桌面触摸双击从点击被 overlay 遮挡的 `VideoPlayer` finder 改为按播放区域坐标发送手势，消除 Flutter 的 missed hit-test 警告。

共享播放核心和 Mobile interaction controller 测试未改动。播放初始化、Seek clamp、临时倍速 lease、静音记忆、音量边界与失败反馈仍由 `video_playback_controller_test.dart` 完整持有；移动手势状态转换仍由 `mobile_video_interaction_controller_test.dart` 持有。

## 覆盖率取舍

本批 LCOV 分母保持 18,933 行，命中行减少 49 行，全部来自主动减少的媒体页面/controller 状态排列。关键生产 owner 的当前行覆盖率仍为：

| 生产 owner | 行覆盖率 |
| --- | ---: |
| `video_playback_controller.dart` | 234 / 240（97.50%） |
| `mobile_video_interaction_controller.dart` | 97 / 104（93.27%） |
| `video_player_page.dart` | 296 / 314（94.27%） |
| `media_route_pages.dart` | 47 / 50（94.00%） |
| `desktop_video_interaction_controller.dart` | 188 / 214（87.85%） |

媒体安全边界、HTTP Range、路径穿越、远端 peer headers、资源解析和缓存键测试均不在本批改动范围。无障碍基础契约没有以提速为由删除。

## 累计结果

从首次审计基线到第三批完成：

| 指标 | 初始基线 | 当前 | 累计变化 |
| --- | ---: | ---: | ---: |
| 测试代码 | 60,975 行 | 54,978 行 | 净减 5,997 行（9.8%） |
| 显式注册点 | 1,960 | 1,778 | -182（-9.3%） |
| 覆盖率运行节点 | 2,130 | 1,869 | -261（-12.3%） |
| 覆盖率墙钟时间 | 213.505 秒 | 145.772 秒 | -67.733 秒（-31.7%） |
| Flutter 原始行覆盖率 | 16,982 / 18,942（89.65%） | 16,755 / 18,933（88.50%） | -1.16 个百分点 |

覆盖率分母累计少 9 行，是第一批删除专用测试后 `AppConstrainedContent` 不再进入 LCOV source 集合所致；第二、三批分母都没有继续变化。

## 验证

- 固定 7 文件媒体基准：81 个测试通过，reporter 0:08，父进程墙钟 16.383 秒，无 missed hit-test 警告。
- `flutter test test/features/media/presentation/pages/video_player_desktop_test.dart --reporter compact`：11 个测试通过。
- `flutter test --reporter compact`：1,869 个测试通过，reporter 1:40，父进程墙钟 108.815 秒。
- `flutter test --exclude-tags=udp --coverage --reporter compact`：1,869 个测试通过，reporter 2:17，父进程墙钟 145.772 秒。
- `flutter analyze`：通过，无 issue。
- `dart run tool/check_import_boundaries.dart`：通过，检查 392 个文件，0 条违规。

## 后续

三批累计覆盖率墙钟已下降 31.7%，超过实施方案的 20% 阶段目标。继续删减不应再追求测试数量；若还有第四批，应只处理经测量确认的慢 Widget 分片或 data/controller 的明确重复，不再触碰媒体核心状态、parser、migration、安全或 generation lifecycle。
