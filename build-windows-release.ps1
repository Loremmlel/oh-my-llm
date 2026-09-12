[CmdletBinding()]
param(
  [string]$OutputDir = "artifacts\windows"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-ProjectVersion {
  param(
    [Parameter(Mandatory)]
    [string]$PubspecPath
  )

  $versionLine = Select-String -Path $PubspecPath -Pattern '^\s*version:\s*(.+)\s*$' | Select-Object -First 1
  if (-not $versionLine) {
    throw "无法从 pubspec.yaml 读取版本号。"
  }

  return $versionLine.Matches[0].Groups[1].Value.Trim()
}

function Assert-LatestArtifactNotRunning {
  param(
    [Parameter(Mandatory)]
    [string]$LatestDirectory
  )

  $latestExecutable = [System.IO.Path]::GetFullPath(
    (Join-Path $LatestDirectory "oh_my_llm.exe")
  )
  $runningProcesses = @(
    Get-CimInstance Win32_Process -Filter "Name='oh_my_llm.exe'" -ErrorAction SilentlyContinue |
      Where-Object {
        $_.ExecutablePath -and
        [string]::Equals(
          [System.IO.Path]::GetFullPath($_.ExecutablePath),
          $latestExecutable,
          [System.StringComparison]::OrdinalIgnoreCase
        )
      }
  )

  if ($runningProcesses.Count -eq 0) {
    return
  }

  $processIds = ($runningProcesses.ProcessId | Sort-Object) -join ", "
  throw "检测到 oh_my_llm-windows-latest 正在运行（PID: $processIds）。请先关闭这些窗口或进程，再重新构建；脚本尚未修改发布目录。"
}

$repoRoot = Split-Path -Parent $PSCommandPath
$pubspecPath = Join-Path $repoRoot "pubspec.yaml"
$projectVersion = Get-ProjectVersion -PubspecPath $pubspecPath
$safeVersion = $projectVersion -replace '[^0-9A-Za-z\.\-_+]', '_'
$artifactRoot = Join-Path $repoRoot $OutputDir
$latestDir = Join-Path $artifactRoot "oh_my_llm-windows-latest"
$zipPath = Join-Path $artifactRoot "oh_my_llm-windows-$safeVersion.zip"
$releaseDir = Join-Path $repoRoot "build\windows\x64\runner\Release"

Assert-LatestArtifactNotRunning -LatestDirectory $latestDir

Write-Host "==> 准备 Windows Release 构建"
Push-Location $repoRoot
try {
  & flutter pub get
  if ($LASTEXITCODE -ne 0) {
    throw "flutter pub get 执行失败。"
  }

  & flutter build windows --release
  if ($LASTEXITCODE -ne 0) {
    throw "flutter build windows --release 执行失败。"
  }
}
finally {
  Pop-Location
}

if (-not (Test-Path $releaseDir)) {
  throw "未找到 Windows Release 输出目录：$releaseDir"
}

New-Item -ItemType Directory -Path $artifactRoot -Force | Out-Null

# 构建期间仍可能有人启动 latest，发布前再次检查以避免删到一半。
Assert-LatestArtifactNotRunning -LatestDirectory $latestDir

# 清理旧版本文件夹（只保留 latest）
Get-ChildItem -Path $artifactRoot -Directory -Filter "oh_my_llm-windows-*" -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName -ne $latestDir } |
  Remove-Item -Recurse -Force

# 覆盖 latest 文件夹
if (Test-Path $latestDir) {
  Remove-Item -Path $latestDir -Recurse -Force
}
Copy-Item -Path $releaseDir -Destination $latestDir -Recurse

# 生成当前版本 zip
Compress-Archive -Path $latestDir -DestinationPath $zipPath -Force

Write-Host ""
Write-Host "Windows Release 输出："
Write-Host "  latest 文件夹: $latestDir"
Write-Host "  版本压缩包:    $zipPath"
