# SDD ledger — plan: docs/superpowers/plans/2026-08-18-settings-transfer-registry.md

## Setup

- Worktree: `D:/personal/oh-my-llm/.worktrees/settings-transfer-registry`
- Branch: `codex/settings-transfer-registry`
- Starting HEAD: `af00c2ef83d0b0d6491ecda13eac3872dfd4fbb2`
- Hook path: `D:\personal\oh-my-llm\.githooks`
- Current version: `3.60.6+0` (the plan's historical baseline was re-read and not assumed)
- Toolchain: Flutter 3.44.8 stable / Dart 3.12.2; both satisfy the plan's allowed range.
- Initial focused baseline failed before tests because the sqlite3 native-assets download hit a TLS handshake error. `Invoke-WebRequest` to the same URL returned HTTP 200 and the existing validated `build/native_assets/windows/sqlite3.dll` from the main checkout was copied into this worktree's generated build directory. The baseline was then rerun successfully: `96` tests, `EXIT=0`, `logs/settings-transfer-baseline.log`.

## Preflight scan

The scan checked the plan's Global Constraints, every task's own file/interface/test consistency, and every pair of tasks sharing a file or interface before Task 1 dispatch.

| Row | Tasks | Shared file or interface | Producer / consumer relationship | Finding and ruling |
| --- | --- | --- | --- | --- |
| P1 | 1 → 3 | `SettingsTransferDocument` and top-level codec | Task 1 defines the v9 document; Task 3 decodes/creates it in the coordinator | Compatible; Task 3 must consume the exact v9 result types and keep participant routing out of the domain codec. |
| P2 | 1 → 7 | Structured `SettingsTransferDocument` Sync payload | Task 1 defines the wire-safe document; Task 7 embeds it in Sync v4 | Compatible; Sync may import the domain document but not Settings application/presentation. |
| P3 | 2 → 3 | Participant/catalog types and typed change boxes | Task 2 defines the catalog and erasure boundary; Task 3 consumes it for generic coordination | Compatible; coordinator branches only on typed catalog contracts, never concrete settings fields. |
| P4 | 2 → 4 | `SettingsTransferParticipant<T>` and summary/change contracts | Task 2 defines the participant API; Task 4 implements five concrete participants | Compatible; collection participants own codec/merge semantics behind the shared contract. |
| P5 | 2 → 5 | Participant API, groups, sensitivity and catalog lookup | Task 2 defines primitives; Task 5 registers the replacing participants and production catalog | Compatible; replacing participants use the same typed contract and no second registration list. |
| P6 | 3 → 4 | Coordinator change preparation and participant `applyImport` contract | Task 3 executes prepared changes; Task 4 supplies collection changes/writers | Compatible; Task 4 must preserve prepare write-free and persistence-ACK semantics. |
| P7 | 3 → 5 | Coordinator/catalog provider composition | Task 3 supplies the coordinator; Task 5 creates the production catalog/provider binding | Compatible; Task 5 must register all nine only once. |
| P8 | 3 → 6 | `SettingsExportPreparation` / `SettingsImportPreparation` and batch execution | Task 3 supplies application operations; Task 6 adapts Clipboard UI to them | Compatible; Clipboard stays in Settings presentation and application confirmation remains authoritative. |
| P9 | 3 → 7 | Coordinator-backed Settings Sync facade | Task 3 supplies export/prepare/execute; Task 7 projects it through the Sync-owned port | Compatible; facade maps DTOs mechanically and does not enumerate concrete participants. |
| P10 | 4 → 5 | `settings_transfer_participants_test.dart` and five participant implementations | Task 4 owns collection participants/tests; Task 5 extends the same test surface for replacing participants | Compatible; Task 5 must preserve Task 4 coverage and only add its owned cases. |
| P11 | 4 → 9 | Real SQLite/provider composition | Task 4 fixes provider ACK order and collection persistence; Task 9 proves cross-store integration | Compatible; integration consumes the corrected public behavior, not private controller details. |
| P12 | 5 → 6 | Production catalog/provider and replacing participant behavior | Task 5 assembles the registry; Task 6 consumes it for Clipboard export/import | Compatible; empty replace sections remain explicit clear commands. |
| P13 | 5 → 7 | Production catalog projection through Sync facade | Task 5 provides the nine registrations; Task 7 derives Sync groups/sensitivity | Compatible; Sync has no parallel field enumeration. |
| P14 | 5 → 9 | Catalog contract snapshot and real composition | Task 5 locks the production key/fixture snapshot; Task 9 validates final composition and local-only exclusions | Compatible; final cleanup must leave the snapshot as the only production registration proof. |
| P15 | 6 → 9 | Legacy workflow/executor retirement boundary | Task 6 removes Settings presentation consumers but intentionally leaves legacy files for old Sync; Task 9 deletes them after migration | Compatible; no legacy file is deleted before Task 7/8 consumers are migrated. |
| P16 | 7 → 8 | Sync controller, `sync_types.dart`, operation/import widgets, fakes and controller/UI tests | Task 7 introduces v4 port/protocol and temporary prepared-import state; Task 8 completes descriptor-driven controller/UI migration | Sequential dependency, not a contradiction; Task 8 consumes Task 7's DTO/result names and removes the four-category adapter. |
| P17 | 7 → 9 | Sync v4/v9 protocol and integration vocabulary | Task 7 migrates production protocol; Task 9 updates integration tests and removes legacy aggregates | Compatible; integration cleanup occurs only after v4/v9 paths are green. |
| P18 | 8 → 9 | Removal of `SyncCategory`/`SettingsSyncSelection` and final integration assertions | Task 8 removes the category adapter; Task 9 performs zero-hit audits and final end-to-end checks | Compatible; Task 9 treats any remaining production/test hit as a failure. |
| C1 | 1 | v9 document tests vs document/codec files | Tests cover round-trip, strict top-level shape, version errors and defensive immutability required by the code contract | Self-consistent; no conflict. |
| C2 | 2 | Catalog tests vs typed primitives/catalog files | Tests cover registration validation, ordering, sensitivity and typed lookup supplied by the public contracts | Self-consistent; no conflict. |
| C3 | 3 | Fake-participant tests vs coordinator API and sealed results | Tests cover export, prepare, stale, serialization, partial failure, locking and one-shot execution | Self-consistent; no conflict. |
| C4 | 4 | Merger/controller/participant tests vs five concrete implementations | Tests exercise merge priority, ACK ordering, collection codecs and no-op semantics named by the task | Self-consistent; no conflict. |
| C5 | 5 | Replacing participants, production catalog and contract snapshot | Tests bind the exact nine keys, groups, sensitivities and canonical fixtures to v9 | Self-consistent; no conflict. |
| C6 | 6 | Clipboard/preset UI changes vs helpers/cases/dialog tests | Tests exercise global import, current-tab export, sensitive confirmation, clear sections and standard preset documents | Self-consistent; no conflict. |
| C7 | 7 | Facade/port/protocol rewrites vs Sync protocol/facade/controller tests | Tests cover v4 versioning, structured document payloads, subset/sensitivity validation and prepared-import mapping | Self-consistent; no conflict. |
| C8 | 8 | Dynamic controller/UI changes vs descriptor-driven tests | Tests cover production and fake groups, select-all, sensitivity, summaries and state reset | Self-consistent; no conflict. |
| C9 | 9 | Legacy deletion and integration tests | Integration tests are migrated and green before deletion, then zero-hit/static/focused/full gates verify retirement | Self-consistent; no conflict. |

No plan contradiction or plan-mandated review defect was found in the scan. Execution remains ordered because Tasks 6–8 intentionally share a bounded migration boundary.

## Decisions

Ruling: use the existing validated sqlite3 native asset from the main checkout to unblock the isolated-worktree baseline after independently confirming the download URL returned HTTP 200 — this keeps the test command unchanged and avoids changing dependency or certificate configuration; if the asset were stale, native SQLite behavior could be misrepresented, so the risk is limited by its exact package-generated path and matching current dependency cache.

Ruling: interpret the specification's unspecified “stable key rule” as the ASCII lower-camel grammar `[a-z][A-Za-z0-9]*` already used by all nine canonical participant keys and six group wire keys — this makes the v9 envelope reject punctuation/ambiguous wire names and keeps the document codec independent of the runtime catalog; if a future approved participant needs `_`, `-`, or an uppercase-leading key, this decision will require an explicit format-version/spec change or a reviewed task fix.

Task 1: minor (deferred): add JSON-text scalar/array malformed cases and a broader key boundary matrix if later coverage review still requires them; current implementation already rejects those shapes through the top-level map check.

Task 1: fix round 1/5 (1 addressed, 0 open — stable section-key grammar was documented and covered by legal-unknown/illegal-boundary tests; commits bcd3f62..4304248d)
Task 1: complete (commits af00c2e..4304248d, review clean)

Task 2: review finding (Important): `ErasedSettingsTransferParticipant` accepted arbitrary erased implementations and optional `SettingsTransferParticipantRuntime` allowed direct participants to bypass mandatory change/value type checks; the brief requires the box boundary to always validate participant identity and change type before apply.
Task 2: review finding (Minor/deferred): commit includes `pubspec.yaml` only because the repository post-commit version hook amends every commit; no source-scope fix is authorized or needed.
Task 2: fix round 1/5 (2 addressed, 1 open — sealed/forced box boundary and identity/value/fingerprint tests added; independent correct-valueType wrong-writeValue regression still open; commits 6a54b8d..848febd)
Task 2: fix round 2/5 (1 addressed, 0 open — application-internal erased change fixture isolates correct valueType with invalid writeValue and proves zero writer calls; commits 848febd..6bec465)
Task 2: minor (deferred): full suite still has the unrelated pre-existing `test/features/sync/application/sync_server_controller_test.dart:124` failure; Task 2 focused tests, analyze and boundary gate pass.
Task 2: complete (commits 4304248d..6bec4655, review clean)
Task 3: minor (deferred): `settings_transfer_coordinator.dart` uses package imports for same-feature domain files instead of the repository's relative-import style; final review should triage this without changing behavior.
Task 3: minor (deferred): one coordinator test title says “相同本地值” while its fixture intentionally uses a different local value; rename if the test remains in the final suite.
Task 3: minor (deferred): full suite still has the unrelated pre-existing `test/features/sync/application/sync_server_controller_test.dart:124` failure; Task 3 focused tests, analyze and boundary gate pass.
Task 3: complete (commits 6bec4655..50dc280d, review clean)
