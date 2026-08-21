# Scoped Test Suite Cleanup Design

## Goal

Reduce redundant and low-value tests while preserving meaningful regression protection in these directories only:

- `test/app`
- `test/architecture`
- `test/core`
- `test/integration`
- `test/helpers`

The requested `text/helper` path is treated as the evident typo `test/helpers`. The current verified inventory is 49 Dart files, 7,698 lines, and 244 static test declarations; loop-generated runtime cases make the executed case count higher.

## Non-goals

- Do not modify `lib/` or product behavior.
- Do not clean tests under `test/features` or any other test directory.
- Do not optimize solely for a lower test count or shorter runtime.
- Do not weaken architecture, migration, security, protocol, concurrency, or persistence contracts to improve coverage statistics.
- Do not change `dart_test.yaml`, CI workflows, timeouts, or test concurrency.

If a valuable test cannot be made deterministic without a new production seam, retain it when reliable; otherwise record the limitation instead of expanding this cleanup into production code.

## Decision Standard

Every registered test receives one of five dispositions:

| Disposition | Required evidence | Action |
|---|---|---|
| Keep | Protects a unique externally observable contract or decision branch | Leave intact, except for clarity-only edits |
| Delete | Assertion is tautological, only proves fixture/framework behavior, or is fully subsumed by another test with the same trigger and observable result | Remove the whole test and any now-unused setup/imports |
| Merge | Multiple tests exercise the same decision path and differ only by input/expected data | Replace with one table-driven test while retaining case-specific diagnostics |
| Rewrite | Contract is useful but the test observes implementation details or relies on nondeterministic scheduling | Assert public behavior/state and use a deterministic completion signal |
| Record | A real problem requires production changes outside the approved scope | Make no code change and report the exact blocker |

Line coverage is a guardrail, not the value definition. A test may remain valuable without increasing covered lines when it uniquely verifies a boundary, negative case, schema transition, security rule, or protocol outcome.

## Audit Method

### 1. Establish the baseline

Run the five scoped directory suites with coverage and redirected output. Record the exit code, elapsed time, registered test count, and scoped `lcov.info` snapshot before editing.

### 2. Inspect each test semantically

For every test, identify:

1. The production or test-support unit exercised.
2. The input or trigger.
3. The externally observable result.
4. The decision branch or regression contract protected.
5. The nearest overlapping test.

A deletion is permitted only when this mapping shows no unique contract. Similar setup or similar assertions alone do not prove duplication.

### 3. Apply focused cleanup

Work in bounded groups: helpers and simple core utilities, core infrastructure, app/architecture, then integration. After each group, run the directly affected test files before continuing.

Typical rewrite targets include:

- runtime type-name checks replaced by request/response behavior;
- Widget implementation or internal-property assertions replaced by visible text, semantics, navigation, callback, or state outcomes;
- `Duration.zero` scheduling guesses replaced by stream, subscription, provider, repository, or Future completion signals;
- repeated boundary examples consolidated into a table with named cases;
- assertions of constructors, inheritance, or fixtures removed unless they protect serialization or protocol compatibility.

### 4. Compare coverage and contracts

After cleanup, regenerate coverage for the same scoped suites and compare executable-line coverage by production file. Any loss must be explained by removed non-contractual execution or restored with a meaningful behavioral test. Raw percentage equality is not required, but unexplained loss blocks completion.

### 5. Verify repository health

Run, in order:

1. all changed test files;
2. all five scoped directory suites;
3. `dart run tool/check_import_boundaries.dart`;
4. `flutter analyze --no-pub` if normal analysis stalls after dependency resolution;
5. the full test suite using the repository-mandated redirected command;
6. `git diff --check` and a final scope audit.

## Fragility Rules

The cleanup must follow the repository's behavioral testing conventions:

- Do not locate widgets by internal `Key`, pixel position, or incidental widget properties.
- Do not assert absence of an implementation widget type merely to describe layout.
- Do not use generic settling or arbitrary real delays as a substitute for an observable completion event.
- A negative assertion must be bounded by a positive event that proves the observation window completed.
- Schema version assertions remain lower bounds unless a migration specifically requires an exact intermediate version.
- Security redaction cases may be parameterized, but every known sensitive-key category must remain covered.

## Deliverables

The implementation handoff must include:

- the final list of deleted tests and why each lacked a unique contract;
- merged tests and the cases preserved by each table;
- rewritten fragile tests and the public behavior now observed;
- noteworthy tests retained despite apparent overlap and the distinct contract they protect;
- scoped and full verification results;
- any recorded out-of-scope production seam or suspected issue.

## Acceptance Criteria

- Excluding this design and its implementation-plan artifact, only the five approved test directories change during implementation.
- Every deletion has a concrete redundancy or tautology justification.
- No unique error, boundary, migration, security, protocol, persistence, or lifecycle branch is silently removed.
- No new arbitrary delay, internal finder, pixel assertion, broad settle, timeout increase, or allowlist weakening is introduced.
- Changed Dart files pass formatting checks.
- Targeted tests, scoped suites, architecture boundary gate, analyzer, and full suite pass with fresh output.
- Coverage comparison contains no unexplained production-line regression.
- Final status distinguishes completed code changes, verification evidence, and recorded out-of-scope findings.
