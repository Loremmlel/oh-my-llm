# Copilot Instructions for `oh-my-llm`

## Build, test, and lint commands

This repository uses standard Flutter CLI commands for day-to-day work, plus root PowerShell scripts for release packaging.

```powershell
flutter pub get
flutter analyze
flutter test
flutter test test\features\chat\chat_screen_test.dart
flutter test test\features\chat\chat_screen_test.dart --plain-name "chat screen copies raw message content without reasoning"
flutter test test\features\chat\application\chat_sessions_controller_test.dart
flutter test test\core\persistence\app_database_migration_test.dart
flutter test test\app\shell\app_shell_scaffold_test.dart
flutter build windows
flutter build apk
.\build-windows-release.ps1
.\build-android-apk.ps1
```

## Repository workflow

- Prefer small, audited changes. If a feature block is complete, commit it before moving on.
- When splitting large Dart files, use `import` / `export` boundaries instead of `part` / `part of`.
- Keep existing behavior intact unless the task explicitly asks for a behavior change.
- Keep generated release artifacts in `artifacts\` and do not commit local Android signing files such as `android\key.properties` or `android\app\self-use-release.jks`.

## Comment style guide

Comments should use Simplified Chinese and follow these conventions (reference: `lib\features\chat\presentation\widgets\streaming_markdown_view.dart`):

**Doc comments** (use `///`):
- Classes and public methods: detailed explanation of purpose, mechanism, and when to use
- Complex items: include examples, formulas, or usage patterns (e.g., dynamic interval formula in `StreamingMarkdownView`)
- Fields: add doc comments if their purpose is not self-evident
- Never place doc comments after `@override`; place them before the annotation

**Inline comments** (use `//`):
- Prefer explanatory comments (explain "why", not "what") over descriptive ones
- Only add descriptive comments when code is complex, verbose, or impossible to understand directly
- Keep comments concise and end with a period

**Section dividers for large classes:**
- Use format: `// ── Category ──────────────────────────────────────────────────────────────`
- Group related methods (e.g., lifecycle, public operations, private helpers) for clarity

## High-level architecture

- The app boots through `lib\main.dart` -> `lib\bootstrap.dart`, where `SharedPreferences` is created once and injected through Riverpod via `sharedPreferencesProvider`.
- `lib\app\app.dart`, `lib\app\navigation\app_destination.dart`, `lib\app\router\app_router.dart`, and `lib\app\shell\app_shell_scaffold.dart` define the global shell: GoRouter owns the four top-level screens (`chat`, `history`, `favorites`, `settings`), and the shell swaps between desktop `NavigationRail` and compact mobile `NavigationBar` / `endDrawer` layouts. The favorites detail page is a separate route.
- The codebase follows a feature-first split under `lib\features\...`, usually with `application`, `data`, `domain`, and `presentation` layers:
  - `settings`: local CRUD for model configs, prompt templates, fixed prompt sequences, and chat defaults
  - `chat`: conversation state, persistence, streaming client, and the main chat UI
  - `history`: grouped search / rename / batch delete UI over the same conversation state
  - `favorites`: saved assistant replies, collection management, and the favorites detail view
- Persistent state is local-first. Model configs and chat defaults still use SharedPreferences-backed JSON, while chat history, prompt templates, fixed prompt sequences, favorites, and collections now live in SQLite through `core\persistence\app_database.dart`. `chat_defaults` is a single JSON object, not a versioned list.
- `lib\features\chat\application\chat_sessions_controller.dart` is the center of the app. It owns:
  - active conversation selection
  - creation / rename / delete
  - sending messages
  - edit-and-regenerate behavior
  - retrying only the latest assistant reply
  - streaming assistant updates into persisted state
  - error handling and inline error display (errors appear as assistant messages in the conversation, not as popups)
- Chat requests are built manually in `lib\features\chat\data\openai_compatible_chat_client.dart` using `package:http`, not an SDK. The client uses a **Strategy pattern** (`VendorPayloadAdapterRegistry` in `vendor_payload_adapters.dart`) to handle per-vendor API differences:
  - **OpenAI official**: sends native `reasoning_effort`, receives `delta.reasoning_content`
  - **Google AI compatible**: sends `extra_body.google.thinking_config.include_thoughts: true`, receives `delta.thinking` or `extra_content.google.thought_signature`
  - **DeepSeek**: sends `thinking: {"type": "enabled"|"disabled"}`, receives `delta.thinking_content`
  - **Other compatible hosts**: normalized `thinking` field, receives `delta.reasoning_content`
- SSE parsing is factored into `lib\features\chat\data\chat_chunk_parser.dart` (`ChatChunkParser` class), which handles:
  - Splitting `<thought>` XML tags (Google Gemma models)
  - Accumulating various `thinking` fields (`delta.thinking`, `delta.reasoning_content`, `delta.thinking_content`)
  - Correctly merging high-frequency chunks in the 300 ms flush window without losing vendor-specific fields
- Stream state (`ChatStreamingReply`, `ChatSessionsState`, `applyStreamingReplyToConversation`) is factored into `lib\features\chat\application\chat_sessions_state.dart` to reduce controller file size; the controller re-exports this module so downstream imports remain unchanged.
- Scroll and anchor logic is factored into `lib\features\chat\presentation\chat_scroll_controller.dart` (`ChatScrollController`), using callbacks to communicate with the owning `State` widget.
- Markdown rendering uses a dual-engine switch in `lib\features\chat\presentation\widgets\chat_markdown_engine.dart`: default `flutter_smooth_markdown` StreamMarkdown path (no length-based full re-render interval), with legacy `flutter_markdown_plus` kept as rollback path during migration.
- Network logging is centralized in `lib\core\logging\app_logger.dart` (singleton pattern), writing to `{AppData}/app_log.txt`. All HTTP requests/responses/errors are recorded for debugging vendor API compatibility issues.
- History and chat share the same time-grouping logic from `lib\features\chat\domain\chat_conversation_groups.dart`; if grouping behavior changes, update both surfaces consistently.

## Key conventions

- New chat conversations inherit **default model** and **default prompt template** from settings. The chat screen no longer lets users pick them directly; those defaults are managed in `SettingsScreen`.
- **Model display in UI**: Assistant messages show the actual model's display name (e.g., "DeepSeek V4 Flash", "Gemini 3.1 Flash Lite") instead of generic "Model" label. Stored in `ChatMessage.assistantModelDisplayName`, displays as "Anonymous Model" if empty (for migrated older records).
- Fixed prompt sequences are **user-message-only** ordered steps for manual comparison workflows. They are configured in settings, launched from the chat composer through an independent runner dialog, and must never auto-send the whole sequence in one go.
- Reasoning is modeled separately from answer text:
  - assistant reply text lives in `ChatMessage.content`
  - reasoning content lives in `ChatMessage.reasoningContent` (vendor-agnostic, normalized internally)
  - reasoning metadata lives in `ChatMessage.assistantModelDisplayName`
  - UI, persistence, and copy behavior should keep them separate; each feature must decide independently whether to show reasoning
- Prompt templates are prepended to request history in `ChatSessionsController._buildRequestMessages()` as:
  1. system prompt, if present
  2. template messages
  3. conversation messages
- Editing an older user message does **not** replay the rest of the conversation. The controller truncates after the edited user turn, then regenerates a new assistant reply from that point.
- History search intentionally matches only conversation title and **user** messages, never assistant replies.
- Conversation titles are derived from the first user message (`15` characters via `characters`) unless the user renamed the conversation explicitly. Custom titles show only the title in history list (no preview text) to save space on mobile; desktop shows tooltip on hover.
- The OpenAI-compatible request payload is host-sensitive (handled by `VendorPayloadAdapterRegistry`):
  - official OpenAI hosts: omit `thinking`, send native `reasoning_effort`
  - Google AI compatible: omit `reasoning_effort`, send `extra_body.google.thinking_config.include_thoughts: true`
  - DeepSeek and others: send `thinking: {"type":"enabled"|"disabled"}`
  - compatible-host effort values are normalized in adapters before sending
- On mobile, the favorites detail top metadata bar must always enforce width constraints and prevent horizontal overflow (long timestamps/source titles must wrap or ellipsize safely).
- Widget tests usually seed storage with `SharedPreferences.setMockInitialValues(...)` and inject dependencies with `ProviderScope` overrides. When chat history, favorites, or collections are involved, also override `appDatabaseProvider` with the test database helper.
- When splitting tests, keep only one runnable `*_test.dart` entrypoint per suite; move shared cases into helper files such as `*_cases.dart` so Flutter does not discover them as separate test targets.
- This repo is being developed in small audited increments: each completed feature or fix is expected to be committed separately instead of batching unrelated work into one commit.

## Test coverage

Test structure: single `*_test.dart` entry point + multiple `*_cases.dart` helpers. Cases files export `void registerXxxTests()` but are NOT runnable test targets.

**Core test files:**
- `test/features/favorites/` — FavoritesScreen, FavoriteDetailScreen, ManageCollectionsDialog widget tests; FavoritesController unit tests
- `test/features/chat/chat_screen/chat_screen_favorites_cases.dart` — Chat↔Favorites bookmark flow
- `test/features/chat/application/chat_sessions_controller_test.dart` — ChatSessionsController: create/rename/delete conversations, send messages, edit, retry, error handling
- `test/core/persistence/app_database_migration_test.dart` — AppDatabase schema: user_version=3, all V1-V3 tables, default values, FK cascades, indexes
- `test/app/shell/app_shell_scaffold_test.dart` — AppShellScaffold: wide layout (NavigationRail), compact layout (NavigationBar), breakpoint behavior

**Test patterns:**
- Widget tests: `SharedPreferences.setMockInitialValues(...)` + `ProviderScope(overrides: [...appDatabaseProvider])` + `pumpWidget`
- Unit tests: `ProviderContainer` + `AppDatabase.inMemory()` + `ProviderContainer.read()` / `read(...notifier)`
- Fake clients: `FakeChatCompletionClient` (from test helpers) with `enqueueChunks()` and `enqueueError()` for streaming tests
- Database: `createTestDatabase(preferences)` runs full migration stack V1→V3
- Error injection: catch `ChatCompletionException` in controller; stream.error() for null-content cleanup tests
- Parser tests: inject mock vendor adapters via constructor to validate Strategy pattern behavior per vendor
- Adapter tests: verify payload construction, field presence/absence, and error handling for each vendor

## Test design rules

### Layer boundaries

- `widget test` should focus on user-visible paths, cross-widget integration, and final observable outcomes.
- `controller / application test` should cover state transitions, branching, request context assembly, checkpoint injection, exclusion logic, and error handling.
- `data / client test` should cover vendor differences, payload construction, SSE parsing, and error propagation.
- `domain / repository / migration test` should cover model contracts, persistence semantics, grouping rules, and migration safety.
- If lower layers already have stable contract tests, do not reassert the same internal details in widget tests.

### Assertion priority

Prefer assertions on:

1. final business result or state,
2. persisted data,
3. final request content,
4. core user-visible output.

Avoid using these as the primary assertion unless there is no better option:

- exact `find.byTooltip(...)` copy,
- exact snackbar / label / counter text,
- private `ValueKey(...)` structure,
- `requestHistory[N]` magic indexes,
- provider internals from widget tests,
- widget implementation details such as `maxLines`, `subtitle`, or `Scrollbar.controller`.

If a tooltip must be used to locate an action, pair it with a business-result assertion rather than asserting the tooltip text itself.

### Feature examples

- Chat widget tests should not directly assert `userMessageSegments`, default prompt/model provider state, or builder-level request assembly details. “Remember model / Prompt” scenarios should prefer verifying the next real send, and request assertions should target the request produced by the current action (for example `.last`) rather than fixed indexes.
- Favorites widget tests should prefer saved state, source metadata, and navigation results over snackbar copy, tooltip copy, or list-item rendering details.
- History widget tests should prefer visible list changes and navigation outcomes over reading `chatSessionsProvider` or hard-coding debounce timing constants.
- Settings widget tests should prefer repository / persisted-data assertions over dialog copy, form controller text, or duplicated wide-layout structure checks across multiple dialogs.

### Test shape and maintenance

- Keep a single runnable `*_test.dart` entrypoint and move shared scenario bodies into `*_cases.dart`.
- Prefer helpers and combination tests over many tiny trim / empty / single-field passthrough tests.
- Before adding a widget test, check:
  1. Is this a user-noticeable regression?
  2. Should this assertion still hold after a UI refactor?
  3. Is the same behavior already covered at a lower layer?

If the answer to 2 or 3 is "no", prefer moving the assertion down a layer, merging it into a broader contract test, or deleting it.

## Design patterns and refactoring

**Strategy Pattern (vendor payload adapters):**
- `VendorPayloadAdapter` interface abstracts vendor-specific API differences
- `VendorPayloadAdapterRegistry` holds a registry of adapter implementations (OpenAI, Google, DeepSeek, Default)
- `OpenAiCompatibleChatClient` queries the registry to get the correct adapter, then calls `buildPatch()` to customize the request payload
- Benefit: eliminates vendor-specific `if` branches scattered throughout the client; new vendors can be added by implementing the interface and registering with the registry

**File splitting with export boundaries:**
- When a file exceeds ~300-400 lines, split into focused modules using `import` / `export` boundaries
- Example: `ChatSessionsState` extracted from `ChatSessionsController` into separate file; controller re-exports to keep external imports unchanged
- Example: `ChatChunkParser` extracted from `OpenAiCompatibleChatClient` into separate file; parser handles all SSE frame decoding
- Example: `ChatScrollController` extracted from `ChatScreen` to isolate scroll/anchor management
- Benefit: improved readability, testability, and reduced circular import risk

**Singleton pattern (logging):**
- `AppLogger` initialized once in `bootstrap.dart`, injected as dependency where needed
- Centralized logging of all HTTP traffic for debugging vendor API compatibility issues
- Automatic cleanup when log file exceeds 1 MB or on app shutdown
