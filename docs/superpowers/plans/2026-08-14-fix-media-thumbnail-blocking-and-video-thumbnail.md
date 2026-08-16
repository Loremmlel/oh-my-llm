# 修复媒体缩略图主线程阻塞与视频预览图生成失败 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 消除图片缩略图生成对 Dart 主 isolate 的同步阻塞（修复文件夹图片多时视频播放器与 UI 卡顿），并修复视频缩略图因 ffprobe stdout 类型强转崩溃而完全无法生成的问题。

**Architecture:** 缩略图生成器（`MediaThumbnailGenerator`）是媒体 feature 的 data 层纯 Dart 组件，图片与视频缩略图共用同一个 `generate()` 入口。修复分两条独立路径：① 图片缩略图用 `Isolate.run` 把 `package:image` 的同步解码/缩放/编码整体挪进后台 isolate，并在 `generate()` 入口加并发门控限制同时生成的缩略图数量；② 视频路径的 `_getVideoDuration` 把 ffprobe 的 `stdoutEncoding` 显式设为 `utf8`，并对 stdout 做 String/字节双类型兼容解析（`DartThumbnailProcessRunner.run` 的 `stdoutEncoding` 参数默认为 null，导致真实 `Process.run` 返回字节而非 String，原有 `as String` 强转必然崩溃）。

**Tech Stack:** Dart `^3.11.5` / Flutter 3.44.x · `package:image`（纯 Dart 同步图片编解码）· `dart:isolate` · `dart:convert` · `dart:async` · 外部进程 ffmpeg/ffprobe（经 `ThumbnailProcessRunner` 抽象注入）

**Spec:** 本次修复没有独立 spec 文档，依据 2026-08-14 的根因调查。两点根因均已实测复现：
1. `MediaThumbnailGenerator._generateImageThumbnail`（`lib/features/media/data/scanning/media_thumbnail_generator.dart:61-77`）用 `package:image` 的同步 API 在主 isolate 解码/缩放/编码。实测单张 4000×3000 JPEG 耗时 554ms、连续 12 张 5844ms，期间主 isolate 事件循环完全停摆；`video_player` 的进度/缓冲/纹理上传事件全部依赖该事件循环，故文件夹图片多时视频播放卡顿。
2. `_getVideoDuration`（同文件:156）写 `result.stdout as String`，但 `DartThumbnailProcessRunner.run` 的 `stdoutEncoding` 参数默认 null，真实 `Process.run(..., stdoutEncoding: null)` 返回 `List<int>`，强转抛 `TypeError: _Uint8ArrayView is not a subtype of type 'String'`，所有视频缩略图在探测时长一步即失败。单测用脚本化 runner 直接构造 String 型 stdout，绕过了真实行为，故测试全绿线上必炸。

## Global Constraints

- Flutter 3.44.x stable / Dart `^3.11.5`；项目所有命令用 PowerShell 7。
- 代码注释与 doc 注释**简体中文**（`///` 写「为什么」，`//` 写「为什么」不写「做了什么」）。
- 测试名一律**简体中文**，描述触发条件与预期行为。
- 禁止 `part` / `part of`。
- 提交前必须对本次改动的 Dart 文件执行 `dart format`，暂存后再用 `dart format --output=none --set-exit-if-changed` 校验。
- 测试输出必须重定向到仓库根目录 ignored 的 `logs/`，禁止直接跑裸 `flutter test`。red/green 证据用 `logs/<任务>-red.log` / `logs/<任务>-green.log`。
- 视频测试注入脚本化 runner（`_ScriptedProcessRunner`），**禁止依赖主机 ffmpeg 安装状态**；回归测试用字节型 stdout 精确模拟真实 `Process.run` 默认行为。
- 缺陷回归测试必须证明「修复前失败、修复后通过」；Task 1 有明确 red/green 证据，Task 2 是性能修复，用行为契约测试 + 现有测试全过作为验证（性能属性无法用自动化测试稳定断言，禁用 timing 依赖断言）。
- 图片缩略图生成在 `Isolate.run` 中执行时，闭包只能捕获可发送值（路径 String），返回值只能是可发送类型（`List<int>`）；`ThumbnailException` 只含 String message，可发送，后台抛出会原样转发到主 isolate。

---

### Task 1: 修复视频缩略图——ffprobe 时长探测的 stdout 解码

**Files:**
- Modify: `lib/features/media/data/scanning/media_thumbnail_generator.dart`
  - `_getVideoDuration`（当前第 135-163 行）：ffprobe 调用显式传 `stdoutEncoding: utf8`，stdout 解析改为兼容 String 与字节
  - 文件顶部 import 增加 `dart:convert`
- Test: `test/features/media/data/scanning/media_thumbnail_generator_test.dart`
  - 在 `group('视频缩略图')` 内新增一个回归用例

**Interfaces:**
- Consumes: 现有 `_ScriptedProcessRunner`（返回构造好的 `ThumbnailProcessResult`，忽略 `stdoutEncoding` 参数）、现有 `versionOk` / `durationResult` / `extractionResult` 辅助、`_generateImageBytes('jpg')` 辅助。均在测试文件内已有。
- Produces: `MediaThumbnailGenerator.generate(String relativePath)` 对视频路径不再抛 `TypeError`，返回 ffmpeg 取帧的 JPEG 字节。`_getVideoDuration` 返回类型仍是 `Future<double>`。

- [ ] **Step 1: 写失败回归测试**

在 `test/features/media/data/scanning/media_thumbnail_generator_test.dart` 的 `group('视频缩略图')` 内（紧邻现有「短视频成功」用例后）新增：

```dart
test('ffprobe 返回字节型 stdout 时仍能解析时长（真实 Process.run 默认返回字节）', () async {
  await createVideoFile();
  final jpeg = _generateImageBytes('jpg');
  runner.enqueue(versionOk);
  runner.enqueue(versionOk);
  // 字节型 duration stdout：DartThumbnailProcessRunner.run 的 stdoutEncoding 参数
  // 默认 null，真实 Process.run(..., stdoutEncoding: null) 返回 List<int> 而非 String。
  runner.enqueue(
    ThumbnailProcessResult(
      exitCode: 0,
      stdout: utf8.encode('8.0'),
      stderr: '',
    ),
  );
  runner.enqueue(extractionResult(jpeg));

  final result = await generator.generate('/test.mp4');

  expect(result, jpeg);
});
```

说明：`utf8.encode('8.0')` 返回 `Uint8List`。修复前 `_getVideoDuration` 的 `result.stdout as String` 对它强转抛 `TypeError`，本用例失败；修复后走字节分支正确解析时长 `8.0` → 中间帧 `4.0` → 取帧成功，返回 `jpeg`。

- [ ] **Step 2: 运行测试，确认失败（red）**

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/features/media/data/scanning/media_thumbnail_generator_test.dart --plain-name "字节型" 2>&1 | Out-File -Encoding utf8 logs/media-thumb-task1-red.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 150 logs/media-thumb-task1-red.log
```

Expected: `EXIT≠0`，tail 出现 `type '_Uint8ArrayView' is not a subtype of type 'String' in type cast` 或 `_Uint8List` 相关 TypeError。

- [ ] **Step 3: 实现最小修复**

修改 `lib/features/media/data/scanning/media_thumbnail_generator.dart`：

顶部 import 增加一行：

```dart
import 'dart:convert';
```

把 `_getVideoDuration` 中 ffprobe 调用改为显式 `utf8`，并把 stdout 解析改为双类型兼容：

```dart
/// 通过 ffprobe 获取视频时长（秒）。
Future<double> _getVideoDuration(String filePath) async {
  final result = await _processRunner
      .run(
        'ffprobe',
        [
          '-v',
          'error',
          '-show_entries',
          'format=duration',
          '-of',
          'default=noprint_wrappers=1:nokey=1',
          filePath,
        ],
        // ffprobe 输出是 UTF-8 文本，与 ffmpeg 取帧（显式 stdoutEncoding: null 取原始字节）不同。
        stdoutEncoding: utf8,
      )
      .timeout(
        const Duration(seconds: ffmpegTimeoutSeconds),
        onTimeout: () => throw ThumbnailException('ffprobe 执行超时'),
      );

  if (result.exitCode != 0) {
    throw ThumbnailException('无法获取视频时长');
  }

  // ThumbnailProcessRunner 的实现可能忽略 stdoutEncoding 约定（脚本化 runner、
  // 或真实 Process.run 在部分环境返回字节），两种类型都要兼容。
  final output = switch (result.stdout) {
    String text => text,
    List<int> bytes => String.fromCharCodes(bytes),
    _ => '',
  }.trim();
  final duration = double.tryParse(output);
  if (duration == null || duration <= 0) {
    throw ThumbnailException('无法解析视频时长: $output');
  }

  return duration;
}
```

保留其余逻辑不变（`_generateVideoThumbnail` 的 ffmpeg 取帧调用继续显式 `stdoutEncoding: null`，已按 `List<int>` 处理）。

- [ ] **Step 4: 运行测试，确认通过（green）**

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/features/media/data/scanning/media_thumbnail_generator_test.dart 2>&1 | Out-File -Encoding utf8 logs/media-thumb-task1-green.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 150 logs/media-thumb-task1-green.log
```

Expected: `EXIT=0`。同时确认现有 `视频缩略图` 全部用例仍通过（现有用例的 durationResult 走 `String text` 分支，不受影响）。

- [ ] **Step 5: 格式化并提交**

```powershell
git diff --name-only -- '*.dart'
dart format lib/features/media/data/scanning/media_thumbnail_generator.dart test/features/media/data/scanning/media_thumbnail_generator_test.dart
git add lib/features/media/data/scanning/media_thumbnail_generator.dart test/features/media/data/scanning/media_thumbnail_generator_test.dart
dart format --output=none --set-exit-if-changed lib/features/media/data/scanning/media_thumbnail_generator.dart test/features/media/data/scanning/media_thumbnail_generator_test.dart
git commit -m "fix(media): 视频缩略图兼容 ffprobe 字节型 stdout" -m "DartThumbnailProcessRunner 的 stdoutEncoding 默认 null，真实 Process.run 返回字节，_getVideoDuration 的 as String 强转导致所有视频缩略图在时长探测一步崩溃。显式传 utf8 并兼容双类型解析。"
```

---

### Task 2: 图片缩略图生成移出主 isolate 并加并发门控

**Files:**
- Modify: `lib/features/media/data/scanning/media_thumbnail_generator.dart`
  - `_generateImageThumbnail`（当前第 61-77 行）：改用 `Isolate.run`
  - `generate()`（当前第 43-58 行）：在生成动作外包一层并发门控
  - 文件顶部 import 增加 `dart:async` 与 `dart:isolate`
  - 文件底部新增 `_ConcurrencyGate` 私有类
- Test: `test/features/media/data/scanning/media_thumbnail_generator_test.dart`
  - 在 `group('图片缩略图')` 内新增并发生成的行为契约用例

**Interfaces:**
- Consumes: Task 1 之后 `generate`/`_generateImageThumbnail` 的签名不变（`Future<List<int>> generate(String relativePath)`）。`_ScriptedProcessRunner`、`_generateImageBytes('png')` 辅助已有。
- Produces: `generate(String relativePath)` 对图片返回后台 isolate 生成的 JPEG 字节；同一时刻最多 `maxConcurrentThumbnails`（4）个缩略图生成在途，其余排队。对外行为契约不变：`ThumbnailException`（解码失败）、`FileSystemException`（文件不存在）语义保持。

- [ ] **Step 1: 新增并发生成的行为契约测试**

在 `test/features/media/data/scanning/media_thumbnail_generator_test.dart` 的 `group('图片缩略图')` 内新增：

```dart
test('并发生成多个图片缩略图全部成功（并发门控不丢失请求）', () async {
  for (var i = 0; i < 8; i++) {
    await File(
      '${tempDir.path}/img$i.png',
    ).writeAsBytes(_generateImageBytes('png'));
  }
  final results = await Future.wait(
    [for (var i = 0; i < 8; i++) generator.generate('/img$i.png')],
  );
  for (final r in results) {
    expect(r, isNotEmpty);
    expect(r[0], 0xFF);
    expect(r[1], 0xD8);
  }
});
```

说明：这是行为契约测试（8 个不同文件并发生成，全部返回有效 JPEG，门控不得丢请求/死锁），不是 timing 断言。实现前（同步解码）它也能通过，故本任务验证方式是「该测试 + 现有图片用例全部通过」，性能收益用 Step 4 的时序脚本人工确认。

- [ ] **Step 2: 运行新增测试（实现前基线）**

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/features/media/data/scanning/media_thumbnail_generator_test.dart --plain-name "并发" 2>&1 | Out-File -Encoding utf8 logs/media-thumb-task2-baseline.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 150 logs/media-thumb-task2-baseline.log
```

Expected: `EXIT=0`（同步实现下 2×2 小图解码很快）。此步骤建立基线，证明用例可运行、逻辑正确。

- [ ] **Step 3: 实现修复——`Isolate.run` + 并发门控**

修改 `lib/features/media/data/scanning/media_thumbnail_generator.dart`：

顶部 import 增加两行（`dart:convert` 已在 Task 1 加入，勿重复）：

```dart
import 'dart:async';
import 'dart:isolate';
```

类内增加门控常量与实例：

```dart
/// 同时生成的缩略图上限：网格一次可见的 tile 会并发触发生成，
/// 不设限会同时读取/解码大量原图，打满磁盘 IO 与内存。
static const int maxConcurrentThumbnails = 4;

final _ConcurrencyGate _gate = _ConcurrencyGate(maxConcurrentThumbnails);
```

把 `generate` 的生成动作包进门控（`resolvePath` / `existsSync` 校验留在门控外，它们是轻量同步 IO）：

```dart
Future<List<int>> generate(String relativePath) async {
  final resolvedPath = _scanner.resolvePath(relativePath);
  final file = File(resolvedPath);
  if (!file.existsSync()) {
    throw FileSystemException('文件不存在', resolvedPath);
  }
  return _gate.run(() async {
    final ext = extensionFromFileName(relativePath);
    if (isImageFile(relativePath)) {
      return _generateImageThumbnail(resolvedPath);
    } else if (isVideoFile(relativePath)) {
      return _generateVideoThumbnail(resolvedPath);
    } else {
      throw ThumbnailException('不支持的文件类型: $ext');
    }
  });
}
```

把 `_generateImageThumbnail` 改为后台 isolate 执行：

```dart
/// 图片缩略图：读取 → 解码 → 缩放 → 编码 JPEG，整体在后台 isolate 执行。
///
/// package:image 的解码/缩放/编码都是同步 CPU 密集操作，直接在主 isolate 跑会在
/// 图片多的文件夹一次加载网格时把事件循环阻塞数百毫秒到数秒，拖垮依赖主事件循环
/// 的视频播放与 UI。Isolate.run 只传入路径字符串、只传回 JPEG 字节，均是可发送类型。
Future<List<int>> _generateImageThumbnail(String resolvedPath) {
  return Isolate.run<List<int>>(() {
    final bytes = File(resolvedPath).readAsBytesSync();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw ThumbnailException('无法解码图片: $resolvedPath');
    }

    // 缩放，保持宽高比，最长边 ≤ thumbnailMaxSize
    final resized = img.copyResize(
      decoded,
      width: thumbnailMaxSize,
      height: thumbnailMaxSize,
      maintainAspect: true,
    );

    return img.encodeJpg(resized, quality: jpegQuality);
  });
}
```

文件底部（`ThumbnailException` 之前）新增并发门控：

```dart
/// 限制缩略图生成并发数量的 FIFO 门控。
///
/// 超出上限的请求排队等待，不丢失；门控只控制「同时进行中的生成」数量，
/// 不引入额外延迟（空转时直接放行）。
final class _ConcurrencyGate {
  _ConcurrencyGate(this._limit);

  final int _limit;
  int _active = 0;
  final List<Completer<void>> _waiters = [];

  Future<T> run<T>(Future<T> Function() action) async {
    await _acquire();
    try {
      return await action();
    } finally {
      _release();
    }
  }

  Future<void> _acquire() async {
    if (_active < _limit) {
      _active++;
      return;
    }
    final completer = Completer<void>();
    _waiters.add(completer);
    await completer.future;
  }

  void _release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeAt(0).complete();
    } else {
      _active--;
    }
  }
}
```

- [ ] **Step 4: 验证**

先跑新增并发用例 + 图片/视频全部用例：

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/features/media/data/scanning/media_thumbnail_generator_test.dart 2>&1 | Out-File -Encoding utf8 logs/media-thumb-task2-green.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 150 logs/media-thumb-task2-green.log
```

Expected: `EXIT=0`，包含新增并发用例与 Task 1 的字节型 stdout 用例。

再人工确认主 isolate 不再被图片解码阻塞（性能收益证据，不作为自动化断言）：临时写 `tool/debug_thumb_isolate.dart`，在主 isolate 用 `Timer.periodic` 打点，同时并发生成 12 张大图缩略图，对比修复前（同步：打点停顿近 6 秒）与修复后（Isolate.run：打点连续，无停顿）。确认后删除该临时脚本。

- [ ] **Step 5: 全量回归**

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter analyze 2>&1 | Out-File -Encoding utf8 logs/media-thumb-task2-analyze.log; Write-Host "ANALYZE_EXIT=$LASTEXITCODE"; Get-Content -Tail 60 logs/media-thumb-task2-analyze.log
```

Expected: 无 error（若存在既有 warning 需说明与本次改动无关）。

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test --reporter compact 2>&1 | Out-File -Encoding utf8 logs/fltest.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 150 logs/fltest.log
```

Expected: `EXIT=0`，全量测试通过。

- [ ] **Step 6: 格式化并提交**

```powershell
git diff --name-only -- '*.dart'
dart format lib/features/media/data/scanning/media_thumbnail_generator.dart test/features/media/data/scanning/media_thumbnail_generator_test.dart
git add lib/features/media/data/scanning/media_thumbnail_generator.dart test/features/media/data/scanning/media_thumbnail_generator_test.dart
dart format --output=none --set-exit-if-changed lib/features/media/data/scanning/media_thumbnail_generator.dart test/features/media/data/scanning/media_thumbnail_generator_test.dart
git commit -m "fix(media): 图片缩略图生成移出主 isolate 并限流" -m "package:image 解码/缩放/编码为同步 CPU 密集操作，图片多时主 isolate 被连续占满导致视频播放与 UI 卡顿。改用 Isolate.run 后台执行，并在 generate 入口加并发门控限制同时生成的缩略图数量。"
```
