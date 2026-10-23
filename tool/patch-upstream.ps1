# SPDX-License-Identifier: GPL-3.0-or-later
<#
.SYNOPSIS
    复现 PiliPlus 上游的「SDK + material_ui 补丁」构建前置步骤（等价于上游 CI 的 lib/scripts/patch.ps1）。

.DESCRIPTION
    为什么必须打补丁（2026-10-02 实测结论）：
      PiliPlus 的 lib/common/widgets/** 里有大量「框架内部件的自有副本」，它们直接继承或引用
      Flutter 与 material_ui 的**内部符号**（RenderParagraph.textPainter、BottomSheetState、
      StandardBottomSheetState、TabBar 内部 state 等）。这些符号在官方稳定版里是私有的（下划线前缀），
      所以**未打补丁的环境下 flutter analyze 会报 118 个 error**，flutter build / flutter test 直接编译失败。
      上游的做法是构建前把补丁 git apply 到 Flutter SDK 与 pub 缓存里的 material_ui 包上，
      把这些内部符号 expose 出来（外加若干行为补丁）。

    与上游 patch.ps1 的差异（为什么不能直接跑上游脚本）：
      1. 上游把 pub 缓存路径写死为 hosted/pub.dev；本机走镜像源，包在 hosted/pub.flutter-io.cn，这里自动探测；
      2. 上游会写全局 git 身份（git config --global user.name ci），本脚本不碰全局配置；
      3. 本脚本额外提供 -Status（能力探测）与 -Revert（一键回滚）。

.PARAMETER Platform
    android（默认）或 windows。两者共用 21 个通用 SDK 补丁；android 额外需要 bottom_sheet_android / scroll_view / navigator。

.PARAMETER Status
    只做能力探测，不修改任何文件。

.PARAMETER Revert
    回滚：SDK 用 git 还原（要求 SDK 是干净 git 检出），material_ui / cupertino_ui 删目录（pub 会重新拉取）。

.EXAMPLE
    .\tool\patch-upstream.ps1 -Status
    .\tool\patch-upstream.ps1 -Platform windows
    .\tool\patch-upstream.ps1 -Revert
#>
param(
    [ValidateSet('android', 'windows')]
    [string]$Platform = 'android',
    [switch]$Status,
    [switch]$Revert
)

$ErrorActionPreference = 'Stop'
$app = Split-Path $PSScriptRoot -Parent
# 跨平台：git 在 Windows 本机是 PortableGit，CI 上就用 PATH 里的 git
$git = 'E:\dev\PortableGit\cmd\git.exe'
if (-not (Test-Path $git)) { $git = 'git' }
# 仓库内相对路径（统一用 /，Windows 与 Linux 都能解析）
function Get-AppPath([string]$rel) { Join-Path $app ($rel -replace '\\', '/') }

$flutterRoot = $env:FLUTTER_ROOT
if (-not $flutterRoot) { $flutterRoot = 'E:\dev\flutter' }
if (-not (Test-Path $flutterRoot)) { throw "找不到 Flutter SDK：$flutterRoot（先 . .\tool\dev-env.ps1）" }

# 与上游 lib/scripts/patch.ps1 保持同步（快照 2026-09-30）。上游改动那份文件时，这里要同步。
$CommonSdkPatches = @(
    'modal_barrier', 'text_selection', 'mouse_cursor', 'image_anim', 'layout_builder',
    'navigation_drawer', 'popup_menu', 'fab', 'null_safety_for_selectable_region',
    'selectable_region', 'editable_text', 'text_field', 'scroll_position', 'scrollable',
    'scrollable_gesture', 'draggable_scrollable_sheet', 'scaffold', 'text', 'text_painter',
    'sliver', 'refresh_indicator'
)
$PlatformSdkPatches = @{
    android = @('bottom_sheet_android', 'scroll_view', 'navigator')
    windows = @()
}
$CommonMaterialPatches = @(
    'modal_barrier_material', 'navigation_drawer', 'popup_menu', 'fab',
    'text_field', 'scaffold', 'refresh_indicator', 'tabs'
)
$PlatformMaterialPatches = @{
    android = @('bottom_sheet_android')
    windows = @()
}

$sdkPatches = $CommonSdkPatches + $PlatformSdkPatches[$Platform]
$materialPatches = $CommonMaterialPatches + $PlatformMaterialPatches[$Platform]

# --- pub 缓存定位（跨平台：Windows 用 %LOCALAPPDATA%\Pub\Cache，Linux/macOS 用 ~/.pub-cache；镜像 or 官方源）
$pubRoot = if ($env:PUB_CACHE) {
    $env:PUB_CACHE
} elseif ($IsWindows -or $env:OS -eq 'Windows_NT') {
    Join-Path $env:LOCALAPPDATA 'Pub\Cache'
} else {
    Join-Path $HOME '.pub-cache'
}
$hostedCandidates = @()
if ($env:PUB_HOSTED_URL) { $hostedCandidates += ($env:PUB_HOSTED_URL -replace '^https?://', '' -replace '/.*$', '') }
$hostedCandidates += @('pub.flutter-io.cn', 'pub.dev')
$pubCache = $null
foreach ($h in $hostedCandidates) {
    $cand = Join-Path $pubRoot "hosted\$h"
    if (Test-Path $cand) { $pubCache = $cand; break }
}
if (-not $pubCache) { $pubCache = Join-Path $pubRoot 'hosted\pub.dev' }

function Invoke-Git([string]$dir, [string[]]$gitArgs) {
    Push-Location $dir
    # 注意：git 把「补丁已应用」之类的失败信息写 stderr，而本脚本 EAP=Stop 时
    # 「2>&1 重定向 + 原生 stderr」会被 PowerShell 当成终止错误直接中断脚本。
    # 这里临时把 EAP 降级，只靠 $LASTEXITCODE 判断成败。
    $prevEap = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $out = & $git @gitArgs 2>&1 | Out-String
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $prevEap
        Pop-Location
    }
    return @{ Code = $code; Out = $out }
}

function Test-PatchApplied([string]$dir, [string]$patchPath) {
    return (Invoke-Git $dir @('apply', '--check', '--reverse', $patchPath)).Code -eq 0
}

function Get-MaterialDir {
    # 优先按构建真正使用的版本定位：从 .dart_tool/package_config.json 读 material_ui 的解析路径。
    # （pub 缓存里可能有多个版本——例如手动 `dart pub cache add` 拉下来对比过——按名字排序会选错。）
    $pkgConfig = Join-Path (Join-Path $app '.dart_tool') 'package_config.json'
    if (Test-Path $pkgConfig) {
        try {
            $cfg = Get-Content $pkgConfig -Raw -Encoding UTF8 | ConvertFrom-Json
            $entry = $cfg.packages | Where-Object { $_.name -eq 'material_ui' } | Select-Object -First 1
            if ($entry) {
                $uri = $entry.rootUri -replace '^file://', ''
                $uri = [System.Uri]::UnescapeDataString($uri)
                if ($IsWindows -or $env:OS -eq 'Windows_NT') { $uri = $uri -replace '/', '\' }
                if (Test-Path $uri) { return (Get-Item $uri) }
            }
        } catch { }
    }
    # 兜底：取版本号最大的一个
    Get-ChildItem $pubCache -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like 'material_ui-*' } |
        Sort-Object { [version]($_.Name -replace '^material_ui-', '') } |
        Select-Object -Last 1
}

# --- 能力探测：不看补丁计数，直接验证「内部符号是否已可见」
function Get-Capability {
    $sdkFile = Join-Path $flutterRoot 'packages/flutter/lib/src/rendering/paragraph.dart'
    $sdkOk = (Test-Path $sdkFile) -and
        [bool](Select-String -Path $sdkFile -Pattern 'TextPainter get textPainter' -Quiet)
    $matDir = Get-MaterialDir
    $matOk = $false
    $matProbe = '（未找到 material_ui）'
    if ($matDir) {
        $matFiles = Get-ChildItem $matDir.FullName -Recurse -Filter *.dart
        $matOk = [bool]($matFiles | Select-String -Pattern 'class StandardBottomSheetState[\s<{]' -Quiet)
        $matProbe = $matDir.Name
    }
    return [pscustomobject]@{ SdkOk = $sdkOk; MaterialOk = $matOk; MaterialProbe = $matProbe; MaterialDir = $matDir }
}

# ---------------------------------------------------------------- Status
if ($Status) {
    $cap = Get-Capability
    Write-Host "Flutter SDK : $flutterRoot"
    Write-Host "pub 缓存    : $pubCache"
    $sdkApplied = ($sdkPatches | Where-Object { Test-PatchApplied $flutterRoot (Get-AppPath "lib\scripts\$_.patch") }).Count
    Write-Host ("SDK 补丁    : {0}/{1} 可反向校验通过" -f $sdkApplied, $sdkPatches.Count)
    if ($cap.SdkOk) {
        Write-Host "  [OK] 能力探测：SDK 已暴露 RenderParagraph.textPainter" -ForegroundColor Green
    } else {
        Write-Host "  [!!] 能力探测：SDK 未暴露 textPainter → 未打补丁，flutter analyze 会报 118 error" -ForegroundColor Red
    }
    if ($cap.MaterialOk) {
        Write-Host "  [OK] 能力探测：$($cap.MaterialProbe) 已暴露 StandardBottomSheetState" -ForegroundColor Green
    } else {
        Write-Host "  [!!] 能力探测：$($cap.MaterialProbe) 未暴露内部符号 → 需打 material 补丁" -ForegroundColor Red
    }
    Write-Host "`n（补丁计数仅供参考：多个补丁改动同一处时，单独反向校验会失败，属正常。）"
    exit 0
}

# ---------------------------------------------------------------- Revert
if ($Revert) {
    Write-Host "回滚 Flutter SDK（git 还原）..."
    $r = Invoke-Git $flutterRoot @('checkout', '--', '.')
    if ($r.Code -ne 0) { throw "SDK 回滚失败，需 $flutterRoot 是 git 检出：$($r.Out)" }
    Get-ChildItem $pubCache -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like 'material_ui-*' -or $_.Name -like 'cupertino_ui-*' } |
        ForEach-Object {
            Remove-Item $_.FullName -Recurse -Force
            Write-Host "  已删除 $($_.Name)（下次 pub get 重新拉取干净副本）"
        }
    Write-Host "回滚完成" -ForegroundColor Green
    exit 0
}

# ---------------------------------------------------------------- Apply
$failed = @()

Write-Host "== Flutter SDK 补丁（$($sdkPatches.Count) 个，平台 $Platform）==" -ForegroundColor Cyan
foreach ($n in $sdkPatches) {
    $p = Get-AppPath "lib\scripts\$n.patch"
    $res = Invoke-Git $flutterRoot @('apply', $p)
    if ($res.Code -eq 0) { Write-Host "  + $n"; continue }
    if (Test-PatchApplied $flutterRoot $p) { Write-Host "  = $n（已应用）"; continue }
    Write-Host "  x $n 失败" -ForegroundColor Red
    $failed += $n
}

Write-Host "== material_ui 补丁（$($materialPatches.Count) 个）==" -ForegroundColor Cyan
$matDir = Get-MaterialDir
if (-not $matDir) { throw "pub 缓存里找不到 material_ui，请先执行 flutter pub get。查找路径：$pubCache" }
Write-Host "  目标：$($matDir.Name)"
foreach ($n in $materialPatches) {
    $p = Get-AppPath "lib\scripts\material\$n.patch"
    $res = Invoke-Git $matDir.FullName @('apply', $p)
    if ($res.Code -eq 0) { Write-Host "  + $n"; continue }
    if (Test-PatchApplied $matDir.FullName $p) { Write-Host "  = $n（已应用）"; continue }
    Write-Host "  x $n 失败" -ForegroundColor Red
    $failed += "material/$n"
}

Write-Host ""
if ($failed.Count) {
    Write-Host "有 $($failed.Count) 个补丁失败：$($failed -join ', ')" -ForegroundColor Red
    Write-Host "多半是上游更新了补丁、或 Flutter 版本漂移（本机应锁 3.47.5）。" -ForegroundColor Yellow
    exit 1
}
$cap = Get-Capability
if ($cap.SdkOk -and $cap.MaterialOk) {
    Write-Host "补丁全部就位，能力探测通过" -ForegroundColor Green
} else {
    Write-Host "补丁已应用但能力探测未通过（SDK=$($cap.SdkOk) material=$($cap.MaterialOk)），请检查。" -ForegroundColor Yellow
}
Write-Host "回滚：.\tool\patch-upstream.ps1 -Revert" -ForegroundColor DarkGray
Write-Host "注意：补丁打在 SDK 与 pub 缓存上，flutter upgrade / fvm 重装 / 删缓存都会丢失，需重跑本脚本。" -ForegroundColor Yellow
Write-Host "构建请加 --no-pub，避免 pub get 覆盖被补丁过的包。" -ForegroundColor Yellow