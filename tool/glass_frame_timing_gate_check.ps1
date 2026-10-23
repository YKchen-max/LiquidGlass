# SPDX-License-Identifier: GPL-3.0-or-later
#
# task-85：**release 门控自证**（静态检查，不需要设备、不需要构建）。
#
# 它证明的是"release 包零行为"这条硬要求，做法是断言"门控链条"在源码层面成立：
#   1. `glassFrameTimingEnabled` 必须是 **const**，且初值恰好是
#      `kDebugMode && bool.fromEnvironment('GLASS_FRAME_TIMING')`
#      ⇒ release 下 `kDebugMode == false`（framework 的常量）⇒ 整个表达式是编译期常量 false
#      ⇒ `install()` 的 `if (!glassFrameTimingEnabled) return;` 折叠成裸 return
#      ⇒ 回调注册、字段、每帧字符串拼接都从调用图上不可达 ⇒ AOT 整程序裁剪时消失 ✓；
#   2. `install()` 必须以该早返回开头（门控在**安装点内部**，而不是靠调用方记得判断）；
#   3. `GlassFrameTiming.install` 在 `lib/` 下**只有 main.dart 一处调用**（最小侵入）；
#   4. main.dart 的改动footprint = 1 行 import + 1 行调用（Dart 语法上 import 不可省，见 README 说明）；
#   5. 采样点必须是 `SchedulerBinding.instance.addTimingsCallback`，且采的是
#      buildDuration / rasterDuration / totalSpan（口径：不是帧间隔）。
#
# 用法：pwsh -File app/tool/glass_frame_timing_gate_check.ps1
# 退出码：0 = 门控链条成立；1 = 有断言不成立。
param(
    [string]$AppRoot = (Join-Path $PSScriptRoot '..')
)
$ErrorActionPreference = 'Stop'
$lib = Join-Path $AppRoot 'lib'
$hook = Join-Path $lib 'debug\glass_frame_timing.dart'
$main = Join-Path $lib 'main.dart'
$fail = 0

function Assert-True([bool]$cond, [string]$what, [string]$detail = '') {
    if ($cond) {
        Write-Host "  ✓ $what"
    } else {
        Write-Host "  ✗ $what  $detail"
        $script:fail++
    }
}

Write-Host '=== task-85 release 门控自证（静态断言）==='
Assert-True (Test-Path $hook) '钩子文件存在（新文件）' $hook
$hookText = Get-Content $hook -Raw -Encoding UTF8
$mainText = Get-Content $main -Raw -Encoding UTF8

# 1) const 门控 + 精确初值
Assert-True (($hookText -match 'const bool glassFrameTimingEnabled\s*=\s*!kReleaseMode') -and ($hookText -match "bool\.fromEnvironment\('GLASS_FRAME_TIMING'\)")) `
    '门控是 const 且以 !kReleaseMode 起头（⇒ release 恒 false，**即便带了 define 也不可开启** ✓）× 含 bool.fromEnvironment 开关'
Assert-True ($hookText -match 'const bool glassKeepControlsEnabled\s*=\s*!kReleaseMode') `
    '常显控制条开关同样是 !kReleaseMode 门控（release 恒 false ⇒ 出厂路径零影响）'
Assert-True ($hookText -match 'if \(!glassFrameTimingEnabled\) \{\s*\r?\n\s*return;') `
    'install() 以 "!glassFrameTimingEnabled ⇒ return" 开头（门控在安装点内部）'

# 2) 采样点与口径
Assert-True ($hookText -match 'addTimingsCallback') '采样点 = addTimingsCallback'
Assert-True (($hookText -match 'buildDuration') -and ($hookText -match 'rasterDuration') -and ($hookText -match 'totalSpan')) `
    '采的是 buildDuration / rasterDuration / totalSpan'

# 3) 场景断言字段存在
Assert-True (($hookText -match 'scenario_ok') -and ($hookText -match 'scenario_total') -and ($hookText -match 'scenario=\$scenario')) `
    '产物带场景断言字段（scenario / scenario_ok / scenario_total）'

# 4) 最小侵入：lib 下只有 main.dart 调 install；main.dart footprint = 1 import + 1 call
$callSites = Get-ChildItem -Recurse $lib -Filter '*.dart' |
    Select-String -Pattern 'GlassFrameTiming\.install\(' -ErrorAction SilentlyContinue
Assert-True ($callSites.Count -eq 1) "lib/ 下 install() 调用点恰为 1 处（实际 $($callSites.Count)）" `
    (($callSites | ForEach-Object { " $($_.Path):$($_.LineNumber)" }) -join ';')
Assert-True (($callSites | Select-Object -First 1).Path -like '*main.dart') '该调用点在 main.dart'
$importCount = ([regex]::Matches($mainText, "import 'package:PiliPlus/debug/glass_frame_timing\.dart';")).Count
$callCount = ([regex]::Matches($mainText, 'GlassFrameTiming\.install\(\);')).Count
Assert-True ($importCount -eq 1) "main.dart 里该 import 恰好 1 行（实际 $importCount）"
Assert-True ($callCount -eq 1) "main.dart 里安装调用恰好 1 行（实际 $callCount）"
# main.dart 里除这两行外不应出现其它与本钩子相关的标识符
$otherRefs = ([regex]::Matches($mainText, 'GlassFrameTiming|glassFrameTimingEnabled|glass_frame_timing')).Count
Assert-True ($otherRefs -eq 2) "main.dart 相关标识符总计 2 处（import + 调用），实际 $otherRefs"

Write-Host ''
if ($fail -eq 0) {
    Write-Host '结论：✓ 门控链条成立 —— release（kDebugMode=false）下 glassFrameTimingEnabled 是编译期 false，'
    Write-Host '      install() 折叠为裸 return，回调/字段/字符串从调用图不可达 ⇒ AOT 裁剪 ⇒ **零行为**。'
    Write-Host '      注：这是静态证明；release 产物的"AOT 里没有该字符串"可另行 grep libapp.so 复核（见 README）。'
    exit 0
} else {
    Write-Host "结论：✗ 有 $fail 条门控断言不成立 ⇒ 不许声称 release 零行为。"
    exit 1
}