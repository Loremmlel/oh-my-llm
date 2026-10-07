param(
    [ValidateSet('create', 'restore', 'analyze', 'build', 'run', 'test')]
    [string]$Stage,
    [Parameter(Mandatory)][int]$TimeoutMs,
    [string]$OutputName = 'long-text-results-noto',
    [string]$Entry = 'main.dart'
)
$ErrorActionPreference = 'Stop'
$Repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$Project = Join-Path $Repo 'logs/long-text-benchmark'
$LogRoot = Join-Path $Repo 'logs'
New-Item -ItemType Directory -Force $LogRoot | Out-Null
$env:LONG_TEXT_RESULT = Join-Path $LogRoot "$OutputName.json"
$Commands = @{
    create = 'flutter create --empty --platforms windows --no-pub --project-name long_text_benchmark logs/long-text-benchmark'
    restore = 'Push-Location ../../tool/long_text_benchmark; flutter pub get; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; Pop-Location; Copy-Item ../../tool/long_text_benchmark/pubspec.lock ./pubspec.lock; flutter pub get --enforce-lockfile'
    analyze = 'flutter analyze'
    build = 'flutter build windows --profile --no-pub'
    run = '$Bench = Start-Process ./build/windows/x64/runner/Profile/long_text_benchmark.exe -WindowStyle Hidden -PassThru; $Bench.WaitForExit(); exit $Bench.ExitCode'
    test = 'flutter test test/editor_contract_test.dart --reporter compact'
}
if ($Stage -in @('restore', 'analyze', 'build')) {
    foreach ($Destination in @($Project, $PSScriptRoot)) {
        $FontDirectory = Join-Path $Destination 'assets/fonts'
        New-Item -ItemType Directory -Force $FontDirectory | Out-Null
        Copy-Item -LiteralPath (Join-Path $Repo 'assets/fonts/NotoSansSC-VF.ttf') -Destination $FontDirectory
    }
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'pubspec.yaml') -Destination $Project
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $Entry) -Destination (Join-Path $Project 'lib/main.dart')
}
$WorkingDirectory = if ($Stage -eq 'create') { $Repo } elseif ($Stage -in @('test', 'analyze')) { $PSScriptRoot } else { $Project }
if ($Stage -eq 'run') {
    $Executable = [IO.Path]::GetFullPath((Join-Path $Project 'build/windows/x64/runner/Profile/long_text_benchmark.exe'))
    if (Get-Process long_text_benchmark -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $Executable }) {
        throw 'A benchmark instance is already running; concurrent results would be invalid.'
    }
}
$Command = '$ProgressPreference = "SilentlyContinue"; ' + $Commands[$Stage] + '; exit $LASTEXITCODE'
$Encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Command))
$Stdout = Join-Path $LogRoot "long-text-benchmark-$Stage.log"
$Stderr = Join-Path $LogRoot "long-text-benchmark-$Stage-stderr.log"
# 统一等待并限制整棵子进程树，避免 Flutter 启动或原生应用卡住后无限挂起。
$Process = Start-Process pwsh.exe -ArgumentList @('-NoProfile', '-EncodedCommand', $Encoded) -WorkingDirectory $WorkingDirectory -WindowStyle Hidden -RedirectStandardOutput $Stdout -RedirectStandardError $Stderr -PassThru
if (-not $Process.WaitForExit($TimeoutMs)) {
    $Process.Kill($true)
    $Process.WaitForExit()
    throw "$Stage exceeded ${TimeoutMs}ms; process tree terminated. See $Stdout"
}
$Tail = if ($Stage -eq 'test') { 150 } else { 20 }
Get-Content -Tail $Tail $Stdout
Get-Content -Tail $Tail $Stderr
Write-Host "EXIT=$($Process.ExitCode)"
exit $Process.ExitCode
