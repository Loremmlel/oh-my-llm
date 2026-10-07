# 长文本输入组件调研与实测

日期：2026-10-06。范围：聊天、设置中的各类提示词，以及 Agent 文档等所有可能编辑长文本的字段。

## 结论

用户录屏中的主要卡顿已在独立原生输入框中复现并定位：原文的 CRLF 换行触发昂贵的原生段落布局。12,502 字符原文含 427 个 CRLF；仅在诊断副本中将其统一为 LF，原生字符输入对应 UI 帧中位耗时从 172.257ms 降至 9.274ms。CPU 采样约 93.8% 经由 `_NativeParagraph._layout`。应优先处理编辑边界的换行规范，再决定是否需要替换编辑器；不是所有大文本卡顿都能据此归因于 CRLF。

`re_editor 0.10.0` 在早期合成文本对照中显著降低 UI 工作量，但不再作为本次录屏问题的首选修复方向，当前也不能直接全局替换 `TextField`。

- 144 个场景、2880 次计时编辑全部完成；无 Flutter 运行错误、无正文校验失败、无缺失帧，每次计时恰好关联一帧。
- 72 组相同条件的插入／删除比较中，候选组件的 UI 工作量 P95 均低于原生输入框；本次最小改善约 2.01 倍。该结果只代表本机合成负载，不是通用性能保证。
- 候选组件的默认混合换行保真和可编辑文本 Semantics 两项兼容性门禁失败，必须先处理。
- 早期合成正文只有 LF 或没有硬换行，因此没有覆盖原文 CRLF 的主要触发条件；这解释了当时未能复现用户描述的卡顿。
- 调研后已接入共享换行处理，业务修复提交为 `9bac1b9`，位于 `fix/long-text-crlf-input`；没有新增应用依赖或迁移数据库。

## 实测环境与方法

Windows 11 专业版 10.0.26300；AMD Ryzen 7 5800H；系统枚举 GPU 为 NVIDIA GeForce RTX 3060 Laptop GPU（未单独确认 Flutter 实际选择的图形适配器）。Flutter 3.47.5 stable，Dart 3.13.4，原生 Windows profile 构建。没有以 debug/widget test 的耗时代替性能结果。

根因定位时确认正在运行的正式应用是 `artifacts/windows/oh_my_llm-windows-latest/oh_my_llm.exe`，版本 4.3.1+0；其 `flutter_windows.dll` 与当前 SDK 的 release 引擎 SHA256 相同，均为 `8BD7B61EEE31AA436EDB182DB41624D1CD3B2688A7E03622320DBEAE067B5251`。

两组件均使用项目内的 Noto Sans SC 字体，字号 16、行高 1.5，宽 720／360、高 320 逻辑像素，自动换行。正文长度为 5000／10000／50000 UTF-16 单元；此处不含代理对，混合中文、ASCII 和标点，不能理解成纯汉字数量。

字体以工程内资产打包，通过 FontLoader 在启动前显式加载，成功读入 17,772,300 字节；打包文件与仓库字体 SHA256 一致，均为 `A3041811A78C361B1DE50F953C805E0244951C21C5BD412F7232EF0D899AF0DA`。

文本分两类：约 174 字符一段，以及整篇没有硬换行。操作包含中间插入、末尾插入和中间插入 4096 字符，每次随后删除对应内容。每场景先预热 6 次，再计时 20 次；两轮反转编辑器顺序，每个条件累计 20 次插入和 20 次删除。

关闭候选语法高亮、折叠分析和符号补全；长行渲染上限设为 1000000，高于全部样本，未以截断内容换速度。全文相等检查在每次操作后执行。基准独立于应用业务，没有模板编译或草稿监听。

主指标为同步控制器更新与对应帧 UI build 时长之和；后者包括构建、布局和绘制准备。光栅化单列。这个指标不是从物理按键到屏幕出现字符的端到端延迟。选择映射、校验和写盘在计时窗口外。

## 性能结果

下表为宽 720 时中间插入一个字的 UI 工作量，单位毫秒；P50/P95 来自两轮合并的 20 个插入样本。

| 长度 | 形态 | TextField P50 | re_editor P50 | TextField P95 | re_editor P95 |
|---|---|---:|---:|---:|---:|
| 5000 | 分段 | 1.72 | 0.47 | 1.87 | 0.55 |
| 5000 | 单段 | 1.98 | 0.77 | 3.92 | 0.87 |
| 10000 | 分段 | 2.85 | 0.52 | 7.20 | 0.64 |
| 10000 | 单段 | 3.04 | 1.15 | 7.27 | 1.21 |
| 50000 | 分段 | 13.31 | 1.03 | 33.52 | 1.18 |
| 50000 | 单段 | 15.37 | 3.53 | 34.29 | 3.84 |

宽 360 的相同操作：50000 字符分段时 P95 为 15.79 → 1.16ms，单段为 14.99 → 4.70ms。两种宽度均在 Windows 测得，窄窗口不等于 Android 性能。

50000 字符、宽 720 的其他插入操作：

| 形态 | 操作 | TextField P95 | re_editor P95 |
|---|---|---:|---:|
| 分段 | 末尾插入一字 | 13.22 | 0.56 |
| 单段 | 末尾插入一字 | 13.56 | 3.71 |
| 分段 | 中间插入 4096 字符 | 14.75 | 0.65 |
| 单段 | 中间插入 4096 字符 | 14.85 | 2.26 |

批量操作通过控制器插入，不含剪贴板读取；插入内容本身有换行，可能拆开原来的长段，因此不可直接与单字插入推导线性关系。全部 72 组条件中候选 UI P95 最大为 4.707ms。

原生 50000 字符中间插入的 P95 明显高于中位数，存在尾部抖动。样本规模较小，不将 P95 倍数宣传成长期稳定加速比。主要结论是候选在分段和不分段长文中都有改善，而不只是短行代码场景。

## 兼容性门禁

测试位于 `tool/long_text_benchmark/test/editor_contract_test.dart`；最终 6 项中 4 项通过、2 项失败。失败为候选适配前的真实差异，未修改断言来掩盖。

| 项目 | 结果 | 含义 |
|---|---|---|
| 长文跨行替换、撤销、重做 | 通过 | 本次控制器操作能还原全文 |
| 表情、组合字符退格 | 通过 | 覆盖 🙂、e + 组合重音、👩‍💻 |
| 拼音组合后提交中文 | 通过 | 模拟 Windows 平台增量输入；不是物理 IME 验收 |
| 原生 TextField 可编辑文本语义 | 通过 | 为语义测试提供阳性对照 |
| 候选默认混合换行原样保留 | 失败 | `甲\r\n乙\n丙\r\n` 读回为 `甲\n乙\n丙\n` |
| 候选可编辑文本语义 | 失败 | 未找到同时包含 text-field 标记与全文值的 Semantics 节点 |

`CodeLineOptions` 可选择统一 LF 或 CRLF，但不等价于原样保留混合换行。后续适配需要明确全文保存契约，不能无声改变已有 Prompt 字符串。

无障碍问题不能仅加一个读出正文的标签就视为解决；仍需覆盖焦点、编辑动作、选择和文本更新。当前测试只证明最基础的文本字段语义已经不等价，没有完成 Narrator/TalkBack 验收。

源码审查还确认候选向系统输入法同步当前行而非完整文档，并启用 delta model。这解释了部分性能优势，也带来第三方输入法整篇全选／跳转的兼容边界；上游存在对应移动端报告。不能把模拟组合输入通过推广到所有输入法。

## 采用建议

### 实际应用录屏补充

用户随后提供 `E:\BrowserDownload\视频\2026-10-06 21-56-15.mp4`，报告正文约一万字、实际输入明显卡顿。该长度来自用户估计，未从录屏推算全文字数。

已读取录屏元数据并检查全程采样帧及输入片段的密集帧序列：视频长 11.866667 秒，1280×720，30fps；容器报告 356 帧，本次实际解码取得 355 帧。入口为“编辑固定顺序提示词”的步骤正文；操作包括拼音组字、提交中文、英文输入和换行后的内容滚动。此处不是聊天页，也没有模板实时编译；对应正文是 `fixed_prompt_sequence_form_dialog.dart` 中未挂 `onChanged` 的普通 `TextField`，左侧列表只监听步骤标题控制器。

录屏本身上限为 30fps，且没有按键时间戳或 Flutter timeline，不能由重复画面推断应用的实际 FPS、输入延迟或丢帧数。用户的实际操作反馈仍是需要复现的问题，不能用本轮独立基准中的毫秒数否定。

进一步检查逐帧时间戳与正文区域的像素变化：

- 相邻录制帧时间戳间隔为 33.333～33.334ms，没有录制时间戳缺口；这是视频输出节奏，不是应用渲染耗时，也不能排除 OBS 重复采样。
- 换行后的正文滚动在 5.800000、5.833333、5.866667 秒三个相邻帧中分别向上移动约 1、19、7 像素，累计约 27 像素。这三个变化帧之间没有重复画面，但采样精度不足以判断 60Hz 下是否漏帧。
- 本机 SDK 的 `EditableText` 将光标跟随滚动设为 100ms、`Curves.fastOutSlowIn`。30fps 对这段动画通常只能采到约三个变化阶段，位移不均匀本身不能作为卡顿证据。
- 中文组字阶段的可见文字更新间隔约 167～367ms，英文阶段约 167～400ms。缺少按键／平台输入事件时间，不能区分自然输入间隔与输入处理延迟；不能把这些间隔换算成应用 FPS。静止阶段约半秒一次的小面积变化主要对应光标闪烁。

逐帧分析脚本及结果为 `logs/video-input-review/analyze_frames.py`、`frame-analysis.json`、`frame-analysis.log`，换行片段连续帧为 `scroll-frames.png`。分析使用正文区域像素差与垂直对齐，不依赖未录入的输入法候选窗口。

现有基准直接写入 controller，每次操作等待下一帧，将选区准备放在计时外；它没有覆盖真实输入法事件节奏、composing 区间的连续变化、平台输入入口及完整的光标自动滚动过程。因此“组件对比性能改善”成立，不等于“现有应用一万字输入达到 60fps”，也尚未证明替换后实际问题消失。

源码进一步确认这个覆盖差异：`EditableTextState.updateEditingValue` 在平台文字变化后调用 `_scheduleShowCaretOnScreen(withAnimation: true)`，并明确说明程序修改不会触发同样的光标滚动。该差异是后续测量重点，尚未证实为实际卡顿根因。

后续真实场景验收应以这个固定顺序提示词对话框为复现入口：保留原文和实际约束，采集 profile 的连续 UI/raster 帧及输入事件时间，覆盖中文 composing/commit、英文输入、换行和 caret 自动滚动。分别定位 `EditableText.updateEditingValue`、文本布局和滚动阶段；再在同场景下验证候选组件，避免用直接设置 controller 的结果替代真实输入链路。

录屏元数据及抽帧产物仅保存在 ignored 的 `logs/video-input-review/`，没有将用户 Prompt 正文写入报告或上传外部服务。

### 60fps 录屏中的输入显示滞后

后续有效录屏为 `E:\BrowserDownload\视频\2026-10-06 22-08-10.mp4`，1280×720、60fps、24.016667 秒，同时包含应用和输入法候选窗。中间的 `22-06-19.mp4` 捕获的是其他显示器上的浏览器，不用于应用分析。

本次实际解码 1439 帧，相邻时间戳间隔 16.666～16.667ms。逐帧对齐候选内容与框内 composing 文本，发现多次候选已经反映新输入，但框内仍保留之前的拼音：

| 候选变化时间 | 框内对应变化时间 | 录屏中的相对显示差 | 对应现象 |
|---|---|---|---|
| 4.333333 秒 | 4.500000 秒 | 约 167ms / 10 帧 | 首个 `l` 的候选已出现，框内稍后出现 `l` |
| 5.950000 秒 | 6.116667 秒 | 约 167ms / 10 帧 | 首个 `h` 的候选已出现，框内稍后出现 `h` |
| 9.700000 秒 | 9.850000 秒 | 150ms / 9 帧 | 候选首项变成“云”，框内从 `yu` 变为 `yun` |
| 10.200000 秒 | 10.366667 秒 | 约 167ms / 10 帧 | 候选反映后续音节，框内稍后从 `yun` 变为 `yun'y` |

这是不同 UI 对同一组输入的可见状态差，比单纯的逐字出现间隔更能支持输入显示滞后。它不是物理按键到显示的精确延迟，也不能仅凭视频区分平台输入处理、Dart UI 线程、布局、呈现或捕获路径各自的贡献。当前不能将其解释为应用仅有 6fps，更不能据此断言某个函数阻塞了 167ms。

另一个可复核现象是候选窗在组字开始时先出现在屏幕顶部，随后在框内拼音出现的同一帧移到编辑框附近。这为 IME 光标位置同步提供了调查线索，但尚未证明位置异常与文字延迟同源。

两次换行滚动分别在 8.733333～8.800000 秒和 12.216667～12.283333 秒连续五个录制帧发生位移，变化帧之间未出现重复画面；与 SDK 的短时非匀速动画相容，未观察到动画中途长时间冻结。该结果只覆盖这两个片段，不是整体 60fps 验收。

本轮优先诊断方向改为真实 IME 事件到 composing 文本显示的链路，同时记录候选位置同步；保留全文布局和 caret 滚动指标，避免只用直接写 controller 的基准代替。应将短文本与原长文本、中文 composing 与英文直接输入放在同一实际应用/profile 环境中对照。

本地证据位于 ignored 的 `logs/video-input-review-3/`：`analysis.json` 和 `analysis.log` 为像素变化时序，`ime-start.png`、`ime-restart.png`、`ime-pause.png` 为带时间戳的候选／输入行连续帧，`scroll-1.png`、`scroll-2.png` 为两段滚动连续帧。该录屏分析阶段没有修改正式应用。

### 原文对照与 CPU 定位

从应用数据库只读提取录屏对应正文到 ignored 的诊断目录，未修改数据库。原文 12,502 字符、429 行，其中 CR 427 个、LF 428 个；没有代理对。对照文本仅执行 `CRLF → LF`，变为 12,075 字符，保留相同的 429 行及其他全部字符。

`input_probe.dart` 使用同一 Noto Sans SC 字体、16px、680×270 逻辑像素的普通 `TextField`。每条路径连续输入 12 次，前两次预热，后十次记录；四条路径都逐次核对结果字符串。框架路径直接调用 `EditableTextState.updateEditingValue`；原生路径通过独立 runner 将 `WM_CHAR` 发给自己的 Flutter 子窗口，经过 Windows embedder 和平台通道，但不等同于真实 IME。

下表为对应 UI 帧耗时，中位数／最大值，单位 ms。这里的 UI 帧包含构建、布局和绘制准备，不是屏幕呈现时间。

| 路径 | 原始 CRLF 正文 | 仅统一为 LF |
|---|---:|---:|
| controller 替换 | 184.100 / 196.156 | 8.902 / 9.691 |
| 框架平台入口，普通字符 | 175.113 / 183.316 | 8.499 / 9.229 |
| 框架平台入口，composing | 172.006 / 174.583 | 9.406 / 10.665 |
| Windows WM_CHAR | 172.257 / 173.769 | 9.274 / 9.564 |

原文的 native-char 分发总耗时最大约 1.2ms，主要开销在之后的 UI 帧。相同问题在 controller、框架平台入口、Windows 字符入口均复现，说明真实 IME 不是复现慢布局的必要条件。录屏中的候选位置更新滞后与 UI 被长布局占用相容，但没有单独证明全部候选位置异常均由此引起。

再次使用原始 CRLF 文本开启 CPU profiler，四条路径的 UI 帧中位数约 189～192ms，采样开销使绝对数值略有上升，故不把这轮用于无 profiler 的速度比。8622 个 CPU 样本中，8084 个经过 `_NativeParagraph._layout`（93.8%），调用链为 `RenderEditable.performLayout → TextPainter.layout → _NativeParagraph.layout/_layout`。这定位到 Flutter 原生段落布局边界；尚未对引擎的 C++ 函数做符号级采样，不能进一步断言某个 Skia 字体回退函数是根因。

证据：`logs/input-probe-exact-cpu.json`（该次尝试采样时 profiler 未启用，但帧计时有效）、`logs/input-probe-lf.json`、`logs/input-probe-profiled.json` 与其 `.cpu.json`。有效三轮均无输入校验错误、每条路径十个计时样本。首次提取使用 Windows 文本模式，意外扩展了 CRLF，`input-probe-actual.json` 不作为原文证据；后来改为原始 UTF-8 字节写入，核对长度 12,502 后重新完成全部原文与 LF 对照。旧二进制误启动的 `input-probe-results.json` 同样无效。

该定位阶段建议在共享长文本编辑边界处理 CRLF，随后按下面的方案接入应用。没有自动清洗用户数据库；实际系统输入法的手工回归仍需执行。

## 应用修复

共享 `LongTextEditingController` 位于 `lib/core/widgets/long_text_editing_controller.dart`，加载、粘贴及程序赋值将 CRLF／单独 CR 转为 LF。选区按删除的 CR 数量映射 UTF-16 偏移，保留反向选择和亲和性。活跃 composing 区域不被改写，提交后再归一化。

控制器保留原文基线：未修改或撤销回原文时，`textForSave()` 返回原始字符串；实际修改后保存 LF。表单原有 trim 策略仅作用于修改后的正文。`loadText()` 用于切换文档／恢复草稿，普通赋值属于编辑。数据库与导出协议不变，没有启动批量清洗。

覆盖聊天正文、模板变量、预设／模板／固定顺序／记忆提示词，以及 Agent 的任务、文档、摘要、配置提示词。Agent 状态回写按归一化文本比较，避免输入法组字期间的原始 CRLF 被草稿回写打断。正则表达式模式字段保留原有行为，因为实际 CR 可能参与匹配语义。

新增回归覆盖混合换行、emoji UTF-16 偏移、反向选择、平台 composing/commit、撤销重做、四类生产提示词表单的保存／取消、聊天草稿切换、Agent 文档未修改取消及任务组字回写。生产表单性能入口为 `tool/long_text_form_profile.dart`，直接复用固定顺序提示词对话框与应用主题，不连接用户数据库。

### 生产表单 profile 结果

执行 `./tool/run_long_text_form_profile.ps1 -Fixture logs/input-probe-private-fixture.txt`，Windows profile 构建成功、运行退出码 0。同一份 12,502 字符／427 个 CR 的原文由生产控制器加载，实际输入区为 660×269 逻辑像素。每条路径排除 2 次预热，保留 20 次追加输入。结果文件 `logs/long-text-form-profile.json` 无运行错误，40 个样本各关联一帧，原文基线、编辑正文和光标校验全部通过。

| 生产表单输入路径 | UI 中位数 | UI P95 | UI 最大值 | raster 最大值 |
|---|---:|---:|---:|---:|
| 普通字符 | 10.142ms | 11.721ms | 11.978ms | 2.399ms |
| composing | 9.974ms | 14.147ms | 14.512ms | 3.555ms |

P95 使用每组 20 个样本的第 19 个有序值。表中为合并主干弹窗修复后的复测；此前一次中位数为 9.017／8.833ms，原始记录另存 `logs/long-text-form-profile-before-dialog-merge.json`。相比之前原始 CRLF 独立输入框约 172ms 的慢布局，生产表单接入后回到约 10ms 的量级；两个实验的字体样式与几何约束不完全相同，因此不将这两组数字作为严格同场景加速比。此次测量走框架平台输入入口，包含实际表单布局，但没有真实系统 IME／物理键盘，也不是端到端显示延迟或持续 60fps 保证。Android 真机尚未验证。

### 应用回归验证

- `flutter test --reporter compact`：合并最新主干弹窗修复后，2012 项全部通过，131 秒，完整日志 `logs/fltest.log`。进程硬超时设为 240 秒，未触发。
- `flutter test test/features/agent/presentation/agent_screen_test.dart --reporter compact`：7 项通过，含 CRLF 草稿组字回写保护；硬超时 60 秒，未触发。
- 修改／新增的 17 个应用及测试、生产表单探针 Dart 文件通过 `dart format --output=none --set-exit-if-changed`。
- `git diff --check`：通过。
- `flutter analyze`：通过，无问题；合并主干后再次检查为 16.3 秒，日志 `logs/long-text-analyze.log`。
- 独立研究包 `run.ps1 -Stage analyze -TimeoutMs 120000`：通过，无问题，6.9 秒，日志 `logs/long-text-benchmark-analyze.log`。根应用排除该独立包，避免 CI 在未还原其单独依赖时误分析。
- `dart run tool/check_import_boundaries.dart`：检查 439 个文件，0 条违规，日志 `logs/long-text-boundaries.log`。
- Windows 生产表单 profile 构建与 40 次计时通过；没有替换正在运行的 Release 安装包，没有执行 Android 真机验收。

## CRLF 高开销的引擎机制

### 锁定源码与关键分支

本机 Flutter 3.47.5 的 engine revision 为 `af7e796e161ae0bb1ff0758c71a7105418bd9ded`，其 [DEPS](https://github.com/flutter/flutter/blob/af7e796e161ae0bb1ff0758c71a7105418bd9ded/DEPS#L19) 锁定 Skia `8df24be66531469e576a806749a0202ae26b8d08`。以下分析针对该提交，不以最新主干代替运行版本。

1. [Unicode UAX #29，GB3](https://www.unicode.org/reports/tr29/#GB3) 规定 CR 与紧随其后的 LF 之间不分字素簇。CRLF 因此是一个包含两个码点的簇；LFCR、CR 加空格再 LF 则没有这个组合关系。这个标准规则本身不要求昂贵运算。
2. 应用 Noto Sans SC 的 Unicode cmap 没有 U+000D／U+000A 映射。控制字符没有可见字形是正常的，不能据此认定字体损坏。Skia [sortOutGlyphs](https://github.com/google/skia/blob/8df24be66531469e576a806749a0202ae26b8d08/modules/skparagraph/src/OneLineShaper.cpp#L313) 在遇到新字素簇时用 `glyph != 0 || isControl8` 判断已解决；同一簇的后续 glyph 却走 `else if (glyph == 0)`，没有重复控制字符豁免。
3. 所以 CR 位于簇首时被豁免，后续缺字 LF 又把整个簇标成未解决；单独 LF 位于簇首时不会触发该分支。随后 [clusteredText](https://github.com/google/skia/blob/8df24be66531469e576a806749a0202ae26b8d08/modules/skparagraph/src/OneLineShaper.cpp#L744) 扩展到整个字素簇边界，进入 [matchResolvedFonts](https://github.com/google/skia/blob/8df24be66531469e576a806749a0202ae26b8d08/modules/skparagraph/src/OneLineShaper.cpp#L424) 的缺字回退流程。
4. 放大因素在回退循环：外层逐个处理未解决片段，尝试字体的 visitor 又 [遍历当时所有未解决片段并重新 shape](https://github.com/google/skia/blob/8df24be66531469e576a806749a0202ae26b8d08/modules/skparagraph/src/OneLineShaper.cpp#L681)。已尝试字体集合属于当前片段，无法直接阻止其他片段再次尝试相同字体；回退字体缓存也不等于缓存“这个簇已经确定无法解决”。数百个 CRLF 会放大这些重复工作。

Windows 的 [FontCollection::defaultFallback](https://github.com/google/skia/blob/8df24be66531469e576a806749a0202ae26b8d08/modules/skparagraph/src/FontCollection.cpp#L202) 最终可以进入系统字体匹配；但目前没有 C++ 符号级计数，不能把额外耗时全部归给 DirectWrite 的某一次调用，也不能断言每次输入恰好发生多少次系统字体搜索。已有证据支持的具体缺陷是控制字符豁免在 CRLF 簇后续 glyph 上失效，继而进入反复字体回退／重塑形的慢路径。

### 可证伪的干预实验

新增 `crlf_mechanism_probe.dart`：直接计时 `dart:ui Paragraph.layout`，剥离 TextField、输入法、业务监听、绘制与视频捕获。Windows profile，16px，宽 680；每个条件两轮、第二轮反转顺序，每轮 2 次预热后记录 5 次，共 20 个条件／200 个有效样本。每次添加不同短后缀，避免整段缓存命中；后缀构造和行度量读取不在计时窗口内。结果为 `logs/crlf-mechanism.json`，`complete=true`，各条件均 10 个样本。

首先保持 427 行合成正文相同，仅替换行间字符：

| 行间字符 | layout 中位数 | 排除的解释 |
|---|---:|---|
| LF | 8.665ms | 基线 |
| CRLF | 249.009ms | 可在纯段落中复现 |
| LFCR | 9.104ms | 同样多一个 CR、字符数相同，也可很快 |
| CR + 空格 + LF | 8.947ms | 保留全部 CR/LF、字符更多，打断组合后恢复 |
| 两个 LF | 8.818ms | 行数从 428 增至 855，仍然很快 |

再保持用户原文的全部 CRLF 不变，使用四份仅供实验的字体副本。`make_control_fonts.py` 用 fontTools 4.60.1 将指定控制码点映射到已有空格 glyph；核对 `glyf/hmtx/hhea/fvar/gvar` 表未改变，应用正式字体 SHA256 保持 `A3041811A78C361B1DE50F953C805E0244951C21C5BD412F7232EF0D899AF0DA`。

| 字体副本 cmap 干预 | 原文 CRLF layout 中位数 | 原文转 LF 中位数 |
|---|---:|---:|
| 无（原字体） | 187.610ms | 6.370ms |
| 只补 CR | 191.815ms | 6.360ms |
| 只补 LF | 6.402ms | 5.848ms |
| CR、LF 都补 | 6.218ms | 5.947ms |

这些原文条件排版后均为 543 行。**只补 LF 有效、只补 CR 无效**与上述分支对“簇首／后续 glyph”的不对称处理一致，能区分它与“CR 本身处理慢”“文本多了几个字符”“双换行多排一遍”等解释。诊断字体不是发布方案，也没有写入应用 assets 或安装到系统。

固定 427 行合成正文，只把前 N 个 LF 改成 CRLF：N 为 1／10／50／100／200／427 时，中位数分别为 8.820／9.638／13.770／24.763／65.891／249.009ms。明显超线性的增长与重复处理未解决片段的源码结构相容；没有底层计数，不把它写成已证明的精确 O(N²) 次数公式。

结果文件 SHA256：`36A39F7D42FB44CCB3B203932598379694CE4E6689612B4835DE64DCF60EDD8D`。复现步骤见工具 README。用户原文、诊断字体、上游源码下载和逐次计时保留在 ignored 的 logs 下；报告只记录统计和源码链接。

### 上游历史与结论边界

Skia 在 2021-02-26 已有 [Treat control codepoints as resolved](https://github.com/google/skia/commit/b7b9a2328102873c44bd94022b2752e9ed46304b) 提交，关联旧 bug 11370／11380，说明控制字符缺字豁免有明确历史背景。但本次无法读取这两个旧 issue 正文，不能称它们已经定位或修复了当前 CRLF 性能问题；检索也没有找到可核验的一一对应修复结论。

源码与定向干预对机制的支持已明显强于之前仅到 `_NativeParagraph._layout` 的 CPU 采样。尚未做的是：带 C++ 符号的逐函数耗时、上游引擎补丁前后 A/B，以及其他系统与字体的完整矩阵。因此 PR 使用“源码与干预实验支持的机制定位”，不宣称已在上游确认或修复。应用继续采用 LF 编辑边界方案，不引入修改字体、私有引擎或替换输入组件。

### 候选编辑器的后续适配门禁

若换行处理后仍有超长文本需求，候选编辑器可以继续验证；其性能方向通过初步对照，通用替换门禁未通过。采用前需要验证：

1. 先解决原文保真和可编辑语义；明确上下文菜单、选择、撤销、表单校验及焦点归属。
2. Windows 微软拼音与 Android 实际输入法分别测试组合输入、候选提交、跨行选择、全选、粘贴、撤销及软换行边界。
3. 接入真实草稿／模板监听后复测，避免逐键将所有行重新合成全文、回写 controller，抵消编辑器的局部更新优势。
4. 适配通过后，按长文本字段用途统一迁移，不在跨过某个字数时临时切换内核。

候选编辑器对照没有证明其业务接入后的最终速度、Android 性能、真实输入法延迟、冷启动成本或独立内存优势。JSON 的 RSS 是进程当时驻留内存，包含先前场景的分配，不作为组件内存对比。

## 复现与证据

- 复现命令和指标定义：`tool/long_text_benchmark/README.md`。
- 原始有效结果：`logs/long-text-results-noto.json`。
- 完整汇总：`logs/long-text-results-noto.csv`。
- profile 构建：`logs/long-text-build.log`，成功。
- 独立工程静态分析：调研阶段通过；该日志路径后被应用静态分析复用，当前 `logs/long-text-analyze.log` 对应正式应用。
- 兼容性测试：`logs/long-text-test.log`，4 通过／2 失败。
- 基准代码 SHA256：`252926D933DCECB433EA03171D9B319CA180B0C8B89E494226CA359031548CFB`。
- 原始结果 SHA256：`4869B04FA0D5BFB40763A0F52B49F374DC31AD75F0D324D02EEFF322C2AF3DCB`。
- CSV SHA256：`A7946A2B55D2635CECE0B2EBF663216794D2BE8BB7DDD720FFE94DB02E25037B`。

首次 GUI 启动未被正确同步等待，遗留实例造成重叠，该批数据全部作废。随后一次单实例运行发现外层相对字体路径未被正确打包，该批不能称为同字体测试，也从最终比较中排除。报告只使用显式加载字体后的 `long-text-results-noto` 完整单实例运行。启动器已增加同步等待、进程树硬超时和重复实例拒绝。

工具源码及锁文件可保留和重放；`logs/` 仍是 ignored 本地产物。早期候选编辑器兼容性门禁的失败不表示正式应用测试回归；应用修复的验证单独记录。

## 一手资料

- [Flutter 长文本输入性能问题 #114158](https://github.com/flutter/flutter/issues/114158)：重复 issue，关闭不表示已解决。
- [Flutter 性能分析指南](https://docs.flutter.dev/perf/ui-performance)：性能测试使用 profile 和实际运行环境。
- [re_editor 包及接口说明](https://pub.dev/packages/re_editor)：独立布局／绘制、自动换行、菜单 UI 需自行接入。
- [re_editor 源码](https://github.com/reqable/re-editor)：本轮以本机 Pub 缓存中的 0.10.0 发布包为审查对象，未修改第三方源码。
- [移动端整篇 IME 操作报告 #117](https://github.com/reqable/re-editor/issues/117)：当前行桥接与文档级选择的差异，属于上游报告，未在本轮 Android 真机复现。
