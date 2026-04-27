<#
.SYNOPSIS
    手动升级应用版本号（minor 或 major）。

.DESCRIPTION
    读取 pubspec.yaml 中的版本号，并按照指定参数升级 minor 或 major 版本。

    - 升级 minor 版本时，patch 归零（例如 1.2.3 -> 1.3.0）。
    - 升级 major 版本时，minor 和 patch 均归零（例如 1.2.3 -> 2.0.0）。
    - build 号（+N 部分）保持不变。

    patch 版本的日常自动递增由 git pre-commit 钩子（.githooks/pre-commit）负责，
    无需通过本脚本手动处理。

.PARAMETER Minor
    升级 minor 版本（x.Y.z 中的 Y），并将 patch 归零。

.PARAMETER Major
    升级 major 版本（X.y.z 中的 X），并将 minor 和 patch 均归零。

.EXAMPLE
    .\scripts\bump-version.ps1 -Minor
    # 1.2.3+4 -> 1.3.0+4

.EXAMPLE
    .\scripts\bump-version.ps1 -Major
    # 1.2.3+4 -> 2.0.0+4
#>

param(
    [switch]$Minor,
    [switch]$Major
)

if (-not $Minor -and -not $Major) {
    Write-Error "请指定 -Minor 或 -Major 参数。示例：.\scripts\bump-version.ps1 -Minor"
    exit 1
}

$pubspecPath = Join-Path $PSScriptRoot ".." "pubspec.yaml"
$content = [System.IO.File]::ReadAllText($pubspecPath, [System.Text.Encoding]::UTF8)

# 提取当前版本号（例如 "1.2.3+4"）
if ($content -match 'version:\s+(\d+)\.(\d+)\.(\d+)\+(\d+)') {
    $majorNum = [int]$Matches[1]
    $minorNum = [int]$Matches[2]
    $patchNum = [int]$Matches[3]
    $buildNum = $Matches[4]
} else {
    Write-Error "无法在 pubspec.yaml 中解析版本号，请确认格式为 'version: x.y.z+n'。"
    exit 1
}

$oldVersion = "$majorNum.$minorNum.$patchNum+$buildNum"

if ($Major) {
    $majorNum++
    $minorNum = 0
    $patchNum = 0
} elseif ($Minor) {
    $minorNum++
    $patchNum = 0
}

$newVersion = "$majorNum.$minorNum.$patchNum+$buildNum"

# 替换 pubspec.yaml 中的版本号
$newContent = $content -replace 'version:\s+\d+\.\d+\.\d+\+\d+', "version: $newVersion"
[System.IO.File]::WriteAllText($pubspecPath, $newContent, [System.Text.Encoding]::UTF8)

Write-Host "版本升级：$oldVersion -> $newVersion"
Write-Host "记得手动 git add pubspec.yaml 并提交。"
