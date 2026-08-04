<#
.SYNOPSIS
  清理残留的 test 进程，解锁 native assets dll。

.DESCRIPTION
  flutter test 在 Windows 上偶发卡住被中断后，dart 子进程可能残留，
  持有 build\native_assets\windows\sqlite3.dll 的加载锁（LoadLibrary 默认
  不共享写权限）。下次 flutter test 的 native assets hook 要重写该 dll 时
  写入失败/卡住，表现为 test 启动卡死（连锁阻塞）。

  本脚本清理残留的 dart.exe / flutter_tester.exe 进程，排除 IDE 的
  analysis server / language server 以免误杀导致 IDE 重新分析。
  跑 test 前若发现启动卡住（连用例都没开始跑）可执行本脚本。

.EXAMPLE
  ./scripts/kill-stale-test-processes.ps1
#>
[CmdletBinding()]
param()

# 排除 IDE 的 analysis server / language server，避免误杀。
$stale = Get-CimInstance Win32_Process -Filter "Name='dart.exe' OR Name='flutter_tester.exe'" -ErrorAction SilentlyContinue |
  Where-Object {
    $_.CommandLine -and
    $_.CommandLine -notmatch 'analysis_server|language-server|language_server|snapshot=.*analysis'
  }

if (-not $stale) {
  Write-Host "未发现残留 test 进程（dart/flutter_tester）。" -ForegroundColor Green
  return
}

$count = @($stale).Count
Write-Host "发现 $count 个残留进程，准备清理：" -ForegroundColor Yellow
$stale | Select-Object ProcessId, Name, CommandLine | Format-List

$stale | ForEach-Object {
  try {
    Stop-Process -Id $_.ProcessId -Force -ErrorAction Stop
    Write-Host "  已终止 PID $($_.ProcessId) ($($_.Name))" -ForegroundColor Green
  } catch {
    Write-Host "  PID $($_.ProcessId) 终止失败: $($_.Exception.Message)" -ForegroundColor Red
  }
}

Write-Host "清理完成，可重新运行 flutter test。" -ForegroundColor Green
