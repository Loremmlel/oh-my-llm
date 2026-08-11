# Targeted Coverage and Deterministic UDP Testing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add direct high-value regression coverage for under-tested settings, Sync, and media boundaries, and replace UDP lifecycle sleeps with deterministic socket/scheduler tests while retaining one real loopback smoke.

**Architecture:** Strengthen existing tests when they already own the contract; add focused repository/transport tests where no direct boundary exists; inject a narrow `SyncClientProtocol` into the controller for state-only tests; and split UDP into a pure announcement codec plus replaceable socket, scheduler, multicast-lock, and lifecycle-session components. Production defaults and public application ports remain unchanged.

**Tech Stack:** Flutter 3.44.x stable (CI 3.44.6), Dart `^3.11.5`, Riverpod 3 `NotifierProvider`, `shared_preferences`, `package:http`, `dart:io` UDP, `flutter_test`, PowerShell 7, LCOV.

**Design Reference:** `docs/superpowers/specs/2026-08-11-targeted-coverage-and-deterministic-udp-design.md`

## Global Constraints

- Follow `AGENTS.md`; comments are Simplified Chinese, no `part`/`part of`, and cross-feature/core/app references use package-root imports beginning with `package:oh_my_llm/`.
- Do not change Sync protocol version 3, Settings export format 7, persisted pairing keys, HTTP routes, user-visible error messages, or trust-domain wiring.
- Production UDP defaults remain `255.255.255.255`, `InternetAddress.anyIPv4`, port 47280, broadcast interval 2 seconds, and idle timeout 6 seconds.
- Do not handle independently running release-app UDP interference in this implementation.
- Do not split Chat/Settings widget test entry files, change `dart_test.yaml`, change CI workflows, increase timeouts, or change concurrency.
- Do not add dependencies; the manual UDP scheduler and test fakes are repository-local.
- Do not add `Future.delayed`, arbitrary `pump`, `pumpAndSettle`, pixel assertions, internal widget keys, or resilience allowlist entries.
- Use malformed raw JSON only in tests explicitly named as persistence/wire compatibility boundaries. Use real model constructors or `TestFixtures` for ordinary valid data.
- Each test protects an external contract, state transition, persistence result, protocol/error mapping, or resource lifecycle. Do not add tests for Equatable `props`, `copyWith`, framework forwarding, or adapter getters.
- Full and focused Flutter test commands must redirect output to a log, capture `$LASTEXITCODE`, print `EXIT=<code>`, and tail the log.
- Before every commit, format every changed Dart file; after staging, run `dart format --output=none --set-exit-if-changed` on staged Dart files.
- Do not stage generated logs, `coverage/`, temporary fixtures, or unrelated user changes.
- Regression fixes discovered during execution require a focused red/green proof. Coverage-only characterization tests may pass immediately against current production behavior; do not manufacture a failure.

## Pre-Implementation Baseline

Before Task 1, create fresh out-of-repository baseline artifacts:

```powershell
$BaselineDir = Join-Path $env:TEMP 'oh-my-llm-targeted-coverage-udp'
New-Item -ItemType Directory -Force $BaselineDir | Out-Null
git rev-parse HEAD | Out-File -Encoding ascii (Join-Path $BaselineDir 'baseline-head.txt')

$CoverageLog = Join-Path $BaselineDir 'baseline-coverage.log'
$Timer = [System.Diagnostics.Stopwatch]::StartNew()
flutter test --exclude-tags=udp --coverage --reporter compact 2>&1 |
  Out-File -Encoding utf8 $CoverageLog
$E = $LASTEXITCODE
$Timer.Stop()
Write-Host "EXIT=$E"
Write-Host ("ELAPSED_SECONDS={0:N3}" -f $Timer.Elapsed.TotalSeconds)
Get-Content -Tail 150 $CoverageLog
if ($E -ne 0) { exit $E }
Copy-Item coverage\lcov.info (Join-Path $BaselineDir 'baseline-lcov.info') -Force

1..3 | ForEach-Object {
  $Run = $_
  $Log = Join-Path $BaselineDir "baseline-udp-$Run.log"
  $Timer = [System.Diagnostics.Stopwatch]::StartNew()
  flutter test test/features/sync/data/sync_udp_discovery_test.dart --reporter compact 2>&1 |
    Out-File -Encoding utf8 $Log
  $E = $LASTEXITCODE
  $Timer.Stop()
  Write-Host ("RUN={0} EXIT={1} ELAPSED_SECONDS={2:N3}" -f $Run, $E, $Timer.Elapsed.TotalSeconds)
  Get-Content -Tail 20 $Log
  if ($E -ne 0) { exit $E }
}
```

Expected baseline: CI-equivalent suite passes with 1,358 cases; UDP file passes with 2 cases and contains three intentional real waits. Record actual timings rather than requiring the previously measured numbers.

---

### Task 1: Add Direct Secure Pairing Repository Contracts

**Files:**
- Create: `test/features/sync/data/secure_sync_pairing_repository_test.dart`
- Test: `lib/features/sync/data/secure_sync_pairing_repository.dart`

**Interfaces:**
- Consumes: `SecureSyncPairingRepository`, `SyncSecureStore`, `SyncPairingRecord`, `VersionedJsonStorage`, SharedPreferences mock storage.
- Produces: direct identity, secret-isolation, round-trip, corruption-cleanup, rollback, and revoke protection without changing production interfaces.

- [ ] **Step 1: Add a recording/failing secure-store fake and typed fixtures**

  Create the test file with these support types and fixtures:

  ```dart
  final class _RecordingSecureStore implements SyncSecureStore {
    final values = <String, String>{};
    final writes = <String>[];
    final deletes = <String>[];
    Object? writeError;
    Object? readError;

    @override
    Future<String?> read(String key) async {
      if (readError case final error?) throw error;
      return values[key];
    }

    @override
    Future<void> write(String key, String value) async {
      writes.add(key);
      if (writeError case final error?) throw error;
      values[key] = value;
    }

    @override
    Future<void> delete(String key) async {
      deletes.add(key);
      values.remove(key);
    }
  }

  SyncPairingRecord _record(String peerId) => SyncPairingRecord(
    peer: SyncPeerIdentity(id: peerId, displayName: '远端-$peerId'),
    createdAt: DateTime(2026, 1, 1),
    lastUsedAt: DateTime(2026, 1, 2),
  );
  ```

  In `setUp`, call `SharedPreferences.setMockInitialValues({})`, obtain the instance, create `_RecordingSecureStore`, and create the repository. Do not expose production private constants through new getters.

- [ ] **Step 2: Add identity and successful persistence tests**

  Add these three tests:

  ```dart
  test('ensureLocalIdentity 首次生成后保持稳定', () async {
    final first = await repository.ensureLocalIdentity([1, 2, 3, 4]);
    final second = await repository.ensureLocalIdentity([9, 9, 9, 9]);

    expect(first.id, 'AQIDBA');
    expect(second, first);
    expect(await repository.localIdentity(), first);
  });

  test('save 仅把 secret 写入 secure store 并可完整读取', () async {
    final record = _record('peer-a');
    const secret = [1, 2, 3, 4];

    await repository.save(record: record, secret: secret);

    expect(await repository.load('peer-a'), record);
    expect(await repository.loadAll(), [record]);
    expect(await repository.loadSecret('peer-a'), secret);
    expect(secureStore.writes, hasLength(1));
    expect(
      preferences.getKeys().map(preferences.get).join('\n'),
      isNot(contains(base64Encode(secret))),
    );
  });

  test('revoke 只移除目标 peer 的 secret 与 metadata', () async {
    await repository.save(record: _record('peer-a'), secret: [1]);
    await repository.save(record: _record('peer-b'), secret: [2]);

    await repository.revoke('peer-a');

    expect(await repository.load('peer-a'), isNull);
    expect(await repository.load('peer-b'), _record('peer-b'));
    expect(await repository.loadSecret('peer-a'), isNull);
    expect(await repository.loadSecret('peer-b'), [2]);
  });
  ```

- [ ] **Step 3: Add corruption and rollback boundary tests**

  Add named tests for these exact outcomes:

  ```dart
  test('secret 缺失时 load 拒绝记录并清理孤立 metadata', () async {
    final record = _record('peer-a');
    await repository.save(record: record, secret: [1, 2, 3]);
    secureStore.values.clear();

    expect(await repository.load('peer-a'), isNull);
    expect(await repository.loadAll(), isEmpty);
    expect(preferences.getString('sync.v3.pairings'), isNull);
  });

  test('secret base64 损坏时 loadAll 清理对应 metadata', () async {
    await repository.save(record: _record('peer-a'), secret: [1, 2, 3]);
    final secretKey = secureStore.writes.single;
    secureStore.values[secretKey] = '%%%';

    expect(await repository.loadAll(), isEmpty);
    expect(preferences.getString('sync.v3.pairings'), isNull);
  });

  test('secure store 写入失败时清理目标并抛稳定 StateError', () async {
    secureStore.writeError = StateError('secure write failed');

    await expectLater(
      repository.save(record: _record('peer-a'), secret: [1]),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('无法安全保存 Sync 配对'),
        ),
      ),
    );
    expect(secureStore.deletes, hasLength(1));
    expect(preferences.getString('sync.v3.pairings'), isNull);
  });
  ```

  Add one malformed-metadata test by seeding `sync.v3.pairings` with invalid JSON. Its name must state that it verifies corrupted persisted metadata. Assert `loadAll()` returns empty and the key is removed.

- [ ] **Step 4: Run the repository test and classify any failure before changing production**

  ```powershell
  $Log = Join-Path $env:TEMP 'oh-my-llm-targeted-coverage-udp\task1-secure-pairing.log'
  flutter test test/features/sync/data/secure_sync_pairing_repository_test.dart --reporter compact 2>&1 |
    Out-File -Encoding utf8 $Log
  $E = $LASTEXITCODE
  Write-Host "EXIT=$E"
  Get-Content -Tail 150 $Log
  if ($E -ne 0) { exit $E }
  ```

  Expected: tests pass against current behavior. If a contract fails, stop and determine whether the test exposed a product defect; do not loosen the assertion to recover coverage.

- [ ] **Step 5: Format, stage-check, and commit**

  ```powershell
  dart format test/features/sync/data/secure_sync_pairing_repository_test.dart
  git add -- test/features/sync/data/secure_sync_pairing_repository_test.dart
  dart format --output=none --set-exit-if-changed test/features/sync/data/secure_sync_pairing_repository_test.dart
  git commit -m "test(sync): 补齐安全配对仓库边界"
  ```

---

### Task 2: Expand Settings Transfer Decision Coverage

**Files:**
- Modify: `test/features/settings/application/settings_transfer_workflow_test.dart`
- Test: `lib/features/settings/application/settings_transfer_workflow.dart`

**Interfaces:**
- Consumes: `SettingsTransferWorkflow.buildExportData`, `prepareImport`, real Settings model factories, `SettingsExportCodec`.
- Produces: named export-tab and import-preparation decision coverage without duplicating codec migration or deduplicator comparator internals.

- [ ] **Step 1: Replace hand-written provider setup with shared typed fixtures**

  Import `test/helpers/fixtures.dart` relatively and define only the missing scalar fixtures locally:

  ```dart
  const headers = CustomHeadersConfig(
    headers: [CustomHeaderEntry(key: 'X-Test', value: 'value')],
  );
  const output = OutputProcessingSettings(
    rules: [OutputRegexRule(id: 'rule-1', pattern: 'x')],
  );
  const retry = AutoRetrySettings(maxRetryCount: 2);
  const fontSize = FontSizeSettings(bodyFontSize: 18);
  ```

  Construct the provider with a real `LlmProviderConfig` and `LlmApiProtocol.chatCompletions`; use `TestFixtures.memoryPrompt`, `presetPrompt`, `templatePrompt`, and `fixedSequence` for prompt entities.

- [ ] **Step 2: Register table-driven export tests for all tabs**

  Define a record list containing `tab`, a workflow with exactly that tab populated, and a predicate that validates only its fields. Register one test per record:

  ```dart
  for (final testCase in exportCases) {
    test('${testCase.tab.name} 只导出当前 tab 数据', () {
      final result = testCase.workflow.buildExportData(testCase.tab);
      expect(result, isNotNull);
      testCase.verify(result!);
    });
  }
  ```

  Include providers, presets, prompts, network, outputProcessing, and other. In the prompts case populate memory, template, and fixed sequence together. In the other case assert only retry/font settings are present.

  Register a second named matrix using a default empty workflow and assert `null` for providers, presets, prompts, network, and outputProcessing. Assert `other` is non-null because it always exports the current scalar defaults; this is a distinct existing contract and must not be forced into the null matrix.

- [ ] **Step 3: Register import-preparation outcome tests**

  Add separate named tests for:

  - `clipboardText: null` -> `invalidClipboard`;
  - a raw snapshot with `formatVersion = SettingsExportData.formatVersion + 1` -> `unsupportedVersion`;
  - valid preset data imported through providers tab -> `tabMismatch`;
  - valid preset data equal to the locally supplied preset -> `noNewItems`;
  - valid new preset data -> `ready`, with exactly that preset in `result.data`;
  - valid custom headers through network tab -> `ready`;
  - valid output rules through outputProcessing tab -> `ready`;
  - memory-only, template-only, and fixed-sequence-only data through prompts tab -> `ready`, registered as three named cases so every OR branch is independently protected;
  - retry-only and font-size-only data through other tab -> `ready`, registered separately so both OR branches are independently protected.

  Build unsupported-version JSON with `jsonEncode` and all required top-level lists. This raw map is permitted because the test name states that it verifies the future-format boundary.

- [ ] **Step 4: Run the focused workflow suite**

  ```powershell
  $Log = Join-Path $env:TEMP 'oh-my-llm-targeted-coverage-udp\task2-settings-transfer.log'
  flutter test test/features/settings/application/settings_transfer_workflow_test.dart --reporter compact 2>&1 |
    Out-File -Encoding utf8 $Log
  $E = $LASTEXITCODE
  Write-Host "EXIT=$E"
  Get-Content -Tail 150 $Log
  if ($E -ne 0) { exit $E }
  ```

  Expected: all existing and added workflow contracts pass without production changes.

- [ ] **Step 5: Format, stage-check, and commit**

  ```powershell
  dart format test/features/settings/application/settings_transfer_workflow_test.dart
  git add -- test/features/settings/application/settings_transfer_workflow_test.dart
  dart format --output=none --set-exit-if-changed test/features/settings/application/settings_transfer_workflow_test.dart
  git commit -m "test(settings): 覆盖传输工作流决策树"
  ```

---

### Task 3: Inject Sync Client Protocol Operations and Test Controller State

**Files:**
- Create: `lib/features/sync/application/ports/sync_client_protocol.dart`
- Modify: `lib/features/sync/application/sync_client_protocol_coordinator.dart`
- Modify: `lib/features/sync/application/sync_client_controller.dart`
- Modify: `test/features/sync/application/sync_test_fakes.dart`
- Modify: `test/features/sync/application/sync_client_controller_test.dart`

**Interfaces:**
- Consumes: existing coordinator public operations, `DiscoveredServer`, `SettingsExportData`, `SyncCategory`.
- Produces: `SyncClientProtocol`; `SyncClientProtocolCoordinator implements SyncClientProtocol`; `SyncClientController({SyncClientProtocol? protocol})`; scripted protocol and discovery fakes for state tests.

- [ ] **Step 1: Write a controller test that requires protocol injection**

  Add a `_buildContainer` helper to `sync_client_controller_test.dart` that attempts to construct:

  ```dart
  syncClientControllerProvider.overrideWith(
    () => SyncClientController(protocol: protocol),
  ),
  ```

  Add the first test: connect through `FakeSyncClientTransport`, call `pairWithCode(' 123456 ')`, and assert the fake received trimmed code `123456`, phase returns to `connected`, and `isPaired` becomes true.

- [ ] **Step 2: Run the test to verify the seam is absent**

  ```powershell
  $Log = Join-Path $env:TEMP 'oh-my-llm-targeted-coverage-udp\task3-red.log'
  flutter test test/features/sync/application/sync_client_controller_test.dart --reporter compact 2>&1 |
    Out-File -Encoding utf8 $Log
  $E = $LASTEXITCODE
  Write-Host "EXIT=$E"
  Get-Content -Tail 150 $Log
  if ($E -eq 0) { throw 'Expected compile failure before SyncClientProtocol injection exists' }
  ```

  Expected: compile failure because `SyncClientProtocol` and the `protocol` constructor parameter do not exist.

- [ ] **Step 3: Create the protocol interface and implement it on the coordinator**

  Create `sync_client_protocol.dart` with the exact interface from the design:

  ```dart
  abstract interface class SyncClientProtocol {
    Future<bool> isPaired(DiscoveredServer server);

    Future<void> pair({
      required DiscoveredServer server,
      required String code,
      required String displayName,
    });

    Future<SettingsExportData> requestSettings({
      required DiscoveredServer server,
      required Set<SyncCategory> categories,
      required bool confirmedSensitive,
    });

    Future<void> forgetPairing(DiscoveredServer server);

    void clearSessions();
  }
  ```

  Use package imports for the Settings model and relative imports for Sync models. Change only the coordinator declaration:

  ```dart
  final class SyncClientProtocolCoordinator implements SyncClientProtocol {
  ```

  Add the interface import; do not alter coordinator method bodies.

- [ ] **Step 4: Add optional constructor injection to the controller**

  Change the controller fields/build path to:

  ```dart
  class SyncClientController extends Notifier<SyncClientState> {
    SyncClientController({SyncClientProtocol? protocol})
      : _injectedProtocol = protocol;

    final SyncClientProtocol? _injectedProtocol;
    late final SyncClientProtocol _protocolCoordinator;

    @override
    SyncClientState build() {
      _protocolCoordinator = _injectedProtocol ??
          SyncClientProtocolCoordinator(
            transport: ref.read(syncClientTransportProvider),
            pairingRepository: ref.read(syncPairingRepositoryProvider),
            crypto: ref.read(syncCryptoProvider),
            clock: ref.read(syncClockProvider),
          );
      ref.onDispose(_invalidateDiscovery);
      return SyncClientState();
    }
  }
  ```

  Keep `SyncClientController.new` as the production NotifierProvider factory.

- [ ] **Step 5: Expand the shared fakes**

  Make `FakeSyncClientTransport` support `addError(Object)` and idempotent close. Add `ScriptedSyncClientProtocol implements SyncClientProtocol` with:

  ```dart
  bool paired = false;
  Object? pairError;
  Object? requestError;
  SettingsExportData requestResult = const SettingsExportData(
    modelProviders: [],
    memoryPrompts: [],
    presetPrompts: [],
    templatePrompts: [],
    fixedPromptSequences: [],
  );
  Completer<void>? pairGate;
  Completer<void>? requestGate;
  String? pairedCode;
  bool? requestedSensitiveConfirmation;
  Set<SyncCategory>? requestedCategories;
  int forgetCount = 0;
  int clearSessionsCount = 0;
  int isPairedCount = 0;
  ```

  `isPaired` increments `isPairedCount` and returns `paired`. `pair` awaits `pairGate`, records trimmed input received from the controller, then throws `pairError` or sets `paired = true`. `requestSettings` awaits `requestGate`, records categories/confirmation, then throws `requestError` or returns `requestResult`. `forgetPairing` increments the counter and clears `paired`; `clearSessions` increments its counter.

  Extend `FakeSettingsSyncFacade` with `SettingsExportData? deduplicatedResult`; `deduplicateIncoming` returns that override when present and otherwise returns its input. This lets the controller reach `noNewData` without duplicating deduplicator behavior.

- [ ] **Step 6: Add deterministic discovery, pair, and request state tests**

  Add a helper that starts discovery, registers `waitForProviderState` before emitting a compatible server, emits it, and awaits `connected`.

  Register independent tests for:

  - incompatible server -> `error` with `设备版本不兼容，需要更新`, without calling `isPaired`;
  - discovery `addError(StateError('boom'))` -> `发现过程出错: Bad state: boom`;
  - pair success;
  - `SyncProtocolFailure(pairingRejected)` from pair -> protocol user message;
  - `SyncTransportException('传输失败')` from pair -> transport user message;
  - request returns a new preset -> `received` with deduplicated data;
  - request returns content already removed by a configurable fake facade -> `noNewData`;
  - pairingRequired and pairingRejected request failures -> `forgetCount == 1`, `isPaired == false`, and protocol message;
  - ordinary protocol failure preserves pairing state;
  - transport and unexpected request failures map to their separate messages;
  - toggleCategory clears sensitive confirmation, stale data, and errors;
  - selectAllCategories selects every category and clears transient confirmation/data/errors;
  - resetToConnected clears transient confirmation/data/errors while preserving the server and selected categories.

  Register pairingRequired/pairingRejected through a named case loop so each becomes a separate test. Keep pair protocol failure and pair transport failure as separate tests because their expected exception types and regression reasons differ.

- [ ] **Step 7: Add stale-completion race tests without sleeps**

  Pair race:

  ```dart
  protocol.pairGate = Completer<void>();
  final pairFuture = notifier.pairWithCode('123456');
  notifier.cancelAndReset();
  protocol.pairGate!.complete();
  await pairFuture;
  expect(container.read(syncClientControllerProvider), SyncClientState());
  ```

  Request race follows the same shape with `requestGate`, after connecting and selecting one category. Assert late data does not leave idle state and `clearSessionsCount == 1` after reset. Equality may be used here as the final public state assertion; do not add a separate Equatable test.

- [ ] **Step 8: Run controller and coordinator suites**

  ```powershell
  $Log = Join-Path $env:TEMP 'oh-my-llm-targeted-coverage-udp\task3-sync-controller.log'
  flutter test test/features/sync/application/sync_client_controller_test.dart test/features/sync/application/sync_client_controller_execute_test.dart test/features/sync/application/sync_transport_controller_test.dart --reporter compact 2>&1 |
    Out-File -Encoding utf8 $Log
  $E = $LASTEXITCODE
  Write-Host "EXIT=$E"
  Get-Content -Tail 150 $Log
  if ($E -ne 0) { exit $E }
  ```

  Expected: exit 0; controller state tests use no crypto setup and existing protocol/integration tests remain unchanged.

- [ ] **Step 9: Format, stage-check, and commit**

  ```powershell
  $Files = @(
    'lib/features/sync/application/ports/sync_client_protocol.dart',
    'lib/features/sync/application/sync_client_protocol_coordinator.dart',
    'lib/features/sync/application/sync_client_controller.dart',
    'test/features/sync/application/sync_test_fakes.dart',
    'test/features/sync/application/sync_client_controller_test.dart'
  )
  dart format $Files
  git add -- $Files
  dart format --output=none --set-exit-if-changed $Files
  git commit -m "refactor(sync): 解耦客户端协议状态测试"
  ```

---

### Task 4: Add HTTP Sync Client Transport Boundary Tests

**Files:**
- Create: `test/features/sync/data/http_sync_client_transport_test.dart`
- Test: `lib/features/sync/data/http_sync_client_transport.dart`

**Interfaces:**
- Consumes: `HttpSyncClientTransport.send`, `MockClient`, `SyncProtocolCodec`, typed Sync messages.
- Produces: direct success, decode, protocol, HTTP status, request-correlation, timeout, and generic network error mapping coverage.

- [ ] **Step 1: Create typed request/response fixtures and a transport helper**

  Use:

  ```dart
  const server = DiscoveredServer(
    deviceName: '服务器',
    ip: '127.0.0.1',
    httpPort: 8080,
    serverId: 'server-1',
  );
  const request = PairingChallengeRequest(
    requestId: 'request-1',
    clientIdentity: 'client-1',
  );

  PairingChallengeResponse response({String requestId = 'request-1'}) =>
      PairingChallengeResponse(
        requestId: requestId,
        pairingId: 'pairing-1',
        challengeNonce: 'bm9uY2U=',
        serverIdentity: 'server-1',
      );
  ```

  Create each transport with a `MockClient`. Assert POST path `/sync`, content type, and decoded request only in the success test; other tests focus on their distinct outcome.

- [ ] **Step 2: Add success and response decision tests**

  Implement the success test exactly as follows:

  ```dart
  test('合法响应返回匹配 requestId 的 typed message', () async {
    final expected = response();
    final client = MockClient((incoming) async {
      expect(incoming.method, 'POST');
      expect(incoming.url.path, '/sync');
      expect(incoming.headers['Content-Type'], 'application/json');
      final decoded = SyncProtocolCodec.decode(incoming.body);
      expect(decoded, isA<SyncProtocolDecodeSuccess>());
      expect((decoded as SyncProtocolDecodeSuccess).message, request);
      return http.Response(
        SyncProtocolCodec.encode(expected),
        200,
        headers: const {'Content-Type': 'application/json'},
      );
    });
    addTearDown(client.close);

    final result = await HttpSyncClientTransport(client).send(
      server: server,
      request: request,
    );

    expect(result, expected);
  });
  ```

  Add four further independent tests named `malformed body 映射为公开格式错误`, `typed protocol error 保持 SyncProtocolFailure 类型`, `非 2xx typed response 映射 HTTP 状态错误`, and `响应 requestId 不匹配时拒绝响应`. Return respectively invalid JSON with status 200, an encoded `SyncProtocolError` with status 200, an encoded matching response with status 503, and an encoded success response using `requestId: 'other-request'` with status 200.

  For the protocol-error test encode:

  ```dart
  const SyncProtocolError(
    requestId: 'request-1',
    failure: SyncProtocolFailure(SyncProtocolErrorCode.pairingRejected),
  )
  ```

  Assert exact stable `userMessage` values, not stack traces or exception implementation fields.

- [ ] **Step 3: Add immediate timeout and network exception mappings**

  Use `MockClient((_) => throw TimeoutException('synthetic'))` and assert `SyncTransportException.userMessage == '请求超时，请检查网络连接'` with a TimeoutException cause. Use a separate `StateError('offline')` case and assert the public message contains `同步失败` and `offline`.

  These tests must complete immediately; never wait for the production 30-second Future timeout.

- [ ] **Step 4: Run, format, and commit**

  ```powershell
  $File = 'test/features/sync/data/http_sync_client_transport_test.dart'
  dart format $File
  $Log = Join-Path $env:TEMP 'oh-my-llm-targeted-coverage-udp\task4-http-transport.log'
  flutter test $File --reporter compact 2>&1 | Out-File -Encoding utf8 $Log
  $E = $LASTEXITCODE
  Write-Host "EXIT=$E"
  Get-Content -Tail 150 $Log
  if ($E -ne 0) { exit $E }
  git add -- $File
  dart format --output=none --set-exit-if-changed $File
  git commit -m "test(sync): 覆盖客户端 HTTP 错误映射"
  ```

---

### Task 5: Replace Environment-Dependent Video Thumbnail Coverage

**Files:**
- Modify: `test/features/media/data/media_thumbnail_generator_test.dart`
- Test: `lib/features/media/data/media_thumbnail_generator.dart`
- Consume: `lib/features/media/data/thumbnail_process_runner.dart`

**Interfaces:**
- Consumes: existing `ThumbnailProcessRunner.run` seam.
- Produces: deterministic video seek, capability-cache, ffprobe, ffmpeg, and process-error contracts independent of host ffmpeg installation.

- [ ] **Step 1: Add a scripted process runner**

  Define:

  ```dart
  final class _ProcessCall {
    const _ProcessCall(this.executable, this.arguments, this.stdoutEncoding);
    final String executable;
    final List<String> arguments;
    final Encoding? stdoutEncoding;
  }

  final class _ScriptedProcessRunner implements ThumbnailProcessRunner {
    final calls = <_ProcessCall>[];
    final responses = <Future<ThumbnailProcessResult> Function()>[];

    void enqueue(ThumbnailProcessResult result) {
      responses.add(() async => result);
    }

    void enqueueError(Object error) {
      responses.add(() => Future<ThumbnailProcessResult>.error(error));
    }

    @override
    Future<ThumbnailProcessResult> run(
      String executable,
      List<String> arguments, {
      Encoding? stdoutEncoding,
    }) {
      calls.add(_ProcessCall(executable, List.of(arguments), stdoutEncoding));
      return responses.removeAt(0)();
    }
  }
  ```

  In `setUp`, create `_ScriptedProcessRunner` and pass it explicitly to `MediaThumbnailGenerator(scanner: scanner, processRunner: runner)`. The video group must never construct a generator with the default process runner.

  Add imports for `dart:convert` and `thumbnail_process_runner.dart`.

- [ ] **Step 2: Replace the ambiguous fake-video test with successful deterministic calls**

  For a short video, enqueue successful `ffmpeg -version`, `ffprobe -version`, duration `8.0`, and JPEG bytes. Assert the extraction call contains `-ss`, `4.0`, uses `stdoutEncoding: null`, and returns bytes.

  Generate a second video through the same generator, enqueue only duration `20.0` and JPEG bytes, assert seek `5.0`, and assert version commands occurred exactly once across both generations. This protects both seek branches and success caching in one coherent lifecycle.

- [ ] **Step 3: Add named ffprobe/ffmpeg failure matrices**

  Register separate tests for these public outcomes:

  - ffmpeg or ffprobe version command returns non-zero -> `ffmpeg 未安装，无法生成视频缩略图`;
  - version command throws `ProcessException` -> `ffmpeg 未安装或无法启动`;
  - version command throws another Exception -> `ffmpeg 检测失败`;
  - ffprobe returns non-zero -> `无法获取视频时长`;
  - ffprobe outputs `abc`, `0`, or `-1` -> `无法解析视频时长`, registered through named data cases;
  - ffmpeg extraction returns non-zero with String stderr -> exit code and text appear in the exception;
  - ffmpeg extraction returns non-zero with byte stderr -> decoded text appears;
  - ffmpeg extraction returns empty stdout -> `ffmpeg 未输出数据`.

  Each test scripts the minimum commands needed to reach its branch. Do not accept multiple unrelated exception types in one assertion.

- [ ] **Step 4: Run the media generator suite**

  ```powershell
  $File = 'test/features/media/data/media_thumbnail_generator_test.dart'
  dart format $File
  $Log = Join-Path $env:TEMP 'oh-my-llm-targeted-coverage-udp\task5-media-thumbnail.log'
  flutter test $File --reporter compact 2>&1 | Out-File -Encoding utf8 $Log
  $E = $LASTEXITCODE
  Write-Host "EXIT=$E"
  Get-Content -Tail 150 $Log
  if ($E -ne 0) { exit $E }
  ```

  Expected: exit 0 on machines with or without ffmpeg; no test launches a real external process.

- [ ] **Step 5: Stage-check and commit**

  ```powershell
  git add -- test/features/media/data/media_thumbnail_generator_test.dart
  dart format --output=none --set-exit-if-changed test/features/media/data/media_thumbnail_generator_test.dart
  git commit -m "test(media): 固化视频缩略图进程边界"
  ```

---

### Task 6: Extract and Test the UDP Announcement Codec

**Files:**
- Create: `lib/features/sync/data/sync_udp_announcement_codec.dart`
- Create: `test/features/sync/data/sync_udp_announcement_codec_test.dart`
- Modify: `lib/features/sync/data/sync_udp_discovery.dart`

**Interfaces:**
- Consumes: UDP v3 envelope fields and `DiscoveredServer`.
- Produces: `const SyncUdpAnnouncementCodec`, `encode`, and nullable `decode` exactly as specified; discovery delegates wire encoding/validation to it.

- [ ] **Step 1: Write codec tests before the codec exists**

  Add a valid round-trip test:

  ```dart
  const codec = SyncUdpAnnouncementCodec();
  final bytes = codec.encode(
    httpPort: 54321,
    deviceName: 'Test-PC',
    serverId: 'server-1',
  );
  final server = codec.decode(data: bytes, sourceAddress: '127.0.0.1');
  expect(server?.deviceName, 'Test-PC');
  expect(server?.httpPort, 54321);
  expect(server?.serverId, 'server-1');
  expect(server?.ip, '127.0.0.1');
  expect(server?.protocolRange, SyncProtocolRange.local);
  ```

  Register raw-JSON reject cases for non-map JSON, wrong app, wrong version, missing/non-int minimum or maximum, minimum zero, maximum below minimum, port 0/65536/non-int, empty server ID, and blank device name. Include invalid UTF-8 and invalid JSON byte cases. Every case expects `null` and has a diagnostic name.

- [ ] **Step 2: Run the codec test to verify red**

  ```powershell
  $Log = Join-Path $env:TEMP 'oh-my-llm-targeted-coverage-udp\task6-codec-red.log'
  flutter test test/features/sync/data/sync_udp_announcement_codec_test.dart --reporter compact 2>&1 |
    Out-File -Encoding utf8 $Log
  $E = $LASTEXITCODE
  Write-Host "EXIT=$E"
  Get-Content -Tail 150 $Log
  if ($E -eq 0) { throw 'Expected missing SyncUdpAnnouncementCodec failure' }
  ```

- [ ] **Step 3: Implement the pure codec**

  Implement `encode` with the existing exact envelope and `decode` with a single guarded parse. Return `null` for every validation failure; construct `DiscoveredServer` only after all fields validate. Use `SyncProtocolVersionPolicy.current` and `SyncProtocolRange.local` rather than duplicating numeric protocol constants where possible, while preserving the encoded value 3.

  The file imports only `dart:convert` and Sync domain models. It must not import Flutter, Riverpod, sockets, timers, MethodChannel, or logging.

- [ ] **Step 4: Delegate existing discovery code to the codec**

  Add a static const codec in the current discovery class. Replace its inline `jsonEncode` payload construction with `codec.encode`. Replace its listener JSON parse/validation block with:

  ```dart
  final server = _codec.decode(
    data: datagram.data,
    sourceAddress: datagram.address.address,
  );
  if (server == null) return;
  controller.add(server);
  resetTimeout();
  ```

  Preserve existing socket, timer, logging, and lock behavior in this task.

- [ ] **Step 5: Run codec and real UDP tests**

  ```powershell
  $Log = Join-Path $env:TEMP 'oh-my-llm-targeted-coverage-udp\task6-codec-green.log'
  flutter test test/features/sync/data/sync_udp_announcement_codec_test.dart test/features/sync/data/sync_udp_discovery_test.dart --reporter compact 2>&1 |
    Out-File -Encoding utf8 $Log
  $E = $LASTEXITCODE
  Write-Host "EXIT=$E"
  Get-Content -Tail 150 $Log
  if ($E -ne 0) { exit $E }
  ```

- [ ] **Step 6: Format, stage-check, and commit**

  ```powershell
  $Files = @(
    'lib/features/sync/data/sync_udp_announcement_codec.dart',
    'lib/features/sync/data/sync_udp_discovery.dart',
    'test/features/sync/data/sync_udp_announcement_codec_test.dart'
  )
  dart format $Files
  git add -- $Files
  dart format --output=none --set-exit-if-changed $Files
  git commit -m "refactor(sync): 提取 UDP 公告编解码边界"
  ```

---

### Task 7: Add Deterministic UDP Runtime and Lifecycle Sessions

**Files:**
- Create: `lib/features/sync/data/sync_udp_socket.dart`
- Create: `lib/features/sync/data/sync_udp_scheduler.dart`
- Create: `lib/features/sync/data/sync_multicast_lock.dart`
- Create: `lib/features/sync/data/sync_udp_sessions.dart`
- Create: `test/features/sync/data/sync_udp_test_fakes.dart`
- Create: `test/features/sync/data/sync_udp_discovery_lifecycle_test.dart`
- Modify: `lib/features/sync/data/sync_udp_discovery.dart`

**Interfaces:**
- Consumes: `SyncUdpAnnouncementCodec`, `RawDatagramSocket`, `Timer`, current multicast MethodChannel.
- Produces: socket/factory, scheduler/task, multicast-lock, broadcast/listen session interfaces; `SyncUdpDiscovery.system`; injectable discovery constructor; deterministic lifecycle tests.

- [ ] **Step 1: Add the public runtime interfaces**

  Create `sync_udp_socket.dart` with:

  ```dart
  import 'dart:io';

  final class SyncUdpDatagram {
    const SyncUdpDatagram({
      required this.data,
      required this.address,
      required this.port,
    });

    final List<int> data;
    final InternetAddress address;
    final int port;
  }

  abstract interface class SyncUdpSocket {
    Stream<SyncUdpDatagram> get datagrams;
    int get port;
    set broadcastEnabled(bool value);
    int send(List<int> data, InternetAddress address, int port);
    Future<void> close();
  }

  abstract interface class SyncUdpSocketFactory {
    Future<SyncUdpSocket> bind(InternetAddress address, int port);
  }
  ```

  Create `sync_udp_scheduler.dart` with:

  ```dart
  abstract interface class SyncUdpScheduledTask {
    bool get isActive;
    void cancel();
  }

  abstract interface class SyncUdpScheduler {
    SyncUdpScheduledTask schedule(
      Duration delay,
      void Function() callback,
    );

    SyncUdpScheduledTask periodic(
      Duration interval,
      void Function() callback,
    );
  }
  ```

  Create `sync_multicast_lock.dart` with:

  ```dart
  abstract interface class SyncMulticastLock {
    Future<void> acquire();
    Future<void> release();
  }
  ```

  Create `sync_udp_sessions.dart` with:

  ```dart
  import '../domain/models/discovered_server.dart';

  abstract interface class SyncUdpBroadcastSession {
    Future<void> stop();
    Future<void> get done;
  }

  abstract interface class SyncUdpListenSession {
    Stream<DiscoveredServer> get servers;
    Future<void> get ready;
    int get port;
    Future<void> close();
    Future<void> get done;
  }
  ```

  Keep private session implementations in `sync_udp_discovery.dart`; no implementation type is exported.

  Production adapters:

  - `const RawSyncUdpSocketFactory()` binds with `RawDatagramSocket.bind(address, port)`, wraps read events as `SyncUdpDatagram`, exposes `socket.port`, forwards broadcast/send, and closes idempotently.
  - `const TimerSyncUdpScheduler()` returns a small Timer-backed task for one-shot and periodic schedules.
  - `const PlatformSyncMulticastLock()` owns the existing channel name and preserves the current Android-only, log-and-continue behavior.

- [ ] **Step 2: Add manual fakes used only by data tests**

  In `sync_udp_test_fakes.dart`, implement:

  ```dart
  final class ManualSyncUdpTask implements SyncUdpScheduledTask {
    ManualSyncUdpTask(
      this.delay,
      this._callback, {
      required this.repeating,
    });
    final Duration delay;
    final void Function() _callback;
    final bool repeating;
    var _active = true;
    @override
    bool get isActive => _active;
    void fire() {
      if (!_active) return;
      if (!repeating) _active = false;
      _callback();
    }
    @override
    void cancel() => _active = false;
  }

  final class ManualSyncUdpScheduler implements SyncUdpScheduler {
    final oneShotTasks = <ManualSyncUdpTask>[];
    final periodicTasks = <ManualSyncUdpTask>[];

    @override
    SyncUdpScheduledTask schedule(
      Duration delay,
      void Function() callback,
    ) {
      final task = ManualSyncUdpTask(
        delay,
        callback,
        repeating: false,
      );
      oneShotTasks.add(task);
      return task;
    }

    @override
    SyncUdpScheduledTask periodic(
      Duration interval,
      void Function() callback,
    ) {
      final task = ManualSyncUdpTask(
        interval,
        callback,
        repeating: true,
      );
      periodicTasks.add(task);
      return task;
    }
  }
  ```

  Also implement:

  - `FakeSyncUdpSocket` with a StreamController, sent-datagram records, `port`, broadcast flag, idempotent close count, `emit`, and `emitError`;
  - `QueuedSyncUdpSocketFactory` whose queue returns sockets or throws scripted bind errors and records requested address/port;
  - `RecordingSyncMulticastLock` with acquire/release counts and optional acquire/release errors.

  All StreamControllers expose explicit `close()` and are registered with test teardown.

- [ ] **Step 3: Write failing broadcaster lifecycle tests**

  Instantiate `SyncUdpDiscovery` with the fakes and add:

  ```dart
  test('广播立即发送、周期触发后再发送、stop 后不再发送', () async {
    final session = await discovery.startBroadcasting(
      httpPort: 54321,
      deviceName: 'Test-PC',
      serverId: 'server-1',
      broadcastAddress: InternetAddress.loopbackIPv4,
      discoveryPort: 48001,
    );

    expect(socket.sent, hasLength(1));
    scheduler.periodicTasks.single.fire();
    expect(socket.sent, hasLength(2));
    await session.stop();
    scheduler.periodicTasks.single.fire();
    expect(socket.sent, hasLength(2));
    await session.done;
  });
  ```

  Add a second test that calls `stop()` twice and asserts socket close and lock release each occurred once.

- [ ] **Step 4: Run broadcaster tests to verify red**

  ```powershell
  $Log = Join-Path $env:TEMP 'oh-my-llm-targeted-coverage-udp\task7-broadcast-red.log'
  flutter test test/features/sync/data/sync_udp_discovery_lifecycle_test.dart --plain-name "广播" --reporter compact 2>&1 |
    Out-File -Encoding utf8 $Log
  $E = $LASTEXITCODE
  Write-Host "EXIT=$E"
  Get-Content -Tail 150 $Log
  if ($E -eq 0) { throw 'Expected failure before injectable UDP sessions exist' }
  ```

- [ ] **Step 5: Refactor broadcasting to an injectable service and session**

  Give `SyncUdpDiscovery` the constructor and `system` instance from the spec. Add `defaultDiscoveryPort = 47280`. `startBroadcasting`:

  1. acquires the lock;
  2. binds `anyIPv4` port zero through the factory;
  3. enables broadcast;
  4. encodes once;
  5. sends immediately;
  6. schedules periodic sends;
  7. returns an idempotent session whose cleanup cancels the periodic task, closes the socket, releases the lock, and completes `done`.

  If bind fails after lock acquisition, release the lock before rethrowing. Preserve send-error logging without terminating the session.

- [ ] **Step 6: Run broadcaster tests to green**

  Run the same command as Step 4. Expected: exit 0 and no real-time wait.

- [ ] **Step 7: Add listener lifecycle tests before implementing the session**

  Add these tests using Completers and explicit fake events:

  - `ready` completes after bind and exposes fake socket port;
  - a valid codec datagram emits one server, cancels the old one-shot task, and creates a replacement deadline;
  - malformed bytes emit no server and leave the original deadline active;
  - firing the active deadline closes socket/stream, releases lock, and completes `done`;
  - cancelling the stream after bind closes resources once;
  - calling `close()` before a delayed bind future completes makes `ready` throw `StateError('UDP 监听已关闭')`, then closes the subsequently returned socket without publishing events;
  - bind failure completes `ready` with the bind error, closes the server stream, releases the lock, and completes `done`.

  For the delayed-bind case, register `expectLater(session.ready, throwsA(isA<StateError>()))` before calling `close()`, then complete the queued `Completer<SyncUdpSocket>`; do not use time. For bind failure, register the `ready` error expectation before completing the scripted bind future so the Future error is always observed.

- [ ] **Step 8: Run listener tests to verify red**

  ```powershell
  $Log = Join-Path $env:TEMP 'oh-my-llm-targeted-coverage-udp\task7-listener-red.log'
  flutter test test/features/sync/data/sync_udp_discovery_lifecycle_test.dart --plain-name "监听" --reporter compact 2>&1 |
    Out-File -Encoding utf8 $Log
  $E = $LASTEXITCODE
  Write-Host "EXIT=$E"
  Get-Content -Tail 150 $Log
  if ($E -eq 0) { throw 'Expected listener lifecycle failures before session implementation' }
  ```

- [ ] **Step 9: Implement listener session lifecycle**

  `listenForServers` returns synchronously with a session and starts async acquisition/bind internally. Implement one shared idempotent cleanup Future. The session's stream controller `onCancel` calls cleanup. Only decoded non-null announcements add to the stream and replace the one-shot deadline.

  Enforce these exact completion rules:

  - successful bind -> set port -> complete `ready`;
  - close-before-bind -> complete `ready` with `StateError('UDP 监听已关闭')`; after bind resolves, close socket and complete `done`;
  - bind error while active -> complete `ready` with error, close stream, release lock, complete `done`;
  - timeout -> close stream through shared cleanup;
  - repeated timeout/cancel/close -> reuse cleanup Future and release once.

- [ ] **Step 10: Run all fake-runtime lifecycle tests**

  ```powershell
  $Log = Join-Path $env:TEMP 'oh-my-llm-targeted-coverage-udp\task7-lifecycle-green.log'
  flutter test test/features/sync/data/sync_udp_discovery_lifecycle_test.dart --reporter compact 2>&1 |
    Out-File -Encoding utf8 $Log
  $E = $LASTEXITCODE
  Write-Host "EXIT=$E"
  Get-Content -Tail 150 $Log
  if ($E -ne 0) { exit $E }
  ```

  Expected: exit 0; the lifecycle test file contains no `Future.delayed` or real socket.

- [ ] **Step 11: Format, stage-check, and commit**

  ```powershell
  $Files = @(
    'lib/features/sync/data/sync_udp_socket.dart',
    'lib/features/sync/data/sync_udp_scheduler.dart',
    'lib/features/sync/data/sync_multicast_lock.dart',
    'lib/features/sync/data/sync_udp_sessions.dart',
    'lib/features/sync/data/sync_udp_discovery.dart',
    'test/features/sync/data/sync_udp_test_fakes.dart',
    'test/features/sync/data/sync_udp_discovery_lifecycle_test.dart'
  )
  dart format $Files
  git add -- $Files
  dart format --output=none --set-exit-if-changed $Files
  git commit -m "refactor(sync): 注入 UDP 运行时生命周期"
  ```

---

### Task 8: Wire UDP Sessions and Replace Real-Time UDP Tests

**Files:**
- Modify: `lib/features/sync/data/http_udp_sync_server_transport.dart`
- Modify: `lib/features/sync/data/http_sync_client_transport.dart`
- Modify: `test/features/sync/data/sync_udp_discovery_test.dart`
- Modify: `test/architecture/test_resilience_policy_test.dart`
- Verify: `lib/app/composition/cross_feature_bindings.dart`

**Interfaces:**
- Consumes: `SyncUdpDiscovery.system`, `SyncUdpBroadcastSession`, `SyncUdpListenSession`.
- Produces: transport ownership of sessions; one real loopback smoke with no intentional delay; empty UDP Future.delayed allowlist.

- [ ] **Step 1: Inject discovery into concrete transports**

  Change the client constructor to:

  ```dart
  HttpSyncClientTransport(
    this._client, {
    SyncUdpDiscovery? discovery,
  }) : _discovery = discovery ?? SyncUdpDiscovery.system;

  final SyncUdpDiscovery _discovery;

  @override
  Stream<DiscoveredServer> discoverServers() async* {
    final session = _discovery.listenForServers();
    try {
      await session.ready;
      yield* session.servers;
    } finally {
      await session.close();
    }
  }
  ```

  Change the server transport to accept the same optional discovery, store `SyncUdpBroadcastSession?`, and await `stop()` before HTTP shutdown. Keep repeated `stop()` safe and preserve UDP-before-HTTP order. Existing app composition continues calling default constructors and requires no data/application import change.

- [ ] **Step 2: Rewrite the tagged UDP file to one loopback smoke**

  Replace both existing tests and all three `Future.delayed` calls with:

  ```dart
  test('loopback listener 能收到 system broadcaster 的真实 UDP 公告', () async {
    final discovery = SyncUdpDiscovery.system;
    final listener = discovery.listenForServers(
      bindAddress: InternetAddress.loopbackIPv4,
      discoveryPort: 0,
      timeout: const Duration(seconds: 2),
    );
    SyncUdpBroadcastSession? broadcaster;
    addTearDown(() async {
      await broadcaster?.stop();
      await listener.close();
      await listener.done;
    });

    await listener.ready;
    final received = listener.servers.firstWhere(
      (server) => server.serverId == 'udp-loopback-smoke',
    ).timeout(const Duration(seconds: 2));

    broadcaster = await discovery.startBroadcasting(
      httpPort: 54321,
      deviceName: 'Test-PC',
      serverId: 'udp-loopback-smoke',
      broadcastAddress: InternetAddress.loopbackIPv4,
      discoveryPort: listener.port,
      broadcastInterval: const Duration(minutes: 1),
    );

    final server = await received;
    expect(server.deviceName, 'Test-PC');
    expect(server.httpPort, 54321);
    expect(server.ip, InternetAddress.loopbackIPv4.address);
  });
  ```

  Keep `@Tags(['udp'])` and update the file comment to describe a loopback smoke and the CI exclusion. The two-second `timeout` is only a failure bound and is not forbidden.

- [ ] **Step 3: Remove the resilience allowlist exception**

  Change:

  ```dart
  const _futureDelayedAllow = <String, int>{};
  ```

  Update its comment to state that no real `Future.delayed` is allowed in the test tree. Do not weaken `_verifyExactAllow` or the lexical scanner.

- [ ] **Step 4: Run resilience, real UDP, and Sync suites**

  ```powershell
  $Dir = Join-Path $env:TEMP 'oh-my-llm-targeted-coverage-udp'

  foreach ($Target in @(
    'test/architecture/test_resilience_policy_test.dart',
    'test/features/sync/data/sync_udp_discovery_test.dart',
    'test/features/sync'
  )) {
    $Name = ($Target -replace '[\\/:]', '-')
    $Log = Join-Path $Dir "task8-$Name.log"
    flutter test $Target --reporter compact 2>&1 | Out-File -Encoding utf8 $Log
    $E = $LASTEXITCODE
    Write-Host "TARGET=$Target EXIT=$E"
    Get-Content -Tail 150 $Log
    if ($E -ne 0) { exit $E }
  }
  ```

  Expected: resilience test finds zero delayed calls; the real UDP file executes one case; all Sync tests pass.

- [ ] **Step 5: Measure three warm UDP runs without adding a performance assertion**

  ```powershell
  $Measurements = @()
  1..3 | ForEach-Object {
    $Run = $_
    $Log = Join-Path $env:TEMP "oh-my-llm-targeted-coverage-udp\after-udp-$Run.log"
    $Timer = [System.Diagnostics.Stopwatch]::StartNew()
    flutter test test/features/sync/data/sync_udp_discovery_test.dart --reporter compact 2>&1 |
      Out-File -Encoding utf8 $Log
    $E = $LASTEXITCODE
    $Timer.Stop()
    if ($E -ne 0) { Get-Content -Tail 150 $Log; exit $E }
    $Measurements += $Timer.Elapsed.TotalSeconds
    Write-Host ("RUN={0} ELAPSED_SECONDS={1:N3}" -f $Run, $Timer.Elapsed.TotalSeconds)
  }
  $Sorted = $Measurements | Sort-Object
  Write-Host ("MEDIAN_SECONDS={0:N3}" -f $Sorted[1])
  ```

  Report the median and compare it to the captured baseline. Do not fail the suite on a wall-clock threshold.

- [ ] **Step 6: Format, stage-check, and commit**

  ```powershell
  $Files = @(
    'lib/features/sync/data/http_udp_sync_server_transport.dart',
    'lib/features/sync/data/http_sync_client_transport.dart',
    'test/features/sync/data/sync_udp_discovery_test.dart',
    'test/architecture/test_resilience_policy_test.dart'
  )
  dart format $Files
  git add -- $Files
  dart format --output=none --set-exit-if-changed $Files
  git commit -m "test(sync): 移除 UDP 真实等待"
  ```

---

### Task 9: Coverage Audit and Repository Verification

**Files:**
- Verify all files listed in Tasks 1-8.
- Compare: `%TEMP%\oh-my-llm-targeted-coverage-udp\baseline-lcov.info`
- Generate: `coverage/lcov.info` and temporary after-run logs.
- Do not commit: `coverage/`, `fltest*.log`, or temporary reports.

**Interfaces:**
- Consumes: completed test/production changes and repository gates.
- Produces: fresh formatting, architecture, analyzer, targeted coverage, full-suite, and timing evidence plus a line-level targeted coverage classification.

- [ ] **Step 1: Format all changed Dart files and verify staged formatting**

  ```powershell
  $Changed = git diff --name-only --diff-filter=ACM -- '*.dart'
  if ($Changed) {
    dart format $Changed
    dart format --output=none --set-exit-if-changed $Changed
  }
  $Staged = git diff --cached --name-only --diff-filter=ACM -- '*.dart'
  if ($Staged) {
    dart format --output=none --set-exit-if-changed $Staged
  }
  ```

- [ ] **Step 2: Run architecture and analyzer gates**

  ```powershell
  dart run tool/check_import_boundaries.dart
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

  flutter analyze 2>&1 | Out-File -Encoding utf8 flanalyze.log
  $E = $LASTEXITCODE
  Write-Host "EXIT=$E"
  Get-Content -Tail 150 flanalyze.log
  if ($E -ne 0) { exit $E }
  ```

- [ ] **Step 3: Run Settings, Media, Sync, and resilience scopes**

  ```powershell
  $Log = Join-Path $env:TEMP 'oh-my-llm-targeted-coverage-udp\after-scoped.log'
  flutter test test/features/settings test/features/media test/features/sync test/architecture/test_resilience_policy_test.dart --reporter compact 2>&1 |
    Out-File -Encoding utf8 $Log
  $E = $LASTEXITCODE
  Write-Host "EXIT=$E"
  Get-Content -Tail 150 $Log
  if ($E -ne 0) { exit $E }
  ```

- [ ] **Step 4: Generate fresh CI-equivalent coverage**

  ```powershell
  $Log = Join-Path $env:TEMP 'oh-my-llm-targeted-coverage-udp\after-coverage.log'
  $Timer = [System.Diagnostics.Stopwatch]::StartNew()
  flutter test --exclude-tags=udp --coverage --reporter compact 2>&1 |
    Out-File -Encoding utf8 $Log
  $E = $LASTEXITCODE
  $Timer.Stop()
  Write-Host "EXIT=$E"
  Write-Host ("ELAPSED_SECONDS={0:N3}" -f $Timer.Elapsed.TotalSeconds)
  Get-Content -Tail 150 $Log
  if ($E -ne 0) { exit $E }
  Copy-Item coverage\lcov.info (Join-Path $env:TEMP 'oh-my-llm-targeted-coverage-udp\after-lcov.info') -Force
  ```

- [ ] **Step 5: Compare targeted LCOV lines and classify changes**

  Use this PowerShell reader:

  ```powershell
  function Read-Lcov([string]$Path) {
    $Files = @{}
    $Current = $null
    foreach ($Line in Get-Content $Path) {
      if ($Line.StartsWith('SF:')) {
        $Current = $Line.Substring(3).Replace('\', '/')
        $Files[$Current] = @{}
      } elseif ($Current -and $Line.StartsWith('DA:')) {
        $Pair = $Line.Substring(3).Split(',')
        $Files[$Current][[int]$Pair[0]] = [int]$Pair[1]
      } elseif ($Line -eq 'end_of_record') {
        $Current = $null
      }
    }
    return $Files
  }

  $Dir = Join-Path $env:TEMP 'oh-my-llm-targeted-coverage-udp'
  $Before = Read-Lcov (Join-Path $Dir 'baseline-lcov.info')
  $After = Read-Lcov (Join-Path $Dir 'after-lcov.info')
  $Targets = @(
    'lib/features/sync/data/secure_sync_pairing_repository.dart',
    'lib/features/settings/application/settings_transfer_workflow.dart',
    'lib/features/sync/application/sync_client_controller.dart',
    'lib/features/sync/data/http_sync_client_transport.dart',
    'lib/features/media/data/media_thumbnail_generator.dart',
    'lib/features/sync/data/sync_udp_discovery.dart'
  )

  foreach ($Target in $Targets) {
    $BeforeLines = $Before[$Target]
    $AfterLines = $After[$Target]
    $BeforeHit = @($BeforeLines.GetEnumerator() | Where-Object Value -gt 0).Count
    $AfterHit = @($AfterLines.GetEnumerator() | Where-Object Value -gt 0).Count
    $AfterFound = $AfterLines.Count
    Write-Host "$Target BEFORE_HIT=$BeforeHit AFTER_HIT=$AfterHit AFTER_FOUND=$AfterFound"
    foreach ($Entry in $BeforeLines.GetEnumerator()) {
      if ($Entry.Value -gt 0 -and $AfterLines[$Entry.Key] -eq 0) {
        Write-Host "HIT_TO_MISS $Target:$($Entry.Key)"
      }
    }
  }
  ```

  Classify every hit-to-miss line as moved/extracted code, incidental execution, or lost contract. A lost external contract blocks completion and requires restoring a focused test. New files are summarized from the after snapshot because they have no baseline record.

- [ ] **Step 6: Run the full suite including UDP with the mandated command**

  ```powershell
  flutter test --reporter compact 2>&1 | Out-File -Encoding utf8 fltest.log
  $E = $LASTEXITCODE
  Write-Host "EXIT=$E"
  Get-Content -Tail 150 fltest.log
  if ($E -ne 0) { exit $E }
  ```

- [ ] **Step 7: Audit resilience tokens and changed paths**

  ```powershell
  rg -n "Future(?:<[^>]+>)?\.delayed|pumpAndSettle|find\.byKey|chunkDelay" test
  $BaselineHead = (Get-Content (Join-Path $env:TEMP 'oh-my-llm-targeted-coverage-udp\baseline-head.txt')).Trim()
  git diff --check
  git diff --check $BaselineHead HEAD
  git status --short
  git diff --stat $BaselineHead HEAD
  git diff --name-only $BaselineHead HEAD
  ```

  Expected token audit: only scanner fixture strings/comments and the one approved animation helper settle appear; no executable `Future.delayed` remains. Changed production files are limited to the protocol seam and UDP data/transport files; changed tests are limited to the named Settings, Media, Sync, and resilience files plus the two documentation files.

- [ ] **Step 8: Commit any final verification-only corrections and documentation when authorized**

  If verification required code/test corrections, commit them with the narrowest accurate semantic message after rerunning their focused test. When documentation commits are authorized, stage only:

  ```powershell
  git add -- docs/superpowers/specs/2026-08-11-targeted-coverage-and-deterministic-udp-design.md docs/superpowers/plans/2026-08-11-targeted-coverage-and-deterministic-udp.md
  git commit -m "docs: 记录定向覆盖与 UDP 测试方案"
  ```

  Do not commit merely to satisfy the plan if the user has not authorized commits.

## Final Handoff Checklist

- [ ] Report before/after executed cases, CI-equivalent wall time, and three-run UDP median.
- [ ] Report before/after line coverage for every targeted existing file and after coverage for new production files.
- [ ] List every hit-to-miss line and its classification; state explicitly if there are none.
- [ ] Report the exact direct contracts added for pairing persistence, settings transfer, controller state, HTTP mapping, media process behavior, UDP codec, and UDP lifecycle.
- [ ] Confirm the real UDP suite contains one tagged loopback smoke and zero intentional sleeps.
- [ ] Confirm `_futureDelayedAllow` is empty and the resilience gate passes.
- [ ] Confirm production UDP defaults, Sync v3, Settings v7, user-visible messages, and trust-domain wiring are unchanged.
- [ ] Report focused tests, architecture checker, analyzer, CI-equivalent coverage suite, full suite, format check, and `git diff --check` with exit codes.
- [ ] List commits only if they were actually created; otherwise state that changes remain uncommitted.
