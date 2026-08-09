# Phase 16 - 个人自用 Release 可靠性 Implement Plan（精简版）

> 本 Plan 是《Phase 16 - 可分发 Release 能力》在“仅个人自用、Windows + Android 本地构建与侧载”前提下的**最小执行版**。它只保护签名身份、覆盖安装、版本辨识和真实 Release 启动这几项个人数据安全契约，**不代表原 Phase 16 的“可公开分发”验收已完成**。
>
> 本 Plan 以 Phase 16 文档和当前仓库为依据，不重新解释完整 Architecture Review Report。Phase 1 已建立 CI 质量门禁，Phase 2 已确立 `pubspec.yaml` + `post-commit` 的本地版本事实源；本 Plan 不修改这两项既有结论。

---

## 一、目标与完成语义

实施完成后，个人自用 Release 应满足：

1. Android Release 只使用 `android/app/self-use-release.jks` 对应的自用签名，缺失或配置不完整时明确失败，不得回退到 debug signing。
2. 现有 keystore 和 `key.properties` 只验证、只复用，任何自动化都不得覆盖、删除或“修复”现有签名身份。
3. 全新环境首次构建时可生成新的自用 keystore；新密码随机生成并仅保存在被 ignore 的本地配置中，不写入仓库或日志。
4. Android `versionCode` 由 `pubspec.yaml` 的语义版本确定性派生，在现有 major/minor/patch 升级规则下严格单调，不增加第二个需手工维护的版本源。
5. Windows ZIP 和 Android APK 旁边生成一份本地构建凭据，至少记录版本、commit、工作树是否 dirty 和产物 SHA-256；该凭据只用于个人回溯，不宣称是可验证供应链 provenance。
6. 两平台各有一份简短的人工 Release smoke 清单，并在真实 Release binary 上完整执行一次。

完成上述工作后，只能将状态记为“**Phase 16 个人自用子集完成；可分发 Release 仍未触发**”。

---

## 二、当前事实与风险基线

### 2.1 已确认现状

- `build-android-apk.ps1` 在首次构建时生成 `android/app/self-use-release.jks` 和 `android/key.properties`，但密码目前硬编码在脚本中。
- `android/app/build.gradle.kts` 在缺少 release key 时选择 debug signing；因此“Release 构建成功”不能证明它与已安装 APK 具有同一签名身份。
- `pubspec.yaml` 当前为 `3.29.72+0`，Gradle 直接使用 Flutter 的 `versionCode`；`+0` 不具备可用的 Android 升级顺序语义。
- `build-windows-release.ps1` 和 `build-android-apk.ps1` 会复制产物，但不保存 commit/dirty/hash 本地凭据。
- CI 已执行 format/analyze/test，但不构建 Windows/Android Release；这对个人自用阶段可接受。

### 2.2 本机签名文件保护约束

计划编写时，以下两个文件都已存在且被 `android/.gitignore` 覆盖：

- `android/app/self-use-release.jks`
- `android/key.properties`

它们是用户的本地私密数据，不是可再生成的构建缓存。实施前必须只记录 keystore 的 SHA-256 基线，不输出 `key.properties` 内容；每次构建后再比对 keystore hash，不一致立即停止。

```powershell
Get-FileHash -Algorithm SHA256 -LiteralPath .\android\app\self-use-release.jks
git check-ignore -v -- android/app/self-use-release.jks android/key.properties
```

---

## 三、关键实现决策

### 3.1 唯一自用构建入口

- Android 自用 Release 的标准入口为 `.\build-android-apk.ps1`。
- `flutter build apk --release` 仍可作为底层命令，但缺少 release signing 或有效 `--build-number` 时必须失败，不得生成 debug-signed 或 `versionCode=0` 的伪 Release。
- Android debug 构建与 `flutter run` 不依赖自用 keystore，新 clone 在没有签名文件时仍应可正常调试。
- Windows 仍使用 `.\build-windows-release.ps1`，不在本 Plan 引入 Windows 代码签名。

### 3.2 签名状态机

`build-android-apk.ps1` 必须先按下表判定状态，再调用 Flutter：

| keystore | `key.properties` | 行为 |
|---|---|---|
| 不存在 | 不存在 | 视为全新环境；生成随机密码和新 key pair，写入两个本地 ignore 文件 |
| 存在 | 存在 | 解析并用 `keytool -list` 验证 keystore/密码/alias，验证成功后原样复用 |
| 存在 | 不存在 | 立即失败，要求从加密备份恢复配置；不生成新配置 |
| 不存在 | 存在 | 立即失败，要求从加密备份恢复 keystore；不生成新 key |

其他约束：

- 新密码使用 .NET 加密随机数生成器生成至少 128 bit 随机值，使用不含 shell 特殊字符的 hex 编码。为兼容 JDK 默认 PKCS12，store/key 可使用同一随机密码。
- 生成过程使用临时文件，只在 `keytool` 成功后移入最终路径；脚本不得清理或覆盖任何已存在的最终文件。
- 旧的硬编码密码仅从“新 key 生成逻辑”中移除；已存在的旧 key 通过现有 `key.properties` 继续使用，不轮换签名身份。
- 密码不写入 console、build receipt、test log 或 Git diff。

### 3.3 Android `versionCode` 派生

使用不需额外状态的固定公式：

```text
versionCode = major * 1,000,000 + minor * 1,000 + patch
```

例如 `3.29.72+0 -> versionName 3.29.72, versionCode 3029072`。

边界契约：

- `major` 取 `0..2099`，`minor` 和 `patch` 各取 `0..999`；派生结果必须在 Android 允许的正整数范围内。
- 任意字段超界或版本格式不合法时构建失败，不截断、取模或回退为 `1`。
- `.githooks/post-commit`、`scripts/bump-version.ps1` 和 `pubspec.yaml` 的 `+0` 保持不变。`+0` 是源码仓库中的占位 build number；真实 Android Release 由构建脚本显式传入 `--build-name` 和派生后的 `--build-number`。
- 有效的语义版本通过现有 major/minor/patch 升级时，上述映射必须严格递增。该契约用纯 PowerShell 用例验证。

### 3.4 Gradle 失败语义

`android/app/build.gradle.kts` 的 release build type 不再引用 debug signing config。增加仅挂到 release lifecycle 的 validation task，在打包前验证：

1. `key.properties` 的四个必需字段非空；
2. `storeFile` 存在；
3. Flutter 传入的 `versionCode > 0`；
4. release build type 使用 release signing config。

验证不得在 Gradle configuration 阶段无条件抛错，否则会误伤没有自用 key 的 debug 开发。需用无 key 的临时 worktree 实测“debug 成功、release 失败”。

### 3.5 本地构建凭据

两个构建脚本在成功复制产物后，在同目录写入 `<artifact>.build-info.json`：

```json
{
  "schemaVersion": 1,
  "platform": "android",
  "artifactFile": "oh_my_llm-android-3.29.72+3029072.apk",
  "versionName": "3.29.72",
  "versionCode": 3029072,
  "gitCommit": "<40-char HEAD>",
  "gitDirty": false,
  "sha256": "<artifact SHA-256>",
  "builtAtUtc": "<ISO-8601 UTC>"
}
```

- Windows 的 `versionCode` 为 `null`，其他字段一致。
- Android 产物命名使用实际安装版本：`oh_my_llm-android-<versionName>+<versionCode>.apk`。Windows 继续使用现有 pubspec 完整版本命名。
- dirty 工作树不阻塞个人构建，但 receipt 必须如实记录 `gitDirty: true`。
- receipt 与 `artifacts/` 一样保持 ignore，不加入 Git；不加密钥、密码、机器用户名或绝对路径。

---

## 四、文件范围

### 4.1 新增

- `scripts/release_helpers.ps1`
  - 可测试的版本解析/`versionCode` 派生、签名文件状态判定、Git 状态及 build receipt 写入函数。
- `scripts/verify-self-use-release.ps1`
  - 无 Flutter 构建的快速契约验证：版本映射、越界失败、签名文件四种状态和 receipt 脱敏字段。
- `docs/release/self-use-release.md`
  - 自用签名加密备份/恢复指南、标准构建入口、人工 smoke 清单和本地执行记录模板。

### 4.2 修改

- `build-android-apk.ps1`
  - 移除新 key 的硬编码密码；实现签名状态机、确定性 `versionCode`、新产物命名和 receipt。
- `android/app/build.gradle.kts`
  - 删除 debug signing fallback，增加只影响 release 任务的签名/`versionCode` 验证。
- `build-windows-release.ps1`
  - 复用 release helper，为 ZIP 生成本地 build receipt；不修改打包内容和签名语义。
- `README.md`、`AGENTS.md`、`CLAUDE.md`
  - 把 Android 自用构建入口、实际产物命名、签名恢复警告和 `versionCode` 派生规则同步为单一事实。

### 4.3 明确不修改

- `pubspec.yaml`、`.githooks/post-commit`、`scripts/bump-version.ps1`、`scripts/verify-version-hook.sh`。
- `.github/workflows/**`：不增加 Release build/upload/tag job，不要求 CI 保管 signing secret。
- `integration_test/**`、`test_driver/**`、Android manifest、Windows runner、业务代码和应用数据 schema。
- `android/app/self-use-release.jks`、`android/key.properties`：两者始终保持 untracked/ignored，不作为实施 diff。

---

## 五、实施任务与提交节点

### Task 1 - 固化 Android 自用签名身份

**目标：** 保证现有 APK 的升级签名不变，任何签名缺失不再被 debug key 掩盖。

- [ ] **Step 1：记录不含 secret 的基线。**

  记录 `git status --short`、keystore SHA-256；用当前脚本生成一个基线 APK，用 Android SDK `apksigner verify --print-certs` 记录 signer certificate SHA-256。记录只放在 ignored `artifacts/release-contract/`，不读取或复制 `key.properties` 内容到终端。

- [ ] **Step 2：先写签名状态契约验证。**

  在临时目录构造“都缺失 / 都存在 / 只有 key / 只有 properties”四种状态。后两种必须返回明确的恢复错误，不得进入生成路径。首次运行时新密码不得等于旧硬编码值。

- [ ] **Step 3：实现 helper 与 Android build 状态机。**

  抽出可测函数；已存在 pair 执行 `keytool -list` 验证并原样复用，只有都不存在时才生成新 pair。不为旧 key 更换密码或 alias。

- [ ] **Step 4：删除 Gradle debug fallback。**

  release build type 仅允许 release signing config，在 release lifecycle 内对配置与文件做 fail-fast 验证；确保 debug lifecycle 不触发该验证。

- [ ] **Step 5：验证现有 signer 没有变化。**

  重新构建 APK，比对构建前后 keystore SHA-256 和 APK signer certificate SHA-256。两者都必须与 Step 1 一致。

- [ ] **Step 6：提交。**

  ```text
  fix(release): 固化 Android 自用签名身份
  ```

  显式 stage `build-android-apk.ps1`、`android/app/build.gradle.kts`、helper 和 verifier；签名文件不得出现在 staged list。

### Task 2 - 派生可升级版本并生成本地构建凭据

**目标：** 不改造 Phase 2 版本 hook，仍使安装包具有确定、单调且可回溯的身份。

- [ ] **Step 1：先写版本映射红灯用例。**

  至少覆盖：

  - `3.29.72+0 -> 3029072`；
  - patch：`3.29.72 -> 3.29.73` 递增；
  - minor reset：`3.29.999 -> 3.30.0` 递增；
  - major reset：`3.999.999 -> 4.0.0` 递增；
  - 非法格式、`minor/patch > 999`、`major > 2099`、结果为 `0` 全部失败。

- [ ] **Step 2：实现映射并传入 Flutter build。**

  Android 脚本传入 `--build-name <major.minor.patch> --build-number <derived>`，并使用实际安装版本命名 APK。Gradle release validation 同时拒绝 `versionCode <= 0`。

- [ ] **Step 3：为两个平台生成 build receipt。**

  两个脚本共用 receipt helper。用临时文件写完 JSON 后再移入最终位置，防止中断后留下一份看似有效的半成品凭据。验证 JSON 不含 signing properties 及绝对路径。

- [ ] **Step 4：检查真实产物。**

  Android 用 `aapt dump badging` 或 `apkanalyzer manifest version-code` 读回 APK 内嵌 `versionName/versionCode`；Windows 检查 ZIP 可解压且 runner/Flutter DLL 完整。重算两个产物的 SHA-256，必须与 receipt 一致。

- [ ] **Step 5：提交。**

  ```text
  build: 派生自用版本并记录构建凭据
  ```

### Task 3 - 写入备份/恢复和真实 Release smoke 契约

**目标：** 让“不丢签名”和“Release 真能用”成为可执行操作，不把文档写成已完成的外部备份证明。

- [ ] **Step 1：编写签名加密备份与恢复指南。**

  文档必须说明：

  - keystore 与 `key.properties` 必须成对备份；
  - 备份应在仓库和开发机之外的加密存储中；
  - 记录原始 keystore SHA-256，恢复后先校验 hash 再构建；
  - 丢失原 key 后生成新 key 不是“恢复”，新 APK 无法覆盖安装旧 APK；
  - 仓库只能提供流程和校验工具，不能宣称用户已完成外部备份。

- [ ] **Step 2：定义五项人工 smoke。**

  在 Windows Release 目录和 Android Release APK 上分别执行：

  1. **覆盖/替换后启动**：Android 用新 APK 覆盖安装现有应用，Windows 从新 Release 目录启动；无签名、DLL 或 runner 错误。
  2. **存量数据恢复**：现有会话、设置和最近选择可读，不因覆盖安装/替换 binary 而清空。
  3. **一次流式聊天**：使用已有配置发送一条消息，确认推理与正文分离、流式结束可用且无 inline error。
  4. **文件与媒体插件**：选择一个目录/文件，打开一张图片和一个本地视频，确认权限、file picker 与 video player 正常。
  5. **Sync/安全存储基本路径**：使用已配对设备执行一次连接/同步，重启后安全存储中的配对身份仍可用。

  本地执行记录写入 ignored `artifacts/release-smoke-<UTC-date>.md`，记录 artifact 文件名/hash、设备/系统版本、每项 PASS/FAIL 和简短备注，不记录 API key、配对 secret 或聊天正文。

- [ ] **Step 3：同步仓库入口文档。**

  README 面向用户只保留简短入口和备份警告；AGENTS/CLAUDE 记录实施者所需的版本公式、禁止 debug fallback、签名文件保护和验证命令。

- [ ] **Step 4：在真实 Release binary 上执行并记录 smoke。**

  若没有可用 Android 真机或第二台已配对设备，可先完成代码子任务，但 Phase 16 个人自用子集仍标记为 `pending manual smoke`，不得把“已写清单”当作“已验证设备”。

- [ ] **Step 5：提交。**

  ```text
  docs(release): 记录自用备份与 release smoke
  ```

---

## 六、最终验证

### 6.1 快速契约与静态检查

```powershell
pwsh -NoProfile -File .\scripts\verify-self-use-release.ps1
rg -n 'signingConfigs\.getByName\("debug"\)|oh-my-llm-self-use' android/app/build.gradle.kts build-android-apk.ps1 scripts
git diff --check
flutter analyze
```

期望：verifier `EXIT=0`；`rg` 零命中；diff check 和 analyze 通过。

### 6.2 全量测试（强制重定向）

```powershell
flutter test --reporter compact 2>&1 | Out-File -Encoding utf8 fltest.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest.log
```

必须得到 `EXIT=0`。本 Plan 不新增 Dart 生产代码；若实施过程意外触及 Dart，仍必须按仓库规范执行 `dart format` 和 staged format check。

### 6.3 真实构建与产物检查

```powershell
.\build-windows-release.ps1
.\build-android-apk.ps1
```

验证：

- 两个命令成功，并为 ZIP/APK 生成 build receipt。
- receipt 中的 artifact filename、SHA-256、HEAD/dirty 与现状一致。
- APK 内嵌 `versionName` 等于 pubspec semantic version，`versionCode` 等于派生公式结果。
- APK signer certificate SHA-256 和 Task 1 基线一致。
- keystore 文件 SHA-256 在整个实施前后一致。

### 6.4 无 key 负向验证

不得移动、改名或删除当前工作区的真实签名文件。在经过绝对路径确认的临时 Git worktree 中验证：

1. 无 `key.properties`/keystore 时 debug APK 可成功构建；
2. 直接 release build 必须以明确的自用签名缺失错误失败；
3. 通过标准 `.\build-android-apk.ps1` 首次初始化后，release 可成功；
4. 临时 worktree 中生成的 key 只属于该临时环境，不复制回主工作区。

清理临时 worktree 前必须校验其 resolved absolute path 位于本次创建的临时目录内。

### 6.5 人工 smoke

Windows 和 Android 的五项 smoke 都必须 PASS，本地记录中的 artifact hash 与最终交付产物一致。任何一项失败时，只记录失败和建立独立修复任务；除非问题是本 Plan 对构建脚本/Gradle 的直接回归，否则不在 Phase 16 中扩大业务修复范围。

---

## 七、验收矩阵

| 个人自用验收项 | 证据 |
|---|---|
| 现有签名身份未变 | 实施前后 keystore hash 与 APK cert digest 相同 |
| Release 不回退 debug signing | Gradle 零 debug-signing 引用；无 key 临时 worktree 的 release 构建明确失败 |
| Debug 开发不被误伤 | 无 key 临时 worktree 的 debug 构建通过 |
| 签名不会被部分状态自动重建 | 四状态 verifier 通过，两种不一致状态均 fail-fast |
| 新环境不再使用硬编码密码 | 首次初始化 verifier 证明随机值；仓库搜索旧密码零命中 |
| `versionCode` 确定且单调 | 边界/过渡用例通过；APK 读回值等于公式结果 |
| 产物可个人回溯 | ZIP/APK receipt 中的 version/commit/dirty/hash 与实际一致 |
| Release 真实关键路径可用 | Windows/Android 五项人工 smoke 记录均 PASS |
| 签名恢复边界说清 | 备份/恢复文档存在，且未虚假宣称外部备份已完成 |
| 基础质量未回归 | verifier、`flutter analyze`、全量测试全部 `EXIT=0` |

---

## 八、严格 Out of Scope 与未来触发条件

本精简 Plan **不实施**：

- Android 正式发布/upload key、CI secret 注入、key rotation 或应用商店接入。
- Windows Authenticode 证书、MSIX/安装器、SmartScreen 声誉或自动更新。
- Git tag/GitHub Release、CI 发布 job、SLSA/attestation、可重现构建或远程 artifact 保管。
- 自动化设备 E2E、购买 Windows/Android runner，或把全部 widget/unit test 复制成 integration tests。
- 为了 smoke 顺手改造 Sync、media、chat、manifest、runner 或权限架构。

出现以下任一情况时，重新启用原《Phase 16 - 可分发 Release 能力》而不继续扩展本精简 Plan：

1. APK/Windows 包开始安装到无法随时卸载、清空数据的他人设备；
2. 计划在 GitHub Release、网盘、群聊或应用商店持续发布；
3. 需要多人/多机器维护同一发布签名；
4. 需要证明产物必然来自某个 tag 且必然通过质量 job；
5. 需要应用商店的版本、签名、审核和升级契约。
