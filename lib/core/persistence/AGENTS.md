# 持久化与迁移

适用于 SQLite 基础设施，以及依赖它的 feature 数据层和迁移测试。先读根与 [lib/AGENTS.md](../../AGENTS.md)；测试同时遵守 [test/AGENTS.md](../../../test/AGENTS.md)。

## Schema 生命周期

- [AppDatabase](app_database.dart) 的 `.open()` 用于生产目录，`.inMemory()` 用于测试，`.forPath()` 用于跨 Isolate；构造执行 PRAGMA 配置及 schema 初始化。
- 版本以 `PRAGMA user_version` 和 `AppDatabase.currentSchemaVersion` 为准，不在文档复制当前版本号。全新库创建完整当前 schema；当前版本正常打开；支持的旧版本按顺序逐级迁移，不能跳步或只修改 user_version。
- 未来版本、低于明确最低支持版本或 malformed schema 显式拒绝（`AppDatabaseSchemaVersionException`），不能静默重建或 fallback。
- **已发布迁移不滚动退役**：迁移实现、合法旧版本 fixture、数据保留测试随迁移链长期保留；新增版本只追加下一步。普通 schema PR 不提高最低支持版本；放弃旧版须经用户明确授权，以独立兼容性 PR 说明受影响数据、迁移/导出路径和回滚方案。
- 当前 schema 契约集中验证一次，历史步骤验证各自的数据保留与迁移语义。新增版本还需从最低支持版本完整顺序迁移到当前版本，证明链条未断。
- 最低版本保证使用 `>=` 断言，避免新增版本无故破坏无关测试；迁移失败回滚等要求“版本未改变”的契约应精确断言原版本，不能用 `>=` 掩盖意外升级。

## Repository 与兼容边界

- 全量加载/全量写入的实体复用 `SqliteEntityRepository<T>`，以 tableName、selectColumns、insertColumns、rowToEntity、entityToValues 声明映射；`HasIdAndUpdatedAt` 配合 `SettingsEntityController<T>`。
- 高频流式聊天写入走 `BackgroundChatConversationRepository` 的后台 Isolate 和 80 ms 防抖合并，避免阻塞 UI。
- SharedPreferences JSON 使用 `VersionedJsonStorage`。历史 JSON / Settings 格式别名有明确支持生命周期，当前格式唯一 canonical，退出支持的旧格式显式失败。
- 新增临时兼容层同时说明原因、所在边界、删除条件和保护测试；一次性 canonicalization 不变成永久 fallback。已发布 schema 迁移不是临时 shim。
- 对外品牌与持久化身份分开；Windows 数据目录、数据库/应用标识约束见根 AGENTS.md，不能借迁移或品牌调整改变旧数据位置。
