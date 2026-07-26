# Phase 6 - Sync Media 状态与资源生命周期 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 固化 sync/media state 的不可变快照和值相等语义，并将同步服务、发现和媒体页面状态的保活与释放责任落实为可验证的 Riverpod 生命周期契约。

**Architecture:** 不新增 transport、backend 或协议抽象。各 Provider 的生命周期直接在其声明与中文 doc comment 中表达：运行中的同步服务是由用户显式启动、可跨页面观察者存活的会话；发现、媒体浏览和随机播放属于页面会话；持久化偏好与一次性网卡枚举属于应用配置/缓存而非可释放资源。公开集合在 state 构造边界复制为不可变快照，state 仅比较可观察字段的值而不依赖模型对象的 identity。

**Tech Stack:** Flutter、Dart 3、Riverpod 3.3.x（`NotifierProvider(isAutoDispose: true)`、`ref.keepAlive()`、`ref.onDispose()`、`ProviderContainer.pump()`）、Equatable、`package:http`。

---

> 本 Plan 仅基于 `Phase 6 - Sync Media 状态与资源生命周期.md` 细化，未重新读取或重新解释 Architecture Review Report。Phase 文档的 TD、范围、依赖与验收条件完整且不矛盾，**无需回查 Review Report**。严格遵守 Phase 1 前置条件；不提前实施 Phase 7 的 transport/media backend 注入，也不实施 Phase 8 的配对或协议状态。

## 一、现状核对结论（2026-07-26）

| 项目 | 当前实现 | 本计划的最小动作 |
|---|---|---|
| `SyncClientState.selectedCategories` | `final Set` 直接接收调用方集合；`toggleCategory` 虽复制，但构造和 `copyWith` 仍会暴露可变输入；state 没有值相等 | 构造边界 `Set.unmodifiable`，并按 category 值比较；不增加 discovery transport seam。 |
| `MediaBrowserState.items/pathHistory` | 两个 `List` 直接暴露；`copyWith` 继续传递引用；state 没有值相等 | 构造边界 `List.unmodifiable`，按 `FileItem` 可观察字段和值路径比较。 |
| `ShufflePlaybackActive.playlist` | 也是公开的可变 `List`，Idle/Loading/Active 没有统一值相等 | 一并冻结 playlist，三个状态改为可值比较，避免留下同类 state 漏洞。 |
| `SyncServerController` | provider 默认不自动释放；`start()` 已持有 `KeepAliveLink`，但在非 auto-dispose Provider 上没有实际保活意义；重启会新增 link 而只关闭最后一个 | 改为 auto-dispose；只创建一个运行期 link，显式 `stop`、app pause 与 container dispose 释放 server/UDP/handler 生命周期。 |
| `SyncClientController` | 有 discovery subscription 的 `onDispose`，但 provider 默认全局存活 | 改为页面级 auto-dispose；取消、重新发现和 dispose 都终止本轮发现，过期 callback 不可重建 state。 |
| `MediaBrowserController` / `ShufflePlaybackController` | 两者默认全局存活；`TabBarView` 离开媒体 Tab 后仍可保留 child watcher | 改为 auto-dispose；`SyncScreen` 在离开媒体 Tab 时显式 reset 两个页面会话，回到 Tab 时重新由已发现 server 建立浏览状态。 |
| `VideoPlayerPage` | 页面自己的 `VideoPlayerGestureController.dispose()` 已释放 timer 与 `VideoPlayerController`；app pause 时暂停播放 | 不改变播放 backend；补充资源所有权说明及“pop 后 controller 被 dispose”的回归测试。 |
| prefix/root/interface providers | prefix 与根目录是 SharedPreferences 配置；网卡列表是完成后无持有句柄的 Future cache，网卡索引是 UI 选择 | 保持非 auto-dispose，补清晰 doc comment；不把所有 Provider 机械改为 autoDispose。 |

工作树另有未跟踪的 `docs/第一轮审查/Phase 5 - Implement Plan.md`，属于先前工作；实施本计划时不得 stage、修改或纳入 Phase 6 提交。

## 二、目标资源与状态契约

### 2.1 生命周期决策表

| Provider / 资源 | Owner 与级别 | 保活策略 | 离开页面 / 重建 / 失败 / 应用关闭 |
|---|---|---|---|
| `syncServerControllerProvider` 的 HTTP server、UDP broadcaster、请求 handlers（以及仅被 handlers 引用的 scanner/cache/generator） | 用户点击“启动广播”创建的 **同步服务会话** | `isAutoDispose: true`；仅在 `start()` 成功后以一个 `KeepAliveLink` 保活 | 离开 Sync 页面时，运行中服务继续存在；显式 `stop()`、app `paused` 或 `ProviderContainer` dispose 时停止 UDP 与 HTTP、清空运行字段并关闭 link。失败不建立 link，保留 error state 直到观察者离开或再次 start。 |
| `syncClientControllerProvider` 的 UDP discovery subscription 和发现/同步 UI state | **Sync 页面会话** | `isAutoDispose: true`，不调用 keepAlive | 观察者消失、取消、切换 client/server 模式或 app pause 均取消 discovery；再次进入页面从 idle 重建。过期 discovery 或 HTTP completion 不得写回已取消/已 dispose 的 state。 |
| `mediaBrowserControllerProvider` 的目录请求与导航快照 | Android **媒体 Tab 页面会话** | `isAutoDispose: true`，不调用 keepAlive | 离开媒体 Tab 时 `reset()` 清除 server、items、history 与错误；再次进入时由 SyncScreen 用当前发现 server 加载根目录。整个 Sync 页面被移除后由 auto-dispose 释放；过期 HTTP completion 不得恢复已 reset 的浏览 state。 |
| `shufflePlaybackControllerProvider` 的随机播放列表与索引 | Android **媒体 Tab 页面会话** | `isAutoDispose: true`，不调用 keepAlive | 离开媒体 Tab、目录改变、播放末尾退出或手动 reset 时回到 Idle；进入媒体 Tab 后只在用户再次点击随机播放时重建列表。 |
| `VideoPlayerPage` 的 `VideoPlayerController`、hide/hint timers | **视频路由页面** | Flutter `State.dispose()` 直接拥有，不经 Provider 保活 | pop 必须 dispose controller/timer；app paused 仅 pause，不自动销毁，保持既有产品行为。 |
| `selectedBroadcastPrefixLengthProvider`、`mediaRootDirectoryProvider` | **应用配置** | 保持非 auto-dispose | 值由 SharedPreferences 恢复；没有 socket/process/stream，无 release 动作。 |
| `availableInterfacesProvider`、`selectedInterfaceIndexProvider` | **应用缓存/服务端设置 UI state** | 保持非 auto-dispose | Future 完成后没有持有网络句柄；离开页面不触发资源释放。Phase 7 前不引入网卡扫描 backend。 |

### 2.2 不可变与值相等规则

- `SyncClientState`、`SyncServerState`、`MediaBrowserState` 和 `ShufflePlaybackState` 统一继承 `Equatable`；公开 collection 在构造函数 initializer 中 snapshot，不让调用方保留同一可变集合。
- 不修改 `FileItem`、`DiscoveredServer`、`NetworkInterfaceInfo` 或 `SettingsExportData` 的所在分层/API。State 自己的 `props` 将这些对象投影成其实际可观察值：server/interface 使用字段 record；`deduplicatedData` 使用既有 `toJsonString()`；media item 使用 `(name, isDirectory, sizeBytes, relativePath, lastModified, mimeType, thumbnailUrl)` record。
- `selectedCategories` 的 props 用排序后的 enum index 列表，避免 Set 插入顺序影响相等性。列表仍保持显示/请求顺序；只有集合语义归一化。
- 每次 controller 发布 state 都经过构造边界；高频路径不在 getter/Widget 中重复复制。目录加载、切换分类、随机播放和回退都只在 state 变更边界分配 snapshot。

### 2.3 过期异步结果规则

`SyncClientController` 与 `MediaBrowserController` 各维护私有 monotonically increasing generation。启动 discovery/HTTP 请求时捕获 generation；`cancelAndReset`、新的 discovery、媒体 `reset()` 和 provider dispose 均使旧 generation 失效。异步/stream callback 在发布 state 前检查 `ref.mounted` 与 generation 相等；不相等时静默返回。该规则不取消 app-scoped `peerHttpClientProvider`，也不引入 Phase 7 的 client/transport factory。

## 三、文件修改清单

### 修改

| 文件 | 修改职责 |
|---|---|
| `lib/features/sync/application/sync_client_controller.dart` | `SyncClientState` 的不可变 snapshot/Equatable；页面级 auto-dispose；discovery 与 request 的 generation guard；doc 明确取消与重建语义。 |
| `lib/features/sync/application/sync_server_controller.dart` | `SyncServerState` 的 Equatable；会话级 auto-dispose + 单一 keep-alive link；停止顺序和 handler/scanner 的 owner doc；无 listener 时的保活/释放安全。 |
| `lib/features/sync/application/broadcast_prefix_length_provider.dart` | doc 明确它是持久化应用配置，非资源 Provider；逻辑和 persistence key 不变。 |
| `lib/features/sync/application/network_interface_provider.dart` | doc 明确已完成的接口枚举为应用 cache、index 为设置 UI state，均不持有 socket。 |
| `lib/features/media/application/media_browser_controller.dart` | `MediaBrowserState` 的 list snapshot/Equatable；页面级 auto-dispose；`reset()` 与 request generation guard。 |
| `lib/features/media/application/media_root_directory_controller.dart` | doc 明确根目录是应用配置，实际 scanner 生命周期属于 sync server handlers；逻辑不变。 |
| `lib/features/media/application/shuffle_playback_controller.dart` | sealed state 的 Equatable；`ShufflePlaybackActive.playlist` snapshot；页面级 auto-dispose doc。 |
| `lib/features/sync/presentation/sync_screen.dart` | 仅编排 lifecycle：媒体 Tab 进入时初始化，离开时 reset browser/shuffle；仅在媒体 Tab 活跃时 watch media state，避免 AppBar 自己无条件成为 media browser 的常驻观察者。 |
| `lib/features/media/presentation/media_browser_tab.dart` | doc 说明本 widget 是 media page-session 的观察者；保持目录变化清空 shuffle 的既有职责，不创建 backend。 |
| `lib/features/media/presentation/pages/video_player_page.dart` | doc 明确 video controller 属于路由页面、pause 与 dispose 的不同语义；不改变播放器实现。 |
| `test/features/sync/application/sync_client_controller_test.dart` | 增加不可变、值相等、auto-dispose 后重建的 controller 契约测试。 |
| `test/features/sync/application/sync_server_controller_test.dart` | 增加运行会话 keep-alive、显式 stop 后可释放、container dispose 清理 socket 的测试；现有 real server 测试在 tearDown 先 stop。 |
| `test/features/media/application/media_browser_controller_test.dart` | 增加 source collection 隔离、值相等、reset、auto-dispose/rebuild、reset 后忽略 delayed HTTP completion 的测试。 |
| `test/features/media/application/shuffle_playback_controller_test.dart` | 增加 playlist snapshot、Idle/Loading/Active 值相等和 auto-dispose/rebuild 测试。 |
| `test/features/sync/sync_screen/sync_screen_render_cases.dart` | 增加 Android media Tab 离开后两个页面会话均 reset、再次进入重新初始化的用户行为测试。 |
| `test/features/sync/sync_screen/sync_screen_test_helpers.dart` | 为 Android target override 与测试 HTTP/Provider overrides 增加最小 helper；仍通过 `pumpTestApp()` 注入 DB/preferences。 |
| `test/features/media/presentation/video_player_page_test.dart` | 让现有 fake controller 记录 dispose，覆盖 pop 后恰好释放一次；不以私有 widget key/布局作断言。 |

### 明确不修改

- `lib/features/sync/data/**`（包括 `SyncUdpDiscovery`、`SyncHttpServer`）的 construction API、任何 `SyncServerTransport`，以及 `lib/features/media/data/**` 的 scanner/handler/cache/backend：均属于 Phase 7 之后的注入边界。
- 配对、认证、协议版本、session negotiation：属于 Phase 8。
- `peerHttpClientProvider`、HTTP 信任域、日志/脱敏：保持 Phase 3 结论。
- SharedPreferences key/JSON、SQLite schema/migration、媒体 API 路径、随机算法与播放器 UI 行为。
- Riverpod 版本、代码生成、全局 ports/repository 改造，或对所有 Provider 的机械 autoDispose。

## 四、实施任务、测试策略与独立提交

> 每个任务都先加入失败测试，确认它因缺少该契约而失败，再写最小实现。所有 Flutter test 命令使用项目强制重定向模式；**不要**直接运行全量 `flutter test` 或使用 `tee`。Git commit 在 Bash 执行，且不纳入现有未跟踪的 Phase 5 计划文件。

### Task 1：冻结 Sync/Media state snapshot，并让相等语义可推理

**Files:**

- Modify: `lib/features/sync/application/sync_client_controller.dart`
- Modify: `lib/features/sync/application/sync_server_controller.dart`
- Modify: `lib/features/media/application/media_browser_controller.dart`
- Modify: `lib/features/media/application/shuffle_playback_controller.dart`
- Modify: `test/features/sync/application/sync_client_controller_test.dart`
- Modify: `test/features/sync/application/sync_server_controller_test.dart`
- Modify: `test/features/media/application/media_browser_controller_test.dart`
- Modify: `test/features/media/application/shuffle_playback_controller_test.dart`

- [ ] **Step 1: 写不可变与值相等的失败测试。**

  在现有 application test 中新增以下四组外部契约；不用 `find.byKey` 或内部 state 字段写入。

  ```dart
  test('SyncClientState snapshots selectedCategories and compares category values', () {
    final source = <SyncCategory>{SyncCategory.providers};
    final state = SyncClientState(selectedCategories: source);
    source.add(SyncCategory.presets);

    expect(state.selectedCategories, {SyncCategory.providers});
    expect(
      () => state.selectedCategories.add(SyncCategory.presets),
      throwsUnsupportedError,
    );
    expect(
      state,
      SyncClientState(selectedCategories: {SyncCategory.providers}),
    );
  });

  test('MediaBrowserState snapshots item and history inputs and compares values', () {
    final items = <FileItem>[testVideoItem];
    final history = <String>['/'];
    final state = MediaBrowserState(items: items, pathHistory: history);
    items.clear();
    history.add('/movies');

    expect(state.items, [testVideoItem]);
    expect(state.pathHistory, ['/']);
    expect(() => state.items.clear(), throwsUnsupportedError);
    expect(() => state.pathHistory.add('/x'), throwsUnsupportedError);
    expect(state, MediaBrowserState(items: [testVideoItem], pathHistory: ['/']));
  });

  test('ShufflePlaybackActive snapshots playlist and all state variants compare by value', () {
    final playlist = <VideoItem>[testVideoItem];
    final active = ShufflePlaybackActive(
      playlist: playlist,
      currentIndex: 0,
      directoryPath: '/',
    );
    playlist.clear();

    expect(active.playlist, [testVideoItem]);
    expect(() => active.playlist.clear(), throwsUnsupportedError);
    expect(const ShufflePlaybackIdle(), const ShufflePlaybackIdle());
    expect(const ShufflePlaybackLoading(), const ShufflePlaybackLoading());
  });
  ```

  对 `SyncServerState` 再断言两个含相同 `NetworkInterfaceInfo(name, ip)` 的 state 相等、不同 `servedRequestCount` 不相等。对 SyncClient 再覆盖相同 server field 与相同 `SettingsExportData.toJsonString()` 的 value equality，避免 identity 漏洞。

- [ ] **Step 2: 运行定向测试，确认现状失败。**

  ```powershell
  flutter test test/features/sync/application/sync_client_controller_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase6-client-state.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 120 fltest-phase6-client-state.log
  flutter test test/features/media/application/media_browser_controller_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase6-browser-state.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 120 fltest-phase6-browser-state.log
  flutter test test/features/media/application/shuffle_playback_controller_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase6-shuffle-state.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 120 fltest-phase6-shuffle-state.log
  ```

  预期：至少 mutable collection 与 `equals` 断言失败；这是 TD-12 的红灯，而非网络失败。

- [ ] **Step 3: 实现 state 边界。**

  四个文件都 import `package:equatable/equatable.dart`。把原先的 `const` state 构造替换成可 snapshot 的普通构造（默认空集合可保留 `const []`/`const {}` 输入），并用下面的模式；不要为了 props 修改 domain/data model。

  ```dart
  class SyncClientState extends Equatable {
    SyncClientState({
      this.phase = SyncPhase.idle,
      this.server,
      Set<SyncCategory> selectedCategories = const {},
      this.errorMessage,
      this.deduplicatedData,
      this.sourceDeviceName,
    }) : selectedCategories = Set.unmodifiable(selectedCategories);

    final Set<SyncCategory> selectedCategories;

    @override
    List<Object?> get props => [
      phase,
      (server?.deviceName, server?.ip, server?.httpPort),
      selectedCategories.map((category) => category.index).toList()..sort(),
      errorMessage,
      deduplicatedData?.toJsonString(),
      sourceDeviceName,
    ];
  }
  ```

  `MediaBrowserState` 使用 `List.unmodifiable(items)` 与 `List.unmodifiable(pathHistory)`；props 中把 item 映射为 `(name, isDirectory, sizeBytes, relativePath, lastModified, mimeType, thumbnailUrl)` record。`SyncServerState` 的 props 用 `(selectedInterface?.name, selectedInterface?.ip)`。`ShufflePlaybackState` 成为 `sealed class ... extends Equatable`，Idle/Loading 的 `props` 是 `const []`，Active 的 initializer 为 `playlist = List.unmodifiable(playlist)` 且 props 包含 playlist/index/path。所有 `const SyncClientState`、`const MediaBrowserState`、`const ShufflePlaybackActive` 调用点和测试改为非 const；状态行为和字段名不改。

- [ ] **Step 4: 运行 state 回归。**

  ```powershell
  flutter test test/features/sync/application/sync_client_controller_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase6-client-state.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 120 fltest-phase6-client-state.log
  flutter test test/features/sync/application/sync_server_controller_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase6-server-state.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 120 fltest-phase6-server-state.log
  flutter test test/features/media/application/media_browser_controller_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase6-browser-state.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 120 fltest-phase6-browser-state.log
  flutter test test/features/media/application/shuffle_playback_controller_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase6-shuffle-state.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 120 fltest-phase6-shuffle-state.log
  ```

  预期：四条均 `EXIT=0`，公开集合不可修改且等值 snapshot 不产生错误差异。

- [ ] **Step 5: 提交 state 契约。**

  ```bash
  git add lib/features/sync/application/sync_client_controller.dart \
          lib/features/sync/application/sync_server_controller.dart \
          lib/features/media/application/media_browser_controller.dart \
          lib/features/media/application/shuffle_playback_controller.dart \
          test/features/sync/application/sync_client_controller_test.dart \
          test/features/sync/application/sync_server_controller_test.dart \
          test/features/media/application/media_browser_controller_test.dart \
          test/features/media/application/shuffle_playback_controller_test.dart
  git commit -m "refactor(sync-media): 固化状态快照与值相等"
  ```

### Task 2：落实同步 server/client 的会话与页面生命周期

**Files:**

- Modify: `lib/features/sync/application/sync_client_controller.dart`
- Modify: `lib/features/sync/application/sync_server_controller.dart`
- Modify: `lib/features/sync/application/broadcast_prefix_length_provider.dart`
- Modify: `lib/features/sync/application/network_interface_provider.dart`
- Modify: `lib/features/media/application/media_root_directory_controller.dart`
- Modify: `test/features/sync/application/sync_client_controller_test.dart`
- Modify: `test/features/sync/application/sync_server_controller_test.dart`

- [ ] **Step 1: 写 provider 生命周期红灯测试。**

  使用 `ProviderContainer` 的 listener + `await container.pump()`，不用 `Future.delayed`。测试依据 Riverpod 3 的确定性调度：关闭 listener 后 pump 会等待 auto-dispose；运行中的 server 的 keep-alive link 则阻止该 dispose。

  ```dart
  test('running sync server survives observer removal until explicit stop', () async {
    final container = buildContainer();
    final subscription = container.listen(
      syncServerControllerProvider,
      (_, _) {},
    );
    final controller = container.read(syncServerControllerProvider.notifier);
    await controller.start();

    subscription.close();
    await container.pump();
    expect(container.exists(syncServerControllerProvider), isTrue);

    await controller.stop();
    await container.pump();
    expect(container.exists(syncServerControllerProvider), isFalse);
  });

  test('idle sync client is disposed after its page listener closes and rebuilds idle', () async {
    final container = buildContainer();
    final subscription = container.listen(
      syncClientControllerProvider,
      (_, _) {},
    );
    container.read(syncClientControllerProvider.notifier).toggleCategory(
      SyncCategory.providers,
    );

    subscription.close();
    await container.pump();
    expect(container.exists(syncClientControllerProvider), isFalse);
    expect(container.read(syncClientControllerProvider).phase, SyncPhase.idle);
    expect(container.read(syncClientControllerProvider).selectedCategories, isEmpty);
  });
  ```

  为 server container 新增 `tearDown`：若 provider 仍 exists，`await notifier.stop()` 后再 `container.dispose()`，确保真实 HTTP/UDP fixture 不泄漏给并行测试。另加“container dispose 后同一 port 不再接受 HTTP”的行为测试：start、记录 port、dispose、向该 port 发 `http.get` 并断言 `throwsA(isA<http.ClientException>())`；不通过 sleep 轮询端口。

- [ ] **Step 2: 运行红灯测试。**

  ```powershell
  flutter test test/features/sync/application/sync_server_controller_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase6-server-lifecycle.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest-phase6-server-lifecycle.log
  flutter test test/features/sync/application/sync_client_controller_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase6-client-lifecycle.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest-phase6-client-lifecycle.log
  ```

  预期：server 在关闭 listener 后当前仍为默认全局 provider，或 stop 后仍存在；client 也不会 auto-dispose。

- [ ] **Step 3: 实现声明的生命周期和过期保护。**

  1. 两个 provider 改为 `NotifierProvider<..., ...>(..., isAutoDispose: true)`；不要改成 family，也不要创建 transport 接口。
  2. `SyncServerController.start()` 成功后执行 `_keepAliveLink ??= ref.keepAlive()`，确保 device-name restart 不累计未关闭 link。`stop()` 的顺序固定为：保存当前 link 并置空 → `await _cleanup()` → 发布 `isRunning: false/httpPort: null/servedRequestCount: 0` → close 保存的 link。这样无 listener 时也先完成可观察的停止与 socket cleanup，再让 auto-dispose 执行 `onDispose` 的幂等 cleanup。
  3. 保持 `_cleanup()` 的 UDP stop → HTTP stop 顺序和幂等置空；在 controller/provider doc 中写明 handlers、scanner、thumbnail cache/generator 由 `_httpServer` 的运行会话拥有，而非独立全局资源。
  4. `SyncClientController` 增加 `_generation` 与 `_invalidateDiscovery()`：先递增 generation、取消并清空 subscription。`startDiscovery()`、`cancelAndReset()` 与 `ref.onDispose` 均经该方法；`listen` 的 data/onDone/onError 和 `requestSync()` 中每个 await 后在 state write 前检查 `ref.mounted && generation == requestGeneration`。只有当前 generation 才能更新 `state`。
  5. 在 prefix/interface/root provider 的中文 doc 中写入 2.1 的非资源理由；不改变其 provider 类型、SharedPreferences 写法、Future cache 或 selection 行为。

- [ ] **Step 4: 运行同步 lifecycle 全量定向回归。**

  ```powershell
  flutter test test/features/sync/application/sync_client_controller_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase6-client-lifecycle.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest-phase6-client-lifecycle.log
  flutter test test/features/sync/application/sync_client_controller_execute_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase6-client-execute.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest-phase6-client-execute.log
  flutter test test/features/sync/application/sync_server_controller_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase6-server-lifecycle.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest-phase6-server-lifecycle.log
  flutter test test/features/sync/application/broadcast_prefix_length_provider_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase6-prefix.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 120 fltest-phase6-prefix.log
  ```

  预期：均 `EXIT=0`；测试不包含固定 duration、微秒阈值或端口 sleep。

- [ ] **Step 5: 提交 sync 生命周期。**

  ```bash
  git add lib/features/sync/application/sync_client_controller.dart \
          lib/features/sync/application/sync_server_controller.dart \
          lib/features/sync/application/broadcast_prefix_length_provider.dart \
          lib/features/sync/application/network_interface_provider.dart \
          lib/features/media/application/media_root_directory_controller.dart \
          test/features/sync/application/sync_client_controller_test.dart \
          test/features/sync/application/sync_server_controller_test.dart \
          test/features/sync/application/broadcast_prefix_length_provider_test.dart
  git commit -m "refactor(sync): 明确服务与发现生命周期"
  ```

### Task 3：落实媒体 Tab 与视频路由的页面会话边界

**Files:**

- Modify: `lib/features/media/application/media_browser_controller.dart`
- Modify: `lib/features/media/application/shuffle_playback_controller.dart`
- Modify: `lib/features/sync/presentation/sync_screen.dart`
- Modify: `lib/features/media/presentation/media_browser_tab.dart`
- Modify: `lib/features/media/presentation/pages/video_player_page.dart`
- Modify: `test/features/media/application/media_browser_controller_test.dart`
- Modify: `test/features/media/application/shuffle_playback_controller_test.dart`
- Modify: `test/features/sync/sync_screen/sync_screen_test_helpers.dart`
- Modify: `test/features/sync/sync_screen/sync_screen_render_cases.dart`
- Modify: `test/features/media/presentation/video_player_page_test.dart`

- [ ] **Step 1: 写媒体 session 的失败测试。**

  `media_browser_controller_test.dart` 使用受控 `Completer<http.Response>` MockClient，执行 `initWithServer` 后 `reset()`、再 complete 旧 response，断言 state 仍是 root/no-server/empty（即旧请求不能重建 session）。同时按以下模式验证 auto-dispose 的可重建性：

  ```dart
  test('media browser page session resets after its listener is released', () async {
    final container = createMediaTestContainer(httpClient: okMockClient('[]'));
    final subscription = container.listen(
      mediaBrowserControllerProvider,
      (_, _) {},
    );
    await initBrowserAndWait(container);

    subscription.close();
    await container.pump();
    expect(container.exists(mediaBrowserControllerProvider), isFalse);
    expect(container.read(mediaBrowserControllerProvider), const MediaBrowserState());
  });
  ```

  对 shuffle 做同样的 observer-close/pump/rebuild Idle 测试。Screen test 使用 Android target override：进入媒体 Tab 并让 browser 有 server，然后切回“连接”，断言 browser 无 server、空 history，shuffle 为 Idle；再进入媒体 Tab，断言请求根目录重新发生。测试只检查可观察 provider state/文本，不以 `TabController` 或私有 key 断言。

  Video page 的 fake controller 新增 `disposeCount`，`dispose()` 自增；push 后 pop，`pump()` 一帧，断言 `disposeCount == 1`。这验证资源释放，不断言布局或 gesture 私有实现。

- [ ] **Step 2: 运行红灯测试。**

  ```powershell
  flutter test test/features/media/application/media_browser_controller_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase6-browser-lifecycle.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest-phase6-browser-lifecycle.log
  flutter test test/features/media/application/shuffle_playback_controller_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase6-shuffle-lifecycle.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest-phase6-shuffle-lifecycle.log
  flutter test test/features/sync/sync_screen_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase6-sync-screen.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest-phase6-sync-screen.log
  ```

  预期：当前 provider 不会因 listener 消失而 dispose，离开 Tab 也没有 reset；旧 browser response 可回填 reset state。

- [ ] **Step 3: 实现页面 session。**

  1. media browser 与 shuffle provider 均设 `isAutoDispose: true`，且不调用 `keepAlive`。保留 `peerHttpClientProvider` 的全局 owner。
  2. `MediaBrowserController` 加 `void reset()`：generation 加一并发布新的 `MediaBrowserState()`；`initWithServer`、`loadDirectory` 和返回导航为每次请求捕获 generation，HTTP await 完成后仅在 `ref.mounted && captured == _generation` 时发布结果。`reset()` 后旧 response 既不填入 items，也不覆盖 error/load 状态。保持现有 URL、error 文案和 history 成功后才 push 的规则。
  3. `SyncScreen._onTabChanged()` 在 index 已稳定时，若从媒体 Tab 离开，依次调用 browser `reset()` 与 shuffle `reset()`；进入媒体 Tab 时保持既有 `initWithServer(MediaServerInfo(...))`。`build` 只有在 Android 且媒体 Tab 当前选中时才 `watch(mediaBrowserControllerProvider)` 来计算 AppBar actions，其余 Tab 不额外订阅 browser state。
  4. 在 `MediaBrowserTab` doc 写明它在 Tab 仍被 `TabBarView` offstage 保留时不等于媒体 session 仍有效；session 边界由 SyncScreen 的 reset 统一裁定。保持现有目录改变清空 shuffle listener。
  5. 在 `VideoPlayerPage` doc 写明：`paused` 只 pause；route `dispose` 才释放 controller/timer。代码只在为让 dispose 测试可观察而需要时改 fake，不引入 Provider 或 process runner。

- [ ] **Step 4: 运行媒体和 screen 回归。**

  ```powershell
  flutter test test/features/media/application/media_browser_controller_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase6-browser-lifecycle.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest-phase6-browser-lifecycle.log
  flutter test test/features/media/application/shuffle_playback_controller_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase6-shuffle-lifecycle.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest-phase6-shuffle-lifecycle.log
  flutter test test/features/media/application/shuffle_playback_controller_behavior_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase6-shuffle-behavior.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest-phase6-shuffle-behavior.log
  flutter test test/features/sync/sync_screen_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase6-sync-screen.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest-phase6-sync-screen.log
  flutter test test/features/media/presentation/video_player_page_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase6-video-page.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest-phase6-video-page.log
  ```

  预期：均 `EXIT=0`；释放证据来自 `ProviderContainer.pump()`、listener close、route pop 和可控 Completer，不依赖任意延时。

- [ ] **Step 5: 提交媒体生命周期。**

  ```bash
  git add lib/features/media/application/media_browser_controller.dart \
          lib/features/media/application/shuffle_playback_controller.dart \
          lib/features/sync/presentation/sync_screen.dart \
          lib/features/media/presentation/media_browser_tab.dart \
          lib/features/media/presentation/pages/video_player_page.dart \
          test/features/media/application/media_browser_controller_test.dart \
          test/features/media/application/shuffle_playback_controller_test.dart \
          test/features/sync/sync_screen/sync_screen_test_helpers.dart \
          test/features/sync/sync_screen/sync_screen_render_cases.dart \
          test/features/media/presentation/video_player_page_test.dart
  git commit -m "refactor(media): 约束浏览与播放页面会话"
  ```

### Task 4：范围审计与最终质量门禁

**Files:**

- Modify only files already listed above when verification directly发现本 Phase 回归；不顺手重构 data/backend/protocol。

- [ ] **Step 1: 格式化本 Phase Dart 改动。**

  ```powershell
  dart format lib/features/sync/application/sync_client_controller.dart lib/features/sync/application/sync_server_controller.dart lib/features/sync/application/broadcast_prefix_length_provider.dart lib/features/sync/application/network_interface_provider.dart lib/features/media/application/media_browser_controller.dart lib/features/media/application/media_root_directory_controller.dart lib/features/media/application/shuffle_playback_controller.dart lib/features/sync/presentation/sync_screen.dart lib/features/media/presentation/media_browser_tab.dart lib/features/media/presentation/pages/video_player_page.dart test/features/sync/application/sync_client_controller_test.dart test/features/sync/application/sync_server_controller_test.dart test/features/sync/application/broadcast_prefix_length_provider_test.dart test/features/media/application/media_browser_controller_test.dart test/features/media/application/shuffle_playback_controller_test.dart test/features/sync/sync_screen/sync_screen_test_helpers.dart test/features/sync/sync_screen/sync_screen_render_cases.dart test/features/media/presentation/video_player_page_test.dart
  ```

- [ ] **Step 2: 执行 static analysis。**

  ```powershell
  flutter analyze 2>&1 | Out-File -Encoding utf8 flanalyze-phase6.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 flanalyze-phase6.log
  ```

  预期：`EXIT=0` 且 `No issues found!`。

- [ ] **Step 3: 按强制格式运行全量测试。**

  ```powershell
  flutter test --reporter compact 2>&1 | Out-File -Encoding utf8 fltest.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest.log
  ```

  预期：`EXIT=0`、末尾 `All tests passed!`。若失败，使用 `Select-String -Pattern "失败测试名" -Path fltest.log -Context 0,30` 定位；修复仅限本计划 File Scope，之后重新运行失败文件、analyze 和全量测试。

- [ ] **Step 4: 进行范围与生命周期审计。**

  ```powershell
  rg -n "NotifierProvider<.*Sync(Client|Server)|NotifierProvider<.*(MediaBrowser|ShufflePlayback)|isAutoDispose: true|keepAlive\(" lib/features/sync/application lib/features/media/application
  rg -n "Set\.unmodifiable|List\.unmodifiable|extends Equatable" lib/features/sync/application/sync_client_controller.dart lib/features/sync/application/sync_server_controller.dart lib/features/media/application/media_browser_controller.dart lib/features/media/application/shuffle_playback_controller.dart
  rg -n "SyncServerTransport|MediaRouteFactory|ProcessRunner|pair|auth|protocol" lib/features/sync lib/features/media
  git diff --check
  git status --short
  ```

  审计标准：四个 state 的公开 collection 都 snapshot 且具值相等；仅 server 成功运行时有单一 keep-alive；client/browser/shuffle 都是 auto-dispose 页面会话；未出现 Phase 7 transport/backend、Phase 8 protocol/session/auth 或机械全局 provider 改造；`docs/第一轮审查/Phase 5 - Implement Plan.md` 仍不在 staged file list。

- [ ] **Step 5: 仅在必要时提交最小门禁修复。**

  仅当 Step 2–4 发现本 Phase 直接造成的问题时，使用 `fix(sync-media): 修复生命周期回归` 提交，并且 `git add` 只能包含第四节已列出的、导致该失败的最小文件集；没有失败则不创建空提交，也不借机开展 Phase 7/8 工作。

## 五、提交序列总览

| 节点 | Commit message | 独立价值 |
|---|---|---|
| 1 | `refactor(sync-media): 固化状态快照与值相等` | TD-12：外部无法原地改变公开集合，state 更新可按值推理。 |
| 2 | `refactor(sync): 明确服务与发现生命周期` | TD-13：同步 server 会话保活有唯一 owner，发现页面离开可释放。 |
| 3 | `refactor(media): 约束浏览与播放页面会话` | TD-13：媒体 Tab reset/rebuild 和视频路由 dispose 成为产品契约。 |
| 4（仅必要时） | `fix(sync-media): 修复生命周期回归` | 最终门禁发现的最小范围修复。 |

## 六、验收矩阵与自检

| Phase 6 验收项 | 计划证据 |
|---|---|
| TD-12 所有公开可变集合与不一致值语义已处理 | Task 1 的 snapshot/Equatable tests；`Set/List.unmodifiable` 与 props 审计。 |
| 每类资源有明确 keep-alive policy，代码与测试一致 | 2.1 决策表；Task 2 listener-close/pump/server socket test；Task 3 reset/rebuild/pop tests。 |
| 页面离开、重建、重连、dispose 与保活行为可验证 | client/browser/shuffle `ProviderContainer.pump()` 重建；server listener removal + stop；SyncScreen media Tab transition；VideoPlayer route pop。 |
| 无微秒 timing 或任意 delay 作为唯一释放证据 | 所有 release tests 使用 listener close + `container.pump()`、Completer 或 route pop；不加 `Future.delayed`。 |
| 不机械改所有 Provider | prefix/root/interface 明确保留非 auto-dispose，且说明它们没有活跃资源。 |
| 不提前 Phase 7/8 | 文件清单、rg 范围审计和“不修改”清单均排除 transport/backend/protocol/auth。 |
| `flutter analyze` 与全量测试通过 | Task 4 的重定向命令，要求 `EXIT=0`。 |

**自检结果：** 覆盖 TD-12、TD-13 与所有 Verification/Completion Criteria；state props 不依赖范围外模型改造；每个资源策略都有 owner、释放点和无 timing 的测试证据；没有 TBD/TODO 或未定义的 backend/interface。实施顺序先 state 合同、再 sync 生命周期、再 media 生命周期，符合“先明确 owner/保活，再进入 Phase 7 construction boundary”的依赖顺序。
