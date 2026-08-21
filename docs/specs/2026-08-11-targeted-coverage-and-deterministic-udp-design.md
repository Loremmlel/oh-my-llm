# Targeted Coverage and Deterministic UDP Testing Design

## Goal

Strengthen regression protection around the currently under-tested settings transfer, Sync security/persistence, Sync client state, HTTP transport, and media thumbnail boundaries, while replacing the real-time UDP lifecycle waits with deterministic socket/scheduler tests and retaining one real loopback smoke test.

The work optimizes for externally observable contracts, not raw test count or a target coverage percentage. Production behavior, wire formats, persistence formats, CI concurrency, and timeouts remain unchanged.

## Verified Baseline

The baseline was measured on Windows with Flutter 3.44.8, Dart 3.12.2, and the repository-configured concurrency of 8. CI remains pinned to Flutter 3.44.6, so absolute hosted timing may differ slightly.

| Scope | Executed cases | Test-runner time | Wall time |
|---|---:|---:|---:|
| Full suite, including UDP | 1,360 | 37s | 41.96s |
| CI-equivalent, excluding UDP with coverage | 1,358 | 60s | 64.22s |
| `test/features/sync/data/sync_udp_discovery_test.dart` | 2 | 5s | 9.12s |
| `test/features/chat/chat_screen_test.dart` | 56 | 20s | 24.38s |
| `test/features/settings/settings_screen_test.dart` | 30 | 10s | 13.77s |

The current LCOV snapshot contains line data only; it has no branch (`BRDA`) or function (`FN`) records.

| Coverage scope | Hit lines | Found lines | Line coverage |
|---|---:|---:|---:|
| All production files | 12,764 | 14,995 | 85.12% |
| Application/data focus | 4,628 | 5,301 | 87.30% |
| Sync application/data | 707 | 981 | 72.07% |
| Media application/data | 467 | 534 | 87.45% |
| Settings application/data | 657 | 750 | 87.60% |
| Chat application/data | 2,670 | 2,906 | 91.88% |

The main full-suite wall-clock bottlenecks are the large Chat and Settings widget entry files. They are recorded but not changed by this project. The requested performance change is limited to UDP tests.

## Scope

### Included

- Add direct persistence/security coverage for `SecureSyncPairingRepository`.
- Expand `SettingsTransferWorkflow` coverage through table-driven export and import decision tests.
- Add a narrow protocol-operations interface so `SyncClientController` state transitions can be tested without replaying cryptographic wire exchanges.
- Add direct `HttpSyncClientTransport.send` boundary tests with a fake HTTP client.
- Replace the environment-dependent media video-thumbnail test with deterministic `ThumbnailProcessRunner` tests.
- Extract UDP announcement encoding/validation into a pure codec.
- Introduce replaceable UDP socket, scheduler, and multicast-lock boundaries.
- Expose explicit UDP broadcast/listen lifecycle sessions with readiness and completion signals.
- Replace real-time UDP lifecycle assertions with zero-sleep fake-runtime tests.
- Retain one `udp`-tagged real loopback send/receive smoke test.
- Remove the UDP `Future.delayed` exception from the repository resilience allowlist.
- Generate fresh coverage and classify targeted line changes after implementation.

### Excluded

- Handling or simulating an independently running release application that broadcasts or listens on the production discovery port.
- Isolating production and test processes from each other through process IDs, namespaces, or application-instance filtering.
- Splitting `chat_screen_test.dart` or `settings_screen_test.dart` into multiple test-runner entry files.
- Changing `dart_test.yaml`, CI workflow concurrency, global test timeouts, or the CI UDP exclusion policy.
- Adding a global coverage threshold or treating line coverage as the definition of test value.
- Testing Equatable `props`, `copyWith`, framework forwarding, default getters, or concrete Material widget types merely to increase coverage.
- Adding a virtual scheduler for media process timeouts or the background chat repository watchdog. Those branches remain out of scope unless a future product requirement demands deterministic timeout testing.
- Changing Sync protocol version 3, Settings export format 7, pairing data layout, HTTP routes, or persisted keys.

## Test-Selection Standard

For every uncovered area, choose one of these dispositions:

| Situation | Required action |
|---|---|
| An existing test should catch the regression but uses weak or environment-dependent inputs/assertions | Strengthen or replace the existing test |
| A different externally observable outcome, test layer, or expected failure reason is missing | Add an independent test case at the lowest stable layer |
| A high-level test only visits the line incidentally and cannot identify the boundary failure | Add a focused boundary test |
| The line is a getter, equality list, framework adapter forwarding, or unreachable platform detail without a product contract | Record and leave uncovered |

Every new test must identify its trigger, public observable, layer, and expected regression failure reason. Similar setup or overlapping line coverage does not make two contracts duplicates.

## Coverage Workstreams

### Secure pairing repository

`SecureSyncPairingRepository` currently has no direct repository test and covers only 17 of 79 executable lines in the CI-equivalent run. This is a genuine security and persistence gap.

Add repository tests using `SharedPreferences.setMockInitialValues` and a recording/failing `SyncSecureStore`. Protect these contracts:

1. `ensureLocalIdentity` creates an ID from the supplied random bytes once and returns the persisted identity thereafter.
2. `save` writes the secret only to secure storage and writes only non-secret pairing metadata to SharedPreferences.
3. `save` followed by `load`, `loadAll`, and `loadSecret` returns the stored record and secret.
4. Missing or malformed secure secret causes the pairing record to be rejected and stale metadata to be removed.
5. Secure-store write failure triggers cleanup and surfaces the repository's stable `StateError`.
6. `revoke` removes both secret and metadata while preserving unrelated peer records.
7. Malformed versioned metadata is rejected and removed.

Malformed storage input is allowed here because this is explicitly a persistence compatibility and corruption boundary. Tests may seed the stable persisted keys used by the repository.

### Settings transfer workflow

The existing workflow test contains only one provider export case and one tab-mismatch case. Strengthen that file rather than creating a parallel suite.

Register named table cases for:

- each export tab with empty data and populated data;
- prompts containing any of memory, template, or fixed-sequence content;
- invalid clipboard, unsupported version, tab mismatch, fully deduplicated input, and ready input;
- network, output-processing, and other scalar tab matching.

The workflow tests assert only the selected tab's exported fields and the final `SettingsImportPreparationKind`/deduplicated payload. They do not repeat `SettingsExportCodec` migration tests or `SettingsImportDeduplicator` comparator tests.

### Sync client controller

`SyncClientController` currently constructs `SyncClientProtocolCoordinator` directly, forcing controller tests to reproduce pairing proofs, session establishment, encryption, and replay validation before they can observe a simple state transition. Those protocol details are already protected by coordinator and integration tests.

Introduce this application-layer interface:

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

`SyncClientProtocolCoordinator` implements this interface. `SyncClientController` accepts an optional constructor-injected `SyncClientProtocol`; production creates the existing coordinator when no override is supplied. No new global provider is needed, and session ownership remains per controller instance.

Controller tests then use a scripted fake protocol and the existing controllable discovery transport. Protect:

- incompatible discovery result;
- discovery stream error;
- pair success and both protocol/transport failure mappings;
- request success with new data;
- request success with no new data;
- pairing-required/rejected failure revokes the pairing and clears `isPaired`;
- ordinary protocol, transport, and unexpected failures preserve their distinct user messages;
- cancelling/resetting while pair/request work is pending ignores the stale completion;
- category changes and reset clear sensitive confirmation and stale imported data.

Tests wait on Provider state, StreamController events, or Completers. They do not sleep or test cryptographic internals.

### HTTP Sync client transport

Add direct tests for `HttpSyncClientTransport.send` using `package:http/testing.dart` or a small scripted `http.BaseClient`. Protect:

- valid typed response with matching request ID;
- malformed response body;
- typed `SyncProtocolError` response;
- non-2xx response containing an otherwise valid typed message;
- mismatched response request ID;
- a client future that throws `TimeoutException`;
- an ordinary client/network exception.

No real server or 30-second wait is used. A directly thrown `TimeoutException` verifies the transport's error mapping rather than the Dart `Future.timeout` implementation.

### Media thumbnail generator

Replace the current test that accepts either a `ThumbnailException` or `ProcessException` depending on the host environment. Use the existing `ThumbnailProcessRunner` production seam.

The fake runner records executable, arguments, and `stdoutEncoding`, and returns or throws scripted results. Protect:

- short video selects its midpoint;
- video of at least ten seconds selects 5.0 seconds;
- successful ffmpeg/ffprobe availability detection is cached;
- ffprobe non-zero exit and invalid/non-positive duration remain distinct failures;
- ffmpeg non-zero exit preserves string or byte stderr in the public message;
- empty ffmpeg output is rejected;
- `ProcessException`, other process exceptions, and unavailable executable results map to their documented `ThumbnailException` categories.

The existing deterministic image, unsupported-extension, corrupt-image, and missing-file tests remain. Media timeout callbacks are not forced through real waits and receive no new scheduler seam in this project.

## Deterministic UDP Architecture

### Pure announcement codec

Create `SyncUdpAnnouncementCodec` in the Sync data layer. It owns the stable UDP JSON envelope:

- `app == "oh-my-llm"`;
- protocol announcement version 3;
- minimum and maximum protocol version;
- non-empty `deviceName` and `serverId`;
- integer HTTP port in `1..65535`.

Its public operations are:

```dart
final class SyncUdpAnnouncementCodec {
  const SyncUdpAnnouncementCodec();

  List<int> encode({
    required int httpPort,
    required String deviceName,
    required String serverId,
  });

  DiscoveredServer? decode({
    required List<int> data,
    required String sourceAddress,
  });
}
```

Malformed JSON, wrong app/version, non-integer or non-positive protocol bounds, a maximum below the minimum, invalid port, and empty identity/name return `null`. The codec does not log, open sockets, or manage time.

### Socket boundary

Create a data-layer socket adapter that prevents the discovery coordinator from depending directly on `RawSocketEvent` and `Datagram`:

```dart
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

`RawSyncUdpSocketFactory` and its private/raw adapter are the only code that touches `RawDatagramSocket`. Socket close must be idempotent.

### Scheduler boundary

Create a small scheduler instead of importing a test clock into production:

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

The production implementation wraps `Timer`/`Timer.periodic`. Tests use a manual scheduler whose tasks fire only when explicitly advanced or invoked. No new package dependency is required.

### Multicast lock boundary

Move Android MethodChannel handling behind:

```dart
abstract interface class SyncMulticastLock {
  Future<void> acquire();
  Future<void> release();
}
```

`PlatformSyncMulticastLock` preserves the current behavior: no-op outside Android, invoke the existing channel on Android, and log rather than fail discovery when channel acquisition/release throws. Tests use a recording fake to verify balanced lifecycle calls.

### Discovery service and lifecycle sessions

Convert `SyncUdpDiscovery` from a static utility into an injectable data service with a `system` instance backed by the production adapters:

```dart
final class SyncUdpDiscovery {
  SyncUdpDiscovery({
    required SyncUdpSocketFactory socketFactory,
    required SyncUdpScheduler scheduler,
    required SyncMulticastLock multicastLock,
    SyncUdpAnnouncementCodec codec = const SyncUdpAnnouncementCodec(),
  });

  static final SyncUdpDiscovery system = SyncUdpDiscovery(
    socketFactory: const RawSyncUdpSocketFactory(),
    scheduler: const TimerSyncUdpScheduler(),
    multicastLock: const PlatformSyncMulticastLock(),
  );

  Future<SyncUdpBroadcastSession> startBroadcasting({
    required int httpPort,
    required String deviceName,
    required String serverId,
    InternetAddress? broadcastAddress,
    Duration broadcastInterval = const Duration(seconds: 2),
    int discoveryPort = SyncUdpDiscovery.defaultDiscoveryPort,
  });

  SyncUdpListenSession listenForServers({
    Duration timeout = const Duration(seconds: 6),
    InternetAddress? bindAddress,
    int discoveryPort = SyncUdpDiscovery.defaultDiscoveryPort,
  });
}
```

The optional port/address parameters are data-layer testability inputs. Production transports use the unchanged defaults: `255.255.255.255`, `InternetAddress.anyIPv4`, and port 47280.

Broadcast and listen calls return explicit sessions:

```dart
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

Lifecycle requirements:

- `ready` completes only after multicast lock acquisition, socket bind, and broadcast enablement succeed; after `ready`, `port` exposes the actual bound port, including an OS-assigned port when the requested port was zero.
- listener bind/acquisition errors complete `ready` with the error and close `servers`; the transport awaits `ready`, so the same startup error is emitted through the application-facing discovery stream exactly once.
- cancelling the server stream calls `close()`.
- `stop()`/`close()` are idempotent and share one cleanup Future.
- cleanup cancels scheduled tasks and subscriptions, closes the socket, releases the multicast lock exactly once, closes the stream when applicable, and then completes `done`.
- cancellation before asynchronous bind completes is safe: `ready` completes with `StateError('UDP 监听已关闭')`, a subsequently created socket is immediately closed, and no events are published.
- only a successfully decoded announcement resets the idle timeout, preserving current behavior.
- send failures continue to be logged and do not terminate periodic broadcasting.

### Transport ownership

`HttpUdpSyncServerTransport` accepts an optional `SyncUdpDiscovery`, defaults to `SyncUdpDiscovery.system`, stores the returned broadcast session, and awaits `session.stop()` before stopping HTTP.

`HttpSyncClientTransport` accepts an optional `SyncUdpDiscovery`, defaults to the system instance, and implements `discoverServers()` as an `async*` stream that awaits `session.ready`, delegates to `session.servers`, and closes the session in `finally`. Startup errors therefore remain application-facing stream errors, and stream cancellation deterministically owns session cleanup without changing the application port.

No `presentation`, `application`, or domain layer imports the new data runtime types.

## UDP Test Strategy

### Codec tests

Pure table-driven tests cover a valid round trip and all rejected envelope fields. They use raw JSON only because malformed wire input is the explicit boundary under test.

### Fake-runtime lifecycle tests

Use fake sockets, a queued socket factory, a manual scheduler, and a recording multicast lock. Protect:

1. broadcaster sends immediately, periodic fire sends again, and `stop()` prevents later scheduled sends;
2. broadcaster stop closes the socket and releases the lock exactly once even when invoked twice;
3. valid listener datagram publishes one `DiscoveredServer` and replaces the idle deadline;
4. malformed datagram publishes nothing and does not replace the idle deadline;
5. manually firing the active deadline closes the stream and completes `done`;
6. stream cancellation before and after bind releases all resources;
7. bind failure is surfaced once through `ready`/the transport discovery stream and releases an acquired lock.

These tests contain no `Future.delayed`, arbitrary pump, or dependence on OS UDP delivery.

### Real loopback smoke

Keep `test/features/sync/data/sync_udp_discovery_test.dart` tagged `udp`, but reduce it to one positive smoke:

1. create the listener session bound to `InternetAddress.loopbackIPv4` with discovery port zero;
2. await `session.ready`;
3. read the OS-assigned `session.port`;
4. start one broadcaster targeting loopback and `session.port`, with a long periodic interval so only the immediate send matters;
5. await the matching unique `serverId` with a bounded safety timeout;
6. stop/close both sessions and await both `done` Futures.

The safety timeout is a failure bound, not an intentional delay. The old negative real-time test is removed because fake-runtime tests prove timer cancellation and absence of later sends directly.

## Error and Resource Semantics

- Existing user-visible Sync messages remain unchanged.
- UDP decode rejection remains silent; unexpected decode exceptions may be logged but do not fail the listener.
- Socket bind failures remain stream errors for discovery and startup errors for broadcasting.
- Multicast-lock errors remain non-fatal and logged.
- Cleanup is idempotent and ordered: scheduled work/subscriptions, socket, multicast lock, stream completion.
- HTTP Sync transport retains its current decode/protocol/status/request-ID decision order.
- Secure pairing tests must never print or store plaintext/base64 secrets outside the recording secure store.
- Tests must close ProviderContainers, StreamControllers, sockets, databases, and temporary directories through `addTearDown` or deterministic session completion.

## File Map

### Production files to create

- `lib/features/sync/application/ports/sync_client_protocol.dart`: controller-facing protocol operations interface.
- `lib/features/sync/data/sync_udp_announcement_codec.dart`: pure UDP envelope codec.
- `lib/features/sync/data/sync_udp_socket.dart`: socket/datagram interfaces and raw Dart adapter.
- `lib/features/sync/data/sync_udp_scheduler.dart`: scheduled-task interfaces and Timer adapter.
- `lib/features/sync/data/sync_multicast_lock.dart`: multicast-lock interface and platform adapter.
- `lib/features/sync/data/sync_udp_sessions.dart`: public broadcast/listen session interfaces; private idempotent implementations remain in `sync_udp_discovery.dart` beside the lifecycle state they coordinate.

### Production files to modify

- `lib/features/sync/application/sync_client_protocol_coordinator.dart`
- `lib/features/sync/application/sync_client_controller.dart`
- `lib/features/sync/data/sync_udp_discovery.dart`
- `lib/features/sync/data/http_udp_sync_server_transport.dart`
- `lib/features/sync/data/http_sync_client_transport.dart`

### Test files to create

- `test/features/sync/data/secure_sync_pairing_repository_test.dart`
- `test/features/sync/data/http_sync_client_transport_test.dart`
- `test/features/sync/data/sync_udp_announcement_codec_test.dart`
- `test/features/sync/data/sync_udp_discovery_lifecycle_test.dart`
- `test/features/sync/data/sync_udp_test_fakes.dart`

### Test files to modify

- `test/features/settings/application/settings_transfer_workflow_test.dart`
- `test/features/sync/application/sync_client_controller_test.dart`
- `test/features/sync/application/sync_test_fakes.dart`
- `test/features/sync/data/sync_udp_discovery_test.dart`
- `test/features/media/data/media_thumbnail_generator_test.dart`
- `test/architecture/test_resilience_policy_test.dart`

Private session implementations remain in `sync_udp_discovery.dart`; no implementation class is exported. The public interfaces and responsibilities above remain unchanged.

## Verification and Coverage Audit

Implementation follows test-driven development for each production seam:

1. add the smallest failing boundary/state/lifecycle test;
2. run the exact test file and record the expected failure reason;
3. add the minimal production interface or behavior-preserving extraction;
4. rerun the focused test to green;
5. run the owning feature directory before moving to the next commit.

After all work:

1. format every changed Dart file;
2. run the resilience policy test;
3. run Settings, Media, and Sync directories separately with redirected logs;
4. run the real UDP test three warm times and report the median test-runner time;
5. run `dart run tool/check_import_boundaries.dart`;
6. run `flutter analyze`;
7. run the CI-equivalent coverage suite with `--exclude-tags=udp`;
8. compare targeted before/after `DA` lines and classify any unexpected hit-to-miss line;
9. run the full suite including UDP with the mandated redirected PowerShell command;
10. run `git diff --check` and audit changed paths.

Coverage is accepted when every named contract above has a direct test and no existing externally observable contract loses protection. No minimum percentage increase is required, although the targeted repository/workflow/controller/transport/media files are expected to improve.

UDP performance is accepted based on removal of all intentional real waits and a reported warm median. No brittle wall-clock assertion is added to the test suite.

## Acceptance Criteria

- `SecureSyncPairingRepository` has direct security, corruption, rollback, and revocation coverage.
- `SettingsTransferWorkflow` export tabs and import preparation outcomes are covered without duplicating codec/deduplicator internals.
- `SyncClientController` pair/request/error/stale-completion state transitions are deterministic and do not replay cryptographic protocol setup.
- `HttpSyncClientTransport` error mapping is directly covered without real HTTP waits.
- Media video-thumbnail tests are independent of installed ffmpeg/ffprobe state.
- UDP envelope validation is pure and table tested.
- UDP periodic, timeout, cancellation, bind-failure, socket-close, and multicast-lock lifecycles are tested without real time.
- Exactly one `udp`-tagged real loopback smoke remains.
- `test/features/sync/data/sync_udp_discovery_test.dart` contains no `Future.delayed`.
- The UDP exception is removed from `_futureDelayedAllow`; no replacement allowlist entry is introduced.
- Production UDP defaults remain broadcast address `255.255.255.255`, bind address `InternetAddress.anyIPv4`, discovery port 47280, broadcast interval 2 seconds, and idle timeout 6 seconds.
- Sync v3 protocol, Settings v7 format, persisted pairing keys, user-visible error messages, and HTTP trust-domain separation remain unchanged.
- Architecture boundaries, analyzer, targeted suites, CI-equivalent coverage suite, and full suite pass with fresh evidence.
- No Chat/Settings test-entry split, release-app interference handling, timeout increase, arbitrary sleep, broad settle, internal widget key, or line-coverage-only test is introduced.
