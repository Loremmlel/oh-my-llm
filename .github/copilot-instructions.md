# Copilot Instructions for `oh-my-llm`

## Build, test, and lint commands

This repository uses standard Flutter CLI commands for day-to-day work, plus root PowerShell scripts for release packaging.

```powershell
flutter pub get
flutter analyze
flutter test
flutter test test\features\chat\chat_screen_test.dart
flutter test test\features\chat\chat_screen_test.dart --plain-name "chat screen copies raw message content without reasoning"
flutter build windows
flutter build apk
.\build-windows-release.ps1
.\build-android-apk.ps1
```

## Repository workflow

- Prefer small, audited changes. If a feature block is complete, commit it before moving on.
- When splitting large Dart files, use `import` / `export` boundaries instead of `part` / `part of`.
- New comments and doc comments should use Simplified Chinese. Use `///` for doc comments and keep inline comments focused on explaining why.
- Keep existing behavior intact unless the task explicitly asks for a behavior change.
- Keep generated release artifacts in `artifacts\` and do not commit local Android signing files such as `android\key.properties` or `android\app\self-use-release.jks`.

## High-level architecture

- The app boots through `lib\main.dart` -> `lib\bootstrap.dart`, where `SharedPreferences` is created once and injected through Riverpod via `sharedPreferencesProvider`.
- `lib\app\app.dart`, `lib\app\router\app_router.dart`, and `lib\app\shell\app_shell_scaffold.dart` define the global shell: GoRouter owns the three top-level screens (`chat`, `history`, `settings`), and the shell swaps between desktop `NavigationRail` and compact mobile `NavigationBar` / `endDrawer` layouts.
- The codebase follows a feature-first split under `lib\features\...`, usually with `application`, `data`, `domain`, and `presentation` layers:
  - `settings`: local CRUD for model configs, prompt templates, and chat defaults
  - `chat`: conversation state, persistence, streaming client, and the main chat UI
  - `history`: grouped search / rename / batch delete UI over the same conversation state
- Persistent state is local-first. Lightweight settings and templates still use SharedPreferences-backed JSON, while chat history now lives in SQLite through `core\persistence\app_database.dart` and `sqlite_chat_conversation_repository.dart`. `chat_defaults` is a single JSON object, not a versioned list.
- `lib\features\chat\application\chat_sessions_controller.dart` is the center of the app. It owns:
  - active conversation selection
  - creation / rename / delete
  - sending messages
  - edit-and-regenerate behavior
  - retrying only the latest assistant reply
  - streaming assistant updates into persisted state
- Chat requests are built manually in `lib\features\chat\data\openai_compatible_chat_client.dart` using `package:http`, not an SDK. The client parses SSE-style `data:` lines, separates assistant answer text from reasoning text, and applies different request payload rules for official OpenAI hosts vs other OpenAI-compatible hosts.
- History and chat share the same time-grouping logic from `lib\features\chat\domain\chat_conversation_groups.dart`; if grouping behavior changes, update both surfaces consistently.

## Key conventions

- New chat conversations inherit **default model** and **default prompt template** from settings. The chat screen no longer lets users pick them directly; those defaults are managed in `SettingsScreen`.
- Reasoning is modeled separately from answer text:
  - assistant reply text lives in `ChatMessage.content`
  - provider reasoning lives in `ChatMessage.reasoningContent`
  - UI, persistence, and copy behavior should keep them separate
- Prompt templates are prepended to request history in `ChatSessionsController._buildRequestMessages()` as:
  1. system prompt, if present
  2. template messages
  3. conversation messages
- Editing an older user message does **not** replay the rest of the conversation. The controller truncates after the edited user turn, then regenerates a new assistant reply from that point.
- History search intentionally matches only conversation title and **user** messages, never assistant replies.
- Conversation titles are derived from the first user message (`15` characters via `characters`) unless the user renamed the conversation explicitly.
- The OpenAI-compatible request payload is host-sensitive:
  - official OpenAI hosts: omit `thinking`, send native `reasoning_effort`
  - other compatible hosts: send `thinking: {"type":"enabled"|"disabled"}`
  - compatible-host effort values are normalized in the client before sending
- Widget tests usually seed storage with `SharedPreferences.setMockInitialValues(...)` and inject dependencies with `ProviderScope` overrides. When chat history is involved, also override `appDatabaseProvider` with the test database helper.
- When splitting tests, keep only one runnable `*_test.dart` entrypoint per suite; move shared cases into helper files such as `*_cases.dart` so Flutter does not discover them as separate test targets.
- This repo is being developed in small audited increments: each completed feature or fix is expected to be committed separately instead of batching unrelated work into one commit.
