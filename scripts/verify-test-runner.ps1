#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
$Repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$FixtureRoot = Join-Path $Repo 'logs/test-runner-check'
New-Item -ItemType Directory -Force $FixtureRoot | Out-Null
$Runner = (Join-Path $PSScriptRoot 'run-tests.ps1').Replace("'", "''")
$Pwsh = (Get-Process -Id $PID).Path
$OriginalPath = $env:PATH
$OriginalMode = $env:SIYUE_RUNNER_CHECK_MODE
$OriginalPwsh = $env:SIYUE_RUNNER_CHECK_PWSH
$OriginalStub = $env:SIYUE_RUNNER_CHECK_STUB

# 使用 Windows 命令 shim 复现 flutter.bat 的原生 stdout / stderr 和子进程链。
Set-Content -LiteralPath (Join-Path $FixtureRoot 'flutter.cmd') -Encoding ascii -Value @'
@echo off
"%SIYUE_RUNNER_CHECK_PWSH%" -NoProfile -NonInteractive -File "%SIYUE_RUNNER_CHECK_STUB%" %*
exit /b %errorlevel%
'@
Set-Content -LiteralPath (Join-Path $FixtureRoot 'fake-flutter.ps1') -Encoding utf8 -Value @'
Write-Output ('ARGS=' + (ConvertTo-Json -InputObject @($args) -Compress))
[Console]::Error.WriteLine('标准错误也必须写入日志')
if ($env:SIYUE_RUNNER_CHECK_MODE -eq 'failure') { exit 23 }
if ($env:SIYUE_RUNNER_CHECK_MODE -eq 'timeout') {
    $Child = Start-Process (Get-Process -Id $PID).Path -ArgumentList @('-NoProfile', '-NonInteractive', '-Command', 'Start-Sleep -Seconds 60') -WindowStyle Hidden -PassThru
    Write-Output "CHILD=$($Child.Id)"
    Start-Sleep -Seconds 60
}
exit 0
'@

function Invoke-RunnerCheck([string]$Arguments, [int]$ExpectedExit) {
    $Command = "& '$Runner' $Arguments; exit `$LASTEXITCODE"
    $Encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Command))
    $Output = & $Pwsh -NoProfile -NonInteractive -EncodedCommand $Encoded 2>&1
    if ($LASTEXITCODE -ne $ExpectedExit) { throw "预期退出码 $ExpectedExit，实际 $LASTEXITCODE：$Output" }
    return $Output -join [Environment]::NewLine
}

try {
    $env:PATH = $FixtureRoot + [IO.Path]::PathSeparator + $OriginalPath
    $env:SIYUE_RUNNER_CHECK_PWSH = $Pwsh
    $env:SIYUE_RUNNER_CHECK_STUB = Join-Path $FixtureRoot 'fake-flutter.ps1'
    $env:SIYUE_RUNNER_CHECK_MODE = 'success'
    $Output = Invoke-RunnerCheck "-TestPath 'test/中文 路径_test.dart' -PlainName '名称带空格、单引号''和 $ 符号' -LogName 'test-runner-check-success.log' -FlutterArgs @('--coverage')" 0
    if ($Output -notmatch 'TIMEOUT_SECONDS=60 ') { throw '单文件默认超时应为 60 秒' }
    $Log = Get-Content -Raw -LiteralPath (Join-Path $Repo 'logs/test-runner-check-success.log') -Encoding utf8
    $Recorded = ([regex]::Match($Log, '(?m)^ARGS=(.+)').Groups[1].Value | ConvertFrom-Json)
    $Expected = @('test', '--reporter', 'compact', 'test/中文 路径_test.dart', '--plain-name', '名称带空格、单引号''和 $ 符号', '--coverage')
    if ((ConvertTo-Json -InputObject $Recorded -Compress) -ne (ConvertTo-Json -InputObject $Expected -Compress)) { throw "参数转发不一致：$Log" }
    if ($Log -notmatch '标准错误也必须写入日志') { throw '标准错误未落盘' }

    $env:SIYUE_RUNNER_CHECK_MODE = 'failure'
    $Output = Invoke-RunnerCheck "-LogName 'test-runner-check-failure.log'" 23
    if ($Output -notmatch 'TIMEOUT_SECONDS=240 ') { throw '全量默认超时应为 240 秒' }

    $env:SIYUE_RUNNER_CHECK_MODE = 'timeout'
    $null = Invoke-RunnerCheck "-LogName 'test-runner-check-timeout.log' -TimeoutSeconds 5" 124
    $Log = Get-Content -Raw -LiteralPath (Join-Path $Repo 'logs/test-runner-check-timeout.log') -Encoding utf8
    $ChildId = [int][regex]::Match($Log, 'CHILD=(\d+)').Groups[1].Value
    if ($ChildId -le 0 -or (Get-Process -Id $ChildId -ErrorAction SilentlyContinue)) { throw '超时后仍有子进程，或未实际运行到挂起阶段' }
    Write-Host '通过：参数与中文日志、标准错误、成功/失败退出码、默认超时和挂起子进程清理。'
} finally {
    $env:PATH = $OriginalPath
    $env:SIYUE_RUNNER_CHECK_MODE = $OriginalMode
    $env:SIYUE_RUNNER_CHECK_PWSH = $OriginalPwsh
    $env:SIYUE_RUNNER_CHECK_STUB = $OriginalStub
}
exit 0
