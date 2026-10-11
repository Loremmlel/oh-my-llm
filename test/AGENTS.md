# 测试约定

适用于新增、修改、删除和优化测试。先读根 [AGENTS.md](../AGENTS.md)、[执行与日志指南](../CONTRIBUTING.md)，以及被测代码所属领域的 AGENTS.md；测试不因位于 test/ 而绕过产品契约。

## 主验证层与覆盖所有权

- **一个产品契约只有一个主 owner**，矩阵放在能暴露根因的最低稳定边界：纯规则归 domain / parser，持久化归 repository / migration，异步转移归 controller / run，页面归用户可见交互，composition / integration 归真实 wiring。
- 上层不重演下层矩阵，默认最多一条代表性成功路径和一条本层独有的关键失败。新增或保留上层用例须能说明只有本层才会引入的故障机制；层级不同本身不是互补验证的理由。
- 协议、平台、视口、终态等等价类在 owner 层参数化，上层选一个代表值，不再做笛卡尔积。不同 adapter 或失败机制才逐一保留。安全、数据丢失、已发布迁移、协议兼容、并发终态允许跨层保护，但每层明确独有失败原因。
- 测输入输出、状态变化与稳定产品行为，不测框架自动行为或私有实现。copyWith 随模型测试，不随 controller 测；空列表查不到内容、框架自动建 tab 等不单独测试。
- integration 必须经真实生产 wiring / 边界产生下游结果；手工将 controller A 的数据复制给 B 不算集成。不能提前完成待验证动作再归因于被测对象，例如注入已迁移数据库不能证明 bootstrap 执行迁移。

## 缺陷回归与清理

- 确认影响稳定产品行为、数据、安全、协议兼容或跨层 wiring 且能确定性复现的缺陷，必须补回归保护；安全、数据丢失、兼容性优先边界级验证。
- 先补强本应捕获缺陷的现有用例；仅在契约、层级或失败机制不同的情况下新增。用例说明长期契约、主 owner 和本层独有故障，不能只保留当时的 Issue 输入。
- **必须证明修复前失败、修复后通过**：先写失败测试，或临时撤回最小修复验证后立即恢复。保留 `logs/<任务>-red.log` / `logs/<任务>-green.log`，交付记录这组证据；单次 green 不等于已证明回归保护。
- 优先最低稳定层；只有根因在真实 composition、生命周期或跨层数据流时才增加 widget / integration。修复与聚焦回归用例原则上同一提交，不混入无关覆盖率补测。
- 不为框架行为、私有细节、一次性环境故障、不可稳定复现的 timing flake、无契约要求的非法输入或已覆盖路径加测试。安全/兼容性要求的 malformed 输入属于产品边界，必须验证；timing 问题先找可观察完成信号。
- 名称用中文描述触发条件与结果，不写临时 Issue、审查或阶段编号。“回归”说明来源，不是永久保留标签；同层或更低边界已有更小、更强用例时合并或删除原事故用例，并指出继续承担契约的 owner。
- 删除前回答具体什么行为退化会令该用例独立失败，以及哪个现存测试继续保护。无产品行为的构造器、类型、框架转发或恒真断言可删；行覆盖或操作相似不足以证明重复，须比较契约与失败机制。
- 不要求清理目录行覆盖率绝对不降，但每处下降归为其他测试已覆盖、非业务代码或意外丢失行为覆盖；最后一种必须恢复。行覆盖率是诊断证据，不是保留低价值用例的理由。

## 基础设施与组织

- [helpers/test_harness.dart](helpers/test_harness.dart) 的 `pumpTestApp()` 统一建立内存 DB、视口、ProviderScope 与 tearDown 清理，返回 AppDatabase。child / router 互斥且至少传一个，默认视口 1440×1200；extraOverrides 可追加覆盖。
- harness 通过 [test_database.dart](test_database.dart) 的 createTestDatabase(preferences) 建库，注入 appDatabaseProvider、sharedPreferencesProvider、customHeadersMapProvider；需直接验证 SQL 时捕获返回的 DB。
- 普通有效数据用 [TestFixtures](helpers/fixtures.dart) 的 typed factory（model、promptMessage、presetPrompt、fixedSequence 等），需 JSON 时调用模型 toJson；seedPreferences 批量注入 preferences。malformed、旧/未来格式、迁移和协议解码边界可手写原始 Map/JSON，但名称或注释须说明边界。
- widget 种子数据走 Repository API（seedFavorite / seedCollection 等）或 TestFixtures.seedPreferences，不写 raw SQL。
- [FakeChatGenerationClient](helpers/chat/fake_chat_generation_client.dart) 只 override streamCompletion，complete 继承基类；enqueueChunks / enqueueDeltas / enqueueError 排队，requestHistory / requestedTargets / lastRequest 检查调用。
- 大测试按现有 chat / sync / favorites / settings / history 模式拆分：`*_test.dart` import `*_cases.dart` 并调用 register*，helpers 单放。仅 `*_test.dart` 自动发现，cases 文件不能独立替代入口。
- 结构相同的 round-trip、错误类型、比较器用例出现 4 次以上时参数化；共享准备放 setUp / helper。widget 线性操作超过 30 行是审查信号，准备掩盖断言或混有多个场景时才拆；一个连贯用户场景不按行数机械拆分。

## Widget 与异步

- Setup 默认 `pump()`，不默认 pumpAndSettle；同步 sqlite3 / preferences getter 通常一帧足够。
- 异步等待 Provider 状态、受控 stream、Completer、Repository ACK、IO Future 或有限动画等真实完成信号。仅 test body 确实等待已知有限动画时使用 pumpAndSettle，不作为通用“稳定一下”。
- 禁止 `Future.delayed(Duration.zero)`、任意固定延迟、无条件 settle 充当 flush，也不依赖 chunkDelay + pump(delay+2ms) 的微秒 timing；资源释放例外须窄化、解释并进入精确 allowlist。
- 优先可见文本、Semantics、真实交互和逻辑 finder；不使用未声明为稳定契约的内部 Key，不用具体 widget 类型的 findsNothing 替代行为断言。公开稳定 Key 确为导航/集成契约时注明原因。
- 不断言 getTopLeft / getRect 等像素位置、maxLines / expands 等实现属性，不依赖 ID 字母序恰好等于时间序。测试必须走到 expect，不用条件 early-return 掩盖未验证分支。

## 数据与协议

- ON DELETE SET NULL / 外键级联归 schema 测试，不归 controller；迁移规则见 [持久化指南](../lib/core/persistence/AGENTS.md)。
- 当前 schema 契约集中验证；每个已发布步骤保留合法旧 fixture、数据保留和语义测试，新增版本验证最低支持版本到当前版本的完整迁移链，不能滚动删除历史步骤。
- 最低 schema 版本保证用 >=；验证迁移失败回滚、版本不变等精确契约时断言原值，不能用 >= 放过错误升级。
- 敏感字段脱敏测试覆盖所有已知敏感键名；安全和协议输入边界不可因去重而丢失。

## 测试性能任务才适用

- 先用同一命令测三轮取中位数，不能以单次最好/最差、reporter 时间或“感觉慢”下结论。可追加 `--file-reporter json:logs/<任务>.json`，按 testStart / testDone 定位文件与用例。
- 区分编译/load 固定成本与用例成本；优先调查重复 pumpTestApp、路由/Dialog 动画、重建 Provider 树与跨层流程重演，不盲删便宜的纯 Dart 用例。
- 固定文件集做单变量前后对比，再跑三轮全量。只有目标文件变快而全量中位数未改善时报告局部收益。
- 有限动画通过命名 settle helper 等待，默认 Flutter 的 100 ms 步进；仅测试确实断言中间帧时用更小步进。
- 报告节点数、墙钟与 reporter 中位数、原始行覆盖率和关键 owner 覆盖率；解释丢失分支并证明核心 owner 仍受保护，不只给出提速百分比。
