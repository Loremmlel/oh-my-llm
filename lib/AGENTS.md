# 应用架构

适用于 `lib/`。先遵守根 [AGENTS.md](../AGENTS.md)，再按任务读取其中列出的领域规则；测试还需读取 [test/AGENTS.md](../test/AGENTS.md)。

## 分层与依赖

```text
lib/
  app/                      # 入口、路由、shell、theme、跨 feature composition
  bootstrap.dart            # 启动初始化
  core/                     # persistence / http / logging / utils / widgets
  features/<feature>/
    domain/                 # 纯数据模型，零框架依赖
    data/                   # Repository、网络客户端、解析
    application/            # Riverpod Notifier、业务函数、上层所需 ports
    presentation/           # Screen / Widget
```

- 单向依赖：`presentation -> application -> domain`，`data -> domain`（可依赖 `core/`）。presentation 通过 `ref.watch` / `ref.read` 使用 application Provider，不直接 import data 或 `core/persistence/`。
- application 拥有 `application/ports/`（或中性 domain contract），data 提供实现，由 `app/composition/` / `bootstrap.dart` 绑定。feature 不导入协议实现或 composition。
- 跨 feature 通过少量 application facade/command 与 app composition 组合；不直接嵌入其他 feature 的内部 presentation。
- domain 不导入 Flutter、Riverpod、sqlite3。`dart run tool/check_import_boundaries.dart` 是 CI 门禁；allowlist 例外必须窄、可解释且能检测失效条目。

## 启动与持久化分工

修改 [bootstrap.dart](bootstrap.dart) 时保留初始化顺序：binding → Windows window runtime（仅 Windows）→ SharedPreferences → AppDatabase → 依赖数据库目录的 AppNetworkLogger → `onAppLaunch()` → `runApp(ProviderScope(...))`。生产 Windows runtime 调用 `windowManager.ensureInitialized()`。

测试注入参数及约束以该函数 doc comment 为入口：`sharedPreferences`、`database`、`networkLogger`、`windowsWindowInitializer`、`hostPlatform`。生产传 null 获取真实实例；测试用显式 hostPlatform 和 no-op window initializer，不改全局平台状态。database / logger 成对注入，不应让测试 logger 按数据库路径自动落盘。日志为 `{db_parent}/network.log`，10 MB 滚动；Provider overrides 统一注入 preferences、database、logger、custom headers map。

| 数据 | 存储 |
| --- | --- |
| 聊天、消息树选择、收藏/收藏夹、Prompt 模板/固定顺序/记忆、检查点 | SQLite `chat_history.sqlite` |
| 服务商/模型配置、聊天默认值、最近选择记忆 | SharedPreferences JSON，由 `VersionedJsonStorage` 做带版本编解码 |

迁移、格式兼容和 repository 约束见 [持久化规则](core/persistence/AGENTS.md)；修改 feature 中的数据层也需遵守。

## Riverpod 与目录组织

- Provider 命名 `xxxProvider`，控制器为 `XxxController extends Notifier<XxxState>`，类名不带 Provider。派生数据用 Provider 与 `ref.watch(xxxProvider.select((s) => s.field))`，限制重建范围。
- 大控制器可用通过 import 引入的 mixin 拆分；不使用 part。`SettingsEntityController<T>` 是模板方法基类，子类提供 repository，泛型约束可用 `HasIdAndUpdatedAt`。
- Settings application 与 domain models 按 `preferences/`、`providers/`、`prompts/`、`transfer/` 等领域分组，不把所有 controller / model 堆在一层。
- Chat generation 与 workspace ownership 见 [Chat 规则](features/chat/AGENTS.md)；不要把高频流式状态扩大到整个工作区。

## 导航与界面

修改 UI 先读 [DESIGN.md](../DESIGN.md)。收藏详情和媒体路由使用 GoRouter 可序列化 ID/query 参数；不以 `state.extra` 传 domain entity，不在 feature 内新增 MaterialPageRoute 平行栈。
