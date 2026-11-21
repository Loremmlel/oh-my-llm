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
    Get-CimInstance Win32_Process -Filter "Name='oh_my_llm.exe'" -ErrorAction Stop |
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

function Publish-WindowsArtifact {
  param(
    [Parameter(Mandatory)]
    [string]$ReleaseDirectory,
    [Parameter(Mandatory)]
    [string]$ArtifactDirectory,
    [Parameter(Mandatory)]
    [string]$LatestDirectory,
    [Parameter(Mandatory)]
    [string]$ZipFile
  )

  $publishId = [guid]::NewGuid().ToString("N")
  $stagingRoot = Join-Path $ArtifactDirectory ".oh_my_llm-windows-publish-$publishId"
  $stagedLatest = Join-Path $stagingRoot "oh_my_llm-windows-latest"
  $stagedZip = Join-Path $stagingRoot ([System.IO.Path]::GetFileName($ZipFile))
  $backupDirectory = Join-Path $ArtifactDirectory ".oh_my_llm-windows-backup-$publishId"
  $hasBackup = $false

  New-Item -ItemType Directory -Path $stagingRoot -Force | Out-Null
  try {
    Copy-Item -Path $ReleaseDirectory -Destination $stagedLatest -Recurse

    # 剔除 Windows 运行时实际不会加载的随包 DLL：
    # - vk_swiftshader.dll / vulkan-1.dll / zlib.dll：media_kit_libs_windows_video 整包附带的
    #   ANGLE Vulkan/SwiftShader 辅助库；media_kit_video 的 ANGLESurfaceManager 仅使用 D3D11/D3D9/WARP，
    #   且 libGLESv2.dll / libEGL.dll / libmpv-2.dll 均无对它们的静态依赖。
    # - dartjni.dll：Android 插件传递依赖 jni 编出的 FFI 库，Windows 路径不会调用。
    $unusedDlls = @(
      "vk_swiftshader.dll",
      "vulkan-1.dll",
      "zlib.dll",
      "dartjni.dll"
    )
    foreach ($dllName in $unusedDlls) {
      $dllPath = Join-Path $stagedLatest $dllName
      if (Test-Path -LiteralPath $dllPath) {
        Remove-Item -LiteralPath $dllPath
      }
    }

    Compress-Archive -Path $stagedLatest -DestinationPath $stagedZip

    # 查询失败或已有实例时均在修改公开目录前退出。
    Assert-LatestArtifactNotRunning -LatestDirectory $LatestDirectory

    if (Test-Path $LatestDirectory) {
      # 同卷目录重命名只会整体成功或失败；竞态启动不会再造成逐文件删除。
      Move-Item -LiteralPath $LatestDirectory -Destination $backupDirectory
      $hasBackup = $true
    }

    try {
      Move-Item -LiteralPath $stagedLatest -Destination $LatestDirectory
    }
    catch {
      if ($hasBackup -and -not (Test-Path $LatestDirectory)) {
        Move-Item -LiteralPath $backupDirectory -Destination $LatestDirectory
        $hasBackup = $false
      }
      throw
    }

    Move-Item -LiteralPath $stagedZip -Destination $ZipFile -Force

    if ($hasBackup) {
      Remove-Item -LiteralPath $backupDirectory -Recurse -Force
      $hasBackup = $false
    }
  }
  finally {
    if (Test-Path $stagingRoot) {
      Remove-Item -LiteralPath $stagingRoot -Recurse -Force
    }
  }
}

$repoRoot = Split-Path -Parent $PSCommandPath
$pubspecPath = Join-Path $repoRoot "pubspec.yaml"
$projectVersion = Get-ProjectVersion -PubspecPath $pubspecPath
$safeVersion = $projectVersion -replace '[^0-9A-Za-z\.\-_+]', '_'
$artifactRoot = Join-Path $repoRoot $OutputDir
$latestDir = Join-Path $artifactRoot "oh_my_llm-windows-latest"
$zipPath = Join-Path $artifactRoot "oh_my_llm-windows-$safeVersion.zip"
$releaseDir = Join-Path $repoRoot "build\windows\x64\runner\Release"
$symbolDir = Join-Path $repoRoot "build\windows\x64\symbols"

Assert-LatestArtifactNotRunning -LatestDirectory $latestDir

Write-Host "==> 准备 Windows Release 构建"
Push-Location $repoRoot
try {
  # 构建前清理旧 Release 输出目录，避免升级 Flutter 或依赖后残留旧插件 DLL 与过时资源。
  if (Test-Path -LiteralPath $releaseDir) {
    Remove-Item -LiteralPath $releaseDir -Recurse -Force
  }

  & flutter pub get
  if ($LASTEXITCODE -ne 0) {
    throw "flutter pub get 执行失败。"
  }

  & flutter build windows --release --obfuscate "--split-debug-info=$symbolDir"
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

Publish-WindowsArtifact `
  -ReleaseDirectory $releaseDir `
  -ArtifactDirectory $artifactRoot `
  -LatestDirectory $latestDir `
  -ZipFile $zipPath

# 清理旧版本文件夹（只保留 latest）
Get-ChildItem -Path $artifactRoot -Directory -Filter "oh_my_llm-windows-*" -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName -ne $latestDir } |
  Remove-Item -Recurse -Force

$zipSizeMiB = [math]::Round(((Get-Item $zipPath).Length / 1MB), 2)
$dirSizeMiB = [math]::Round((((Get-ChildItem -Path $latestDir -Recurse -File | Measure-Object Length -Sum).Sum) / 1MB), 2)

Write-Host ""
Write-Host "Windows Release 输出："
Write-Host "  latest 文件夹: $latestDir ($dirSizeMiB MiB)"
Write-Host "  版本压缩包:    $zipPath ($zipSizeMiB MiB)"
Write-Host "  Dart 调试符号: $symbolDir"
