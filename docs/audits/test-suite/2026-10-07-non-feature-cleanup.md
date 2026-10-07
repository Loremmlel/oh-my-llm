# 非 feature 测试清理结果（2026-10-07）

本轮扫描 `test/app`、`test/architecture`、`test/core`、`test/integration`、`test/helpers` 的 100 个 Dart 文件；请求中的 `text/helper` 按实际共享目录 `test/helpers` 处理。没有修改 `test/features` 或生产 Dart 代码。

清理前基线为 `1584d6a63adb1d231bdd9c0b1fa674130f145e96`。本轮只做本地提交，不创建 PR。

## 删减依据与继续承担契约的 owner

| 问题 | 处理 | 继续验证的契约 / owner |
| --- | --- | --- |
| peer Header 测试把生产 Provider 替换为 MockClient，无法检出生产密钥泄漏 | 两例改为一条真实 loopback HTTP 测试，保留生产客户端绑定 | `http_client_provider_test.dart` 验证 LLM 收到 Authorization、Cookie、API key 和普通自定义 Header，peer 均收不到 |
| bootstrap 重复启动四次，部分断言仅检查非空或静态接口类型 | 合并成功启动、资源身份、仓库读取和 Windows 初始化；保留非 Windows 与两种启动失败 | `bootstrap_integration_test.dart` 负责资源注入、可见导航、平台初始化与失败释放；迁移归 migration 测试 |
| 聊天集成测试手工重建生产装配链 | 使用 `appCompositionOverrides`，只替换最外部 HTTP 边界；删掉未运行协议的 fixture 分支 | `multi_protocol_chat_generation_integration_test.dart` 验证生产 Chat / LLM / repository 绑定实际发送请求并落盘正文、推理、终态及部分失败回复 |
| 媒体默认密度独立启动容器；同步页重复测试壳层断点 | 密度断言并入已有 Android / Windows 来源测试；删掉两条壳层 smoke | composition 来源测试保留两种密度，`app_shell_scaffold_test.dart` 保留 719→720 真实导航与固定动作 |
| 三种协议的公共选项测试重复启动传输与空 SSE | 编码矩阵移至纯 encoder；摘要和发送前拒绝分别移至客户端 owner | `llm_input_encoder_test.dart` 保留输出上限、缓存键、TTL；Responses 客户端保留无 effort 摘要；`llm_client_test.dart` 保留错误选项零发送 |
| 分页构造器与它直接调用的函数互相比较 | 删除自我一致性测试 | `app_pagination_state_test.dart` 仍用独立预期值验证夹取、进位和省略页码 |
| 同一输入重复计算网格几何；检查 State 创建次数 | 删除重复计算；点击计数后调整宽度验证状态保留 | 几何 owner 保留容差、宽度单调性、无效规格；widget owner 保留长小数父宽度、惰性构建与可见状态 |
| 分页显示、命中区域、跳转和滚动保留分别重复挂载 | 合并同一场景中的断言；用可见输入和捕获的滚动位置替代 controller 文本与魔法偏移 | 分页交互、busy、容量、零页、内联失败、固定头尾与页身份切换均保留 |
| 两个消息版本恢复流程和两个多对话恢复流程重复准备 | 各合为一个连续恢复流程；移除对重型页面 helper 的间接依赖 | 验证新旧分支、图片、原消息 ID、完整 A/B 消息、列表与活动对话；多轮恢复同时验证 finishReason |
| 当前 schema 的结构拆成四次初始化；内存 WAL 断言只能证明 SQLite 行为 | 当前结构集中一次；删除 SQLite 自身不支持内存 WAL 的弱断言 | 每个历史迁移 fixture、数据保留、回滚、版本拒绝、外键与事务原子性测试保持不变 |
| JSON fallback 重复、无意义的异步排队；日志测试重复创建嵌套临时目录 | fallback 合为一张输入表并检查原存储不变；复用一层日志装具 | storage 写入拒绝 / 异常、缓冲容量 / 丢弃 / drain / 在途 flush 均保留 |
| 截断测试自定义 Matcher 和多个容器场景重复 | 改成完整预期字符串与混合嵌套对象；合并 emoji 默认 / 自定义边界 | 字符边界、嵌套 Map/List、标量及完整 emoji 保持覆盖，断言比前缀 / 长度检查更严格 |
| 日期 / 摘要按每行数据注册测试，协议存储值往返依赖自身编码 | 同一规则合为表驱动断言，增加输入 reason；存储编码与解码分别比较固定字面量 | 全部原日期、空白、截断、默认参数和未知协议输入保留 |
| ID 格式测试绑定时间戳和随机数拼接实现 | 删除独立格式测试 | ID 作为不透明标识；消息版本与多对话恢复测试实际验证不同实体和持久身份 |
| Windows 返回键按下与 repeat/up 两次挂载；架构标题硬编码例外数量 | 合并一次按键生命周期；标题改为所有声明例外 | 输入消费、一次返回、其他键放行及真实仓库零违规 / stale allowance 均保留 |

## 保留与暂留

- 保留三个原生协议的工具往返与 Agent 恢复集成测试：经过不同 adapter，涉及不同原生 envelope、reasoning / thinking 回放和持久化失败机制，不属于对称重复。
- 保留 HTTP 信任域、敏感脱敏、SSE byte 切分 / timeout / cancellation、平台竞态和通知终态保护。
- `test/helpers/async` 的现有自测覆盖立即命中、后续变化、错误传播、描述性超时、有限 / 无限动画，具有独立检测价值。
- `test/helpers/matchers.dart` 的 `findsBetween` 没有消费者，而且实现只接受整数，与 Finder 注释不符。本轮暂留，因为删除需要同步改本次范围之外的 `test/test_utils.dart` 公共导出；后续清理根级公共测试工具时一并删除。
- 剩余最慢的单例主要是每个 widget 文件首例的初始化（清理前目录首轮约 1.7–2.7 秒）。没有为减少耗时缩小协议、安全或几何性质测试的输入域。

## 规模与目录基准

| 指标 | 清理前 | 清理后 |
| --- | ---: | ---: |
| 范围内 Dart 文件 | 100 | 96 |
| 自动发现的测试入口 | 82 | 79 |
| 测试物理行 | 19,577 | 18,909 |
| 目录测试运行节点 | 597 | 550 |
| 三轮墙钟时间（秒） | 57.485 / 56.292 / 55.275 | 55.267 / 54.155 / 74.733 |
| 墙钟中位数（秒） | 56.292 | 55.267 |
| reporter 中位数（秒） | 52.266 | 51.307 |
| 原始命中行 / 可插桩行 | 10,185 / 24,868 | 10,197 / 24,868 |
| 原始行覆盖率 | 40.9562% | 41.0045% |

净减 668 行、47 个运行节点（7.9%）。目录墙钟中位数只减少 1.025 秒（1.8%），且波动区间重叠，不能据此声称稳定提速。

目录 LCOV 覆盖所有被加载的生产源文件，分母包含许多不归这些目录负责的 feature 行；40% 是该分片的原始覆盖率，不是全仓覆盖率。最终目录结果没有丢失任何原已命中的生产行。曾因移除 bootstrap 类型断言暂时失去 Chat 装配三行覆盖，已由生产 composition 的真实请求与持久化验证恢复。

| 关键 owner（目录运行） | 清理前命中 / 可插桩 | 清理后命中 / 可插桩 |
| --- | ---: | ---: |
| `lib/core/http` | 170 / 186 | 172 / 186 |
| `lib/core/llm` | 1,322 / 1,427 | 1,322 / 1,427 |
| `lib/core/persistence` | 359 / 387 | 360 / 387 |
| `lib/app` | 802 / 968 | 803 / 968 |
| `lib/features/chat` | 2,708 / 6,716 | 2,710 / 6,716 |

## 全量结果与覆盖行核对

| 指标 | 清理前 | 清理后 |
| --- | ---: | ---: |
| 全量运行节点 | 2,055 | 2,008 |
| 三轮墙钟时间（秒） | 175.429 / 179.500 / 179.146 | 165.132 / 164.877 / 164.506 |
| 墙钟中位数（秒） | 179.146 | 164.877 |
| reporter 中位数（秒） | 174.663 | 160.526 |
| 原始命中行 / 可插桩行 | 22,248 / 24,880 | 22,253 / 24,880 |
| 原始行覆盖率 | 89.4212% | 89.4413% |

清理前后三轮全量均通过。全量墙钟中位数减少 14.269 秒（8.0%）；这是本机带 coverage 命令的前后测量，不能直接外推到 CI 或不带 coverage 的运行。前后按顺序测量，未做交错 A/B；缓存与系统负载仍可能影响差值。

每一阶段的三份目录 LCOV、三份全量 LCOV，其命中行集合均完全一致。前后逐行比较：目录丢失 0 行、增加 12 行；全量丢失 0 行、增加 5 行。分母均未减少，因此覆盖率上升没有来自排除源文件。全量新增命中为真实 peer 客户端创建与释放、非 Android 权限端口、后台仓库读取路径；未发现需要恢复的行为覆盖。

| 关键 owner（全量运行） | 清理前覆盖率（命中 / 可插桩） | 清理后覆盖率（命中 / 可插桩） |
| --- | ---: | ---: |
| `lib/core/http` | 94.6237%（176 / 186） | 95.6989%（178 / 186） |
| `lib/core/llm` | 93.6230%（1,336 / 1,427） | 93.6230%（1,336 / 1,427） |
| `lib/core/persistence` | 94.3152%（365 / 387） | 94.3152%（365 / 387） |
| `lib/app` | 87.8099%（850 / 968） | 87.9132%（851 / 968） |
| `lib/features/chat` | 88.9981%（5,978 / 6,717） | 89.0278%（5,980 / 6,717） |

JSON reporter 的加载和执行分开统计如下。数值是同一轮所有 suite / 用例的耗时总和，再取三轮中位数；并发 8 下不可与墙钟相加。加载包括编译与 runner 等待，widget 首例自身初始化仍计入用例执行，不能把这些统计等同于纯编译或业务 CPU 时间。

| 耗时总和的中位数（秒） | 清理前 | 清理后 |
| --- | ---: | ---: |
| 目录 `loading` | 161.039 | 158.770 |
| 目录用例执行 | 67.048 | 67.593 |
| 目录 setup / teardown | 0.030 | 0.031 |
| 全量 `loading` | 415.326 | 379.505 |
| 全量用例执行 | 413.678 | 381.996 |
| 全量 setup / teardown | 0.034 | 0.027 |

目录执行总和没有下降，少量真实边界验证增加了工作；不能把减少 47 个便宜节点等同于减少 47 份显著执行成本。全量的加载与执行总和均下降，但现有三轮数据不能精确拆出各项改动的独立收益。

## 测量方法与回归证据

Windows 原生 PowerShell 7，`dart_test.yaml` 并发 8。前后均用同一条 Flutter 命令，包含 coverage；不将此结果当作不带 coverage 的日常测试用时。每轮进程树硬超时 240 秒；单文件验证为 60 秒。

```powershell
flutter test --no-pub test/app test/architecture test/core test/integration test/helpers --coverage --coverage-path=logs/test-cleanup-<阶段>-scope-<轮次>.lcov --reporter compact --file-reporter=json:logs/test-cleanup-<阶段>-scope-<轮次>.json
flutter test --no-pub --coverage --coverage-path=logs/test-cleanup-<阶段>-full-<轮次>.lcov --reporter compact --file-reporter=json:logs/test-cleanup-<阶段>-full-<轮次>.json
```

- Header 隔离 red：暂时让 peer Provider 返回 LLM 客户端；新测试以 Authorization 实际泄漏失败。恢复生产绑定后 green，并在三轮目录回归中通过。
- 修改的测试入口定向回归：174 个通过；生产 composition 集成追加定向验证：2 个通过。
- `flutter analyze --no-pub`：通过，无 issue。
- `dart run tool/check_import_boundaries.dart`：通过，检查 446 个文件、0 条违规。
- 三轮目录回归各 550 个通过；三轮全量回归各 2,008 个通过，均包含覆盖率采集。
- 原始过程、JSON reporter、LCOV 和计时记录在 ignored 的 `logs/test-cleanup-*`；全量当前日志使用 `logs/fltest.log`。
