#Requires -Version 7.0
[CmdletBinding()]
param(
    [string[]]$TestPath = @(),
    [string]$PlainName,
    [ValidatePattern('^[^\\/:*?"<>|]+\.log$')]
    [string]$LogName = 'fltest.log',
    [ValidateRange(0, 3600)]
    [int]$TimeoutSeconds = 0,
    [string[]]$FlutterArgs = @()
)

$ErrorActionPreference = 'Stop'
$Repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$LogRoot = Join-Path $Repo 'logs'
New-Item -ItemType Directory -Force $LogRoot | Out-Null
$LogPath = Join-Path $LogRoot $LogName
$Flutter = (Get-Command flutter -CommandType Application, ExternalScript -ErrorAction Stop | Select-Object -First 1).Source
$TestArguments = @('test', '--reporter', 'compact') + $TestPath
if ($PlainName) { $TestArguments += @('--plain-name', $PlainName) }
$TestArguments += $FlutterArgs
if ($TimeoutSeconds -eq 0) {
    $TimeoutSeconds = if ($TestPath.Count -eq 1 -and $TestPath[0] -like '*.dart') { 60 } else { 240 }
}

# 参数作为数据传给子 PowerShell，避免名称中的引号或 shell 字符变成命令。
$Request = @{
    Flutter = $Flutter
    Arguments = $TestArguments
    LogPath = $LogPath
} | ConvertTo-Json -Compress
$Payload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Request))
$Command = @'
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$Request = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__PAYLOAD__')) | ConvertFrom-Json
$TestArguments = @($Request.Arguments)
try {
    & $Request.Flutter @TestArguments *> $Request.LogPath
    exit $LASTEXITCODE
} catch {
    $_ | Out-File -LiteralPath $Request.LogPath -Append -Encoding utf8
    exit 1
}
'@.Replace('__PAYLOAD__', $Payload)
$Encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Command))
$StartOptions = @{
    FilePath = (Get-Process -Id $PID).Path
    ArgumentList = @('-NoProfile', '-NonInteractive', '-EncodedCommand', $Encoded)
    WorkingDirectory = $Repo
    PassThru = $true
}
if ($IsWindows) { $StartOptions.WindowStyle = 'Hidden' }

Write-Host "TIMEOUT_SECONDS=$TimeoutSeconds LOG=$LogPath"
$Process = Start-Process @StartOptions
try {
    if ($Process.WaitForExit($TimeoutSeconds * 1000)) {
        $TestExit = $Process.ExitCode
    } else {
        $Process.Kill($true)
        $Process.WaitForExit()
        $TestExit = 124
        Add-Content -LiteralPath $LogPath -Encoding utf8 -Value "`n测试超过 $TimeoutSeconds 秒，已终止本次进程树。诊断日志并清理本仓库残留测试进程后再重跑。"
    }
} finally {
    if (-not $Process.HasExited) { $Process.Kill($true) }
    $Process.Dispose()
}
Get-Content -LiteralPath $LogPath -Encoding utf8 -Tail 150
Write-Host "EXIT=$TestExit"
exit $TestExit
