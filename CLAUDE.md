# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.
## Notice
You should call user "主人"

## Commands

```powershell
flutter pub get                  # Install dependencies
flutter analyze                  # Static analysis
flutter test                     # Run all tests
flutter test path/to/test.dart   # Run a single test file
flutter test path/to/test.dart --plain-name "test name"  # Run a single test case
flutter run -d windows           # Run on Windows
flutter build windows            # Build Windows release
flutter build apk                # Build Android APK
.\build-windows-release.ps1      # Package Windows release (outputs to artifacts\)
.\build-android-apk.ps1          # Package Android APK (outputs to artifacts\)
```

## Architecture

This is a Flutter desktop/mobile LLM chat client (`oh_my_llm`) targeting Windows and Android. It uses **Riverpod** for state management, **GoRouter** for navigation, **SQLite** (via `sqlite3` v3 with native build hooks) for chat history/favorites/templates, and **SharedPreferences** JSON for provider/model configs.

### Boot sequence

`main.dart` → `bootstrap.dart` initializes `SharedPreferences`, `AppDatabase` (SQLite), runs data migrations (legacy SharedPreferences → SQLite), and starts the network logger. Everything is injected via Riverpod providers (`sharedPreferencesProvider`, `appDatabaseProvider`).

### Navigation shell

`lib/app/shell/app_shell_scaffold.dart` provides responsive navigation: `NavigationRail` on wide screens (≥840dp), `NavigationBar` + `endDrawer` on compact. GoRouter (in `lib/app/router/app_router.dart`) owns the four top-level routes (`/chat`, `/history`, `/favorites`, `/settings`) plus `/favorites/detail`.

### Feature-first structure

Each feature under `lib/features/<name>/` follows a layered split:

- **`chat/`** — The core of the app. `ChatSessionsController` (in `application/`) is the central orchestrator: it handles conversation CRUD, message sending, streaming updates, edit-and-regenerate (message tree), retry, and error-as-message display. `ChatSessionsState` is factored into a separate file to keep the controller manageable.
- **`settings/`** — CRUD for provider configs (SharedPreferences JSON), prompt templates (SQLite), fixed prompt sequences (SQLite), memory prompts (SQLite), and chat defaults.
- **`history/`** — Grouped search/rename/batch-delete over conversations. Shares time-grouping logic with chat via `lib/features/chat/domain/chat_conversation_groups.dart`.
- **`favorites/`** — Saved assistant replies with collection management.

### Streaming and vendor adapter architecture

Chat requests are sent via raw `package:http` (no SDK). The **Strategy pattern** in `lib/features/chat/data/vendor_payload_adapters.dart` handles per-vendor API differences:

- `VendorPayloadAdapter` interface → `VendorPayloadAdapterRegistry` → per-vendor implementations (OpenAI official, Google AI, DeepSeek, default compatible)
- `OpenAiCompatibleChatClient` queries the registry for the matching adapter, calls `buildPatch()` to customize the payload
- SSE parsing is in `ChatChunkParser` (`lib/features/chat/data/chat_chunk_parser.dart`): handles `<thought>` XML tags, accumulates vendor-specific thinking fields, merges chunks within a 300ms flush window

### Dual markdown engine

`lib/features/chat/presentation/widgets/chat_markdown_engine.dart` switches between `flutter_smooth_markdown` (default, streaming-native) and legacy `flutter_markdown_plus` (rollback path). UI updates throttle at 300ms regardless of engine.

### Persistence split

| Data | Storage |
|------|---------|
| Chat history, favorites, collections, templates, fixed sequences, memory prompts | SQLite (`chat_history.sqlite`) |
| Provider/model configs, chat defaults, recent selections | SharedPreferences JSON |

Legacy SharedPreferences data auto-migrates to SQLite on first launch; old keys are deleted after migration.

## Key conventions

- **Error display**: Chat errors appear as inline assistant messages in the conversation, not as popups/snackbars.
- **Reasoning/content split**: Assistant reply text → `ChatMessage.content`, reasoning → `ChatMessage.reasoningContent`. UI, persistence, and copy behavior keep them separate.
- **Message tree**: Editing a user message truncates the conversation after that turn and regenerates a new branch. The old branch is preserved. Only the latest assistant reply can be retried.
- **Conversation titles**: Auto-derived from the first user message (15 characters via `characters` package), unless manually renamed. Custom titles show no preview text in history.
- **History search**: Matches conversation titles and user messages only, never assistant replies.
- **Prompt template prepending order**: system prompt → template messages → conversation messages.
- **Comment style**: Simplified Chinese. `///` for doc comments, `//` for inline ("why", not "what"). Large classes use `// ── Category ────...` dividers.
- **File splitting**: Use `import`/`export` boundaries, never `part`/`part of`.
- **Commits**: Each feature/fix as a separate commit. Don't batch unrelated changes.
- **After `flutter upgrade`**: Run `flutter clean` before `flutter test`. Stale shader caches cause spurious Asset manifest failures.

## Test patterns

Tests use Riverpod's `ProviderContainer` + `ProviderScope` for dependency injection. Key patterns:

```dart
// Widget tests: seed storage + override providers
SharedPreferences.setMockInitialValues({...});
await tester.pumpWidget(
  ProviderScope(
    overrides: [appDatabaseProvider.overrideWith((ref) => testDb)],
    child: const MaterialApp(home: WidgetUnderTest()),
  ),
);

// Unit tests: create container + read notifiers
final container = ProviderContainer(
  overrides: [appDatabaseProvider.overrideWith((ref) => AppDatabase.inMemory())],
);
final controller = container.read(chatSessionsControllerProvider.notifier);

// Fake streaming client
final fake = FakeChatCompletionClient();
fake.enqueueChunks([...]);  // enqueue streaming chunks
fake.enqueueError(exception);  // enqueue an error
```

- Test files use a single `*_test.dart` entry point; shared cases go into `*_cases.dart` helper files (not discovered as test targets).
- Database tests use `AppDatabase.inMemory()` or `createTestDatabase(preferences)` which runs the full V1→V3 migration stack.
- When chat history, favorites, or collections are involved, always override `appDatabaseProvider`.
- Assert on business results, persisted data, or final request content — avoid asserting on widget implementation details, tooltip text, or private keys.

### Test anti-patterns — what NOT to test

- **Don't duplicate across layers**: Test behavior at the source of truth. If a repository method is a thin pass-through to the database, test it at the database/repository layer, not the controller. ON DELETE SET NULL cascade belongs in schema tests, not controller tests.
- **Don't assert widget implementation details**: No `find.byKey` for internal keys, no `findsNothing` on widget types, no exact pixel positions, no widget property values (`expands`, `maxLines`, `minLines`). These break on any refactoring.
- **Don't test trivial mappings**: Enum-to-enum conversions, default values, and generated `copyWith`/`toJson` boilerplate don't need dedicated tests — they're implicitly covered by integration-level tests.
- **Don't write conditional-early-return tests**: A test that can `return` without hitting any `expect` is structurally meaningless.
- **Don't write meta-tests**: Tests that verify two functions produce identical output test implementation consistency, not correctness.
- **Prefer `>=` over `==` for version numbers**: Schema/user_version assertions should use `greaterThanOrEqualTo(N)`.

### What's worth testing at each layer

| Layer | Test focus |
|-------|-----------|
| Domain/model | Non-trivial pure logic: tree manipulation, message building, template parsing |
| Data/repository | Save/load round-trips, query filtering, migration correctness |
| Controller | State transitions, error handling, streaming lifecycle |
| Widget | User-visible behavior: CRUD flows, navigation, dialog interactions |

Pattern duplication across entity types (e.g., CRUD tests for different entities) is acceptable when the entities differ in schema and UX.
