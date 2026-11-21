[CmdletBinding()]
param(
    [string]$OutputDir = "artifacts\android",
    [ValidateSet("arm64", "split", "universal")]
    [string]$AbiMode = "arm64"
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

function Get-KeytoolPath {
    if ($env:JAVA_HOME) {
        $javaHomeKeytool = Join-Path $env:JAVA_HOME "bin\keytool.exe"
        if (Test-Path $javaHomeKeytool) {
            return $javaHomeKeytool
        }
    }

    $keytoolCommand = Get-Command keytool.exe -ErrorAction SilentlyContinue
    if ($keytoolCommand) {
        return $keytoolCommand.Source
    }

    throw "未找到 keytool.exe，请先安装 JDK 或配置 JAVA_HOME。"
}

$repoRoot = Split-Path -Parent $PSCommandPath
$androidDir = Join-Path $repoRoot "android"
$appDir = Join-Path $androidDir "app"
$pubspecPath = Join-Path $repoRoot "pubspec.yaml"
$projectVersion = Get-ProjectVersion -PubspecPath $pubspecPath
$safeVersion = $projectVersion -replace '[^0-9A-Za-z\.\-_+]', '_'
$artifactRoot = Join-Path $repoRoot $OutputDir
$apkBuildDir = Join-Path $repoRoot "build\app\outputs\flutter-apk"
$symbolDir = Join-Path $repoRoot "build\app\outputs\symbols\android-$AbiMode"
$keyPropertiesPath = Join-Path $androidDir "key.properties"
$keystorePath = Join-Path $appDir "self-use-release.jks"
$keyAlias = "selfuse"
$storePassword = "oh-my-llm-self-use"
$keyPassword = "oh-my-llm-self-use"
$storeFileFromAndroidDir = "app/self-use-release.jks"

if (-not (Test-Path $keystorePath)) {
    $keytoolPath = Get-KeytoolPath
    Write-Host "==> 未找到本地 Android release keystore，正在生成自用签名文件"
    & $keytoolPath `
        -genkeypair `
        -v `
        -keystore $keystorePath `
        -storepass $storePassword `
        -alias $keyAlias `
        -keypass $keyPassword `
        -keyalg RSA `
        -keysize 2048 `
        -validity 36500 `
        -dname "CN=oh-my-llm Self Use, OU=Personal, O=Personal, L=Local, ST=Local, C=CN"
    if ($LASTEXITCODE -ne 0) {
        throw "生成 Android keystore 失败。"
    }
}

if (-not (Test-Path $keyPropertiesPath)) {
    @"
storePassword=$storePassword
keyPassword=$keyPassword
keyAlias=$keyAlias
storeFile=$storeFileFromAndroidDir
"@ | Set-Content -Path $keyPropertiesPath -Encoding ASCII
}

$flutterBuildArgs = @(
    "build", "apk", "--release",
    "--obfuscate",
    "--split-debug-info=$symbolDir"
)
switch ($AbiMode) {
    "arm64" {
        # 配合 --split-per-abi 让 AGP 原生剔除第三方 AAR 的其他 ABI 目录，避免残留半残 lib/<abi>/ 目录。
        $flutterBuildArgs += @("--split-per-abi", "--target-platform", "android-arm64")
        $apkMappings = @(
            @{
                Source = Join-Path $apkBuildDir "app-arm64-v8a-release.apk"
                Dest   = Join-Path $artifactRoot "oh_my_llm-android-$safeVersion-arm64-v8a.apk"
            }
        )
    }
    "split" {
        $flutterBuildArgs += "--split-per-abi"
        $apkMappings = @(
            @{
                Source = Join-Path $apkBuildDir "app-arm64-v8a-release.apk"
                Dest   = Join-Path $artifactRoot "oh_my_llm-android-$safeVersion-arm64-v8a.apk"
            },
            @{
                Source = Join-Path $apkBuildDir "app-armeabi-v7a-release.apk"
                Dest   = Join-Path $artifactRoot "oh_my_llm-android-$safeVersion-armeabi-v7a.apk"
            },
            @{
                Source = Join-Path $apkBuildDir "app-x86_64-release.apk"
                Dest   = Join-Path $artifactRoot "oh_my_llm-android-$safeVersion-x86_64.apk"
            }
        )
    }
    "universal" {
        $apkMappings = @(
            @{
                Source = Join-Path $apkBuildDir "app-release.apk"
                Dest   = Join-Path $artifactRoot "oh_my_llm-android-$safeVersion.apk"
            }
        )
    }
}

Write-Host "==> 准备 Android Release APK 构建（ABI 模式：$AbiMode）"
Push-Location $repoRoot
try {
    & flutter pub get
    if ($LASTEXITCODE -ne 0) {
        throw "flutter pub get 执行失败。"
    }

    & flutter @flutterBuildArgs
    if ($LASTEXITCODE -ne 0) {
        throw "flutter $($flutterBuildArgs -join ' ') 执行失败。"
    }
}
finally {
    Pop-Location
}

New-Item -ItemType Directory -Path $artifactRoot -Force | Out-Null
$copiedApks = @()
foreach ($mapping in $apkMappings) {
    if (-not (Test-Path $mapping.Source)) {
        throw "未找到 Android APK 输出文件：$($mapping.Source)"
    }
    Copy-Item -Path $mapping.Source -Destination $mapping.Dest -Force
    $copiedApks += $mapping.Dest
}

Write-Host ""
Write-Host "Android APK 已生成："
foreach ($apkPath in $copiedApks) {
    $sizeMiB = [math]::Round(((Get-Item $apkPath).Length / 1MB), 2)
    Write-Host "  $apkPath ($sizeMiB MiB)"
}
Write-Host ""
Write-Host "Dart 调试符号目录："
Write-Host "  $symbolDir"
Write-Host ""
Write-Host "本地签名文件："
Write-Host "  $keystorePath"
Write-Host "  $keyPropertiesPath"
