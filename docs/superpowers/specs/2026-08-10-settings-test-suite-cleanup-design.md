# Settings Test Suite Cleanup Design

## Goal

Clean only `test/features/settings` to reduce low-value tests, fragility, file-loading overhead, and total execution time while preserving meaningful regression protection and explaining every production-line coverage loss.

The verified baseline on 2026-08-10 is:

- 45 Dart test files;
- 353 executed cases;
- 85.41 seconds for the first redirected directory run;
- 43.44 seconds for a warm-cache redirected coverage run;
- 3,027 of 3,547 executable lines covered under `lib/features/settings` (85.34%).

Baseline logs and LCOV data are stored under `%TEMP%\oh-my-llm-settings-test-cleanup` and are not repository artifacts.

## Scope

Allowed implementation changes:

- delete, merge, rename, or rewrite tests under `test/features/settings`;
- consolidate related 20–80 line model test files into a smaller number of cohesive contract files;
- remove helpers and imports made unused by the cleanup.

Non-goals:

- do not change `lib/`, product behavior, public interfaces, or persistence formats;
- do not change `dart_test.yaml`, CI workflows, test timeout, tags, or concurrency;
- do not modify tests outside `test/features/settings`;
- do not optimize solely for a lower test count or a higher coverage percentage;
- do not commit unless the user explicitly requests a commit.

If a valuable test can only be repaired through a production seam, retain it when reliable and record the limitation instead of expanding scope.

## Decision Standard

Each test is classified by its trigger, externally observable result, test layer, and expected regression failure reason.

| Disposition | Evidence | Action |
|---|---|---|
| Keep | Protects a unique behavior, compatibility rule, error branch, persistence result, or UI wiring | Leave intact except for clarity or fixture cleanup |
| Delete | Proves only a constructor, `props`, fixture, framework behavior, or a contract fully subsumed at the same layer | Remove the whole case and unused setup |
| Merge | Cases exercise the same branch and differ only in input/expected data | Replace with a named table or a larger scenario with case-specific diagnostics |
| Consolidate | Small files protect related contracts but impose separate Flutter test-isolate loading cost | Move the tests into a cohesive contract file without silently dropping assertions |
| Rewrite | The contract is valuable but the assertion observes incidental Widget types/properties or setup internals | Assert visible text, semantics, callback, persisted state, or another public outcome |
| Record | Repair requires production changes outside scope | Do not change it; report the exact blocker |

Two tests are duplicates only when their external contract, test layer, and expected failure reason are all the same. Similar setup, line coverage, or CRUD verbs alone are insufficient.

## Cleanup Strategy

### 1. Domain model contracts

- Delete direct `Equatable.props` inspection and other implementation-only assertions when equality or round-trip behavior already observes the product contract.
- Merge enum parsing, label mapping, fallback, finish-reason classification, and placement-filter variants into named tables.
- Remove isolated `copyWith` tests only when the same mutation is already exercised through a controller or complete domain scenario; retain special clear/reset semantics that are externally significant.
- Preserve old/missing/unknown JSON behavior, protocol compatibility, malformed input rejection, and non-trivial summary/filtering logic.
- Consolidate closely related prompt and settings value-object microfiles without creating an oversized catch-all file.

### 2. Application and data contracts

- Merge single-item success cases when a multi-item case strictly subsumes the same state transition and persistence result.
- Merge save/load/rebuild cases when one restart scenario proves both durable write and restore behavior.
- Retain distinct failure, no-op, deduplication, normalization, ordering, rollback, and compatibility branches.
- Parameterize structurally identical entity-category tests in import/export and deduplication workflows while keeping category names in failure output.
- Preserve trust-domain Header behavior, HTTP error classification, truncated response diagnostics, SQLite round-trips, and rejected-write propagation.

### 3. Presentation and settings-screen contracts

- Replace assertions on incidental Widget classes or button properties with visible loading/error/content, real taps, callback results, dialog lifecycle, or persisted Provider/repository outcomes.
- Keep each distinct form mode, validation outcome, protocol propagation path, destructive confirmation path, and import rollback behavior.
- Merge settings-screen CRUD scenarios only when a more complete flow exercises the same UI entry point and final visible/persisted outcome.
- Remove responsive smoke variants only when no production breakpoint or layout decision exists between the widths and the same reachability contract is already covered.
- Preserve representative narrow and wide layout reachability and every unique cross-layer UI wiring path.

## Performance Strategy

The directory has no executable `Future.delayed`, generic `pumpAndSettle`, or timing-based pixel assertions, so the primary time targets are test-file loading and repeated full widget setup.

- Reduce isolate loading by consolidating model microfiles into cohesive files.
- Reuse existing deterministic pump helpers and typed fixtures.
- Avoid introducing arbitrary waits, broader settling, timeout increases, or shared mutable fixtures.
- Measure warm-cache directory runtime repeatedly before and after cleanup; the first run remains diagnostic because dependency resolution and compilation can dominate it.

Runtime improvement is desirable but not a completion requirement if retaining a unique contract explains the cost.

## Coverage Guardrail

Generate post-cleanup LCOV with the same `test/features/settings` scope and compare `DA` records for `lib/features/settings` against the 3,027/3,547 baseline.

Every line changing from hit to unhit must be classified as one of:

1. implementation-only coverage removed intentionally;
2. a line still protected by another contract but no longer incidentally executed;
3. an unintended behavior-coverage loss.

The third category blocks completion and requires restoring a meaningful test. Raw percentage equality is not mandatory, and adding low-value execution merely to recover a percentage is prohibited.

## Verification

Verification runs in this order:

1. format all changed Dart files;
2. run each changed entry test file with redirected compact output;
3. run `test/features/settings` with redirected compact output at least twice for a warm-cache timing comparison;
4. generate post-cleanup coverage and perform the line-level delta audit;
5. run `dart run tool/check_import_boundaries.dart`;
6. run `flutter analyze --no-pub`;
7. run the full suite using the repository-mandated redirected command;
8. run `git diff --check` and audit that implementation changes remain inside `test/features/settings`.

## Deliverables

The final handoff reports:

- files and tests deleted, with the covering contract or tautology reason;
- table-driven merges and the preserved case matrix;
- microfiles consolidated and their retained contracts;
- fragile assertions rewritten and the public outcome now observed;
- apparently overlapping tests retained and their distinct regression purpose;
- before/after file count, executed cases, warm-cache runtime, and settings coverage;
- targeted, static, architecture, and full-suite verification results;
- any recorded out-of-scope limitation.

## Acceptance Criteria

- Only this design/plan documentation and `test/features/settings` change.
- Every deletion has an explicit no-unique-contract or strict-subsumption justification.
- No unique protocol, compatibility, malformed-input, write-failure, rollback, security, SQLite, or UI-wiring branch is silently removed.
- No new arbitrary delay, broad settle, internal `Key`, pixel assertion, timeout increase, or allowlist weakening is introduced.
- Consolidated files remain cohesive and preserve useful per-case diagnostics.
- Changed Dart files pass formatting checks.
- Targeted tests, settings directory tests, architecture gate, analyzer, and full suite pass with fresh redirected output.
- Coverage comparison has no unexplained production-line regression.
- Final status distinguishes implemented changes, verified behavior, and recorded limitations.
