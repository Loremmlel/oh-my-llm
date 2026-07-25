# Phase 16 - 可分发 Release 能力

## Phase Name

Windows/Android 可分发 Release 签名、版本、provenance 与设备 smoke。

## Why this Phase exists

本 Phase 聚合 TD-33 与 TD-37。正式签名与 provenance 若没有真实 build/launch smoke 仍无法证明可分发；设备 E2E 若继续运行 debug/自签名且不关联版本来源，也不能覆盖 release 契约。两项都由“计划公开分发”触发，必须在 Phase 1 CI 和 Phase 2 版本事实源完成后一起建设。

## Included Technical Debts

- **TD-33（P2）**：缺少 Windows/Android 设备层 E2E 与真实插件、权限、runner、manifest、release 启动验证。
- **TD-37（P1）**：Android 自签名密码硬编码、release 无 key 回退 debug signing、versionCode 不单调、构建与测试/provenance 脱节。

## Dependencies

- 触发条件：项目计划正式分发。个人侧载阶段允许记录现状，不得假称本 Phase 已完成。
- 前置 Phase：Phase 1 CI/coverage，Phase 2 版本事实源，Phase 8 已认证 sync protocol，Phase 12 路由恢复，Phase 14 a11y，Phase 15 稳定测试等待。
- 后续依赖：无；这是发布能力终端 Phase，可在产品尚未分发时延后。
- 顺序理由：只有核心安全、可靠性和 UI contract 稳定后，release smoke 才不会固化临时行为。

## Expected Benefits

- Local self-use 与 distributable release 有明确不同的信任和签名语义。
- 正式构建缺少 secret/key 时明确失败，不再静默使用 debug signing。
- Android versionCode 单调，tag/version/commit/产物 hash 可追溯。
- Release build 必须依赖通过的质量 job。
- Windows/Android 实机 smoke 覆盖启动、配置、插件、权限、local/fake chat 与已认证 sync/media 基本路径。

## File Scope

- CI/release workflows：`.github/workflows/**` 与 Phase 1 质量 job 依赖。
- Android：`android/app/build.gradle.kts`、Android manifests、必要 signing config 模板；敏感值不进入仓库。
- Windows：`windows/runner/**`、`windows/CMakeLists.txt`，仅限 release 启动/provenance 所需。
- 构建与版本脚本：`build-windows-release.ps1`、`build-android-apk.ps1`、`scripts/bump-version.ps1`、`pubspec.yaml`。
- Device tests：`integration_test/**`（新增）、必要的 `test_driver/**` 或平台 runner 配置、发布 smoke 文档。
- Artifact metadata/provenance config。

## Refactor Scope

- 区分本地自用构建与可分发 release，定义各自签名、secret、失败和产物命名语义。
- 将正式 signing secret 通过环境/CI secret 注入，并让 distributable release 在缺 key 时失败。
- 建立单调 versionCode 与 tag/release/commit 的可追溯关系，避免日常 commit 隐式改写成为正式发布来源。
- 让 release build 依赖 Phase 1 质量门禁成功，并记录 artifact provenance/hash/version。
- 为 Windows/Android 各建立 2～4 个关键设备/release smoke，覆盖报告点名的平台插件、权限与启动契约。

## Out Of Scope

- 不在项目尚未计划分发时强迫购买设备/CI runner 或更改个人侧载流程。
- 不新增应用商店业务、自动更新系统或云后端。
- 不扩大 E2E 到复制全部 unit/widget tests。
- 不把 secret、keystore 密码或私钥提交到仓库。

## Risks

- 签名迁移错误会使已安装应用无法升级或导致发布身份变化。
- 设备 runner 的平台差异与权限弹窗可能导致 flaky smoke，必须使用明确等待和最小关键路径。
- versionCode 与语义版本映射若与 Phase 2 当前 hook 冲突，会产生双重版本源。
- Release artifact 未绑定测试 job 或 commit 时 provenance 仍不可信。

## Verification Requirements

- `flutter analyze` 必须通过。
- 全量测试按重定向规范执行并得到 `EXIT=0`。
- `flutter build windows --release` 与 `flutter build apk --release` 在具备正式 secret 的 release 环境成功；缺 secret 的 distributable Android build 必须失败。
- Windows/Android device smoke 在实际 release binary 上通过并保存日志。
- 验证 versionCode 单调、artifact 名称/版本/hash/commit/tag provenance 一致。
- 验证 build job 不能绕过 format/analyze/test 门禁。

## Completion Criteria

- 正式与本地自用 release 的签名边界清晰，无 debug signing 静默降级。
- 版本和产物可追溯，release 构建依赖质量门禁。
- 两平台关键插件/权限/启动/sync-media 路径由设备级 smoke 覆盖。
- 若分发触发条件尚未成立，本 Phase 保持未实施，不能以文档替代完成状态。

## Implement Context For Next Agent

本 Phase 只有在计划正式分发时实施。报告指出 Android 脚本硬编码自签名密码，Gradle 无 release key 会回退 debug signing，build number 为 `+0`，构建不依赖测试；项目也没有 integration_test 设备层，file picker、video_player、SystemChrome、权限、runner/manifest/release 启动未验证。Phase 1/2 应已建立 CI 与当前版本事实，Phase 8 应完成 sync 安全。你的计划需区分 local-self-use 与 distributable release，保护 secret，并用最少关键 smoke 验证实际 release binary；不要扩展为商店/云/自动更新项目。
