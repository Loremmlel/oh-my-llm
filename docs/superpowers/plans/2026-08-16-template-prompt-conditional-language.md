# Template Prompt Conditional Language Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在维持聊天页手动选择模板的前提下，为模板提示词增加 `select` 单选变量、非嵌套 `if / else if / else` 块、动态分支变量字段、保存/导入诊断和 v8 设置交换契约。

**Architecture:** Settings domain 新增一套纯 Dart 编译器与求值器：编译器把模板正文变成不可变程序并产生稳定错误码，求值器只接收程序、正文和字符串变量值。Chat application 用按不可变 `TemplatePrompt` 键控的 Riverpod family 缓存编译结果，发送时只重新求值；Settings 表单直接调用同一编译器。SQLite 继续写现有 `variables_json`，Settings export 从 v7 升到 v8。

**Tech Stack:** Flutter 3.44.x stable（CI 固定 3.44.6；计划编写机为 3.44.8）/ Dart `^3.11.5` / Riverpod 3 `NotifierProvider` / Equatable / 原始 sqlite3 / Flutter Widget tests。

## Global Constraints

- 权威设计为 `docs/superpowers/specs/2026-08-16-template-prompt-conditional-language-design.md`；发现矛盾时停止实现并回到设计评审，不自行扩大语法。
- 当前基线为 `4215177`、`pubspec.yaml` 版本 `3.51.1+0`；执行前重新读取，不能把这两个值当成长期事实。
- 模板仍由聊天页手动选择；不得增加 `/模板名`、自动匹配或其他触发入口。
- 第一版不得实现模板引用、嵌套 `if`、布尔组合、变量间比较、渲染预览、声明但不插值的变量、`|` 转义或完整 `{{...}}` 字面量转义。
- `{{正文}}` 只能位于条件块外；没有顶层 `{{正文}}` 时继续把正文前置。
- 字符串字面量保留双引号内空白，运行时变量值 trim；`select` 保存字符串值，不保存选项索引。
- 独占行控制标签必须删除该行前导空白、标签、尾随空白和行结束符；分支正文缩进必须保留。
- 编译器、求值器和模型位于 Settings domain，零 Flutter/Riverpod/sqlite3 依赖；Chat 不复制解析规则。
- 不增加 SQLite 列、不提升 `PRAGMA user_version`，不修改 Sync wire protocol 版本。
- 不引入内容 hash 缓存；现有表单 220/320ms 防抖和 Chat provider family 是唯一编译频率控制。
- 所有新增注释和测试标题使用简体中文；不得使用 `part` / `part of`。
- 跨 feature import 使用 `package:oh_my_llm/...`，同一 feature 内使用相对路径。
- 测试只等待 Provider 状态、控制器值或有限动画；不得新增 `Future.delayed(Duration.zero)`、任意固定延时或无条件 `pumpAndSettle()`。
- 所有测试、分析和诊断日志写入仓库 ignored 的 `logs/`；完整测试固定写 `logs/fltest.log`。
- 每次提交前格式化全部改动 Dart 文件，暂存后再次执行 `dart format --output=none --set-exit-if-changed`。
- 每个任务只暂存其列出的文件；保留现有未跟踪文件 `docs/superpowers/plans/2026-08-14-fix-media-thumbnail-blocking-and-video-thumbnail.md`，不得修改或提交。
- 本计划不授权 push、PR、设备手测或发布；实施结束只报告实际完成的自动化验证。

### Review dispositions carried into implementation

| Review item | Decision |
| --- | --- |
| 独占行前后空白 | 问题成立；整行连同缩进、尾随空白和行结束符一起删除。 |
| 条件字符串字面量 trim | 问题成立；字面量按引号内原文比较，只有运行时变量值 trim。 |
| 历史 select 值失效 | 场景成立，但拒绝“总是回落第一项”；字段绑定回落当前配置默认项并写回编辑草稿，绕过绑定的非法值仍被发送边界拒绝。 |
| 应用降级读取本地库 | 风险成立，但无法回补已经发布的旧二进制；当前实现保持未知类型回退 text，并在 README 明确旧版可能把控制标签/双分支当普通文本。 |
| `|` 与 `{{` 转义缺失 | 作为 v1 限制接受，只在表单帮助和 README 显眼说明，不扩展语法。 |
| 内容 hash 缓存 | 暂不采用；现有设置页防抖和按完整模板键控的 Provider family 足够，先避免双缓存失效问题。 |
| 稳定错误码 | 采用，domain 测试断言 code/location，Widget 测试断言用户可见信息。 |
| select 持久化结构 | 采用字符串值，不保存索引；SQLite 结构不变。 |

---

## 0. File Structure and Dependency Lock

### New domain files

| File | Responsibility |
| --- | --- |
| `lib/features/settings/domain/template_prompt_language/template_prompt_program.dart` | AST、变量声明、条件、源码位置、诊断、编译结果等不可变类型。 |
| `lib/features/settings/domain/template_prompt_language/template_prompt_compiler.dart` | 单次线性扫描、块结构、声明协调、条件类型检查、持久化变量一致性校验。 |
| `lib/features/settings/domain/template_prompt_language/template_prompt_evaluator.dart` | 有效值解析、条件求值、输出片段、可见变量和运行时值错误。 |
| `test/features/settings/domain/template_prompt_language/template_prompt_compiler_test.dart` | 语法、诊断位置、声明协调和定义校验。 |
| `test/features/settings/domain/template_prompt_language/template_prompt_evaluator_test.dart` | 条件、空白、正文、活动变量和值错误。 |

### New Chat and Settings UI files

| File | Responsibility |
| --- | --- |
| `lib/features/chat/application/composer/template_prompt_compilation_provider.dart` | 以完整不可变 `TemplatePrompt` 为 family 参数缓存定义编译结果。 |
| `lib/features/chat/presentation/widgets/composer/fields/select_variable_field.dart` | 受控下拉单选字段，只读写字符串值。 |
| `test/features/chat/presentation/chat_screen/chat_screen_template_language_cases.dart` | 生产 wiring 下的动态字段、发送、编辑恢复和无效模板用例。 |
| `lib/features/settings/presentation/widgets/prompts/forms/template_prompt_syntax_help.dart` | 新增/编辑表单共用的默认收起语法说明。 |
| `test/features/settings/presentation/widgets/prompts/forms/template_prompt_form_dialog_test.dart` | 说明区、select 默认值、inline 诊断和保存门禁。 |

### Existing files intentionally changed

- Model/persistence: `lib/features/settings/domain/models/prompts/template_prompt.dart`, `lib/features/settings/domain/models/transfer/settings_export_data.dart`, `lib/features/settings/domain/models/transfer/settings_export_codec.dart`, `lib/features/settings/application/transfer/settings_import_deduplicator.dart`.
- Settings UI: `lib/features/settings/presentation/widgets/prompts/forms/template_prompt_form_dialog.dart` plus its new syntax-help widget.
- Chat application: `lib/features/chat/application/composer/templated_user_message_builder.dart`, `lib/features/chat/application/composer/chat_composer_command.dart`.
- Chat presentation: `lib/features/chat/presentation/chat_screen.dart`, `lib/features/chat/presentation/widgets/composer/chat_composer_card.dart`, `lib/features/chat/presentation/widgets/composer/fields/composer_template_variable_fields.dart`, `lib/features/chat/presentation/widgets/composer/fields/number_variable_field.dart`.
- Tests/fixtures: exact files are repeated in each task. `lib/features/settings/domain/template_prompt_parser.dart` and `test/features/settings/domain/template_prompt_parser_test.dart` are removed only after the Settings form no longer imports the legacy parser.
- User documentation: `README.md` gains the supported template-prompt syntax and downgrade warning; no new release-note subsystem is invented.

### Dependency direction

```text
TemplatePrompt model
        ↓
template_prompt_program ← template_prompt_compiler
        ↓                         ↓
template_prompt_evaluator    Settings form / Settings codec
        ↓
Chat compilation provider → message builder / composer widgets
```

Settings domain must not import Chat types. The evaluator emits generic `TemplatePromptOutputChunkKind.template/body`; `templated_user_message_builder.dart` alone maps those chunks to `UserMessageSegmentKind`.

## 1. Execution Preflight

- [ ] **Step 1: Confirm the exact workspace and preserve unrelated state**

Run from `E:\Code\oh-my-llm`:

```powershell
git status --short
git rev-parse --show-toplevel
git rev-parse HEAD
git branch --show-current
git config --get core.hooksPath
Select-String -Path pubspec.yaml -Pattern '^version:'
New-Item -ItemType Directory -Force logs | Out-Null
git rev-parse HEAD | Set-Content -Encoding ascii logs/template-language-base-head.txt
```

Expected before plan execution: repository root is `E:/Code/oh-my-llm`, branch is non-empty, hooks path is `.githooks`, and the media plan remains an unrelated untracked file. If other overlapping template-prompt changes exist, stop and reconcile ownership before editing.

- [ ] **Step 2: Confirm toolchain without upgrading it**

```powershell
flutter --version
dart --version
```

Expected: Flutter is within 3.44.x stable and Dart satisfies `^3.11.5`. Do not run `flutter upgrade`. If the executor changes Flutter during implementation, run `flutter clean` before any test as required by `AGENTS.md`.

- [ ] **Step 3: Run the current focused baseline serially**

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/features/settings/domain/template_prompt_parser_test.dart test/features/settings/domain/models/prompts/template_prompt_test.dart test/features/chat/application/composer/templated_user_message_builder_test.dart 2>&1 | Out-File -Encoding utf8 logs/template-language-baseline.log
$TestExit = $LASTEXITCODE
Write-Host "EXIT=$TestExit"
Get-Content -Tail 120 logs/template-language-baseline.log
if ($TestExit -ne 0) { exit $TestExit }
```

Expected: `EXIT=0`. If startup stalls before any case, run `./scripts/kill-stale-test-processes.ps1` and retry once. Do not start implementation from a failing baseline without identifying whether it is pre-existing.

---

### Task 1: Define the template language model and compiler

**Files:**
- Create: `lib/features/settings/domain/template_prompt_language/template_prompt_program.dart`
- Create: `lib/features/settings/domain/template_prompt_language/template_prompt_compiler.dart`
- Create: `test/features/settings/domain/template_prompt_language/template_prompt_compiler_test.dart`
- Modify: `lib/features/settings/domain/models/prompts/template_prompt.dart`
- Modify: `test/features/settings/domain/models/prompts/template_prompt_test.dart`
- Modify: `test/helpers/fixtures.dart`

**Interfaces:**
- Consumes: existing `TemplatePrompt`, `TemplatePromptVariable`, `templatePromptBodyVariableName`.
- Produces:

```dart
enum TemplatePromptErrorCode {
  invalidPlaceholder,
  invalidSelectOptions,
  conflictingVariableDeclaration,
  invalidBodyDeclaration,
  bodyInsideConditional,
  invalidConditionSyntax,
  undefinedConditionVariable,
  invalidConditionOperator,
  invalidConditionLiteral,
  unexpectedControlTag,
  elseIfAfterElse,
  duplicateElse,
  unclosedIf,
  nestedIf,
  inconsistentStoredVariables,
}

final class TemplatePromptSourceLocation extends Equatable {
  const TemplatePromptSourceLocation({
    required this.offset,
    required this.line,
    required this.column,
  });
  final int offset;
  final int line;
  final int column;
}

final class TemplatePromptDiagnostic extends Equatable {
  const TemplatePromptDiagnostic({
    required this.code,
    required this.location,
    required this.message,
  });
  final TemplatePromptErrorCode code;
  final TemplatePromptSourceLocation location;
  final String message;
}

enum TemplatePromptComparisonOperator {
  equal,
  notEqual,
  greater,
  greaterOrEqual,
  less,
  lessOrEqual,
}

sealed class TemplatePromptConditionLiteral extends Equatable {
  const TemplatePromptConditionLiteral();
}

final class TemplatePromptStringLiteral
    extends TemplatePromptConditionLiteral {
  const TemplatePromptStringLiteral(this.value);
  final String value;
  @override
  List<Object> get props => [value];
}

final class TemplatePromptIntegerLiteral
    extends TemplatePromptConditionLiteral {
  const TemplatePromptIntegerLiteral(this.value);
  final int value;
  @override
  List<Object> get props => [value];
}

final class TemplatePromptCondition extends Equatable {
  const TemplatePromptCondition({
    required this.variableName,
    required this.operator,
    required this.literal,
  });
  final String variableName;
  final TemplatePromptComparisonOperator operator;
  final TemplatePromptConditionLiteral literal;
  @override
  List<Object> get props => [variableName, operator, literal];
}

sealed class TemplatePromptNode extends Equatable {
  const TemplatePromptNode();
}

final class TemplatePromptTextNode extends TemplatePromptNode {
  const TemplatePromptTextNode(this.text);
  final String text;
  @override
  List<Object> get props => [text];
}

final class TemplatePromptVariableNode extends TemplatePromptNode {
  const TemplatePromptVariableNode(this.name);
  final String name;
  @override
  List<Object> get props => [name];
}

final class TemplatePromptConditionalBranch extends Equatable {
  TemplatePromptConditionalBranch({
    required this.condition,
    required List<TemplatePromptNode> nodes,
  }) : nodes = List.unmodifiable(nodes);
  final TemplatePromptCondition condition;
  final List<TemplatePromptNode> nodes;
  @override
  List<Object> get props => [condition, nodes];
}

final class TemplatePromptIfNode extends TemplatePromptNode {
  TemplatePromptIfNode({
    required List<TemplatePromptConditionalBranch> branches,
    List<TemplatePromptNode>? elseNodes,
  }) : branches = List.unmodifiable(branches),
       elseNodes = elseNodes == null ? null : List.unmodifiable(elseNodes);
  final List<TemplatePromptConditionalBranch> branches;
  final List<TemplatePromptNode>? elseNodes;
  @override
  List<Object?> get props => [branches, elseNodes];
}

final class TemplatePromptProgram extends Equatable {
  TemplatePromptProgram({
    required List<TemplatePromptNode> nodes,
    required List<TemplatePromptVariable> declarations,
    required Set<String> conditionVariableNames,
    required this.containsBodyVariable,
  }) : nodes = List.unmodifiable(nodes),
       declarations = List.unmodifiable(declarations),
       conditionVariableNames = Set.unmodifiable(conditionVariableNames);
  final List<TemplatePromptNode> nodes;
  final List<TemplatePromptVariable> declarations;
  final Set<String> conditionVariableNames;
  final bool containsBodyVariable;
  List<TemplatePromptVariable> get inputVariables => List.unmodifiable(
    declarations.where((variable) => !variable.isBody),
  );
  @override
  List<Object> get props => [
    nodes,
    declarations,
    conditionVariableNames,
    containsBodyVariable,
  ];
}

final class TemplatePromptCompilation extends Equatable {
  TemplatePromptCompilation({
    this.program,
    List<TemplatePromptDiagnostic> diagnostics = const [],
  }) : diagnostics = List.unmodifiable(diagnostics);
  final TemplatePromptProgram? program;
  final List<TemplatePromptDiagnostic> diagnostics;
  bool get isValid => program != null && diagnostics.isEmpty;
}

TemplatePromptCompilation compileTemplatePromptContent(String content);

TemplatePromptCompilation compileTemplatePromptDefinition(
  TemplatePrompt templatePrompt,
);

List<TemplatePromptVariable> reconcileCompiledTemplatePromptVariables({
  required TemplatePromptProgram program,
  required List<TemplatePromptVariable> existingVariables,
});
```

`TemplatePromptVariableType` becomes `text, number, select`; `TemplatePromptVariable` adds `List<String> options = const []`, `isSelect`, JSON/copy/props support. Unknown persisted `type` still falls back to `text`; a compiled `select` definition with missing/mismatched persisted options fails `compileTemplatePromptDefinition` instead of silently becoming text.

- [ ] **Step 1: Write failing model tests for select JSON and value semantics**

Add Chinese-named cases to `template_prompt_test.dart`:

```dart
test('select 变量 JSON 往返保留字符串选项且未知类型仍回退 text', () {
  const variable = TemplatePromptVariable(
    name: '人称',
    defaultValue: '二',
    type: TemplatePromptVariableType.select,
    options: ['一', '二', '三'],
  );

  expect(TemplatePromptVariable.fromJson(variable.toJson()), variable);
  expect(variable.isSelect, isTrue);
  expect(
    TemplatePromptVariable.fromJson(const {
      'name': '旧变量',
      'type': 'future-type',
    }).type,
    TemplatePromptVariableType.text,
  );
});
```

Also extend `TestFixtures.templateVariable` with `type` and `options`, and make `TestFixtures.templatePrompt` default variables contain the `正文` variable because its default content already contains `{{正文}}`.

- [ ] **Step 2: Run the model test and verify the red failure**

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/features/settings/domain/models/prompts/template_prompt_test.dart 2>&1 | Out-File -Encoding utf8 logs/template-language-model-red.log
$TestExit = $LASTEXITCODE
Write-Host "EXIT=$TestExit"
Get-Content -Tail 100 logs/template-language-model-red.log
```

Expected: non-zero exit because `TemplatePromptVariableType.select`, `options`, or `isSelect` does not exist. A failure caused only by an environment/plugin startup error is not valid red evidence.

- [ ] **Step 3: Implement the select model extension**

Update the enum, constructor, `copyWith`, `toJson`, `fromJson`, getters and `props`. Always expose `options` as an immutable list:

```dart
const TemplatePromptVariable({
  required this.name,
  this.defaultValue = '',
  this.type = TemplatePromptVariableType.text,
  this.options = const [],
});

final List<String> options;
bool get isSelect => type == TemplatePromptVariableType.select;
```

Use `List.unmodifiable` when decoding/copying non-const external lists. `toString()` storage values remain exactly `text`, `number`, `select`.

- [ ] **Step 4: Run the model test green**

Use the same command with `logs/template-language-model-green.log`. Expected: `EXIT=0`.

- [ ] **Step 5: Write the compiler tests before the compiler**

Create `template_prompt_compiler_test.dart` with parameterized Chinese cases covering:

1. plain, `number`, `select`, and top-level `正文` declarations in first-occurrence order;
2. `{{人称}}` before `{{人称:select|一|二|三}}` still resolves to one select declaration;
3. select option trim plus duplicate/empty/less-than-two diagnostics; every unescaped `|` is a delimiter, so it can never become option content;
4. repeated typed declarations must match type and options;
5. block parsing for `if`, multiple `else if`, optional `else`, and multiple sibling blocks;
6. every error code listed above, with exact line/column on at least `unclosedIf`, `nestedIf`, `bodyInsideConditional`;
7. string literals preserve inner whitespace and accept only `\"` / `\\` escapes;
8. select literals must be declared options; number literals must be integers;
9. unmatched legacy non-control placeholders keep existing behavior; an incomplete `{{#if` is diagnosed as a control error;
10. standalone control lines with `\n`, `\r\n`, indentation and trailing spaces have correct source spans;
11. `compileTemplatePromptDefinition` rejects model/content variable shape mismatches;
12. reconciliation preserves valid defaults, defaults new number to `1`, defaults new select to its first option, and falls back to first option only when the configured default is no longer available.

Also assert that `&&`, `||`, a variable right-hand side, unsupported escapes, and an error located in an inactive branch are still rejected. The compiler validates every branch independent of runtime selection.

Representative assertions:

```dart
test('带类型声明晚于普通引用时统一解析为一个 select 变量', () {
  final result = compileTemplatePromptContent(
    '{{人称}} / {{人称:select|一|二|三}}',
  );

  expect(result.diagnostics, isEmpty);
  final declaration = result.program!.declarations.single;
  expect(declaration.name, '人称');
  expect(declaration.type, TemplatePromptVariableType.select);
  expect(declaration.options, ['一', '二', '三']);
});

test('嵌套 if 返回稳定错误码和内层标签位置', () {
  final result = compileTemplatePromptContent(
    '{{#if 人称 == "一"}}\n{{#if 风格 == "短"}}x{{/if}}\n{{/if}}',
  );

  final diagnostic = result.diagnostics.singleWhere(
    (item) => item.code == TemplatePromptErrorCode.nestedIf,
  );
  expect(diagnostic.location.line, 2);
  expect(diagnostic.location.column, 1);
});
```

- [ ] **Step 6: Run compiler tests and capture the intended red state**

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/features/settings/domain/template_prompt_language/template_prompt_compiler_test.dart 2>&1 | Out-File -Encoding utf8 logs/template-language-compiler-red.log
$TestExit = $LASTEXITCODE
Write-Host "EXIT=$TestExit"
Get-Content -Tail 140 logs/template-language-compiler-red.log
```

Expected: non-zero exit because compiler/program symbols are absent.

- [ ] **Step 7: Implement the immutable AST and source diagnostics**

Create `template_prompt_program.dart`. All collection fields must be defensive `List.unmodifiable` / `Set.unmodifiable`; all value types extend Equatable. Conditions store a typed literal (`String` for text/select, `int` for number) after compilation so the evaluator never reparses expression text.

- [ ] **Step 8: Implement the compiler as a bounded scanner plus validation pass**

Create `template_prompt_compiler.dart` with these phases:

1. scan text and complete `{{...}}` tags by source offset;
2. classify variable, `#if`, `else if`, `else`, `/if`;
3. detect standalone control-tag line bounds before emitting adjacent text nodes;
4. build sibling-only condition blocks; emit `nestedIf` rather than recursing into another block;
5. collect typed and untyped declaration occurrences across the whole program;
6. resolve one declaration per name, then validate conditions so declarations may appear later;
7. reject conditional `正文`, conflicting definitions, invalid literals/operators/options;
8. turn offsets into 1-based line/column locations;
9. reconcile model variables only from a valid program;
10. in `compileTemplatePromptDefinition`, compare persisted variable name/order/type/options to compiled declarations, validate number/select defaults, and return a program whose declaration defaults come from the validated persisted definition rather than the syntax-only initial defaults.

Do not catch all exceptions and return generic diagnostics. Parser recovery may add multiple diagnostics, but every diagnostic must have a specific `TemplatePromptErrorCode` and source location.

- [ ] **Step 9: Run compiler/model tests green**

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/features/settings/domain/template_prompt_language/template_prompt_compiler_test.dart test/features/settings/domain/models/prompts/template_prompt_test.dart 2>&1 | Out-File -Encoding utf8 logs/template-language-compiler-green.log
$TestExit = $LASTEXITCODE
Write-Host "EXIT=$TestExit"
Get-Content -Tail 140 logs/template-language-compiler-green.log
if ($TestExit -ne 0) { exit $TestExit }
```

- [ ] **Step 10: Format, stage only Task 1 files, and commit**

```powershell
$TaskFiles = @(
  'lib/features/settings/domain/models/prompts/template_prompt.dart',
  'lib/features/settings/domain/template_prompt_language/template_prompt_program.dart',
  'lib/features/settings/domain/template_prompt_language/template_prompt_compiler.dart',
  'test/features/settings/domain/models/prompts/template_prompt_test.dart',
  'test/features/settings/domain/template_prompt_language/template_prompt_compiler_test.dart',
  'test/helpers/fixtures.dart'
)
$DartFiles = @($TaskFiles | Where-Object { $_ -like '*.dart' })
dart format $DartFiles
git add -- $TaskFiles
$StagedDartFiles = @(git diff --cached --name-only --diff-filter=ACMR -- '*.dart')
dart format --output=none --set-exit-if-changed $StagedDartFiles
git diff --cached --check
git diff --cached --name-only
git commit -m 'refactor(settings): 建立模板提示词编译模型'
```

Expected staged list: exactly the six Task 1 paths. After the hook, record the final `HEAD` and version; do not assume the pre-hook commit hash.

---

### Task 2: Evaluate compiled templates and expose active variables

**Files:**
- Create: `lib/features/settings/domain/template_prompt_language/template_prompt_evaluator.dart`
- Create: `test/features/settings/domain/template_prompt_language/template_prompt_evaluator_test.dart`

**Interfaces:**
- Consumes: valid `TemplatePromptProgram` (including validated declaration defaults), body string and raw `Map<String, String>` values.
- Produces:

```dart
enum TemplatePromptOutputChunkKind { template, body }
enum TemplatePromptValueErrorCode { invalidNumber, invalidSelectValue }

final class TemplatePromptOutputChunk extends Equatable {
  const TemplatePromptOutputChunk({required this.text, required this.kind});
  final String text;
  final TemplatePromptOutputChunkKind kind;
}

final class TemplatePromptValueError extends Equatable {
  const TemplatePromptValueError({
    required this.variableName,
    required this.code,
    required this.message,
  });
  final String variableName;
  final TemplatePromptValueErrorCode code;
  final String message;
}

final class TemplatePromptEvaluation extends Equatable {
  TemplatePromptEvaluation({
    required List<TemplatePromptOutputChunk> chunks,
    required List<String> activeInputVariableNames,
    required Map<String, String> effectiveValues,
    required List<TemplatePromptValueError> valueErrors,
  }) : chunks = List.unmodifiable(chunks),
       activeInputVariableNames = List.unmodifiable(activeInputVariableNames),
       effectiveValues = Map.unmodifiable(effectiveValues),
       valueErrors = List.unmodifiable(valueErrors);
  final List<TemplatePromptOutputChunk> chunks;
  final List<String> activeInputVariableNames;
  final Map<String, String> effectiveValues;
  final List<TemplatePromptValueError> valueErrors;
  bool get isValid => valueErrors.isEmpty;
  String get content => chunks.map((chunk) => chunk.text).join();
  @override
  List<Object> get props => [
    chunks,
    activeInputVariableNames,
    effectiveValues,
    valueErrors,
  ];
}

String normalizeTemplatePromptVariableDraftValue(
  TemplatePromptVariable variable,
  String? rawValue,
);

TemplatePromptEvaluation evaluateTemplatePrompt({
  required TemplatePromptProgram program,
  required String body,
  required Map<String, String> variableValues,
});
```

`activeInputVariableNames` is ordered by declaration occurrence and includes all condition-control variables, all top-level input variables, and variables in the selected branch only. If a control value is invalid, return its value error and do not guess a branch; still expose control/top-level fields so the user can repair the value.

- [ ] **Step 1: Write evaluator failures first**

Create Chinese-named tests for:

- text/select `==` and `!=`;
- string comparisons are case-sensitive;
- all six numeric operators and negative integers;
- first-match `else if`, final `else`, and no-match/no-else empty output;
- branch-local variable visibility and hidden-value preservation in `effectiveValues`;
- text input trim versus non-trimmed string literal;
- missing/empty values falling back to stored defaults;
- stale select falling back to the current configured default in `normalizeTemplatePromptVariableDraftValue`;
- invalid number and select values returning typed errors;
- a variable placeholder inside the selected branch (for example `{{主角名}}`) being substituted normally, proving branch content is not a nested-template reference;
- body chunk position and body-prepend fallback;
- inline control tags preserving authored whitespace;
- indented standalone control lines removing the whole tag line while retaining branch-body indentation.

Representative test:

```dart
test('独占控制行删除缩进但保留分支正文缩进', () {
  final compilation = compileTemplatePromptContent(
    '视角：{{人称:select|一|三}}\n要求：\n  {{#if 人称 == "一"}}\n  第一人称。\n  {{/if}}\n{{正文}}',
  );
  final evaluation = evaluateTemplatePrompt(
    program: compilation.program!,
    body: '内容',
    variableValues: const {'人称': '一'},
  );

  expect(evaluation.content, '视角：一\n要求：\n  第一人称。\n内容');
});
```

- [ ] **Step 2: Run the evaluator red test**

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/features/settings/domain/template_prompt_language/template_prompt_evaluator_test.dart 2>&1 | Out-File -Encoding utf8 logs/template-language-evaluator-red.log
$TestExit = $LASTEXITCODE
Write-Host "EXIT=$TestExit"
Get-Content -Tail 140 logs/template-language-evaluator-red.log
```

Expected: non-zero exit because evaluator symbols are absent.

- [ ] **Step 3: Implement value resolution and condition evaluation**

The draft-binding normalizer uses this order:

```dart
final trimmed = rawValue?.trim() ?? '';
final candidate = trimmed.isEmpty ? variable.defaultValue : trimmed;
if (variable.isSelect && !variable.options.contains(candidate)) {
  return variable.defaultValue; // compiler guarantees the configured default is valid
}
return candidate;
```

The evaluator is intentionally stricter: empty input uses the configured default, but a non-empty select value outside `options` produces `invalidSelectValue` rather than calling the draft normalizer. Likewise, a non-empty invalid number is not replaced with `1`; it produces `invalidNumber`. This split implements the approved rule that historical values normalize during field binding while a caller that bypasses binding is rejected at send time. Evaluation walks only the selected branch for output but retains effective values for every declared input variable so hidden values can be persisted.

- [ ] **Step 4: Implement generic output chunks and active-variable projection**

Merge adjacent chunks of the same kind. A variable other than `正文` produces a template chunk; `正文` produces a body chunk. If the program lacks a top-level body variable, prepend trimmed non-empty body and one newline only when rendered template content is non-empty, matching the current builder contract.

- [ ] **Step 5: Run compiler and evaluator tests green together**

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/features/settings/domain/template_prompt_language 2>&1 | Out-File -Encoding utf8 logs/template-language-domain-green.log
$TestExit = $LASTEXITCODE
Write-Host "EXIT=$TestExit"
Get-Content -Tail 160 logs/template-language-domain-green.log
if ($TestExit -ne 0) { exit $TestExit }
```

- [ ] **Step 6: Format, stage only Task 2 files, and commit**

```powershell
$TaskFiles = @(
  'lib/features/settings/domain/template_prompt_language/template_prompt_evaluator.dart',
  'test/features/settings/domain/template_prompt_language/template_prompt_evaluator_test.dart'
)
dart format $TaskFiles
git add -- $TaskFiles
$StagedDartFiles = @(git diff --cached --name-only --diff-filter=ACMR -- '*.dart')
dart format --output=none --set-exit-if-changed $StagedDartFiles
git diff --cached --check
git diff --cached --name-only
git commit -m 'refactor(settings): 增加模板提示词求值边界'
```

---

### Task 3: Integrate compiled rendering into Chat application

**Files:**

- Create: `lib/features/chat/application/composer/template_prompt_compilation_provider.dart`
- Modify: `lib/features/chat/application/composer/templated_user_message_builder.dart`
- Modify: `lib/features/chat/application/composer/chat_composer_command.dart`
- Modify: `test/features/chat/application/composer/templated_user_message_builder_test.dart`
- Modify: `test/features/chat/application/composer/chat_composer_command_test.dart`

**Contract:** Chat application must never parse template source itself. A selected template is compiled through one provider, evaluated once per dispatch, and either produces a typed message or a typed failure. Compile/value failures must not call `sendMessage`/`editMessage`, clear the body, or mutate the selected template. The message stores effective string values; stale history normalization belongs to the field-binding flow in Task 4, while a value that bypasses that flow remains a strict send-boundary error.

- [ ] **Step 1: Write failing builder tests for branch rendering and segment boundaries**

Replace direct `TemplatedUserMessage` assumptions with a sealed result assertion. Cover:

1. no template returns trimmed body with no template segments;
2. a valid first-person `select` chooses the first branch and includes only that branch;
3. changing `人称` chooses `else if` and excludes hidden branch text;
4. `{{正文}}` creates a body-kind segment inside the rendered stream;
5. no top-level `{{正文}}` prepends the body and newline using the legacy contract;
6. standalone control-tag indentation is absent while branch body indentation remains;
7. invalid compilation returns diagnostics rather than partial content;
8. invalid number and invalid select input return value errors rather than guessing a branch;
9. an omitted/empty select input uses its configured default in `effectiveVariableValues`;
10. adjacent evaluator chunks of the same kind become one `UserMessageSegment`.

Use this result boundary:

```dart
sealed class TemplatedUserMessageBuildResult {
  const TemplatedUserMessageBuildResult();
}

final class TemplatedUserMessageBuildSuccess
    extends TemplatedUserMessageBuildResult {
  const TemplatedUserMessageBuildSuccess({
    required this.message,
    required this.effectiveVariableValues,
  });

  final TemplatedUserMessage message;
  final Map<String, String> effectiveVariableValues;
}

final class TemplatedUserMessageBuildFailure
    extends TemplatedUserMessageBuildResult {
  const TemplatedUserMessageBuildFailure({
    this.diagnostics = const [],
    this.valueErrors = const [],
  });

  final List<TemplatePromptDiagnostic> diagnostics;
  final List<TemplatePromptValueError> valueErrors;
}
```

- [ ] **Step 2: Run the builder test red and verify the failure reason**

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/features/chat/application/composer/templated_user_message_builder_test.dart 2>&1 | Out-File -Encoding utf8 logs/template-chat-builder-red.log
$TestExit = $LASTEXITCODE
Write-Host "EXIT=$TestExit"
Get-Content -Tail 140 logs/template-chat-builder-red.log
if ($TestExit -eq 0) { throw 'RED gate failed: the new build-result and branch tests unexpectedly passed' }
```

Expected failure: the sealed result classes/provider do not exist, or the old regex renderer outputs control tags/both branches. If the failure is unrelated compilation breakage, repair the test setup before implementation.

- [ ] **Step 3: Add the compilation provider**

Implement exactly one cache boundary:

```dart
final templatePromptCompilationProvider = Provider.autoDispose
    .family<TemplatePromptCompilation, TemplatePrompt>((ref, prompt) {
      return compileTemplatePromptDefinition(prompt);
    });
```

`TemplatePrompt` is immutable and Equatable, so content, variables, defaults, types, and options participate in family-key equality. Do not add a second content-hash map or retain ASTs in persistent state.

- [ ] **Step 4: Replace the regex builder with evaluator-to-message adaptation**

Use this callable contract:

```dart
TemplatedUserMessageBuildResult buildTemplatedUserMessage({
  required String body,
  required TemplatePrompt? templatePrompt,
  TemplatePromptCompilation? compilation,
  Map<String, String> variableValues = const {},
});
```

Rules:

- if `templatePrompt == null`, return success for the trimmed body and ignore `compilation`;
- if a template exists, require a successful compilation; a null/invalid compilation returns failure and never recompiles inside the builder;
- call `evaluateTemplatePrompt` once;
- translate evaluator output chunk kinds to `UserMessageSegmentKind.template/body`;
- preserve evaluator text exactly and merge only adjacent segments with the same kind;
- copy effective values and segments into unmodifiable collections;
- remove all imports and use of `template_prompt_parser.dart`.

- [ ] **Step 5: Write failing command tests for typed rejection and side effects**

Add cases to `chat_composer_command_test.dart`:

- malformed block -> `ChatComposerRejectReason.invalidTemplate`;
- stored variable metadata conflicting with source declarations -> `invalidTemplate`;
- number value `-` -> `invalidTemplateValue`;
- rejected dispatch leaves `FakeChatGenerationClient.requestHistory` empty and retains body/template/variable draft;
- valid select dispatch stores its string value, not an index;
- an explicit select value outside its options -> `invalidTemplateValue`;
- an omitted select value persists the configured default in sent/edited metadata and rendered content;
- existing null-template, empty, no-model, busy, stale-conversation and edit paths remain unchanged.

Keep validation precedence `staleConversation -> busy -> noModel -> template build -> empty` so unrelated rejection behavior does not change.

- [ ] **Step 6: Run the command test red**

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/features/chat/application/composer/chat_composer_command_test.dart 2>&1 | Out-File -Encoding utf8 logs/template-chat-command-red.log
$TestExit = $LASTEXITCODE
Write-Host "EXIT=$TestExit"
Get-Content -Tail 160 logs/template-chat-command-red.log
if ($TestExit -eq 0) { throw 'RED gate failed: command rejection tests unexpectedly passed' }
```

Expected failure: the new reject reasons are absent or invalid template/value input still reaches the generation facade.

- [ ] **Step 7: Make command dispatch consume the shared compilation result**

Extend the enum only with `invalidTemplate` and `invalidTemplateValue`. When a template is selected, read `templatePromptCompilationProvider(template)` once and pass it to the builder. Map compile diagnostics to `invalidTemplate` and runtime value errors to `invalidTemplateValue`. On success:

- use `success.message.content` and `.userMessageSegments`;
- persist `success.effectiveVariableValues`, not the raw intent map;
- start generation before returning accepted exactly as today;
- clear only the body after the generation call has been created;
- do not write compile/evaluation state to `ChatSessionsState`.

- [ ] **Step 8: Run Chat application tests green**

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
$ChatApplicationTests = @(
  'test/features/chat/application/composer/templated_user_message_builder_test.dart',
  'test/features/chat/application/composer/chat_composer_command_test.dart'
)
flutter test $ChatApplicationTests 2>&1 | Out-File -Encoding utf8 logs/template-chat-application-green.log
$TestExit = $LASTEXITCODE
Write-Host "EXIT=$TestExit"
Get-Content -Tail 180 logs/template-chat-application-green.log
if ($TestExit -ne 0) { exit $TestExit }
```

- [ ] **Step 9: Format, stage only Task 3 files, and commit**

```powershell
$TaskFiles = @(
  'lib/features/chat/application/composer/template_prompt_compilation_provider.dart',
  'lib/features/chat/application/composer/templated_user_message_builder.dart',
  'lib/features/chat/application/composer/chat_composer_command.dart',
  'test/features/chat/application/composer/templated_user_message_builder_test.dart',
  'test/features/chat/application/composer/chat_composer_command_test.dart'
)
dart format $TaskFiles
git add -- $TaskFiles
$StagedDartFiles = @(git diff --cached --name-only --diff-filter=ACMR -- '*.dart')
dart format --output=none --set-exit-if-changed $StagedDartFiles
git diff --cached --check
git diff --cached --name-only
git commit -m 'feat(chat): 渲染模板提示词条件分支'
```

**Task 3 acceptance:** The builder has no parser/regex dependency; command rejection is typed and side-effect free; success persists normalized string values and preserves current null-template/edit behavior.

---

### Task 4: Render dynamic template controls in the Chat composer

**Files:**

- Modify: `lib/features/chat/application/composer/composer_draft_controller.dart`
- Modify: `lib/features/chat/presentation/chat_screen.dart`
- Modify: `lib/features/chat/presentation/widgets/composer/chat_composer_card.dart`
- Modify: `lib/features/chat/presentation/widgets/composer/fields/composer_template_variable_fields.dart`
- Modify: `lib/features/chat/presentation/widgets/composer/fields/number_variable_field.dart`
- Create: `lib/features/chat/presentation/widgets/composer/fields/select_variable_field.dart`
- Modify: `test/features/chat/presentation/chat_screen_test.dart`
- Create: `test/features/chat/presentation/chat_screen/chat_screen_template_language_cases.dart`
- Modify: `test/features/chat/presentation/widgets/composer/chat_composer_card_responsive_test.dart`

**Contract:** Selecting a template still uses the existing header. Condition-control variables and variables in the active branch are visible; variables only in inactive branches are hidden without losing their per-template draft values. A compile/value error is inline, never a SnackBar/Dialog, and no generation starts. Historical select values absent from current options visibly and persistently fall back to the current configured default.

- [ ] **Step 1: Register failing production-wiring ChatScreen cases**

Import `chat_screen_template_language_cases.dart` in `chat_screen_test.dart` and call `registerChatScreenTemplateLanguageTests()`. Reuse `chat_screen_test_helpers.dart`, the real `templatePromptsProvider`, real composer draft controller, and `FakeChatGenerationClient`; do not manually transfer state between controllers.

Add these cases with Chinese titles:

1. choosing a select option changes visible branch fields and final sent text;
2. condition-control field remains visible regardless of active branch;
3. typing into branch A, switching to branch B, then returning to A restores A's draft;
4. variables declared outside a condition remain visible in all branches;
5. a number comparison switches branches for `>`, `>=`, `<`, and `<=` boundary values (parameterized);
6. select menu values are the declared strings and the message persists the string, never list index text;
7. editing a historical message whose saved select value was removed shows the current configured default, normalizes the editing draft, and sends that default after submit;
8. a malformed/currently inconsistent template shows inline diagnostic text and send interaction creates no request;
9. number value `-` shows inline field error and send creates no request;
10. switching conversations does not leak selected template, visible branch, or hidden values.
11. updating the selected template through `templatePromptsProvider` with the same ID but new content/options recompiles the new immutable definition, refreshes fields, and never renders the old branch program.

Use visible labels, dropdown interaction, message content, Provider state, and fake request history. Do not assert private widget types or pixel positions.

- [ ] **Step 2: Run the new ChatScreen cases red**

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/features/chat/presentation/chat_screen_test.dart 2>&1 | Out-File -Encoding utf8 logs/template-chat-ui-red.log
$TestExit = $LASTEXITCODE
Write-Host "EXIT=$TestExit"
Get-Content -Tail 180 logs/template-chat-ui-red.log
if ($TestExit -eq 0) { throw 'RED gate failed: dynamic template UI tests unexpectedly passed' }
```

Expected failure: select controls/active-variable filtering do not exist, or both branches remain visible. First fix test harness compilation if the new case registration itself is malformed.

- [ ] **Step 3: Add a bulk draft normalization operation**

Add to `ComposerDraftController`:

```dart
void replaceTemplateVariables(
  String conversationId,
  String templateId,
  Map<String, String> values,
)
```

It must deep-copy and store only when lengths or any key/value differ; do not use Dart `Map.==`, which is identity equality. It replaces only the selected template's nested variable map and preserves body, selection, other template drafts, and other conversations. Test this behavior in the ChatScreen stale-value case; add a controller unit test only if the widget case cannot expose the contract deterministically.

- [ ] **Step 4: Compile once in `ChatComposerCard` and react to controller values**

Convert `ChatComposerCard` to `ConsumerWidget`. For a selected template, watch `templatePromptCompilationProvider(selectedTemplate)`. Inside the expanded composer, use a `ListenableBuilder` whose listenable is `Listenable.merge` over the body controller and all template variable controllers. On each controller change:

- construct the raw value map without mutating Provider state;
- call `evaluateTemplatePrompt` when compilation is valid;
- pass `activeInputVariableNames.toSet()` and `valueErrors` to the field list;
- show the first compile diagnostic or value error inline using the existing theme's error color;
- pass `null` instead of `bindings.onSendPressed` to the message shortcut and both send-button rows while compilation/value validation is invalid;
- keep normal no-template behavior unchanged.

Do not introduce a preview string. Evaluation here is only for field visibility/validation; Task 3 command remains the authoritative send boundary.

Because the card now consumes a Provider, wrap the existing direct responsive test harness in `ProviderScope`; retain its layout assertions unchanged.

- [ ] **Step 5: Implement controlled text, number, and select fields**

Change `ComposerTemplateVariableFields` inputs to:

```dart
final TemplatePromptProgram program;
final Set<String> activeInputVariableNames;
final Map<String, TextEditingController> templateVariableControllers;
final Map<String, TemplatePromptValueError> valueErrorsByVariable;
```

Iterate `program.inputVariables` in declaration order and render only active names. Never delete or recreate hidden controllers. Text remains a `TextField`; number uses `NumberVariableField`; select uses the new `SelectVariableField`.

`SelectVariableField` must be controlled through the existing `TextEditingController`:

```dart
class SelectVariableField extends StatelessWidget {
  const SelectVariableField({
    required this.controller,
    required this.variable,
    this.errorText,
    super.key,
  });
}
```

Use `InputDecorator` plus `DropdownButton<String>`/`DropdownMenuItem<String>` so the selected value always comes from `controller.text`. `onChanged` writes the option string to the controller and moves no indexes into state. Options are rendered exactly as authored. Add `errorText` to `NumberVariableField`; do not weaken its signed-integer formatter or arrow behavior.

- [ ] **Step 6: Project compiled declarations into controllers without discarding hidden values**

In `ChatScreen._syncTemplateVariableControllers`:

- compile the selected immutable template through `ref.read(templatePromptCompilationProvider(template))`;
- for valid compilation, create/retain controllers for every `program.inputVariable`, not only active variables;
- dispose controllers only when a variable is absent from the whole new template definition;
- resolve every saved/default value through `normalizeTemplatePromptVariableDraftValue`;
- for stale select input, set the controller to the configured default;
- do not silently replace invalid number text, because the user must see and repair it;
- preserve `_isProjectingComposerDraft` listener suppression.

If a stale select raw value differs from the resolved value, schedule exactly one guarded `WidgetsBinding.instance.addPostFrameCallback`: re-read the current conversation/template draft, verify the raw value and active editing transaction still match, then call `replaceTemplateVariables`. Do not write a Provider during `build`, and do not use `Future.delayed`.

Apply the same resolver in `_resolvedTemplateValuesForDraft` and editing-message restoration. The source of truth for fallback is `TemplatePromptVariable.defaultValue`; never use `options.first` except the compiler/form's initial default creation.

- [ ] **Step 7: Run focused Chat UI and application regression tests green**

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
$ChatTemplateTests = @(
  'test/features/chat/presentation/chat_screen_test.dart',
  'test/features/chat/presentation/widgets/composer/chat_composer_card_responsive_test.dart',
  'test/features/chat/application/composer/templated_user_message_builder_test.dart',
  'test/features/chat/application/composer/chat_composer_command_test.dart'
)
flutter test $ChatTemplateTests 2>&1 | Out-File -Encoding utf8 logs/template-chat-ui-green.log
$TestExit = $LASTEXITCODE
Write-Host "EXIT=$TestExit"
Get-Content -Tail 200 logs/template-chat-ui-green.log
if ($TestExit -ne 0) { exit $TestExit }
```

- [ ] **Step 8: Format, stage only Task 4 files, and commit**

```powershell
$TaskFiles = @(
  'lib/features/chat/application/composer/composer_draft_controller.dart',
  'lib/features/chat/presentation/chat_screen.dart',
  'lib/features/chat/presentation/widgets/composer/chat_composer_card.dart',
  'lib/features/chat/presentation/widgets/composer/fields/composer_template_variable_fields.dart',
  'lib/features/chat/presentation/widgets/composer/fields/number_variable_field.dart',
  'lib/features/chat/presentation/widgets/composer/fields/select_variable_field.dart',
  'test/features/chat/presentation/chat_screen_test.dart',
  'test/features/chat/presentation/chat_screen/chat_screen_template_language_cases.dart',
  'test/features/chat/presentation/widgets/composer/chat_composer_card_responsive_test.dart'
)
dart format $TaskFiles
git add -- $TaskFiles
$StagedDartFiles = @(git diff --cached --name-only --diff-filter=ACMR -- '*.dart')
dart format --output=none --set-exit-if-changed $StagedDartFiles
git diff --cached --check
git diff --cached --name-only
git commit -m 'feat(chat): 动态展示条件模板变量'
```

**Task 4 acceptance:** Only active branch fields render, hidden drafts survive branch/conversation switches, select values are controlled strings, invalid input cannot start generation, and stale history values visibly use the current configured default.

---

### Task 5: Support authoring and validating the language in Settings

**Files:**

- Modify: `lib/features/settings/presentation/widgets/prompts/forms/template_prompt_form_dialog.dart`
- Create: `lib/features/settings/presentation/widgets/prompts/forms/template_prompt_syntax_help.dart`
- Create: `test/features/settings/presentation/widgets/prompts/forms/template_prompt_form_dialog_test.dart`
- Delete: `lib/features/settings/domain/template_prompt_parser.dart`
- Delete: `test/features/settings/domain/template_prompt_parser_test.dart`

**Contract:** The same compiler used by Chat validates create/edit input. Invalid source produces a stable inline diagnostic and cannot be submitted. Valid source reconciles variable editors; a select default is chosen from a dropdown. A collapsed help area explains the first-version grammar and limitations without adding a render preview.

- [ ] **Step 1: Write failing form tests before changing the form**

Pump `TemplatePromptFormDialog` directly inside `ProviderScope`/`MaterialApp` and capture `onSubmit`. Use controlled `tester.pump(TemplatePromptFormDialog.variableReconcileDebounce)` for the documented finite debounce rather than `pumpAndSettle()`.

Cover:

1. help is collapsed initially; tapping “模板语法说明” reveals examples for text, number, select, if/else if/else and `正文`;
2. help explicitly says no nested `if`, no `|` inside an option, and no direct escaped output of `{{` in v1;
3. typing `{{人称:select|一|二|三}}` renders a default dropdown initially set to `一`;
4. choosing `二` and submitting returns `TemplatePromptVariable(type: select, options: ['一','二','三'], defaultValue: '二')`;
5. editing unrelated text preserves an existing valid select default;
6. changing options from `一|二|三` to `一|三` falls back to the first option only in the authoring form because the configured default was removed;
7. invalid/unclosed/nested blocks show the first diagnostic with line/column and keep the save callback uncalled;
8. while source is temporarily invalid, existing variable default controllers and their values are not disposed or cleared; repairing source restores reconciliation;
9. `{{正文}}` inside a branch is rejected; a top-level body variable keeps the current non-editable hint;
10. an invalid number default is a field-level validation error and is not submitted;
11. no preview heading/output is present.

Prefer visible text and callback data assertions. Keys may be used only where the form already exposes a stable input key.

- [ ] **Step 2: Run the form test red**

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/features/settings/presentation/widgets/prompts/forms/template_prompt_form_dialog_test.dart 2>&1 | Out-File -Encoding utf8 logs/template-settings-form-red.log
$TestExit = $LASTEXITCODE
Write-Host "EXIT=$TestExit"
Get-Content -Tail 180 logs/template-settings-form-red.log
if ($TestExit -eq 0) { throw 'RED gate failed: select/help/diagnostic form tests unexpectedly passed' }
```

Expected failure: the help widget/select default editor/compiler diagnostics do not exist. An asset/plugin startup failure is not valid red evidence.

- [ ] **Step 3: Add the collapsed syntax help widget**

Implement `TemplatePromptSyntaxHelp` as a default-collapsed Material expansion control. Keep the copy short and literal. It must include valid examples:

```text
{{主角名}}
{{章节数:number}}
{{人称:select|一|二|三}}
{{#if 人称 == "一"}}
使用“我”的口吻，主角是{{主角名}}。
{{else if 人称 == "二"}}
使用“你”的口吻。
{{else}}
使用第三人称。
{{/if}}
```

Also state:

- text/select support `==` and `!=`; number also supports `> >= < <=`;
- string literals use double quotes and integer literals are unquoted;
- control tags can be inline or standalone, with standalone tag lines removed;
- `正文` must be outside conditions; without it, body is inserted above the template;
- nested conditions, boolean combinations, template references, preview, option `|` escaping, and literal `{{` escaping are not supported in v1.

Do not add an editor toolbar, syntax insertion buttons, preview panel, or a new settings route.

- [ ] **Step 4: Replace parser reconciliation with compilation state**

Maintain these state fields:

```dart
late TemplatePromptCompilation _compilation;
late List<TemplatePromptVariable> _variables;
```

At init, compile the source content first; when syntax is valid, reconcile it with `initialValue.variables` and then validate the resulting temporary full definition. This lets valid legacy text/number templates retain defaults while still surfacing inconsistent stored metadata. During the existing 220/320ms debounced callback:

1. compile `_pendingContent`;
2. if invalid, update `_compilation` only and preserve `_variables` plus every existing controller;
3. if valid, call `reconcileCompiledTemplatePromptVariables` with `_buildVariablesFromControllers()`;
4. compare name, body role, type, and ordered options in `_sameVariableShape`;
5. update compilation/variables/controllers in one `setState`;
6. remove controllers only for declarations absent from a newly valid program.

Show the first diagnostic directly below the content field as `第 X 行第 Y 列：<message>`. Give the scaffold `submitEnabled: _compilation.isValid`; `_handleSubmit` must flush debounce and explicitly return when compilation is invalid so keyboard submission cannot bypass the button state.

- [ ] **Step 5: Render and validate defaults by variable type**

- body: retain the current hint and force empty default;
- text: retain the text form field;
- number: retain numeric keyboard and add a validator requiring a trimmed integer, with empty resolving to `1` only when reconciliation creates a new number variable;
- select: render `DropdownButtonFormField<String>` with declared options and current configured default. On option-shape change, reconciliation retains the default if still present, otherwise selects `options.first`.

When building form data, copy `type` and immutable `options` for every variable. Never store dropdown index. Before `onSubmit`, construct a temporary definition using form content/variables and require `compileTemplatePromptDefinition` to be valid; treat a mismatch as inline form failure rather than throwing.

- [ ] **Step 6: Run form and domain tests green**

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
$SettingsAuthoringTests = @(
  'test/features/settings/presentation/widgets/prompts/forms/template_prompt_form_dialog_test.dart',
  'test/features/settings/domain/template_prompt_language/template_prompt_compiler_test.dart',
  'test/features/settings/domain/template_prompt_language/template_prompt_evaluator_test.dart',
  'test/features/settings/domain/models/prompts/template_prompt_test.dart'
)
flutter test $SettingsAuthoringTests 2>&1 | Out-File -Encoding utf8 logs/template-settings-form-green.log
$TestExit = $LASTEXITCODE
Write-Host "EXIT=$TestExit"
Get-Content -Tail 200 logs/template-settings-form-green.log
if ($TestExit -ne 0) { exit $TestExit }
```

- [ ] **Step 7: Remove the legacy parser only after proving no production imports remain**

```powershell
$LegacyReferences = @(rg -n "template_prompt_parser|matchTemplatePromptPlaceholders|parseVariableSpec|reconcileTemplatePromptVariables" lib test --glob '!test/features/settings/domain/template_prompt_parser_test.dart')
if ($LASTEXITCODE -eq 0 -and $LegacyReferences.Count -gt 0) {
  $LegacyReferences
  throw 'Legacy template parser still has callers; migrate them before deletion'
}
if ($LASTEXITCODE -gt 1) { throw 'rg failed while auditing legacy parser references' }
```

Then delete `template_prompt_parser.dart` and its old test with the patch tool. Do not leave compatibility wrappers: compiler tests now own legacy text/number placeholder behavior.

- [ ] **Step 8: Re-run the form/domain tests after parser deletion**

Repeat Step 6 and require `EXIT=0`. Also run:

```powershell
rg -n "template_prompt_parser|matchTemplatePromptPlaceholders|parseVariableSpec|reconcileTemplatePromptVariables" lib test
if ($LASTEXITCODE -eq 0) { throw 'Legacy parser symbols remain after deletion' }
if ($LASTEXITCODE -gt 1) { throw 'rg failed during final legacy parser audit' }
```

- [ ] **Step 9: Format, stage Task 5 additions/modifications/deletions, and commit**

```powershell
$TaskFiles = @(
  'lib/features/settings/presentation/widgets/prompts/forms/template_prompt_form_dialog.dart',
  'lib/features/settings/presentation/widgets/prompts/forms/template_prompt_syntax_help.dart',
  'test/features/settings/presentation/widgets/prompts/forms/template_prompt_form_dialog_test.dart',
  'lib/features/settings/domain/template_prompt_parser.dart',
  'test/features/settings/domain/template_prompt_parser_test.dart'
)
$ExistingDartFiles = @($TaskFiles | Where-Object { Test-Path -LiteralPath $_ })
dart format $ExistingDartFiles
git add -A -- $TaskFiles
$StagedDartFiles = @(git diff --cached --name-only --diff-filter=ACMR -- '*.dart')
dart format --output=none --set-exit-if-changed $StagedDartFiles
git diff --cached --check
git diff --cached --name-status
git commit -m 'feat(settings): 支持编辑条件模板'
```

**Task 5 acceptance:** New/edit forms share the compiler, invalid source/defaults cannot submit, select defaults are strings, temporary invalid typing does not erase editor state, syntax help is collapsed and accurate, and the old parser has no remaining references.

---

### Task 6: Persist select metadata, migrate Settings export to v8, and document limits

**Files:**

- Modify: `test/features/settings/data/prompts/sqlite_repositories_test.dart`
- Modify: `lib/features/settings/domain/models/transfer/settings_export_data.dart`
- Modify: `lib/features/settings/domain/models/transfer/settings_export_codec.dart`
- Modify: `test/features/settings/domain/models/transfer/settings_export_data_test.dart`
- Modify: `test/features/settings/domain/models/transfer/settings_export_codec_test.dart`
- Modify: `lib/features/settings/application/transfer/settings_import_deduplicator.dart`
- Modify: `test/features/settings/application/transfer/settings_import_deduplicator_test.dart`
- Modify: `README.md`

**Contract:** SQLite continues using the existing `variables_json` column and stores select choices as values. Settings snapshot format becomes v8; v5/v6/v7 migrate in sequence, v8 validates complete template definitions, and future versions are rejected. Import deduplication distinguishes variable type/options. Documentation warns about syntax limitations and application downgrade risk.

- [ ] **Step 1: Write failing SQLite/model persistence assertions**

Extend the existing `TemplatePrompt round-trip` case in `sqlite_repositories_test.dart` with a select variable whose configured default is the second option. Assert the loaded object equals the original and its raw/default value is the string `二`. Do not add a new table/column or raw SQL widget test.

Run red immediately after the Task 1 model test but before assuming repository support:

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/features/settings/data/prompts/sqlite_repositories_test.dart 2>&1 | Out-File -Encoding utf8 logs/template-sqlite-red.log
$TestExit = $LASTEXITCODE
Write-Host "EXIT=$TestExit"
Get-Content -Tail 120 logs/template-sqlite-red.log
```

If this already passes because generic JSON serialization is sufficient, record it as compatibility evidence and do not invent repository production changes merely to force red. The feature's TDD red evidence already exists at model/compiler boundaries.

- [ ] **Step 2: Write failing v8 codec and comparator tests**

Update `settings_export_data_test.dart` and `settings_export_codec_test.dart` to cover:

1. current encode emits `formatVersion: 8`;
2. v8 select template round-trip preserves ordered options/default string;
3. v7 migrates to v8 with `sourceVersion == 7` and `migrated == true`;
4. v6 migration writes literal v7 before the v7-to-v8 migrator runs;
5. v5 chains v5->v6->v7->v8;
6. v8 current snapshot missing an explicit provider protocol still remains malformed;
7. future v9 is `SettingsExportUnsupportedVersion`;
8. v8 template with malformed block, nested block, mismatched variable metadata, invalid select default, or conditional `正文` is `SettingsExportMalformed` (parameterized by compiler error family);
9. a valid legacy v5-v7 text/number template migrates successfully.

Every template fixture used in a success path must have source declarations matching its stored variables. For example, content containing `{{正文}}` must include the body variable; do not weaken definition validation to preserve invalid test data.

Extend `settings_import_deduplicator_test.dart` so equal content/defaults but different variable type or ordered select options are not deduplicated; fully equal select definitions are deduplicated.

- [ ] **Step 3: Run transfer tests red**

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
$TransferRedTests = @(
  'test/features/settings/domain/models/transfer/settings_export_data_test.dart',
  'test/features/settings/domain/models/transfer/settings_export_codec_test.dart',
  'test/features/settings/application/transfer/settings_import_deduplicator_test.dart'
)
flutter test $TransferRedTests 2>&1 | Out-File -Encoding utf8 logs/template-settings-v8-red.log
$TestExit = $LASTEXITCODE
Write-Host "EXIT=$TestExit"
Get-Content -Tail 180 logs/template-settings-v8-red.log
if ($TestExit -eq 0) { throw 'RED gate failed: v8 migration/validation tests unexpectedly passed' }
```

Expected failure: current version is still 7, v7 is treated as current, or codec accepts an invalid compiled definition.

- [ ] **Step 4: Implement the explicit migration chain**

Set `SettingsExportData.formatVersion = 8` and update its JSON example. Add:

```dart
final class SettingsExportFormatMigratorV7ToV8 {
  const SettingsExportFormatMigratorV7ToV8();

  Map<String, Object?> migrate(Map<String, Object?> source) {
    return {...source, 'formatVersion': 8};
  }
}
```

Correct `SettingsExportFormatMigratorV6ToV7` so both branches write literal `7`, never `SettingsExportData.formatVersion`. Route versions explicitly:

```dart
final normalized = switch (version) {
  5 => _migrateV5ToCurrent(source),
  6 => _migrateV6ToCurrent(source),
  7 => _migrateV7ToCurrent(source),
  8 => source,
  _ => throw StateError('range guard must reject this version'),
};
```

`_migrateV5ToCurrent` calls v5->v6 then the remaining chain; `_migrateV6ToCurrent` calls v6->v7 then v7->v8; `_migrateV7ToCurrent` calls only v7->v8. Do not change `minimumSupportedVersion` or Sync protocol versions.

- [ ] **Step 5: Validate complete templates during current decoding**

In `_decodeCurrent`, decode templates to a local immutable list, then run `compileTemplatePromptDefinition` for each. If any compilation is invalid, throw `FormatException` containing only a safe diagnostic summary; the public codec still maps it to `SettingsExportMalformed` and does not expose internal exceptions.

This validation applies after migration, so v5-v7 success data must also be structurally valid. Unknown persisted variable types keep the model's text fallback, but a fallback that conflicts with explicit source syntax is malformed rather than silently reinterpreted.

- [ ] **Step 6: Compare the complete variable value object during import deduplication**

In `TemplatePromptImportComparator`, preserve the existing title-independent/content-first semantics, but compare each `TemplatePromptVariable` by Equatable value. Its name, default, type and ordered options must all match. Do not compare select indexes or compiled AST identity.

- [ ] **Step 7: Run SQLite and transfer tests green**

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
$PersistenceTransferTests = @(
  'test/features/settings/data/prompts/sqlite_repositories_test.dart',
  'test/features/settings/domain/models/transfer/settings_export_data_test.dart',
  'test/features/settings/domain/models/transfer/settings_export_codec_test.dart',
  'test/features/settings/application/transfer/settings_import_deduplicator_test.dart',
  'test/features/settings/application/transfer/settings_transfer_workflow_test.dart',
  'test/features/settings/application/transfer/settings_sync_facade_test.dart'
)
flutter test $PersistenceTransferTests 2>&1 | Out-File -Encoding utf8 logs/template-settings-v8-green.log
$TestExit = $LASTEXITCODE
Write-Host "EXIT=$TestExit"
Get-Content -Tail 220 logs/template-settings-v8-green.log
if ($TestExit -ne 0) { exit $TestExit }
```

If a success fixture fails only because its source/variables were already inconsistent, correct that fixture in the owning test file and add the path to Task 6 staging. Do not relax production validation. If production behavior beyond the approved design fails, stop and reassess rather than broadening this task.

- [ ] **Step 8: Add user-facing syntax and downgrade documentation**

Add a concise `### 模板提示词` subsection near the existing Prompt/settings documentation in `README.md` containing:

- text, number and select examples;
- the approved block syntax and operator matrix;
- manual template selection remains the trigger;
- hidden branch variables retain their current draft values;
- v1 limitations: no nested `if`, boolean combinations, template references, preview, option `|` escaping, or literal `{{` escaping;
- Settings export v8 compatibility: older supported snapshots migrate forward, older applications reject v8 export;
- application downgrade warning: a version predating conditional templates may read the same local SQLite row but render control tags/both branches as ordinary text; users should back up/export before downgrade and avoid editing/sending such templates in the older application.

Do not claim old versions will crash: current evidence only establishes semantic misrender risk, while unknown variable `type` already has text fallback behavior.

- [ ] **Step 9: Prove no SQLite schema or Sync protocol migration was introduced**

```powershell
$ImplementationBase = (Get-Content -LiteralPath logs/template-language-base-head.txt -Raw).Trim()
$ForbiddenInfrastructure = @(git diff --name-only $ImplementationBase -- lib/core/persistence lib/features/sync/domain/models/protocol)
if ($LASTEXITCODE -ne 0) { throw 'git diff failed during infrastructure scope audit' }
if ($ForbiddenInfrastructure.Count -gt 0) {
  $ForbiddenInfrastructure
  throw 'SQLite infrastructure or Sync protocol files changed'
}
```

Expected: no exception. If paths are printed, inspect them and remove unrelated/schema/protocol changes before continuing. `variables_json` serialization changes are confined to the domain model and existing repository behavior.

- [ ] **Step 10: Format, stage only Task 6 files, and commit**

```powershell
$TaskFiles = @(
  'test/features/settings/data/prompts/sqlite_repositories_test.dart',
  'lib/features/settings/domain/models/transfer/settings_export_data.dart',
  'lib/features/settings/domain/models/transfer/settings_export_codec.dart',
  'test/features/settings/domain/models/transfer/settings_export_data_test.dart',
  'test/features/settings/domain/models/transfer/settings_export_codec_test.dart',
  'lib/features/settings/application/transfer/settings_import_deduplicator.dart',
  'test/features/settings/application/transfer/settings_import_deduplicator_test.dart',
  'README.md'
)
$DartFiles = @($TaskFiles | Where-Object { $_ -like '*.dart' })
dart format $DartFiles
git add -- $TaskFiles
$StagedDartFiles = @(git diff --cached --name-only --diff-filter=ACMR -- '*.dart')
dart format --output=none --set-exit-if-changed $StagedDartFiles
git diff --cached --check
git diff --cached --name-only
git commit -m 'feat(settings): 升级条件模板交换格式'
```

If Step 7 required fixture-only corrections in another test file, explicitly append those exact paths to `$TaskFiles` and explain them in the commit body.

**Task 6 acceptance:** Select metadata survives SQLite/export round trips as strings; migration is v5->v6->v7->v8; invalid definitions are rejected; deduplication respects type/options; downgrade risk and v1 syntax limits are documented without changing DB/Sync versions.

---

## 2. Final Verification and Scope Audit

Run these gates serially after all six commits. Do not start a second Flutter/Dart gate while one is active.

- [ ] **Step 1: Verify every changed Dart file is formatted**

```powershell
$ImplementationBase = (Get-Content -LiteralPath logs/template-language-base-head.txt -Raw).Trim()
$ChangedDartFiles = @(git diff --name-only $ImplementationBase..HEAD -- '*.dart')
if ($ChangedDartFiles.Count -eq 0) { throw 'No Dart implementation changes found' }
dart format --output=none --set-exit-if-changed $ChangedDartFiles
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
git diff --check $ImplementationBase..HEAD
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
```

- [ ] **Step 2: Run the import-boundary gate**

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
dart run tool/check_import_boundaries.dart 2>&1 | Out-File -Encoding utf8 logs/template-language-import-boundaries.log
$GateExit = $LASTEXITCODE
Write-Host "EXIT=$GateExit"
Get-Content -Tail 160 logs/template-language-import-boundaries.log
if ($GateExit -ne 0) { exit $GateExit }
```

If this fails, fix the import direction rather than adding a broad allowlist. Settings domain must remain framework-free and Chat presentation must consume Settings language types through permitted application/domain imports.

- [ ] **Step 3: Run static analysis**

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter analyze --no-pub 2>&1 | Out-File -Encoding utf8 logs/template-language-analyze.log
$AnalyzeExit = $LASTEXITCODE
Write-Host "EXIT=$AnalyzeExit"
Get-Content -Tail 180 logs/template-language-analyze.log
if ($AnalyzeExit -ne 0) { exit $AnalyzeExit }
```

If analysis stalls after dependency resolution, kill stale test processes once and retry `flutter analyze --no-pub`. Do not report a pass without the final `EXIT=0`.

- [ ] **Step 4: Run the complete test suite with mandatory redirection**

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test --reporter compact 2>&1 | Out-File -Encoding utf8 logs/fltest.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 150 logs/fltest.log
if ($TestExit -ne 0) { exit $TestExit }
```

On native-assets startup lock before cases begin, run `./scripts/kill-stale-test-processes.ps1` and retry once. On a real failure, inspect it with `Select-String -Path logs/fltest.log -Pattern '<test name or error>' -Context 0,30`; do not hide it by rerunning only focused tests.

- [ ] **Step 5: Audit forbidden scope and legacy symbols**

```powershell
$ImplementationBase = (Get-Content -LiteralPath logs/template-language-base-head.txt -Raw).Trim()

rg -n "template_prompt_parser|matchTemplatePromptPlaceholders|parseVariableSpec|reconcileTemplatePromptVariables" lib test
if ($LASTEXITCODE -eq 0) { throw 'Legacy parser references remain' }
if ($LASTEXITCODE -gt 1) { throw 'rg failed during legacy parser audit' }

rg -n "part of|^part '" lib/features/settings/domain/template_prompt_language lib/features/chat/application/composer lib/features/chat/presentation/widgets/composer
if ($LASTEXITCODE -eq 0) { throw 'Forbidden part directive introduced' }
if ($LASTEXITCODE -gt 1) { throw 'rg failed during part directive audit' }

rg -n "package:flutter|flutter_riverpod|sqlite3" lib/features/settings/domain/template_prompt_language
if ($LASTEXITCODE -eq 0) { throw 'Settings template language domain imports framework or persistence code' }
if ($LASTEXITCODE -gt 1) { throw 'rg failed during domain dependency audit' }

$ForbiddenInfrastructure = @(git diff --name-only $ImplementationBase..HEAD -- lib/core/persistence lib/features/sync/domain/models/protocol)
if ($LASTEXITCODE -ne 0) { throw 'git diff failed during infrastructure scope audit' }
if ($ForbiddenInfrastructure.Count -gt 0) {
  $ForbiddenInfrastructure
  throw 'SQLite infrastructure or Sync protocol files changed'
}

$ChangedDartPaths = @(git diff --name-only $ImplementationBase..HEAD -- '*.dart')
if ($LASTEXITCODE -ne 0) { throw 'git diff failed during feature scope audit' }
$ForbiddenFeaturePaths = @(
  $ChangedDartPaths | Select-String -Pattern 'preview|auto_trigger|template_reference'
)
if ($ForbiddenFeaturePaths.Count -gt 0) {
  $ForbiddenFeaturePaths
  throw 'Out-of-scope preview/trigger/reference implementation found'
}
```

The first `git diff` must print nothing. Review any scope-audit match semantically before removing it if a pre-existing filename happens to contain one of the words; the intent is to prevent new feature code, not to delete unrelated existing functionality.

- [ ] **Step 6: Audit commit/file ownership and final worktree**

```powershell
$ImplementationBase = (Get-Content -LiteralPath logs/template-language-base-head.txt -Raw).Trim()
git log --oneline --decorate $ImplementationBase..HEAD
git diff --stat $ImplementationBase..HEAD
git diff --name-status $ImplementationBase..HEAD
git status --short
Select-String -Path pubspec.yaml -Pattern '^version:'
git rev-parse HEAD
```

Expected functional commits, in order:

1. `refactor(settings): 建立模板提示词编译模型`
2. `refactor(settings): 增加模板提示词求值边界`
3. `feat(chat): 渲染模板提示词条件分支`
4. `feat(chat): 动态展示条件模板变量`
5. `feat(settings): 支持编辑条件模板`
6. `feat(settings): 升级条件模板交换格式`

The post-commit hook may amend each commit and bump the version; report final hashes/version from the commands, not values predicted by this plan. The pre-existing media plan and this implementation-plan document may remain untracked unless the user separately authorizes documentation commits. No push is authorized.

---

## 3. Requirement-to-Evidence Matrix

| Approved behavior | Implementation owner | Required evidence |
| --- | --- | --- |
| Manual template selection remains the only trigger | Existing header; Tasks 3-4 avoid trigger changes | Existing ChatScreen basics plus scope audit |
| `select` options/defaults are strings | Tasks 1, 4, 5, 6 | Model JSON, dropdown interaction, message metadata, SQLite/export round-trip |
| `if / else if / else`, no nesting | Tasks 1-3 | Compiler error-code/location tests and rendered-content tests |
| Text/select and number operator matrix | Tasks 1-2 | Parameterized compiler/evaluator tests |
| Variables inside an active branch render normally | Tasks 2-4 | Evaluator branch substitution and ChatScreen send case |
| Control variables always show; inactive branch fields hide but retain drafts | Task 4 | Production-wiring Widget cases and draft Provider assertions |
| Historical stale select falls back to configured default | Task 4 | Edit-message Widget case; normalized draft and sent metadata |
| Bypassed invalid value is rejected | Tasks 2-3 | Evaluator and command side-effect tests |
| Top-level `正文` and legacy prepend behavior | Tasks 1-3 | Compiler/body chunk/builder compatibility tests |
| Standalone control lines remove all tag-line whitespace | Tasks 1-3 | LF/CRLF source span and exact content tests |
| Invalid source cannot save/import/send | Tasks 3, 5, 6 | Command, form, codec tests with no side effects |
| Stable diagnostic codes and UI line/column message | Tasks 1 and 5 | Domain enum/location assertions; visible form diagnostic |
| No AST persistence or SQLite schema migration | Tasks 1, 6 | Existing JSON round-trip and no persistence diff |
| Settings export v8 with v5-v7 forward migration | Task 6 | Version-chain tests |
| Collapsed syntax help, including escaping limitations | Task 5 | Widget test of collapsed/expanded copy |
| No nested templates, preview, auto trigger, boolean combinations, or hash cache | Global constraints and scope audit | File/diff review; absence of UI/grammar APIs |

---

## 4. Stop Conditions and Handoff

Stop implementation and ask for design direction if any of these occurs:

- supporting a required example would need nested `if`, boolean combinations, template references, new escaping grammar, or a declaration that never appears as a variable placeholder;
- existing user data reveals a valid legacy contract that the full-definition validator would reject broadly, rather than isolated malformed test fixtures;
- another worktree change overlaps the same template/compiler/form/chat files and ownership cannot be reconciled safely;
- correct behavior requires a SQLite column/user-version change or Sync protocol change;
- a failure can only be hidden through a broad import allowlist, generic exception swallowing, arbitrary delay, or weakening the invalid-template gate;
- focused tests pass but full analysis/suite has a reproducible product regression outside the listed files.

At handoff, report separately:

- which of the six tasks/commits actually completed;
- red/green log paths for each implemented boundary;
- final import-boundary, analyze, and full-suite exit codes;
- final HEAD/version and unpushed status;
- any omitted device/manual verification;
- any remaining unrelated worktree files.

Do not call the feature complete if any required gate is missing or non-zero. Do not commit or push follow-up fixes outside this plan without renewed authorization.
