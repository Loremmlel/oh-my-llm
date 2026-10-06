# 长文本编辑器对照实验

用途：独立比较 Flutter `TextField` 与 `re_editor 0.10.0` 的长文本编辑成本，不修改正式应用依赖或页面。

## 运行

在仓库根目录使用 PowerShell 7；需要可构建 Windows 的 Flutter SDK。

```powershell
./tool/long_text_benchmark/run.ps1 -Stage create -TimeoutMs 60000
./tool/long_text_benchmark/run.ps1 -Stage restore -TimeoutMs 120000
./tool/long_text_benchmark/run.ps1 -Stage analyze -TimeoutMs 60000
./tool/long_text_benchmark/run.ps1 -Stage build -TimeoutMs 240000
./tool/long_text_benchmark/run.ps1 -Stage run -TimeoutMs 240000 -OutputName long-text-results-noto
./tool/long_text_benchmark/summarize.ps1 -InputPath logs/long-text-results-noto.json
./tool/long_text_benchmark/run.ps1 -Stage test -TimeoutMs 60000
```

生成工程位于 ignored 的 `logs/long-text-benchmark/`，日志和原始结果均位于仓库 `logs/`。`run.ps1` 同步等待子进程，并在超时后杀掉整棵子进程树。运行期间不要同时运行其他基准、测试或构建，也不要手动操作基准窗口。

兼容性测试是候选组件的调查门禁，允许暴露第三方实现不满足现有应用预期的事实；失败不能通过放宽断言伪装成已满足迁移要求。

## 矩阵

- Windows 原生 profile 构建，将 Noto Sans SC 复制进工程后通过 FontLoader 显式加载，记录字节数；字号 16、行高 1.5。
- 两种组件都自动换行、编辑区域高 320、宽 720 或 360 逻辑像素。
- 5000、10000、50000 个 UTF-16 单元，正文为中文、英文、数字和标点。基准正文没有代理对，字符数与 UTF-16 单元数一致。
- 两种形态：约 174 字符一段；全文没有硬换行。
- 三种操作：中间插入一个字、末尾插入一个字、中间批量插入 4096 字符；每次插入后在下一次操作中删除对应内容。
- 每场景 26 次编辑，前 6 次预热不计；20 次计时含 10 次插入和 10 次删除。
- 两轮反转编辑器顺序，总计 144 场景、2880 次计时编辑。
- 不启用语法高亮、折叠分析、业务监听；候选长行渲染阈值设为 1000000，高于所有样本，禁止以截断换速度。
- 每次编辑后核对完整字符串，每个场景记录初始和最终校验值。

## 指标与限制

- `updateUs`：控制器替换及同步通知耗时。
- `buildUs`：本次编辑对应 Flutter 帧的 UI 构建、布局、绘制准备耗时。
- `UiWorkUs`：以上两项之和，用于比较本次操作的 UI 工作量，不等同于端到端输入延迟。
- `rasterUs`：独立记录光栅线程耗时，不直接与 UI 耗时相加。
- `throughFrameUs`：从控制器替换开始到 `endOfFrame` 的墙钟耗时，含等待调度，不代表屏幕已经显示。
- 按 `Timeline.now` 与 `FrameTiming.buildStart` 的时间窗口关联帧；原始帧数据保留在 JSON，汇总必须检查无缺失帧。
- `rssBytes` 是进程当时驻留内存，含前面场景及两种编辑器的历史分配，不能当成组件独立内存比较或峰值。

自动化直接调用控制器，选择映射、全文一致性检查和结果写盘在计时窗口外。没有测物理键盘、真实 IME、剪贴板读取、撤销历史长期增长、冷启动时间、Android 真机，也没有加入应用现有草稿和模板业务。兼容性测试中的组合输入通过平台消息模拟，不能替代系统输入法验收。

报告保存在仓库 `docs/`。只有 `complete: true`、字体显式加载成功、144 场景完整、无运行错误、全文校验通过的单实例运行可用于正式比较。首次启动器未正确等待 GUI 程序导致过实例重叠，其数据已作废；随后发现外层相对字体路径未被正确打包，该批结果也不用于最终比较。

## 输入链路定位工具

`input_probe.dart` 是另一入口，比较 controller、框架输入入口、框架 composing 和 Windows `WM_CHAR` 四条路径。每条路径 12 次追加字符，前两次预热；默认使用 100、10000、50000 字符合成文本。可通过环境变量 `INPUT_PROBE_FIXTURE` 指定本地 UTF-8 原文文件，工具只读该文件；生成文件时必须保留原始换行字节，不能让 Windows 文本写入自动扩展 CRLF。

原生路径需要先在生成的独立工程安装 `input_probe.h`：复制到 `logs/long-text-benchmark/windows/runner/`，在 `flutter_window.cpp` include 此头文件，并在 `SetChildContent` 之后调用 `InstallInputProbe(flutter_controller_->engine()->messenger(), flutter_controller_->view()->GetNativeWindow());`。该 runner 的 CMake 在 `apply_standard_settings` 后增加 `target_compile_options(${BINARY_NAME} PRIVATE /utf-8)`。这些改动仅属于 ignored 的诊断工程。

```powershell
./tool/long_text_benchmark/run.ps1 -Stage build -Entry input_probe.dart -TimeoutMs 180000
$env:INPUT_PROBE_FIXTURE = 'E:\Code\oh-my-llm\logs\input-probe-private-fixture.txt'
./tool/long_text_benchmark/run.ps1 -Stage run -TimeoutMs 90000 -OutputName input-probe-exact
```

仅在构建成功后运行；失败后旧二进制仍可能存在。结果必须满足 `errors` 为空、每条路径十个样本且每个样本存在对应帧。设置 `INPUT_PROBE_CPU=1` 可额外启动独立进程的本机 VM service 并采集 CPU 栈；其结果保存在 `<结果文件>.cpu.json`，需确认 RPC 没有 error 且有有效样本。CPU 采样会影响绝对耗时，与未开启采样的数据分开解释。

此工具使用 680×270 编辑区和 16px 字号，没有设置第一套组件对照的 1.5 行高。`nativeHandlerUs` 测量 WM_CHAR 处理，不含真实 IME；`dispatchUs` 包含诊断调用往返；`throughFrameUs` 到 Flutter 帧结束，不等于屏幕呈现。用户正文只存于 ignored 的 `logs/`，不要提交或上传。

## 修复后的生产表单

在根应用包构建专用入口，复用固定顺序提示词的生产对话框、控制器和主题；不执行 bootstrap、不连接用户数据库，也不覆盖 `artifacts/` 发布产物。

```powershell
./tool/run_long_text_form_profile.ps1 -Fixture logs/input-probe-private-fixture.txt
```

脚本构建 `tool/long_text_form_profile.dart` 的 Windows profile 产物，仅在构建成功后启动。构建／运行分别有 300 秒／60 秒整树超时。结果位于 `logs/long-text-form-profile.json`，构建及运行日志前缀为 `long-text-form-`。

两条路径调用生产输入框的 `EditableTextState.updateEditingValue`，分别是普通字符和 composing；每条 22 次输入，前 2 次预热，保留 20 次。检查原文保留、LF 显示、全文与光标一致性。只有 errors 为空、40 个样本均关联到帧才视为完整结果。此测试覆盖实际表单的布局与监听，仍不等同于物理键盘、真实系统输入法或屏幕呈现延迟。

## CRLF 缺字机制实验

`crlf_mechanism_probe.dart` 直接测 `Paragraph.layout`。它组合不同换行排列与四份字体副本，验证“同一字素簇后续控制字符缺字”的源码推断。fontTools 只用于本地生成诊断字体，不是应用或独立 Dart 包的运行依赖；以下命令要求可用的 Python 3.10+。字体副本与用户正文全部留在 ignored 的 logs 下。

```powershell
New-Item -ItemType Directory -Force logs/crlf-engine | Out-Null
python -m pip install --target logs/crlf-engine/python-deps fonttools==4.60.1
$env:PYTHONPATH = (Resolve-Path logs/crlf-engine/python-deps).Path
python tool/long_text_benchmark/make_control_fonts.py assets/fonts/NotoSansSC-VF.ttf logs/crlf-engine/fonts
./tool/long_text_benchmark/run.ps1 -Stage build -Entry crlf_mechanism_probe.dart -TimeoutMs 180000
# 上一步成功后再运行；Fixture 可以是任意本地 UTF-8 CRLF 文本。
$env:CONTROL_FONT_DIR = (Resolve-Path logs/crlf-engine/fonts).Path
$env:INPUT_PROBE_FIXTURE = (Resolve-Path logs/input-probe-private-fixture.txt).Path
./tool/long_text_benchmark/run.ps1 -Stage run -TimeoutMs 90000 -OutputName crlf-mechanism
```

首次使用需先执行本文开头的 create／restore。运行得到 `logs/crlf-mechanism.json`；20 个条件各 10 个有效样本，两轮反转顺序，每轮排除前 2 次预热。追加唯一短后缀避免整段缓存命中；只计 layout 调用，builder、行度量读取和写盘不计时。检查 `complete=true`、200 个样本，以及同条件的行数是否一致。

字体脚本只改变 cmap，将指定 CR／LF 映射到既有空格 glyph，校验轮廓、度量、可变字体表和映射 glyph ID。不得把这些诊断副本替换到正式应用。机制实验不能替代 C++ 符号级计数，也不能把 layout 耗时当成屏幕呈现延迟。

独立包使用自身 `pubspec.lock` 与 package_config 验证，根应用 analyzer 明确排除此目录；应用没有新增 re_editor 依赖。当前启动器日志使用 `long-text-benchmark-<stage>.log` 前缀，避免覆盖应用静态分析及历史输入探针记录。
