### Task 1: Define the canonical Settings transfer v9 document

**Files:**
- Create: `lib/features/settings/domain/models/transfer/settings_transfer_document.dart`
- Create: `lib/features/settings/domain/models/transfer/settings_transfer_document_codec.dart`
- Create: `test/features/settings/domain/models/transfer/settings_transfer_document_codec_test.dart`
- Keep unchanged for now: `settings_export_data.dart`, `settings_export_codec.dart` and their tests

**Interfaces:**

```dart
final class SettingsTransferDocument extends Equatable {
  SettingsTransferDocument({required Map<String, Object?> sections})
    : sections = _freezeJsonObject(sections);

  static const identifier = 'shikiyuzu-oh-my-llm';
  static const formatVersion = 9;

  final Map<String, Object?> sections;
  Map<String, Object?> toJson() => Map.unmodifiable({
    'identifier': identifier,
    'formatVersion': formatVersion,
    'sections': sections,
  });

  @override
  List<Object?> get props => [jsonEncode(toJson())];
}

sealed class SettingsTransferDocumentDecodeResult {
  const SettingsTransferDocumentDecodeResult();
}
final class SettingsTransferDocumentDecodeSuccess
    extends SettingsTransferDocumentDecodeResult {
  const SettingsTransferDocumentDecodeSuccess(this.document);
  final SettingsTransferDocument document;
}
final class SettingsTransferDocumentUnsupportedVersion
    extends SettingsTransferDocumentDecodeResult {
  const SettingsTransferDocumentUnsupportedVersion(this.version);
  final int version;
}
final class SettingsTransferDocumentMalformed
    extends SettingsTransferDocumentDecodeResult {
  const SettingsTransferDocumentMalformed();
}

```

`SettingsTransferDocumentCodec` has exactly three public static members: `decodeJson(String?)`, `decodeObject(Map<String, Object?>)` and `encodeJson(SettingsTransferDocument)`. The first two return `SettingsTransferDocumentDecodeResult`; the last returns `String`.

The constructor/codec copies nested maps/lists into unmodifiable values and accepts only JSON-safe `null/bool/num/String/List/Map<String, Object?>`. Top level must contain exactly `identifier`, `formatVersion`, and `sections`; wrong identifier or wrong types are malformed, integer versions other than 9 are unsupported. The codec validates section key syntax and payload JSON safety but does not know whether a key is registered or how its payload decodes.

- [ ] **Step 1: Write failing v9 document tests**

Cover all of these in Chinese-named tests:

- round-trip preserves a non-empty ordered sections map;
- empty sections is structurally valid;
- v8 and v10 return `UnsupportedVersion` with their exact version;
- null, blank, invalid JSON, wrong identifier, missing/float version, missing/non-map sections and unexpected top-level keys return `Malformed`;
- non-string nested map keys and non-JSON-safe objects are rejected;
- mutating the source map/list after construction cannot change the document;
- `toJson()` returns a defensive structure that callers cannot mutate.

- [ ] **Step 2: Run the new test and record the expected red**

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/features/settings/domain/models/transfer/settings_transfer_document_codec_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/settings-transfer-document-red.log
$TestExit = $LASTEXITCODE
Write-Host "EXIT=$TestExit"
Get-Content -Tail 120 logs/settings-transfer-document-red.log
if ($TestExit -eq 0) { throw '预期 v9 document 类型尚不存在，red 却通过' }
```

Expected red: imports/types for `SettingsTransferDocument` or its codec are missing. Any native-assets or unrelated compilation failure is not valid evidence.

- [ ] **Step 3: Implement the immutable document and strict top-level codec**

Use recursive copy/validation helpers private to `settings_transfer_document.dart`; preserve insertion order with ordinary `LinkedHashMap` behavior wrapped by `Map.unmodifiable`. `props` may use `jsonEncode(toJson())` so nested value equality is structural and deterministic. Do not add participant imports.

- [ ] **Step 4: Run the focused green test**

```powershell
flutter test test/features/settings/domain/models/transfer/settings_transfer_document_codec_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/settings-transfer-document-green.log
$TestExit = $LASTEXITCODE
Write-Host "EXIT=$TestExit"
Get-Content -Tail 120 logs/settings-transfer-document-green.log
if ($TestExit -ne 0) { exit $TestExit }
```

Expected: `EXIT=0`, including v8/v10 rejection and defensive-copy assertions.

- [ ] **Step 5: Format, stage exactly and commit**

```powershell
$TransferFiles = @(
  'lib/features/settings/domain/models/transfer/settings_transfer_document.dart',
  'lib/features/settings/domain/models/transfer/settings_transfer_document_codec.dart',
  'test/features/settings/domain/models/transfer/settings_transfer_document_codec_test.dart'
)
dart format $TransferFiles
git add -- $TransferFiles
dart format --output=none --set-exit-if-changed $TransferFiles
git diff --cached --check
git diff --cached --name-only
git commit -m "feat(settings): 建立设置传输 v9 文档"
```

Expected staged paths are exactly the three listed files. After the hook, record actual `git rev-parse HEAD` and version.

---

