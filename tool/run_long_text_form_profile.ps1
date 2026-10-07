param(
    [Parameter(Mandatory)][string]$Fixture,
    [int]$BuildTimeoutMs = 300000,
    [int]$RunTimeoutMs = 60000
)
$ErrorActionPreference = 'Stop'
$Repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$LogRoot = Join-Path $Repo 'logs'
New-Item -ItemType Directory -Force $LogRoot | Out-Null
$env:LONG_TEXT_FIXTURE = (Resolve-Path -LiteralPath $Fixture).Path
$env:LONG_TEXT_RESULT = Join-Path $LogRoot 'long-text-form-profile.json'
$Executable = Join-Path $Repo 'build/windows/x64/runner/Profile/oh_my_llm.exe'
if (Get-Process oh_my_llm -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $Executable }) {
    throw '诊断构建仍在运行，请先结束该实例。'
}
$Command = 'flutter build windows --profile --target tool/long_text_form_profile.dart --no-pub; exit $LASTEXITCODE'
$Encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Command))
$Build = Start-Process pwsh.exe -WorkingDirectory $Repo -WindowStyle Hidden -ArgumentList @('-NoProfile', '-EncodedCommand', $Encoded) -RedirectStandardOutput (Join-Path $LogRoot 'long-text-form-build.log') -RedirectStandardError (Join-Path $LogRoot 'long-text-form-build-stderr.log') -PassThru
if (-not $Build.WaitForExit($BuildTimeoutMs)) {
    $Build.Kill($true)
    $Build.WaitForExit()
    throw '诊断构建超时，已终止进程树。'
}
Get-Content -Tail 20 (Join-Path $LogRoot 'long-text-form-build.log')
Get-Content -Tail 20 (Join-Path $LogRoot 'long-text-form-build-stderr.log')
if ($Build.ExitCode -ne 0) { exit $Build.ExitCode }
# 仅运行独立入口；不启动应用数据库，也不覆盖发布目录。
$Probe = Start-Process -FilePath $Executable -WorkingDirectory (Split-Path $Executable) -WindowStyle Hidden -RedirectStandardOutput (Join-Path $LogRoot 'long-text-form-run.log') -RedirectStandardError (Join-Path $LogRoot 'long-text-form-run-stderr.log') -PassThru
if (-not $Probe.WaitForExit($RunTimeoutMs)) {
    $Probe.Kill($true)
    $Probe.WaitForExit()
    throw '诊断运行超时，已终止进程树。'
}
Write-Host "EXIT=$($Probe.ExitCode); RESULT=$env:LONG_TEXT_RESULT"
exit $Probe.ExitCode
