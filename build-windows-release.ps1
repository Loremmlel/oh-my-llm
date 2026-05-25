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

$repoRoot = Split-Path -Parent $PSCommandPath
$pubspecPath = Join-Path $repoRoot "pubspec.yaml"
$projectVersion = Get-ProjectVersion -PubspecPath $pubspecPath
$safeVersion = $projectVersion -replace '[^0-9A-Za-z\.\-_+]', '_'
$artifactRoot = Join-Path $repoRoot $OutputDir
$latestDir = Join-Path $artifactRoot "oh_my_llm-windows-latest"
$zipPath = Join-Path $artifactRoot "oh_my_llm-windows-$safeVersion.zip"
$releaseDir = Join-Path $repoRoot "build\windows\x64\runner\Release"

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

# 清理旧版本文件夹（只保留 latest）
Get-ChildItem -Path $artifactRoot -Directory -Filter "oh_my_llm-windows-*" -ErrorAction SilentlyContinue |
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
