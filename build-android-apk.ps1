[CmdletBinding()]
param(
    [string]$OutputDir = "artifacts\android"
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
$apkOutputPath = Join-Path $artifactRoot "oh_my_llm-android-$safeVersion.apk"
$releaseApkPath = Join-Path $repoRoot "build\app\outputs\flutter-apk\app-release.apk"
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

Write-Host "==> 准备 Android Release APK 构建"
Push-Location $repoRoot
try {
    & flutter pub get
    if ($LASTEXITCODE -ne 0) {
        throw "flutter pub get 执行失败。"
    }

    & flutter build apk --release
    if ($LASTEXITCODE -ne 0) {
        throw "flutter build apk --release 执行失败。"
    }
}
finally {
    Pop-Location
}

if (-not (Test-Path $releaseApkPath)) {
    throw "未找到 Android APK 输出文件：$releaseApkPath"
}

New-Item -ItemType Directory -Path $artifactRoot -Force | Out-Null
Copy-Item -Path $releaseApkPath -Destination $apkOutputPath -Force

Write-Host ""
Write-Host "Android APK 已生成："
Write-Host "  $apkOutputPath"
Write-Host ""
Write-Host "本地签名文件："
Write-Host "  $keystorePath"
Write-Host "  $keyPropertiesPath"
