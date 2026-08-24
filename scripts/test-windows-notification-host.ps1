# 构建并运行 windows_notification_host_test 原生测试（含 CMake configure
# 规则矩阵：竞态 delay 开关的拒绝规则）。任一步失败立即以非零退出码结束。
#
# 用法：
#   pwsh -NoProfile -ExecutionPolicy Bypass -File scripts\test-windows-notification-host.ps1
# 输出重定向示例（见 AGENTS.md）：
#   .\scripts\test-windows-notification-host.ps1 2>&1 |
#       Out-File -Encoding utf8 logs\windows-notification-host-native-green.log

param(
    # 证据日志目录；默认仓库根 logs\。
    [string]$LogDir = "",
    # 跳过 configure 矩阵（只构建并运行测试）。
    [switch]$SkipConfigureMatrix
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
if (-not $LogDir) { $LogDir = Join-Path $Root 'logs' }
New-Item -ItemType Directory -Force $LogDir | Out-Null

# 测试进程以 UTF-8 输出中文用例名；按 UTF-8 解码子进程输出。
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

# ── Visual Studio 生成器探测 ──────────────────────────────────────────
# cmake --help 只列出「支持的」生成器而非「已安装的」VS 实例；硬编码单一
# 版本会在只装了其他版本的机器上无法 configure。按 vswhere 探测结果从新到
# 旧降级选择，缺失 vswhere 时退化为安装目录探测。

function Select-CmakeVsGenerator {
    $MajorToGenerator = @{
        '18' = 'Visual Studio 18 2026'
        '17' = 'Visual Studio 17 2022'
        '16' = 'Visual Studio 16 2019'
    }
    $InstalledMajors = New-Object System.Collections.Generic.List[string]
    $VsWhere = Join-Path ${env:ProgramFiles(x86)} `
        'Microsoft Visual Studio\Installer\vswhere.exe'
    if (Test-Path $VsWhere) {
        # 仅认带 C++ 工具集的实例，避免选到纯 shell/Build Tools 缺件安装。
        & $VsWhere -latest -products * `
            -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
            -property installationVersion | ForEach-Object {
            if ($_ -match '^(\d+)\.') { $InstalledMajors.Add($Matches[1]) }
        }
    }
    if ($InstalledMajors.Count -eq 0) {
        foreach ($ProgramFilesRoot in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
            if (-not $ProgramFilesRoot) { continue }
            foreach ($Major in @('18', '17', '16')) {
                $VersionDir = Join-Path $ProgramFilesRoot "Microsoft Visual Studio\$Major"
                if ((Test-Path $VersionDir) -and -not $InstalledMajors.Contains($Major)) {
                    $InstalledMajors.Add($Major)
                }
            }
        }
    }
    foreach ($Major in @('18', '17', '16')) {
        if ($InstalledMajors.Contains($Major)) { return $MajorToGenerator[$Major] }
    }
    return $null
}

$DetectedGenerator = Select-CmakeVsGenerator
if (-not $DetectedGenerator) {
    Write-Host 'FAIL: 未检测到带 C++ 工具集的 Visual Studio 安装，无法确定 CMake 生成器'
    exit 1
}
Write-Host "使用 CMake 生成器：$DetectedGenerator"

# 与 flutter build windows 一致的生成器参数，保证矩阵与正式构建同构。
$GeneratorArgs = @('-G', $DetectedGenerator, '-A', 'x64')

# 构建目录若由其他生成器 configure 过，CMakeCache 会拒绝换生成器复用；
# 检测到不一致时清空该目录，让本次 configure 从干净状态开始。
function Assert-BuildDirMatchesGenerator([string]$BuildDir) {
    $Cache = Join-Path $BuildDir 'CMakeCache.txt'
    if (-not (Test-Path $Cache)) { return }
    $CachedLine = Select-String -Path $Cache `
        -Pattern '^CMAKE_GENERATOR:INTERNAL=(.+)$' | Select-Object -First 1
    if ($null -ne $CachedLine -and
        $CachedLine.Matches[0].Groups[1].Value -ne $DetectedGenerator) {
        Write-Host ("清理由 '{0}' configure 过的构建目录：{1}" -f `
            $CachedLine.Matches[0].Groups[1].Value, $BuildDir)
        Remove-Item -Recurse -Force $BuildDir
    }
}

function Invoke-CmakeLogged([string[]]$ArgumentList, [string]$LogName) {
    $Log = Join-Path $LogDir $LogName
    & cmake @ArgumentList 2>&1 | Out-File -Encoding utf8 $Log
    return $LASTEXITCODE
}

# ── configure 规则矩阵 ────────────────────────────────────────────────
# 规则：testing=OFF 时任何非零 delay 必须在 configure 阶段失败；testing=ON
# 时非零 delay 只允许出现在 Debug 配置的编译定义中（Release/Profile 为 0）。
if (-not $SkipConfigureMatrix) {
    Write-Host '== CMake configure 规则矩阵 =='

    # 1) testing=OFF + 非零 pre delay → 必须失败。
    $MatrixOffDir = Join-Path $Root 'build\windows\notification-host-matrix-off'
    Assert-BuildDirMatchesGenerator $MatrixOffDir
    $Exit = Invoke-CmakeLogged (@('-S', (Join-Path $Root 'windows'), '-B', $MatrixOffDir) +
        $GeneratorArgs + @(
            '-DOMLL_NOTIFICATION_HOST_TESTING=OFF',
            '-DOMLL_NOTIFICATION_PRE_COM_DELAY_MS=500')) 'cmake-matrix-off-delay.log'
    if ($Exit -eq 0) {
        Write-Host 'FAIL: testing=OFF + 非零 delay 未被 configure 拒绝'
        exit 1
    }
    Write-Host 'PASS: testing=OFF + 非零 delay 在 configure 阶段被拒绝'

    # 2)/3) testing=ON + 单一非零 delay → 允许，但定义必须只落在 Debug 配置。
    foreach ($Pair in @(
            @{ Dir = 'notification-host-matrix-pre'; Var = 'OMLL_NOTIFICATION_PRE_COM_DELAY_MS' },
            @{ Dir = 'notification-host-matrix-post'; Var = 'OMLL_NOTIFICATION_POST_COM_PRE_FLUTTER_DELAY_MS' })) {
        $MatrixDir = Join-Path $Root ("build\windows\" + $Pair.Dir)
        Assert-BuildDirMatchesGenerator $MatrixDir
        $Other = if ($Pair.Var -eq 'OMLL_NOTIFICATION_PRE_COM_DELAY_MS') {
            'OMLL_NOTIFICATION_POST_COM_PRE_FLUTTER_DELAY_MS'
        } else {
            'OMLL_NOTIFICATION_PRE_COM_DELAY_MS'
        }
        $Exit = Invoke-CmakeLogged (@('-S', (Join-Path $Root 'windows'), '-B', $MatrixDir) +
            $GeneratorArgs + @(
                '-DOMLL_NOTIFICATION_HOST_TESTING=ON',
                ("-D" + $Pair.Var + "=500"),
                ("-D" + $Other + "=0"))) ("cmake-" + $Pair.Dir + '.log')
        if ($Exit -ne 0) {
            Write-Host ("FAIL: testing=ON + {0} 配置失败（不应失败）" -f $Pair.Var)
            exit 1
        }
        $Project = Join-Path $MatrixDir 'runner\oh_my_llm.vcxproj'
        if (-not (Test-Path $Project)) {
            Write-Host "FAIL: 未找到生成的 $Project"
            exit 1
        }
        [xml]$ProjectXml = Get-Content -Raw -Encoding UTF8 $Project
        $DefineNeedle = $Pair.Var + '=500'
        $DebugNodes = @($ProjectXml.Project.ItemDefinitionGroup | Where-Object {
            $_.Condition -like "*Debug*" -and $_.ClCompile.PreprocessorDefinitions -like "*$DefineNeedle*" })
        $ReleaseNodes = @($ProjectXml.Project.ItemDefinitionGroup | Where-Object {
            $_.Condition -notlike "*Debug*" -and $_.ClCompile.PreprocessorDefinitions -like "*$DefineNeedle*" })
        if ($DebugNodes.Count -eq 0 -or $ReleaseNodes.Count -ne 0) {
            Write-Host ("FAIL: {0} 未被限制在 Debug 配置（Debug 命中 {1}，非 Debug 命中 {2}）" -f `
                $DefineNeedle, $DebugNodes.Count, $ReleaseNodes.Count)
            exit 1
        }
    Write-Host ("PASS: testing=ON 时 {0} 仅进入 Debug 配置的编译定义" -f $Pair.Var)
    }
}

# ── 常规 configure（testing=ON + 默认全 0 delay）────────────────────
$CanonicalDir = Join-Path $Root 'build\windows\notification-host-test'
Assert-BuildDirMatchesGenerator $CanonicalDir
$Exit = Invoke-CmakeLogged (@('-S', (Join-Path $Root 'windows'), '-B', $CanonicalDir) +
    $GeneratorArgs + @('-DOMLL_NOTIFICATION_HOST_TESTING=ON',
        '-DOMLL_NOTIFICATION_PRE_COM_DELAY_MS=0',
        '-DOMLL_NOTIFICATION_POST_COM_PRE_FLUTTER_DELAY_MS=0')) 'cmake-notification-host-test.log'
if ($Exit -ne 0) {
    Write-Host 'FAIL: 默认（全 0 delay + testing=ON）configure 失败'
    exit 1
}
Write-Host 'PASS: 默认 configure 成功（delay 均为 0）'

# ── 构建并运行原生测试 ───────────────────────────────────────────────
Write-Host '== 构建并运行 windows_notification_host_test =='
& cmake --build $CanonicalDir --config Debug --target windows_notification_host_test 2>&1 |
    Out-File -Encoding utf8 (Join-Path $LogDir 'build-windows-notification-host-test.log')
$BuildExit = $LASTEXITCODE
if ($BuildExit -ne 0) {
    Write-Host "FAIL: 原生测试构建失败（exit=$BuildExit）"
    Get-Content -Tail 60 (Join-Path $LogDir 'build-windows-notification-host-test.log')
    exit $BuildExit
}
Write-Host 'PASS: 原生测试构建成功'

# 测试链接 wrapper 静态库后带有 flutter_windows.dll 导入（StandardMethodCodec
# 的实现与 FlutterDesktop 符号同属一个对象文件）；测试本身不初始化 engine，
# 只需在运行目录能看到该 DLL。
$TestDir = Join-Path $CanonicalDir 'runner\Debug'
$FlutterDll = Join-Path $Root 'windows\flutter\ephemeral\flutter_windows.dll'
if (-not (Test-Path $FlutterDll)) {
    Write-Host "FAIL: 缺少 $FlutterDll（先执行一次 flutter pub get / flutter build）"
    exit 1
}
Copy-Item $FlutterDll -Destination $TestDir -Force

$TestExe = Join-Path $TestDir 'windows_notification_host_test.exe'
if (-not (Test-Path $TestExe)) {
    Write-Host "FAIL: 未找到测试可执行文件 $TestExe"
    exit 1
}
& $TestExe 2>&1 | Tee-Object -FilePath (Join-Path $LogDir 'windows-notification-host-test-run.log')
$TestExit = $LASTEXITCODE
Write-Host "windows_notification_host_test EXIT=$TestExit"
exit $TestExit
