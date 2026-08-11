# Favorites, History, Media, and Sync Test Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove tautological, duplicate, implementation-coupled, and unnecessarily expensive tests from Favorites, History, Media, and Sync while preserving unique product, accessibility, security, protocol, persistence, and lifecycle contracts.

**Architecture:** Treat every test as a trigger/observable/test-layer contract. Delete only same-layer duplicates or tests that prove fixtures/frameworks; consolidate data-only variants; replace internal widget assertions with visible behavior, Semantics, navigation, state, or persistence; and compare LCOV hit-to-miss lines after every directory batch. No production seam may be added in this cleanup.

**Tech Stack:** Flutter 3.44.x stable, Dart 3.11+, `flutter_test`, Riverpod 3, raw `sqlite3`, `package:http`, GoRouter, PowerShell 7, LCOV.

## Global Constraints

- Implementation changes are limited to `test/features/favorites`, `test/features/history`, `test/features/media`, and `test/features/sync`.
- Do not modify `lib/`, `dart_test.yaml`, CI workflows, test timeouts, concurrency, or tests outside the four approved directories.
- Preserve unique safety, protocol, compatibility, persistence, accessibility, navigation, and lifecycle contracts even when they do not add line coverage.
- Do not introduce `pumpAndSettle`, arbitrary `Future.delayed`, real sleeps, timeout increases, pixel assertions, new internal keys, or new allowlist entries.
- A small coverage decrease is allowed, but every production hit-to-miss line must be classified; a lost external contract must be restored.
- Use PowerShell 7. Redirect every Flutter test run to a log file and print `EXIT=<code>` plus the last 150 lines.
- Format every changed Dart file before staging, then run `dart format --output=none --set-exit-if-changed` on all changed Dart files.
- The cleanup is a test-only refactor, so verification uses before/after behavior and LCOV evidence rather than manufacturing failing product tests.
- When implementation commits are authorized, set `OMLL_SKIP_BUMP=1` for each test-only commit so the post-commit hook does not modify `pubspec.yaml` outside scope.
- Baseline artifacts are in `%TEMP%\oh-my-llm-fav-history-media-sync-cleanup`.

## Verified Baseline

| Directory | Dart files | Test-code lines | Executed cases | Separate cold run |
|---|---:|---:|---:|---:|
| Favorites | 11 | 1,658 | 88 | 13.35s |
| History | 5 | 639 | 17 | 9.72s |
| Media | 23 | 4,935 | 274 | 12.50s |
| Sync | 20 | 2,160 | 78 | 11.03s |
| Total | 59 | 9,392 | 457 | 46.60s |

The warmed joint JSON run completed in 15.84 test-runner seconds. The joint LCOV run completed in 28.49 seconds. Baseline feature coverage is Favorites 498/538 (92.57%), History 245/256 (95.70%), Media 1,305/1,539 (84.80%), and Sync 928/1,885 (49.23%).

---

### Task 1: Remove Favorites Model Tautologies and Consolidate CRUD Contracts

**Files:**
- Delete: `test/features/favorites/application/favorite_source_conversation_command_test.dart`
- Delete: `test/features/favorites/domain/collection_test.dart`
- Modify: `test/features/favorites/domain/favorite_test.dart`
- Modify: `test/features/favorites/application/favorites_controller_test.dart`
- Modify: `test/features/favorites/data/sqlite_collections_repository_test.dart`
- Modify: `test/features/favorites/data/sqlite_favorites_repository_test.dart`
- Modify: `test/features/favorites/favorites_screen_basics_cases.dart`
- Modify: `test/features/favorites/favorites_screen_detail_cases.dart`

**Interfaces:**
- Consumes: `Favorite.hasReasoning`, `Favorite.displayTitle`, Favorites/Collections Notifiers, `favoriteByIdProvider`, SQLite repository APIs, FavoritesScreen filters and detail routes.
- Produces: the same meaningful Favorites CRUD, filtering, persistence, navigation, reasoning, source-link, and narrow-layout protection without interface self-tests or `Equatable`/`copyWith` restatements.

- [ ] **Step 1: Delete the two files that do not protect product behavior**

  Delete `favorite_source_conversation_command_test.dart`: `_RecordingCommand` only proves that its own implementation assigns parameters and never invokes production composition. Delete `collection_test.dart`: its three tests only restate `copyWith` and `Equatable`; collection mutation and persistence remain covered by controller/repository tests.

- [ ] **Step 2: Reduce `favorite_test.dart` to computed domain behavior**

  Remove all `copyWith`, clear-flag, equality, hash-code, and `sourceAssistantMessageId` field-retention tests. Keep two registered tests, each with named cases inside the body:

  ```dart
  test('hasReasoning 只在推理内容非空时为 true', () {
    for (final (:content, :expected) in [
      (content: '', expected: false),
      (content: '思考过程', expected: true),
    ]) {
      final favorite = Favorite(
        id: 'f1',
        userMessageContent: 'q',
        assistantContent: 'a',
        assistantReasoningContent: content,
        createdAt: DateTime(2026),
      );
      expect(favorite.hasReasoning, expected, reason: 'content=$content');
    }
  });

  test('displayTitle 优先使用自定义标题，否则回退用户消息', () {
    for (final (:title, :expected) in [
      (title: '我的标题', expected: '我的标题'),
      (title: null, expected: '用户消息'),
    ]) {
      final favorite = Favorite(
        id: 'f1',
        userMessageContent: '用户消息',
        assistantContent: '回复',
        title: title,
        createdAt: DateTime(2026),
      );
      expect(favorite.displayTitle, expected, reason: 'title=$title');
    }
  });
  ```

- [ ] **Step 3: Consolidate Favorites and Collections controller paths**

  In `favorites_controller_test.dart` make these exact changes:

  - Keep `add inserts...`, and add the existing `sourceAssistantMessageId: 'msg-42'` input/assertion to it; delete `add 保存 sourceAssistantMessageId`.
  - Replace `remove...`, the two `isFavorited...` tests, and `remove nonexistent...` with one lifecycle test that adds content, observes `isFavorited == true`, removes it, observes an empty list and `isFavorited == false`, then calls `remove('nonexistent')` and verifies state remains empty.
  - Replace the two `moveTo...` tests with one test that moves the same favorite into a valid collection and then to `null`, asserting both observable states.
  - Replace the two Favorite rename tests with one set/clear lifecycle test.
  - Replace the four successful Collections create/rename/delete tests with one lifecycle test that asserts create and rename trim whitespace, the returned ID remains stable, and delete empties state.
  - Replace the two nonexistent Collections mutation tests with one no-op test that invokes rename and delete against absent IDs and verifies the existing collection is unchanged.
  - Delete `FavoritesFilterNotifier`'s three direct initial/set/reset tests. Extend `filter 变更后 favoritesProvider 重新读取列表` to switch through `null`, `''`, the concrete collection ID, and back to `null`, asserting all/unclassified/classified/all results.
  - Keep `favoriteByIdProvider` filter isolation. Replace its rename/move/remove tests with one mutation lifecycle test that observes title update, collection update, and final `null` through `favoriteByIdProvider`.

- [ ] **Step 4: Consolidate Collections repository lifecycle**

  In `sqlite_collections_repository_test.dart`, replace the save, replace, and delete tests with one coherent lifecycle test:

  ```dart
  repository.save(original);
  expect(repository.loadAll().single, original);
  repository.save(original.copyWith(name: '新名称'));
  expect(repository.loadAll().single.name, '新名称');
  repository.delete(original.id);
  expect(repository.loadAll(), isEmpty);
  ```

  Keep the created-at ordering test unchanged because it protects a distinct SQL ordering contract.

- [ ] **Step 5: Consolidate Favorites repository query and mutation matrices**

  In `sqlite_favorites_repository_test.dart`:

  - Delete the empty-table test; every successful mutation test already observes empty/nonempty repository state.
  - Extend the full `loadAll` codec test to include `sourceAssistantMessageId` and `title`, and add a second row with both optional fields `null`; delete the separate source-ID and save-title round-trip groups.
  - Replace the three collection-filter tests with one named matrix that seeds classified and unclassified rows once, then checks default/null, empty-string, and concrete-ID projections.
  - Keep replace-by-ID and created-at ordering as distinct SQL contracts.
  - Delete `delete 不存在的 id 不抛出异常`; raw SQLite `DELETE` no-op behavior is not a repository decision branch.
  - Merge set/clear collection moves into one lifecycle test.
  - Merge absent/present/after-delete `existsByAssistantContent` into one lifecycle test.
  - Merge set/clear `updateTitle` into one lifecycle test.
  - Replace the three `loadById` tests with one two-row lookup test that asserts the full selected row and a missing-ID `null` result. Keep two different `createdAt` values so the test still proves lookup is by ID rather than sort order.

- [ ] **Step 6: Merge FavoritesScreen filter coverage and remove an internal icon contract**

  In `favorites_screen_basics_cases.dart`, replace the separate all/unclassified/collection filter tests with one scenario that seeds one classified and one unclassified favorite, asserts both initially, selects the collection chip and observes only its favorite, then selects `未分类` and observes only the unclassified favorite. Keep list-content rendering, empty screen, empty selected filter, and navigation as distinct UI contracts.

  In `favorites_screen_detail_cases.dart`, keep all eight behavior branches. The move `InkWell` has no tooltip or Semantics label in production, so `find.byIcon(Icons.drive_file_move_outline)` may remain only as the interaction locator; delete the pre-tap icon-presence assertion. The product outcome is the visible `移动到收藏夹` dialog with `未分类` and `技术收藏` choices.

- [ ] **Step 7: Format and verify Favorites**

  ```powershell
  $Changed = git diff --name-only --diff-filter=ACM -- 'test/features/favorites/**/*.dart' 'test/features/favorites/*.dart'
  if ($Changed) { dart format $Changed; dart format --output=none --set-exit-if-changed $Changed }
  $Log = Join-Path $env:TEMP 'oh-my-llm-fav-history-media-sync-cleanup\task1-favorites.log'
  flutter test test/features/favorites --reporter compact 2>&1 | Out-File -Encoding utf8 $Log
  $E = $LASTEXITCODE
  Write-Host "EXIT=$E"
  Get-Content -Tail 150 $Log
  if ($E -ne 0) { exit $E }
  ```

  Expected: exit 0; no import references either deleted file; source linkage, filtering, persistence, navigation, reasoning, and narrow-layout tests remain.

- [ ] **Step 8: Commit the Favorites batch**

  ```powershell
  git add -- test/features/favorites
  $env:OMLL_SKIP_BUMP = '1'
  try { git commit -m "test(favorites): 精简重复与恒真测试" } finally { Remove-Item Env:OMLL_SKIP_BUMP -ErrorAction SilentlyContinue }
  ```

---

### Task 2: Remove History Presentation Implementation Assertions

**Files:**
- Modify: `test/features/history/history_screen/history_screen_search_cases.dart`
- Modify: `test/features/history/history_screen/history_screen_pagination_bar_cases.dart`

**Interfaces:**
- Consumes: History search debounce, title/user/assistant/tree search rules, visible pagination information, page buttons, page-size selector, and jump input.
- Produces: the same History search and pagination decisions without `FilledButton`/`OutlinedButton` appearance contracts or repeated debounce setup.

- [ ] **Step 1: Merge title and user-message search into one bounded UI scenario**

  In `history_screen_search_cases.dart`, keep one pre-debounce assertion only in the first query. Execute `Rust`, advance exactly `HistoryScreen.searchDebounce`, assert only `Rust 重构计划`; then enter `Widget 测试`, advance the same public duration, and assert only `Flutter 路线图`. Delete the old separate title and user-message tests.

  Keep assistant exclusion and all-branches inclusion as separate decision branches, but remove their repeated “old results remain before debounce” blocks. They should enter the query, pump the public debounce duration, pump one frame, and assert the final observable result.

- [ ] **Step 2: Delete pagination tests that only prove Material presentation**

  In `history_screen_pagination_bar_cases.dart`:

  - In the initial render test remove `find.byType(HistoryPaginationBar)`; retain visible `100 条`, visible `1/5`, and Provider page state.
  - Delete `prev/next buttons at boundaries do not trigger navigation`; controller boundary behavior is already protected by `test/features/chat/application/history_pagination_controller_test.dart`, while this test only taps disabled Material buttons.
  - Delete `current page is visually distinguished after navigation`; `FilledButton` versus `OutlinedButton` is an internal rendering choice and page navigation is already covered.
  - In `clicking page number navigates...`, locate the visible page label rather than `find.widgetWithText(OutlinedButton, '3')`. If `find.text('3')` is ambiguous, scope it to the pagination bar ancestor but do not assert the concrete button class.
  - Keep initial state info, next-page wiring, page-number wiring, ellipsis sequence, page-size reset, jump clamp, and jump target.

- [ ] **Step 3: Format and verify History**

  ```powershell
  $Changed = git diff --name-only --diff-filter=ACM -- 'test/features/history/**/*.dart' 'test/features/history/*.dart'
  if ($Changed) { dart format $Changed; dart format --output=none --set-exit-if-changed $Changed }
  $Log = Join-Path $env:TEMP 'oh-my-llm-fav-history-media-sync-cleanup\task2-history.log'
  flutter test test/features/history --reporter compact 2>&1 | Out-File -Encoding utf8 $Log
  $E = $LASTEXITCODE
  Write-Host "EXIT=$E"
  Get-Content -Tail 150 $Log
  if ($E -ne 0) { exit $E }
  ```

  Expected: exit 0; title/user/assistant/tree search decisions, page changes, page-size reset, ellipsis, and jump clamping remain protected.

- [ ] **Step 4: Commit the History batch**

  ```powershell
  git add -- test/features/history
  $env:OMLL_SKIP_BUMP = '1'
  try { git commit -m "test(history): 移除分页实现细节断言" } finally { Remove-Item Env:OMLL_SKIP_BUMP -ErrorAction SilentlyContinue }
  ```

---

### Task 3: Parameterize Media Domain, Filesystem, Cache, and HTTP Boundaries

**Files:**
- Modify: `test/features/media/domain/models/file_item_test.dart`
- Modify: `test/features/media/utils/path_utils_test.dart`
- Modify: `test/features/media/data/media_mime_types_test.dart`
- Modify: `test/features/media/data/media_directory_scanner_test.dart`
- Modify: `test/features/media/data/media_http_handler_test.dart`
- Modify: `test/features/media/data/media_image_http_handler_test.dart`
- Modify: `test/features/media/data/media_recursive_videos_handler_test.dart`
- Modify: `test/features/media/data/media_thumbnail_cache_test.dart`
- Modify: `test/features/media/data/media_thumbnail_generator_test.dart`
- Modify: `test/features/media/data/media_thumbnail_http_handler_test.dart`
- Modify: `test/features/media/data/media_video_http_handler_test.dart`

**Interfaces:**
- Consumes: Media JSON codecs, path normalization/encoding, classification, filesystem scan and traversal rejection, thumbnail caching/generation, HTTP route matching, status codes, headers, and byte-range responses.
- Produces: compact named data matrices with every security and protocol boundary retained.

- [ ] **Step 1: Consolidate FileItem serialization and formatted-size matrices**

  In `file_item_test.dart`, replace the three `toJson` tests and the file/folder `fromJson` tests with one file round-trip and one directory round-trip. Assert optional keys are present only for the file case. Keep missing-field defaults and list decoding. Replace the seven registered formatted-size cases with one test containing the existing case records and `expect(..., reason: 'size=...')`.

- [ ] **Step 2: Convert path utilities to four named matrices**

  In `path_utils_test.dart` create exactly four registered tests:

  1. `encodeMediaPath` matrix containing root, English, Chinese, mixed, multi-segment, space, and already-encoded input with exact expected strings.
  2. invalid `normalizeMediaRoutePath` matrix containing null, empty, whitespace, missing leading slash, root-only, `.`, and `..` segments.
  3. valid normalization matrix containing Chinese/space, `photo..jpg`, repeated separators, and trailing separator.
  4. `buildMediaResourceUrl` matrix containing image/Chinese and video/English endpoints.

  Use records with `name`, `input`, and `expected`; loop inside each test instead of registering a test per row.

- [ ] **Step 3: Collapse MIME classification into three exhaustive tests**

  In `media_mime_types_test.dart` use one extension extraction table, one classification test that iterates all known image/video extensions plus video-as-image/image-as-video/no-extension negatives, and one MIME mapping table. Preserve every existing extension and expected MIME value.

- [ ] **Step 4: Consolidate scanner tests without weakening traversal boundaries**

  In `media_directory_scanner_test.dart`:

  - Convert normal/subdirectory/Chinese path resolution to one named input table.
  - Keep every traversal input but loop inside one registered rejection test.
  - Fold FileItem metadata assertions into the sorted directory-scan happy path.
  - Merge recursive video names, relative paths, and ordering into one result assertion.
  - Merge empty and image-only recursive directories into one named no-video matrix.
  - Keep hidden-file filtering and missing-directory errors.
  - Delete standalone `VideoItem toJson/fromJson 往返一致`; the recursive-handler JSON test and typed recursive-scan result already protect the wire and model fields.

- [ ] **Step 5: Fold duplicate list/image/recursive HTTP success assertions**

  In `media_http_handler_test.dart`, fold directory `type` and file `mimeType` assertions into the root happy path. Keep both trailing-slash and no-trailing-slash routes because route matching differs. Run subdirectory and Chinese paths as a named table. Keep empty and missing-directory status behavior.

  In `media_image_http_handler_test.dart`, add `Accept-Ranges` to the normal-image happy path and delete its standalone test. Run root/subdirectory valid images as a named path table. Keep missing path, missing file, and the explicit non-image-extension pass-through contract.

  In `media_recursive_videos_handler_test.dart`, replace the separate GET/POST/prefix `canHandle` tests with one method/path matrix, and retain recursive success plus traversal rejection.

- [ ] **Step 6: Consolidate thumbnail cache and generator branches**

  In `media_thumbnail_cache_test.dart`:

  - Replace same-input, key-format, and Chinese-path smoke tests with one deterministic-format test using the Chinese path and asserting identical 32-character lowercase hex output.
  - Replace three “field changed” tests with one named sensitivity matrix for relative path, size, and modified time.
  - Replace miss, put/get, size invalidation, and directory creation tests with one lifecycle test that begins with a missing directory, observes a miss, writes bytes, observes directory creation and a hit, then changes size and observes a miss.

  In `media_thumbnail_generator_test.dart`, run supported extension success cases inside one registered test. Keep corrupted image, unsupported type, missing file, and fake-video/ffmpeg failure as four separate tests because their expected exception types differ. Translate the existing English WebP note to a concise Simplified Chinese comment while touching the file.

- [ ] **Step 7: Consolidate thumbnail and video HTTP matrices**

  In `media_thumbnail_http_handler_test.dart`, combine first-generation success and cache-hit byte equality into one lifecycle test. Start one server for a named error table with `/nonexistent.jpg -> 404`, `/ -> 400`, and `/..%2F..%2Fetc -> 403`; assert each status with the URI in `reason`, and retain the missing-file error-body assertion. Keep Chinese success because it covers URI decoding.

  In `media_video_http_handler_test.dart`:

  - Keep one no-Range happy path and remove the redundant small-file variant.
  - Replace the seven successful Range tests with one named table covering closed, single-byte, open-ended, full open-ended, and suffix ranges; assert status, `Content-Range`, body length, and representative first/last byte for each row.
  - Replace out-of-bounds, malformed, and multi-range tests with one invalid-range table asserting 416 for each named input.
  - Keep missing file and missing path.

- [ ] **Step 8: Format and verify Media low-level tests**

  ```powershell
  $Files = @(
    'test/features/media/domain/models/file_item_test.dart',
    'test/features/media/utils/path_utils_test.dart',
    'test/features/media/data/media_mime_types_test.dart',
    'test/features/media/data/media_directory_scanner_test.dart',
    'test/features/media/data/media_http_handler_test.dart',
    'test/features/media/data/media_image_http_handler_test.dart',
    'test/features/media/data/media_recursive_videos_handler_test.dart',
    'test/features/media/data/media_thumbnail_cache_test.dart',
    'test/features/media/data/media_thumbnail_generator_test.dart',
    'test/features/media/data/media_thumbnail_http_handler_test.dart',
    'test/features/media/data/media_video_http_handler_test.dart'
  )
  dart format $Files
  dart format --output=none --set-exit-if-changed $Files
  $Log = Join-Path $env:TEMP 'oh-my-llm-fav-history-media-sync-cleanup\task3-media-low-level.log'
  flutter test test/features/media/data test/features/media/domain test/features/media/utils --reporter compact 2>&1 | Out-File -Encoding utf8 $Log
  $E = $LASTEXITCODE
  Write-Host "EXIT=$E"
  Get-Content -Tail 150 $Log
  if ($E -ne 0) { exit $E }
  ```

  Expected: exit 0; every path traversal, missing resource, invalid range, MIME category, cache invalidation, and filesystem error boundary remains represented.

- [ ] **Step 9: Commit the Media low-level batch**

  ```powershell
  git add -- test/features/media/data test/features/media/domain test/features/media/utils
  $env:OMLL_SKIP_BUMP = '1'
  try { git commit -m "test(media): 参数化文件与 HTTP 边界测试" } finally { Remove-Item Env:OMLL_SKIP_BUMP -ErrorAction SilentlyContinue }
  ```

---

### Task 4: Remove Media Application State Tautologies and Reuse Controller Lifecycles

**Files:**
- Modify: `test/features/media/application/media_browser_controller_test.dart`
- Modify: `test/features/media/application/shuffle_playback_controller_test.dart`
- Modify: `test/features/media/application/shuffle_playback_controller_behavior_test.dart`

**Interfaces:**
- Consumes: MediaBrowser derived state, initialization/loading/error/navigation/reset/autoDispose, Shuffle first/last display properties, start/next/previous/exit/reset/directory-change/URL behavior.
- Produces: controller tests focused on decisions and lifecycle outcomes rather than immutable-list, equality, and `copyWith` implementation.

- [ ] **Step 1: Remove MediaBrowserState implementation tests**

  In `media_browser_controller_test.dart`, delete `快照 item 和 history 输入并按值比较` and `copyWith 保留未指定字段`. Replace `初始状态`, `isAtRoot`, and `canGoBack` with one derived-state table that asserts root/empty and nested/history cases. Delete `build() 初始状态` because the same initial public state is already covered by the derived-state test.

- [ ] **Step 2: Consolidate MediaBrowser controller success lifecycles**

  Merge `initWithServer...` and `loadDirectory HTTP 200...` into one test that initializes with `testServer` and asserts server, root path, returned items, non-loading, and no error. Merge successful `navigateTo` and `goBack` into one scenario that observes pushed history and then restored root. Keep stale-response reset, autoDispose rebuild, missing-server error, HTTP error, network error, failed-navigation history preservation, and no-history `goBack == false`.

- [ ] **Step 3: Reduce ShufflePlaybackState to public derived properties**

  In `shuffle_playback_controller_test.dart`, delete `快照播放列表且所有状态按值比较`. Replace first, last, and single-item tests with one named table asserting `isFirst`, `isLast`, `displayNumber`, `totalCount`, and `currentVideo`. Keep the autoDispose session test.

- [ ] **Step 4: Consolidate Shuffle controller navigation and lifecycle tests**

  In `shuffle_playback_controller_behavior_test.dart`:

  - Keep stale response, missing server, empty list, successful list, HTTP error, and network error as distinct start branches.
  - Retain the probabilistic shuffle-order test unchanged and record it in the final report: deterministic replacement needs an injected RNG production seam, which is outside scope.
  - Replace the five next/previous tests with one playlist navigation lifecycle: inactive next/previous return null; after start, previous at first is null; next advances; previous returns; advancing to last makes next null.
  - Replace the two player-exit tests with one lifecycle that proves a non-last exit stays active, advances to the last item, then proves exit becomes idle.
  - Replace same/different directory tests with one lifecycle that first preserves active state for the same path and then resets for a different path.
  - Keep explicit reset from Active to Idle.
  - Replace the three URL tests with one test covering null server, exact English URL, and encoded Chinese URL.

- [ ] **Step 5: Format and verify Media application tests**

  ```powershell
  $Files = @(
    'test/features/media/application/media_browser_controller_test.dart',
    'test/features/media/application/shuffle_playback_controller_test.dart',
    'test/features/media/application/shuffle_playback_controller_behavior_test.dart'
  )
  dart format $Files
  dart format --output=none --set-exit-if-changed $Files
  $Log = Join-Path $env:TEMP 'oh-my-llm-fav-history-media-sync-cleanup\task4-media-application.log'
  flutter test test/features/media/application --reporter compact 2>&1 | Out-File -Encoding utf8 $Log
  $E = $LASTEXITCODE
  Write-Host "EXIT=$E"
  Get-Content -Tail 150 $Log
  if ($E -ne 0) { exit $E }
  ```

  Expected: exit 0; reset races, autoDispose, all transport outcomes, navigation bounds, player exit, directory changes, and URL encoding remain protected.

- [ ] **Step 6: Commit the Media application batch**

  ```powershell
  git add -- test/features/media/application
  $env:OMLL_SKIP_BUMP = '1'
  try { git commit -m "test(media): 聚焦控制器生命周期契约" } finally { Remove-Item Env:OMLL_SKIP_BUMP -ErrorAction SilentlyContinue }
  ```

---

### Task 5: Rewrite Media Presentation Tests Around Observable Behavior

**Files:**
- Modify: `test/features/media/helpers/media_test_helpers.dart`
- Modify: `test/features/media/presentation/image_viewer_page_test.dart`
- Modify: `test/features/media/presentation/media_browser_navigation_test.dart`
- Modify: `test/features/media/presentation/media_route_pages_test.dart`
- Modify: `test/features/media/presentation/video_player_page_test.dart`
- Modify: `test/features/media/presentation/video_player_accessibility_test.dart`

**Interfaces:**
- Consumes: Media browser callbacks/routes, ImageViewer count/error/swipe/back behavior, routed-page recovery, VideoPlayer gesture/controller effects, disposal, formatted values, and Semantics/keyboard contracts.
- Produces: substantially fewer presentation cases with deterministic test fakes and no `Scaffold`, `Slider`, page-class, or `getRect` outcome contracts.

- [ ] **Step 1: Give the media browser fake deterministic navigation**

  Extend `FakeMediaBrowserController` in `media_test_helpers.dart` with an optional map of path-to-items and override `navigateTo` to update `state.currentPath`, `state.items`, and `state.pathHistory` synchronously. The default behavior must remain the current injected initial state so existing callers need no changes.

  ```dart
  class FakeMediaBrowserController extends MediaBrowserController {
    FakeMediaBrowserController(this.initialState, {this.itemsByPath = const {}});

    final MediaBrowserState initialState;
    final Map<String, List<FileItem>> itemsByPath;

    @override
    MediaBrowserState build() => initialState;

    @override
    Future<void> navigateTo(String path) async {
      state = state.copyWith(
        currentPath: path,
        items: itemsByPath[path] ?? const [],
        pathHistory: [...state.pathHistory, state.currentPath],
      );
    }
  }
  ```

  This fake verifies MediaBrowserTab wiring only; production `navigateTo` remains covered in Task 4.

- [ ] **Step 2: Remove the 10-second virtual network timeout and duplicate viewport routing**

  In `media_browser_navigation_test.dart`, inject the new fake path map in `点击目录只改变浏览路径...`, tap `相册`, pump one frame, and assert the visible path plus router location `/sync`. Delete `tester.pump(const Duration(seconds: 10))` and its timeout comment. In image navigation, replace `find.byType(MediaImageRoutePage)` with visible `1 / 2` gallery state; in missing-server no-navigation, remove the negative page-class assertion because unchanged `/sync` location and the still-visible file row already prove the outcome.

  Reduce the five content-smoke viewports to 390x844, 844x390, and 1024x768, representing compact portrait, constrained landscape, and wide layout. Delete the two-image-route viewport loop entirely because the first image navigation test already verifies the same URI push/back contract and routing has no viewport branch. Keep image route, video route, directory navigation, and missing-server no-navigation as distinct wiring branches.

- [ ] **Step 3: Reduce ImageViewer tests to product behavior**

  In `image_viewer_page_test.dart`:

  - Replace page-counter format, multi-image counter, and initial-index variants with one `initialIndex` test that starts at `3 / 5`.
  - Keep single-image counter suppression and image-load error copy.
  - Delete standalone `返回按钮存在`; back behavior is covered by `返回按钮关闭页面` and route tests.
  - Keep one swipe test that asserts `1 / 5` becomes `2 / 5`.
  - Delete first/last clamp tests because they only reassert PageView framework bounds.
  - Delete the double-tap-error no-crash test; it has no observable product assertion beyond page survival.
  - Delete rapid-three-page and multi-page no-crash tests; the single swipe test protects page-change wiring without repeated scroll animation.
  - Keep back navigation.

- [ ] **Step 4: Replace routed page-class assertions with visible outcomes**

  In `media_route_pages_test.dart`, remove `find.byType(ImageViewerPage)` and `find.byType(VideoPlayerPage)` assertions. Use visible count/file name/recovery copy and router location as outcomes. Keep all path-missing, extension-mismatch, missing-server, recovery-button, and top-level-route branches because they protect serialized route input and recovery behavior.

- [ ] **Step 5: Collapse VideoPlayer visual gesture tests and remove weak implementation checks**

  In `video_player_page_test.dart`:

  - Delete the `页面正常渲染`, `返回按钮存在`, `倍速按钮存在`, `初始控制栏可见`, and `点击视频区域切换控制栏显隐` tests. Their outcomes are `Scaffold`, icon, text, and `Slider` implementation presence; accessibility tests already protect operable controls and surface visibility.
  - Replace the three error tests with one retry lifecycle that asserts visible failure copy and `重试`, taps retry, waits for initialization count 2, and observes the same recoverable error state.
  - Replace `_leftHalf`, `_rightHalf`, and `_center` implementations that call `tester.getRect` with positions derived from the configured logical test viewport. Use 25%, 75%, and 50% of `tester.view.physicalSize / devicePixelRatio`; these coordinates describe the public left/right/surface gesture zones rather than a child widget rectangle.
  - Replace four double-seek tests with one named table for backward, forward, start clamp, and end clamp. Fold visible `15s` and its one-second disappearance into the forward row; delete the two standalone hint tests.
  - Replace long-press speed, release restoration, and visible hint tests with one lifecycle asserting calls `[3.0, 1.0]` and visible `3.0x`. Replace paused/completed no-op tests with one named state matrix.
  - Replace drag seek and start clamp with one named table; fold control-bar restoration into the normal drag row through a visible/semantic action, not `Slider` type.
  - Delete the three `手势与控制栏联动` tests because they only reassert the same hint text and do not observe hidden controls.
  - Delete `播放中无手势时提示隐藏`, `暂停时显示播放图标`, and `播放中触发手势提示时显示手势内容`; positive gesture feedback and play/pause semantics are protected elsewhere.
  - Keep route-pop disposal, but trigger it through the visible/tooltip back action instead of obtaining a Navigator context from `find.byType(VideoPlayerPage)`.
  - Replace three duration-format tests with one named table and three volume-icon tests with one named table.

- [ ] **Step 6: Preserve accessibility failure reasons and remove page-class interaction locators**

  In `video_player_accessibility_test.dart`, keep the existing phonePortrait/wideDesktop matrix plus all surface/control Semantics, loading/error, keyboard, seek, Escape/disposal, live-region uniqueness, progress adjustment, focus order, auto-hide boundary, and focus restoration tests. Replace both `tester.getCenter(find.byType(VideoPlayerPage))` occurrences with the center of `find.semantics.byLabel('视频播放器：test-video.mp4')`. Do not merge accessibility assertions into visual tests because their expected failure reason is distinct.

- [ ] **Step 7: Format and verify Media presentation**

  ```powershell
  $Files = @(
    'test/features/media/helpers/media_test_helpers.dart',
    'test/features/media/presentation/image_viewer_page_test.dart',
    'test/features/media/presentation/media_browser_navigation_test.dart',
    'test/features/media/presentation/media_route_pages_test.dart',
    'test/features/media/presentation/video_player_page_test.dart',
    'test/features/media/presentation/video_player_accessibility_test.dart'
  )
  dart format $Files
  dart format --output=none --set-exit-if-changed $Files
  $Log = Join-Path $env:TEMP 'oh-my-llm-fav-history-media-sync-cleanup\task5-media-presentation.log'
  flutter test test/features/media/presentation --reporter compact 2>&1 | Out-File -Encoding utf8 $Log
  $E = $LASTEXITCODE
  Write-Host "EXIT=$E"
  Get-Content -Tail 150 $Log
  if ($E -ne 0) { exit $E }
  ```

  Expected: exit 0; no executable `getRect`, no 10-second virtual timeout, no product assertion based solely on `Scaffold`, `Slider`, `ImageViewerPage`, or `VideoPlayerPage` type.

- [ ] **Step 8: Run the complete Media directory**

  ```powershell
  $Log = Join-Path $env:TEMP 'oh-my-llm-fav-history-media-sync-cleanup\task5-media-all.log'
  flutter test test/features/media --reporter compact 2>&1 | Out-File -Encoding utf8 $Log
  $E = $LASTEXITCODE
  Write-Host "EXIT=$E"
  Get-Content -Tail 150 $Log
  if ($E -ne 0) { exit $E }
  ```

- [ ] **Step 9: Commit the Media presentation batch**

  ```powershell
  git add -- test/features/media/helpers test/features/media/presentation
  $env:OMLL_SKIP_BUMP = '1'
  try { git commit -m "test(media): 精简播放器与导航组件测试" } finally { Remove-Item Env:OMLL_SKIP_BUMP -ErrorAction SilentlyContinue }
  ```

---

### Task 6: Conservatively Remove Sync Duplicates Without Weakening Security

**Files:**
- Delete: `test/features/sync/domain/models/sync_message_test.dart`
- Modify: `test/features/sync/domain/models/sync_protocol_message_test.dart`
- Modify: `test/features/sync/domain/models/broadcast_prefix_length_test.dart`
- Modify: `test/features/sync/presentation/widgets/interface_selector_test.dart`
- Modify: `test/features/sync/application/sync_client_controller_execute_test.dart`
- Modify: `test/features/sync/application/sync_server_controller_test.dart`
- Modify: `test/features/sync/sync_screen/sync_screen_render_cases.dart`
- Modify: `test/features/sync/sync_screen/sync_screen_responsive_cases.dart`

**Interfaces:**
- Consumes: typed Sync codec/version/category behavior, broadcast prefix calculation, InterfaceSelector wiring, full/partial/error imports, server race/lifecycle/security behavior, and SyncScreen mode/disconnect/media/responsive behavior.
- Produces: fewer Sync tests while retaining every encryption, authentication, protocol, replay, sensitive-data, import, session, and lifecycle boundary.

- [ ] **Step 1: Move the pairing round-trip into the typed protocol codec suite**

  Add `PairingChallengeRequest` to a named round-trip table in `sync_protocol_message_test.dart` alongside `EncryptedSyncRequest`; assert `SyncProtocolCodec.decode(encode(message))` returns the same typed message. Keep the encrypted-envelope no-double-JSON assertion on the encrypted case. Then delete `sync_message_test.dart`, whose misleading “retired v1” test currently performs only this pairing round-trip.

- [ ] **Step 2: Parameterize prefix inputs without removing boundaries**

  In `broadcast_prefix_length_test.dart`, loop all existing IP/prefix expected-address rows inside one registered test, retain non-IPv4 fallback, and loop all storage-value cases inside one registered test. Preserve each case's name in `reason`.

- [ ] **Step 3: Remove InterfaceSelector duplicate default-address tests**

  In `interface_selector_test.dart`, keep three tests:

  1. initial render asserts `/8`, `/16`, `/24`, and the default `/24` address `10.214.98.255` while rejecting the incorrect `/8` address;
  2. persisted `/16` renders `10.214.255.255`;
  3. tapping `/16` changes the visible address from `/24` to `/16`.

  Delete the standalone default-selection and standalone current-broadcast-address tests after folding their assertions into the initial render.

- [ ] **Step 4: Merge full import phase and data assertions**

  In `sync_client_controller_execute_test.dart`, merge `deduplicatedData 非空时推进到 imported` with `写入全部六类数据`: execute once, assert `true`, phase `imported`, and all six categories. Keep null-data no-op, nonempty-category-only behavior, and exception-to-error behavior.

- [ ] **Step 5: Remove SyncServer state equality and strengthen weak lifecycle tests**

  In `sync_server_controller_test.dart`:

  - Delete `SyncServerState 按网卡字段和可观察值比较`.
  - Merge start and stop happy paths into one lifecycle test that asserts running state, port, pairing-code format, then stopped state and zero served count.
  - Rewrite `停止尚未完成时重新 start...` to assert final `isRunning == true` and non-null port after both Futures complete; the current no-assert test is too weak.
  - In repeated stop, remove `identical(firstStop, secondStop)` because Future identity is implementation detail. Await both and assert the public idle state.
  - Merge anonymous settings API-key non-leakage and served-count tests into one HTTP request that asserts unauthorized status, response body excludes `sk-test-key`, and `servedRequestCount == 0`.
  - Keep observer lifetime, container shutdown, start/stop race, failed restart state, stored/default device name, repeated start idempotence, device-name persistence/restart/coalescing, and old-protocol HTTP status.

- [ ] **Step 6: Merge SyncScreen default/disconnect states and separate responsive reachability**

  In `sync_screen_render_cases.dart`, merge title/tabs/mode-selector rendering with default connection-tab content. Merge the two disconnected-state tests into one seeded scenario that first asserts connection-tab error/research content, switches to Sync, then asserts the scoped disconnected placeholder and absence of generic unconnected copy. Keep server-mode switch, pairing retry, category invalidation, Android media reset/re-entry, and Android initial-tab initialization.

  In `sync_screen_responsive_cases.dart`, run compact key-content reachability only at 390px; 600px follows the same compact branch. Keep shell-below/at/above boundary cases. Rewrite the 844x390 Android case to verify only low-height media-tab reachability and no exception; remove its reset assertion because the render test protects reset/re-entry more strongly.

- [ ] **Step 7: Explicitly retain UDP waits and security suites**

  Do not modify `sync_udp_discovery_test.dart`. Its 200ms socket-release wait and 1s/2s negative observation are exactly registered by `test/architecture/test_resilience_policy_test.dart`; safely replacing them requires socket/scheduler production seams or an out-of-scope allowlist edit. Record this retained limitation in the final report.

  Do not remove or merge away the distinct security/compatibility failure reasons in cryptography, session registry, transport authorization, HTTP protocol mapping, protocol version, malformed payload, sensitive confirmation, client secret state, or disconnect stream tests.

- [ ] **Step 8: Format and verify Sync**

  ```powershell
  $Changed = git diff --name-only --diff-filter=ACM -- 'test/features/sync/**/*.dart' 'test/features/sync/*.dart'
  if ($Changed) { dart format $Changed; dart format --output=none --set-exit-if-changed $Changed }
  $Log = Join-Path $env:TEMP 'oh-my-llm-fav-history-media-sync-cleanup\task6-sync.log'
  flutter test test/features/sync --reporter compact 2>&1 | Out-File -Encoding utf8 $Log
  $E = $LASTEXITCODE
  Write-Host "EXIT=$E"
  Get-Content -Tail 150 $Log
  if ($E -ne 0) { exit $E }
  ```

  Expected: exit 0; all UDP cases still pass; every security/protocol/compatibility boundary remains; server restart tests now contain public-state assertions.

- [ ] **Step 9: Commit the Sync batch**

  ```powershell
  git add -- test/features/sync
  $env:OMLL_SKIP_BUMP = '1'
  try { git commit -m "test(sync): 合并重复状态与界面测试" } finally { Remove-Item Env:OMLL_SKIP_BUMP -ErrorAction SilentlyContinue }
  ```

---

### Task 7: Compare Coverage, Recount the Suite, and Run Repository Gates

**Files:**
- Verify only; no planned source or test changes.

**Interfaces:**
- Consumes: baseline logs/LCOV, all six cleanup commits, and repository verification commands.
- Produces: after-LCOV, hit-to-miss classification, before/after inventory and timing, smell audit, full-suite evidence, and scope evidence.

- [ ] **Step 1: Recount files, lines, static declarations, and executed cases**

  ```powershell
  foreach ($Name in @('favorites', 'history', 'media', 'sync')) {
    $Files = Get-ChildItem "test/features/$Name" -Recurse -Filter *.dart
    $Lines = ($Files | ForEach-Object { (Get-Content $_.FullName).Count } | Measure-Object -Sum).Sum
    $Declarations = 0
    foreach ($File in $Files) {
      $Text = Get-Content -Raw $File.FullName
      $Declarations += [regex]::Matches($Text, '(?s)(?:testWidgets|test)\s*\(').Count
    }
    Write-Host "$Name FILES=$($Files.Count) LINES=$Lines DECLARATIONS=$Declarations"
  }
  ```

  Record the executed-case total from the joint compact log; loops can make it differ from declaration count.

- [ ] **Step 2: Audit remaining fragility and explain every legitimate match**

  ```powershell
  rg -n --glob '*.dart' 'pumpAndSettle|Future(?:<[^>]+>)?\.delayed|getTopLeft|getRect|find\.byKey|tester\.widget|find\.byType\((Scaffold|Slider|ImageViewerPage|VideoPlayerPage)\)' test/features/favorites test/features/history test/features/media test/features/sync
  ```

  Expected: only the three documented UDP `Future.delayed` calls remain from prohibited timing patterns. A remaining `find.byType` used to interact with a TextField, TabBar, PageView, Checkbox, or scoped ancestor is acceptable; it must not be the asserted product outcome.

- [ ] **Step 3: Run the four directories jointly twice and record warm timing**

  ```powershell
  $Dir = Join-Path $env:TEMP 'oh-my-llm-fav-history-media-sync-cleanup'
  1..2 | ForEach-Object {
    $Run = $_
    $Log = Join-Path $Dir "after-warm-$Run.log"
    $Watch = [System.Diagnostics.Stopwatch]::StartNew()
    flutter test test/features/favorites test/features/history test/features/media test/features/sync --reporter compact 2>&1 | Out-File -Encoding utf8 $Log
    $E = $LASTEXITCODE
    $Watch.Stop()
    Write-Host "RUN=$Run EXIT=$E ELAPSED_MS=$($Watch.ElapsedMilliseconds)"
    Get-Content -Tail 30 $Log
    if ($E -ne 0) { exit $E }
  }
  ```

  Compare the second run to the 15.84-second warmed test-runner baseline, while reporting shell elapsed time separately.

- [ ] **Step 4: Generate after-LCOV for the exact same scope**

  ```powershell
  $Dir = Join-Path $env:TEMP 'oh-my-llm-fav-history-media-sync-cleanup'
  $After = Join-Path $Dir 'after-lcov.info'
  $Log = Join-Path $Dir 'after-coverage.log'
  flutter test test/features/favorites test/features/history test/features/media test/features/sync --coverage --coverage-path $After --reporter compact 2>&1 | Out-File -Encoding utf8 $Log
  $E = $LASTEXITCODE
  Write-Host "EXIT=$E COVERAGE_EXISTS=$(Test-Path $After)"
  Get-Content -Tail 150 $Log
  if ($E -ne 0 -or -not (Test-Path $After)) { exit 1 }
  ```

- [ ] **Step 5: List and classify every hit-to-miss production line**

  ```powershell
  function Read-Lcov([string]$Path) {
    $Hits = @{}
    $Source = ''
    foreach ($Line in Get-Content $Path) {
      if ($Line -like 'SF:*') {
        $Source = $Line.Substring(3).Replace('\', '/')
      } elseif ($Line -match '^DA:(\d+),(\d+)') {
        $Hits["$Source`:$($Matches[1])"] = [int]$Matches[2]
      }
    }
    return $Hits
  }

  $Dir = Join-Path $env:TEMP 'oh-my-llm-fav-history-media-sync-cleanup'
  $Before = Read-Lcov (Join-Path $Dir 'baseline-lcov.info')
  $After = Read-Lcov (Join-Path $Dir 'after-lcov.info')
  $Lost = foreach ($Key in $Before.Keys) {
    if ($Before[$Key] -gt 0 -and (-not $After.ContainsKey($Key) -or $After[$Key] -eq 0)) { $Key }
  }
  $Lost | Sort-Object
  Write-Host "HIT_TO_MISS=$(@($Lost).Count)"

  $FeatureStats = @{}
  $Feature = $null
  foreach ($Line in Get-Content (Join-Path $Dir 'after-lcov.info')) {
    if ($Line -like 'SF:*') {
      $Source = $Line.Substring(3).Replace('\', '/')
      $Feature = if ($Source -match '(?:^|/)lib/features/(favorites|history|media|sync)/') { $Matches[1] } else { $null }
      if ($Feature -and -not $FeatureStats.ContainsKey($Feature)) {
        $FeatureStats[$Feature] = [PSCustomObject]@{ LF = 0; LH = 0 }
      }
    } elseif ($Feature -and $Line -like 'LF:*') {
      $FeatureStats[$Feature].LF += [int]$Line.Substring(3)
    } elseif ($Feature -and $Line -like 'LH:*') {
      $FeatureStats[$Feature].LH += [int]$Line.Substring(3)
    }
  }
  $FeatureStats.GetEnumerator() | Sort-Object Name | ForEach-Object {
    $Pct = [math]::Round(100 * $_.Value.LH / $_.Value.LF, 2)
    Write-Host "$($_.Name) LH=$($_.Value.LH) LF=$($_.Value.LF) PCT=$Pct"
  }
  ```

  For every line, inspect its source and classify it as incidental implementation execution, covered by a stronger contract with different execution, or lost behavior. Restore a meaningful test for the third category before continuing.

- [ ] **Step 6: Run formatting, architecture, analyzer, and diff gates**

  ```powershell
  $ChangedDart = git diff --name-only (git log -1 --format=%H -- docs/superpowers/plans/2026-08-11-favorites-history-media-sync-test-cleanup.md) -- '*.dart'
  if ($ChangedDart) { dart format --output=none --set-exit-if-changed $ChangedDart }
  dart run tool/check_import_boundaries.dart
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  flutter analyze
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  git diff --check
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  ```

- [ ] **Step 7: Run the full test suite exactly as required**

  ```powershell
  flutter test --reporter compact 2>&1 | Out-File -Encoding utf8 fltest.log
  $E = $LASTEXITCODE
  Write-Host "EXIT=$E"
  Get-Content -Tail 150 fltest.log
  if ($E -ne 0) { exit $E }
  ```

- [ ] **Step 8: Audit implementation scope**

  ```powershell
  $PlanCommit = git log -1 --format=%H -- docs/superpowers/plans/2026-08-11-favorites-history-media-sync-test-cleanup.md
  $Changed = git diff --name-only "$PlanCommit..HEAD"
  $Changed
  $OutOfScope = $Changed | Where-Object {
    $_ -notmatch '^test/features/(favorites|history|media|sync)/'
  }
  if ($OutOfScope) {
    Write-Error "OUT_OF_SCOPE:`n$($OutOfScope -join "`n")"
    exit 1
  }
  ```

  Expected: only the four approved test directories changed after the plan commit; no `pubspec.yaml` bump exists.

- [ ] **Step 9: Prepare the final disposition report**

  Report:

  - before/after files, lines, executed cases, warm timing, and feature coverage;
  - deleted files and tests with continuing same-layer protection;
  - parameterized matrices and all retained named rows;
  - fragile tests rewritten around public outcomes;
  - unique tests deliberately retained, especially accessibility and Sync security/protocol cases;
  - the retained probabilistic shuffle test and three UDP waits as production-seam limitations;
  - every LCOV hit-to-miss line and classification;
  - fresh targeted, scoped, architecture, analyzer, full-suite, formatting, diff, and scope evidence.
