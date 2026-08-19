## Global Constraints (copied from the implementation plan)

- 权威设计是上面的已批准规格；若实现需要改变缺失/空 section 语义、敏感确认边界、跨存储失败语义、Sync group 或版本策略，立即停止并回到规格评审。
- 当前基线为 `f7c378d9efd8c5cb52d11b0d1cb3ff7552922c21`、`pubspec.yaml` 版本 `3.55.14+0`；执行前必须重新读取，不能把它们视为长期事实。
- 默认仅本地。只有显式注册为 `SettingsTransferParticipant<T>` 的设置才可传输；不得扫描 Provider、SharedPreferences key、SQLite table、controller 继承关系或 Dart 类型来自动注册。
- 首批仅注册九项：服务商、预设、记忆提示词、模板提示词、固定顺序提示词、自定义 Header、输出处理、字号、自动重试。`ChatDefaults`、设置当前 Tab、媒体根目录、媒体密度和派生模型目录继续仅本地。
- 不建立“所有设置项”的统一基类。只实现 participant 层的 `ReplacingValueParticipant<T>` 与 `MergingCollectionParticipant<T>`；标量 controller 基类继续保持 out of scope。
- Settings transfer v9 是唯一支持格式；v8、更旧版本和未来版本均显式拒绝。Sync v4 是唯一支持协议；v3、更旧版本和未来版本均显式拒绝。
- 不引入 participant `schemaRevision`。生产 key 集合与 canonical fixtures 只在契约测试中绑定顶层 `formatVersion`；测试 catalog 不受生产快照约束。
- `readLocal()` 必须同步返回已经加载的状态。不得在单个 participant 内启动异步首载；若现有数据不满足，按规格停止而不是偷偷把返回类型改成 `Future`。
- 合并型集合只有非空时形成 section；缺失 section 表示不参与且不改本地。替换型 section 只要选中就形成，空 Header/空输出规则是明确的清空命令。
- 全局剪贴板导入不依赖当前 Settings Tab；当前 Tab 只决定导出 group。单条预设分享必须生成标准 v9 document，不能保留专用 JSON 旁路。
- API Key、Header value、完整 Clipboard 文本和完整 transfer document 不得写日志、摘要或错误文案。敏感导出在返回可写剪贴板文本前确认；敏感导入在 application 执行边界再次确认。
- 不宣称 SQLite 与 SharedPreferences 跨 participant 原子。执行按 catalog 顺序串行；结果必须区分成功、stale preview、失败和部分失败，且重试保持幂等。
- 单 participant 必须等待真实持久化 Future 成功后才发布 Riverpod state 或报告成功。服务商导入是本计划必须修复和测试的已知例外。
- 不修改 SQLite schema、`PRAGMA user_version`、既有本地 SharedPreferences key 或本地 JSON schema。
- Settings domain/application 不导入 Flutter Clipboard；Sync presentation/data 不导入九个具体 Settings controller；跨 feature 只经 Sync-owned port 和 app composition 绑定。
- 不增加宽泛 import-boundary allowlist；任何需要新 allowlist 才能通过的设计应停止实施。
- 所有新增注释与测试标题使用简体中文；不得新增 `part` / `part of`。
- 跨 feature、跨 `core/`、跨 `app/` 使用 `package:oh_my_llm/` 根路径；同一 feature 内部使用相对 import。
- 测试只等待 Provider 状态、受控 stream、`Completer`、存储 ACK 或有限动画；不得新增任意固定延迟、`Future.delayed(Duration.zero)` 或无条件 `pumpAndSettle()`。
- 所有测试、分析与诊断输出写入 ignored 的 `logs/`；全量测试固定写 `logs/fltest.log`。
- 每个提交前格式化本任务所有改动 Dart 文件，暂存后再次运行 `dart format --output=none --set-exit-if-changed`。
- 每个任务只暂存该任务列出的文件；发现用户的无关改动时保留并绕开，重叠改动无法安全分离时停止请求用户处理。
- 每项 red 证据必须因预期缺失类型、缺失行为或新断言失败；若失败来自环境、旧用例或不相关编译错误，先诊断，不能把它当作有效 red。
- 本计划不授权 push、PR、发布、Windows/Android 构建或设备手测；最终只报告实际运行的自动化验证。

### Review dispositions carried into implementation

| 审查点 | 实施约束 |
| --- | --- |
| 空服务商示例与 presence 规则冲突 | v9 fixture 不生成空合并 section；替换型空 section 另测清空。 |
| runtime catalog 与 schema snapshot 职责混淆 | constructor 只做结构校验；生产 snapshot 只在 contract test 比较；fake catalog 使用自己的 fixture。 |
| 双重版本号无独立价值 | 不实现 `schemaRevision`；任一 canonical section 变化提升顶层 `formatVersion`。 |
| facade 同步 prepare 缺少前提 | participant `readLocal()` 明确同步；新异步首载需求触发停止条件。 |
| Change 的“受控操作”含糊 | change 保存输入、最终写入值、摘要与类型化 participant 引用，不保存闭包、不序列化。 |
| 通用 decode 混入 Sync 校验 | document/participant decode 保持通用；requested group subset 只在 Sync facade 的 prepare 路径执行。 |
