# Favorites, History, Media, and Sync Test Cleanup Design

## Goal

Reduce low-value, redundant, fragile, and unnecessarily slow tests under these directories while preserving meaningful regression protection:

- `test/features/favorites`
- `test/features/history`
- `test/features/media`
- `test/features/sync`

The verified baseline contains 59 Dart files, 9,392 lines, and 457 executed test cases. A joint coverage run passes in 28.49 seconds; separate cold directory runs total 46.60 seconds because they repeat Flutter startup.

## Scope

Implementation changes are limited to test code in the four approved directories. The cleanup must not modify:

- `lib/` production code;
- test configuration, CI workflows, timeouts, or concurrency;
- tests outside the four approved directories.

This design document and its implementation plan are workflow artifacts. If a useful timing or determinism improvement requires a new production seam, retain the affected test and record the limitation instead of changing production code.

## Baseline Coverage

The baseline LCOV snapshot is stored outside the repository at `%TEMP%\oh-my-llm-fav-history-media-sync-cleanup\baseline-lcov.info`.

| Feature | Hit lines | Found lines | Line coverage |
|---|---:|---:|---:|
| Favorites | 498 | 538 | 92.57% |
| History | 245 | 256 | 95.70% |
| Media | 1,305 | 1,539 | 84.80% |
| Sync | 928 | 1,885 | 49.23% |

Small coverage decreases are acceptable. Every production line that changes from hit to miss must be classified. Any loss that represents an externally observable business, safety, compatibility, persistence, or lifecycle contract must be restored with a meaningful test.

## Decision Standard

Each registered test receives one of five dispositions:

| Disposition | Required evidence | Action |
|---|---|---|
| Keep | Protects a unique externally observable contract, decision branch, safety boundary, or compatibility rule | Leave intact except for clarity-only edits |
| Delete | Only proves fixture, constructor, framework, type, or implementation behavior, or is fully subsumed at the same layer | Remove the test and now-unused support code |
| Merge | Cases share the same contract, layer, and expected failure reason and differ only by named input/output data | Replace them with a table-driven test that retains case-specific diagnostics |
| Rewrite | The contract is useful but the test observes implementation details or relies on arbitrary scheduling | Assert visible behavior, semantics, navigation, public state, persistence, or an observable completion signal |
| Record | A worthwhile improvement requires production changes outside the approved scope | Retain the test and report the exact limitation |

Similar setup, overlapping line coverage, or the same user flow alone does not establish duplication. A deletion is allowed only when another existing test protects the same external contract at the same test layer and would fail for the same regression.

## Audit Method

For every test, identify:

1. the production behavior exercised;
2. the trigger or input;
3. the externally observable result;
4. the test layer and expected regression failure reason;
5. the nearest overlapping test;
6. the appropriate keep, delete, merge, rewrite, or record disposition.

Work one directory at a time and run its suite after each bounded batch. This keeps failures and coverage changes attributable to a small set of edits.

## Directory Priorities

### Favorites

Review domain constructor, `copyWith`, equality, and JSON cases for assertions that only restate generated or language behavior. Compare Repository, Controller, and Widget coverage for repeated CRUD outcomes. Preserve distinct contracts for collection cascades, uncategorized fallback, source-conversation linkage, ordering, persistence, search, and user-visible detail behavior.

### History

Consolidate search and pagination data variants when they exercise one decision branch. Remove tests that only prove Material disabled behavior or incidental pagination appearance. Preserve title and user-message search boundaries, assistant-message exclusion, page navigation/clamping, page-size behavior, rename/delete actions, and batch operation outcomes.

### Media

Treat Media as the main reduction target because it contains 274 executed cases and the largest presentation files. Compare video-player behavior tests with accessibility tests to eliminate same-layer duplication while preserving Semantics contracts. Consolidate MIME, path, HTTP range, cache, and scanner data matrices where appropriate. Replace page-class, `Scaffold`, `Slider`, icon, pixel, and internal-widget assertions with user-observable navigation, playback, state, resource-release, error, or semantics outcomes.

Preserve navigation, resource disposal, range and traversal safety, cache invalidation, filesystem boundaries, controller lifecycle, keyboard/semantics behavior, and empty/error states.

### Sync

Apply the most conservative deletion standard. Preserve protocol-version handling, typed message validation, cryptography, authentication, nonce/replay protection, secret/header isolation, import classification, persistence, and lifecycle boundaries even when they add little or no line coverage.

Optimize real UDP waits only when the same network contract can be observed deterministically from test code. Review repeated Controller happy paths and viewport variants for same-layer duplication. Retain any UDP timing case that cannot be made reliable without a production clock, socket, or scheduler seam, and record it as out of scope.

## Fragility and Timing Rules

- Do not add `pumpAndSettle`, arbitrary `Future.delayed`, real sleeps, timeout increases, pixel-position assertions, or new internal keys.
- A negative assertion must follow a positive event that proves the observation window completed.
- Use visible copy, Semantics, navigation results, callbacks, Provider state, Repository state, or explicit Future/stream completion as observables.
- Interacting with a Material control by type is acceptable when no stable public locator exists; asserting the control type as the product outcome is not.
- Do not merge accessibility tests into ordinary widget tests when their distinct failure reason is a Semantics regression.
- Do not replace deterministic boundary tests with statistical or timing-sampling assertions.
- Security and compatibility matrices may be parameterized, but all named categories and malformed-input boundaries must remain present.

## Coverage Comparison

After cleanup, generate LCOV for exactly the same four directories. Compare `DA` records for all production files, with focused summaries for `lib/features/favorites`, `history`, `media`, and `sync`.

Classify every hit-to-miss line as one of:

1. incidental implementation execution from a deleted low-value test;
2. code already protected by a stronger test whose input no longer happens to visit that line;
3. a lost external contract that requires restoring or strengthening a test.

The third category blocks completion until protection is restored. Raw percentage equality is not required.

## Verification

Verification proceeds in this order:

1. format every changed Dart test file;
2. run the directly changed test files with redirected output;
3. run each of the four target directories with redirected output;
4. run the four directories jointly and record executed cases and elapsed time;
5. generate after-cleanup LCOV and perform the hit-to-miss classification;
6. run `dart run tool/check_import_boundaries.dart`;
7. run `flutter analyze`;
8. run the full test suite with the repository-mandated redirected PowerShell command;
9. run `git diff --check` and audit changed paths.

Warm timing should be measured consistently after Flutter artifacts are available. Timing claims must distinguish process startup savings from actual per-test savings.

## Deliverables

The final report must include:

- before/after files, test-code lines, executed cases, and timing;
- each deleted test or test group and its concrete redundancy or tautology reason;
- merged tests and the named inputs retained;
- rewritten fragile tests and the public behavior now observed;
- apparently overlapping tests deliberately retained and their distinct contract or failure reason;
- all hit-to-miss production lines and their classification;
- out-of-scope timing or determinism issues that require production seams;
- targeted, scoped, analyzer, architecture, full-suite, formatting, and diff verification results.

## Acceptance Criteria

- Implementation changes remain inside the four approved test directories.
- Every deletion has a same-layer contract argument and identifies continuing protection when applicable.
- No unique safety, protocol, compatibility, persistence, accessibility, navigation, or lifecycle contract is silently removed.
- No new arbitrary delay, broad settle, pixel assertion, timeout increase, or internal implementation contract is introduced.
- Coverage loss is small, explicitly classified, and contains no unexplained product-contract regression.
- The scoped suites and repository verification gates pass with fresh evidence.
- The final report separates completed changes, measured improvements, retained limitations, and verification evidence.
