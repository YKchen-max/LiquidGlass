# SPDX-License-Identifier: GPL-3.0-or-later
<#
.SYNOPSIS
    弹幕 × 玻璃合成性能压测（排期 #13）—— 一键跑完「玻璃控制条 vs 纯色控制条」的帧时序对比。

.DESCRIPTION
    为什么需要这个脚本：排期 #13 是"玻璃能不能和全屏弹幕同屏"的性能战，没有可重复的度量
    手段就无法判定"优化到底有没有用"。本脚本把四件事串成一条命令：

        构建压测页（poc/glass_poc/lib/main_danmaku_bench.dart）
          → 分别以「玻璃控制条 / 纯色控制条」启动（同一套视频动画 + 同一屏弹幕量）
          → 从进程 stdout 抓 Dart VM Service URI
          → 把窗口拉回前台（并持续断言），用 app/tool/measure_fps.py 各采一轮
          → 输出对比表 + 原始 JSON + 证据截图

    被测负载（两档完全一致，只有控制条的渲染档不同）：
        * 视频区：持续变换的本地图片动画（代替真视频外部纹理，必须持续产帧）
        * 弹幕层：自绘 + RepaintBoundary 隔离，同屏条数恒定（默认 200 条 / 发射 20 条/秒）
        * 控制条：LiquidGlassSurface(capability: fakeGlass | solid)

    采样口径与三个已知坑（见 docs/基线数据.md §3、docs/性能压测.md）：
        1. Dart VM Service 只接受 WebSocket（measure_fps.py 已处理）；
        2. 时间线是环形缓冲，单次快照只覆盖最近几秒 → --samples 多次快照取并集；
        3. 帧率高于刷新率 ⇒ 窗口被遮挡/未按 vsync 节流，数据不可当流畅度用 —— 本脚本
           会把窗口置顶并**持续断言前台**，同时把 measure_fps.py 的遮挡自检结果如实抄进报告。

    产物（默认落在 .probe/bench-13/<时间戳>/，该目录不入库）：
        app-<cfg>-<n>.out.log / .err.log   压测页 stdout（含 VM Service URI、参数回显、负载回显）
        fps-<cfg>-<n>.json                 measure_fps.py 的报告（原始数据）
        fps-<cfg>-<n>.txt / .err.txt       工具的完整输出（含遮挡自检）
        shot-<cfg>-<n>-before.png / -during.png   采样前 / 采样进行中的证据截图
        bench-summary.json / bench-summary.md     本次运行的对比表

.PARAMETER Mode
    both（默认）/ glass / solid：测哪几档。

.PARAMETER Runs
    每档轮数（默认 2）。**轮间极差就是本脚本用来判断"差异是否显著"的噪声带**，
    所以至少 2 轮才有意义。

.PARAMETER Seconds / Samples
    传给 measure_fps.py 的采样窗口与快照次数（默认 15 秒 / 4 次）。

.PARAMETER Danmaku / Rate / Seed
    压测页负载：同屏弹幕条数（默认 200）、发射频率条/秒（默认 20）、确定性种子。
    两档跑的是同一组参数，保证负载相同。

.PARAMETER Configuration
    debug（默认，构建快）/ profile（更接近真实性能，全量构建约 7 分钟）。

.PARAMETER SkipBuild
    跳过构建，直接用已有产物（换负载参数时无需重建 —— 负载是运行期命令行参数）。

.PARAMETER OutDir
    产物目录，默认 .probe/bench-13/<yyyyMMdd-HHmmss>。

.EXAMPLE
    . .\dev-env.ps1
    .\bench_suite.ps1
    .\bench_suite.ps1 -Mode glass -Runs 3 -Seconds 20
    .\bench_suite.ps1 -SkipBuild -Configuration profile -Danmaku 300 -Rate 30
#>
[CmdletBinding()]
param(
    [ValidateSet('both', 'glass', 'solid')][string]$Mode = 'both',
    [int]$Runs = 2,
    [double]$Seconds = 15,
    # 快照次数：**默认 30 而不是工具的默认 4**，这是实测出来的（见 docs/性能压测.md §4 坑 2）：
    # 稀疏快照（15s / 4 次）会在并集里留下 2~3 个 1.7~2.6 秒的**假长帧**（环形缓冲取不到的部分），
    # 结果 max 假到 2605ms、聚合 FPS 被低估近一半（178 → 实测 322）；30 次快照后 max 降到 ~30ms、
    # 窗口连续。注意：快照变密会让实际采样窗口超过 --seconds（每次 RPC 自身约 0.6s），以工具的"挂钟"为准。
    [int]$Samples = 30,
    # 前台占比低于它的轮次会被判为"被外部抢了前台"（同时抬高 P99），排除出汇总与判定
    [double]$MinForegroundPct = 95,
    [int]$Danmaku = 200,
    [double]$Rate = 20,
    [int]$Seed = 20261003,
    [ValidateSet('debug', 'profile')][string]$Configuration = 'debug',
    [switch]$SkipBuild,
    [double]$RefreshHz = 165,
    [int]$SettleSeconds = 8,
    [string]$OutDir,
    [switch]$KeepWindow,
    [switch]$MidShot,

    # 互斥锁：采样的那几十秒里**任何并发构建都会污染帧时序**（CPU 抢占 → 尾部变差 → 结论反向），
    # 所以默认先拿 .probe/build-lock.ps1：拿不到就阻塞等待，绝不绕过（见脚本 §.DESCRIPTION 的说明）。
    [string]$LockOwner = 'perf-harness',
    [int]$LockTimeoutSec = 1800,
    [switch]$NoLock,    # 调用方已持有同一把锁时用（脚本里重复 Acquire 会阻塞到超时）
    # 采样顺序：fixed = 每档连续跑完（既有行为，但**是已知伪影来源**：臂内任何单调趋势
    # 都会单方面压低后跑的那档）；alternate = 两遍相反顺序（需 -Runs 为偶数），
    # 使每档各有一半轮次处于"先跑"与"后跑"，从而抵消该伪影。见 docs/性能压测.md §9.5.5。
    [ValidateSet('fixed', 'alternate')][string]$Order = 'fixed',
    # 压测页入口：默认沿用弹幕压测页；多块玻璃等场景可指向自己的页面（默认值下行为与之前一致）
    [string]$Target = 'lib\main_danmaku_bench.dart',
    # 按档位注入子进程环境变量（只影响 Start-Process 起的子进程，跑完还原）。
    # 用途：让两臂在同一会话内交替，避免把会话漂移误判成臂差。
    [hashtable]$EnvGlass = @{},
    [hashtable]$EnvSolid = @{}
)

$ErrorActionPreference = 'Stop'

# ── 路径与前置 ────────────────────────────────────────────────────────
$root      = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent   # app/tool → 仓库根
$pocDir    = Join-Path $root 'poc\glass_poc'
$target    = $Target
$cfgDir    = if ($Configuration -eq 'debug') { 'Debug' } else { 'Profile' }
$exe       = Join-Path $pocDir "build\windows\x64\runner\$cfgDir\glass_poc.exe"
$measure   = Join-Path $PSScriptRoot 'measure_fps.py'
$devEnv    = Join-Path $PSScriptRoot 'dev-env.ps1'
$lockScript = Join-Path $root '.probe\build-lock.ps1'
$flutter   = if (Test-Path 'E:\dev\flutter\bin\flutter.bat') { 'E:\dev\flutter\bin\flutter.bat' } else { 'flutter' }

if (-not $OutDir) {
    $OutDir = Join-Path $root ('.probe\bench-13\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
$OutDir = (Resolve-Path $OutDir).Path

foreach ($need in @($measure, (Join-Path $pocDir $target))) {
    if (-not (Test-Path $need)) { throw "缺少文件：$need" }
}
$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) { throw 'PATH 里找不到 python（measure_fps.py 需要 python + websocket-client）' }
$pythonExe = if ($python.Source -and (Test-Path $python.Source)) { $python.Source } else { 'python' }

# dev-env.ps1 注入镜像与 github 代理（构建期需要）；dot-source 才能影响本进程与其子进程
if (Test-Path $devEnv) { . $devEnv }

# ── Win32 助手（前台断言 / 置顶 / 截图）───────────────────────────────
# PrintWindow(hwnd, hdc, 2) = PW_RENDERFULLCONTENT，之前 #8 就是用它截的 Flutter 窗口。
Add-Type -AssemblyName System.Drawing
if (-not ('BenchWin32' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class BenchWin32 {
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdc, uint flags);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, IntPtr pid);
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool attach);
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
}
'@
}

# 本进程若不声明 DPI 感知，GetWindowRect 会返回**虚拟化**尺寸（本机 150% 缩放 → 1280×720），
# 于是 PrintWindow 只画进左上角那一块，把底部控制条裁掉（实测过一次，截图看着"页面没问题"
# 其实少了一整条被测对象）。实测 SetProcessDPIAware() 后窗口尺寸回到物理像素 1920×1080，
# 截图才完整。必须在使用任何 USER32 坐标前调用。
[void][BenchWin32]::SetProcessDPIAware()
$HWND_TOPMOST   = [IntPtr](-1)
$HWND_NOTOPMOST = [IntPtr](-2)
$SWP_FLAGS      = 0x0001 -bor 0x0002 -bor 0x0010   # NOSIZE | NOMOVE | NOACTIVATE
$SW_RESTORE     = 9

function Read-TextShared {
    param([string]$Path)
    try {
        $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8)
        $t = $sr.ReadToEnd(); $sr.Dispose(); $fs.Dispose()
        return $t
    } catch { return '' }
}

function Set-BenchForeground {
    param([IntPtr]$Hwnd)
    if ([BenchWin32]::IsIconic($Hwnd)) { [void][BenchWin32]::ShowWindow($Hwnd, $SW_RESTORE) }
    [void][BenchWin32]::BringWindowToTop($Hwnd)
    if ([BenchWin32]::GetForegroundWindow() -eq $Hwnd) { return $true }
    # 前台锁：把自己和当前前台窗口的输入队列临时挂到一起，SetForegroundWindow 才会生效
    $fg = [BenchWin32]::GetForegroundWindow()
    $fgThread = [BenchWin32]::GetWindowThreadProcessId($fg, [IntPtr]::Zero)
    $me = [BenchWin32]::GetCurrentThreadId()
    [void][BenchWin32]::AttachThreadInput($me, $fgThread, $true)
    $ok = [BenchWin32]::SetForegroundWindow($Hwnd)
    [void][BenchWin32]::AttachThreadInput($me, $fgThread, $false)
    return $ok
}

function Save-BenchScreenshot {
    param([IntPtr]$Hwnd, [string]$Path)
    $r = New-Object BenchWin32+RECT
    if (-not [BenchWin32]::GetWindowRect($Hwnd, [ref]$r)) { return $false }
    $w = $r.Right - $r.Left; $h = $r.Bottom - $r.Top
    if ($w -le 0 -or $h -le 0) { return $false }
    try {
        $bmp = New-Object System.Drawing.Bitmap $w, $h
        $gfx = [System.Drawing.Graphics]::FromImage($bmp)
        $hdc = $gfx.GetHdc()
        $ok = [BenchWin32]::PrintWindow($Hwnd, $hdc, 2)
        $gfx.ReleaseHdc($hdc); $gfx.Dispose()
        $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
        return $ok
    } catch {
        Write-Warning "截图失败：$($_.Exception.Message)"
        return $false
    }
}

# ── 构建 + 采样（全程持互斥锁）────────────────────────────────────────
$configs = switch ($Mode) { 'both' { @('glass', 'solid') } 'glass' { @('glass') } 'solid' { @('solid') } }
$suiteSw = [System.Diagnostics.Stopwatch]::StartNew()
$prevImpeller = $env:POC_IMPELLER
$lockHeld = $false
$useLock = (-not $NoLock) -and (Test-Path $lockScript)
$rows = @()

try {
    # 0) 互斥锁：构建 + 采样整段持有，避免别的队友在这几十秒里插一个 flutter build 进来
    if ($useLock) {
        Write-Host "[suite] 拿构建/采样互斥锁（owner=$LockOwner，最多等 $LockTimeoutSec 秒）…" -ForegroundColor Cyan
        & $lockScript -Acquire -Owner $LockOwner -Purpose "bench_suite 压测（$Configuration/$Mode/$Runs 轮）" -TimeoutSec $LockTimeoutSec
        if ($LASTEXITCODE -ne 0) {
            throw "拿不到互斥锁（exit $LASTEXITCODE）。不要绕过锁硬跑：并发构建会污染帧时序数据（拿锁：& $lockScript -Status）"
        }
        $lockHeld = $true
    } elseif ($NoLock) {
        Write-Host '[suite] -NoLock：假定调用方已持有互斥锁，本轮不做排他保证' -ForegroundColor DarkGray
    } else {
        Write-Host "[suite] 找不到 $lockScript，跳过互斥锁（并发构建会污染数据）" -ForegroundColor Yellow
    }

    # 1) 构建
    if (-not $SkipBuild) {
        Write-Host "[suite] 构建 $Configuration 压测页（target $target）…" -ForegroundColor Cyan
        $buildSw = [System.Diagnostics.Stopwatch]::StartNew()
        Push-Location $pocDir
        $prevEap = $ErrorActionPreference
        try {
            # Windows PowerShell 5.1 的经典坑：flutter.bat 会往 **stderr** 写
            # "Flutter assets will be downloaded from …"，在 $ErrorActionPreference='Stop'
            # 且做了 2>&1 合并时，PowerShell 会把这行 stderr 当成 NativeCommandError 终止错误，
            # 于是构建还没开始就整段退出（实测踩到一次）。这里临时降级为 Continue，只认退出码。
            $ErrorActionPreference = 'Continue'
            & $flutter build windows "--$Configuration" --target $target *>&1 |
                Out-File -FilePath (Join-Path $OutDir 'build.log') -Encoding utf8
            $buildCode = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $prevEap
            Pop-Location
        }
        $buildSw.Stop()
        Get-Content (Join-Path $OutDir 'build.log') -Tail 6 | ForEach-Object { "         $_" }
        if ($buildCode -ne 0) { throw "flutter build 失败（exit $buildCode），完整日志：$OutDir\build.log" }
        Write-Host ("[suite] 构建完成，用时 {0:N1} 秒" -f $buildSw.Elapsed.TotalSeconds) -ForegroundColor Green
    }
    if (-not (Test-Path $exe)) { throw "找不到产物 $exe（先去掉 -SkipBuild 构建一次）" }

    $env:POC_IMPELLER = '0'   # Windows v1 的既定路线：Skia（见 docs/Impeller实测结论.md）
    $env:PYTHONIOENCODING = 'utf-8'

    # 2) 构建采样序列（-Order alternate 时：两遍相反顺序，每档各占一半轮次）
    if ($Order -eq 'alternate' -and $configs.Count -gt 1 -and ($Runs % 2) -ne 0) {
        throw '-Order alternate 需要 -Runs 为偶数（每遍跑一半轮次，两遍顺序相反）'
    }
    if ($Order -eq 'fixed' -and $configs.Count -gt 1) {
        Write-Warning ('-Order fixed：每档连续跑完。固定顺序是**已知伪影来源**' +
                       '（臂内单调趋势会单方面压低后跑的档；实测 P99 放大约 35%、吞吐约 50%）。' +
                       '要抵消请用 -Order alternate（-Runs 为偶数）。')
    }
    $sequence = @()
    if ($Order -eq 'alternate' -and $configs.Count -gt 1) {
        $half = [int]($Runs / 2)
        $counter = @{}
        $reversed = @($configs[($configs.Count - 1)..0])
        foreach ($pass in @(, $configs) + @(, $reversed)) {
            foreach ($cfg in $pass) {
                for ($i = 1; $i -le $half; $i++) {
                    $counter[$cfg] = 1 + [int]$counter[$cfg]     # 轮号唯一，文件名不冲突
                    $sequence += , @{ cfg = $cfg; run = $counter[$cfg] }
                }
            }
        }
    } else {
        foreach ($cfg in $configs) {
            for ($i = 1; $i -le $Runs; $i++) { $sequence += , @{ cfg = $cfg; run = $i } }
        }
    }

    # 3) 逐轮采样（内层 for 固定只跑一次：结构与原实现一致，便于最小化改动）
    foreach ($item in $sequence) {
        $cfg = $item.cfg
        $label = if ($cfg -eq 'glass') { '玻璃控制条' } else { '纯色控制条' }
        for ($run = $item.run; $run -le $item.run; $run++) {
            $tag    = "$cfg-$run"
            $logOut = Join-Path $OutDir "app-$tag.out.log"
            $logErr = Join-Path $OutDir "app-$tag.err.log"
            $pyOut  = Join-Path $OutDir "fps-$tag.txt"
            $pyErr  = Join-Path $OutDir "fps-$tag.err.txt"
            $json   = Join-Path $OutDir "fps-$tag.json"
            Write-Host "[suite] [$tag] 启动压测页（$label，同屏 $Danmaku 条 / $Rate 条每秒）…" -ForegroundColor Cyan

            $appArgs = @("--bench-mode=$cfg", "--bench-danmaku=$Danmaku",
                         "--bench-rate=$Rate", "--bench-seed=$Seed")
            # 按档位注入环境变量（Process 作用域 + finally 还原 ⇒ 只影响本次子进程）
            $envForTier = if ($cfg -eq 'glass') { $EnvGlass } else { $EnvSolid }
            $savedEnv = @{}
            foreach ($k in @($envForTier.Keys)) {
                $savedEnv[$k] = [System.Environment]::GetEnvironmentVariable($k, 'Process')
                [System.Environment]::SetEnvironmentVariable($k, [string]$envForTier[$k], 'Process')
                Write-Host "[suite] [$tag] env $k=$($envForTier[$k])" -ForegroundColor DarkGray
            }
            try {
                $proc = Start-Process -FilePath $exe -ArgumentList $appArgs `
                    -WorkingDirectory (Split-Path $exe -Parent) `
                    -RedirectStandardOutput $logOut -RedirectStandardError $logErr -PassThru
            } finally {
                foreach ($k in @($savedEnv.Keys)) {
                    [System.Environment]::SetEnvironmentVariable($k, $savedEnv[$k], 'Process')
                }
            }

            # 1) 抓 VM Service URI（已确认 Dart VM Service 只走 WebSocket，measure_fps.py 会转 ws://）
            $uri = $null
            $uriSw = [System.Diagnostics.Stopwatch]::StartNew()
            while ($uriSw.Elapsed.TotalSeconds -lt 60) {
                $text = Read-TextShared $logOut
                if ($text -match 'http://127\.0\.0\.1:\d+/[A-Za-z0-9_\-]+=/') { $uri = $Matches[0]; break }
                if ($proc.HasExited) { break }
                Start-Sleep -Milliseconds 300
            }
            if (-not $uri) {
                Write-Warning "[$tag] 60 秒内没抓到 VM Service URI（进程已退出=$($proc.HasExited)），跳过本轮；看 $logOut"
                if (-not $proc.HasExited) { $proc.Kill() }
                continue
            }
            Write-Host "          VM Service: $uri"

            # 2) 等窗口出现并置前台 + 置顶（防遮挡：帧率高于刷新率就意味着数据不能当流畅度用）
            $hwnd = [IntPtr]::Zero
            $winSw = [System.Diagnostics.Stopwatch]::StartNew()
            while ($winSw.Elapsed.TotalSeconds -lt 40) {
                $proc.Refresh()
                if ($proc.HasExited) { break }
                if ($proc.MainWindowHandle -ne [IntPtr]::Zero -and [BenchWin32]::IsWindowVisible($proc.MainWindowHandle)) {
                    $hwnd = $proc.MainWindowHandle; break
                }
                Start-Sleep -Milliseconds 250
            }
            if ($hwnd -eq [IntPtr]::Zero) {
                Write-Warning "[$tag] 没拿到窗口句柄，跳过本轮"
                if (-not $proc.HasExited) { $proc.Kill() }
                continue
            }
            [void](Set-BenchForeground $hwnd)
            [void][BenchWin32]::SetWindowPos($hwnd, $HWND_TOPMOST, 0, 0, 0, 0, $SWP_FLAGS)

            # 3) 等稳态：压测页打印 ready 之后再留 settle 秒（debug 的 JIT 预热 + 首帧布局）
            $readySw = [System.Diagnostics.Stopwatch]::StartNew()
            while ($readySw.Elapsed.TotalSeconds -lt 20) {
                if ((Read-TextShared $logOut) -match '\[bench\] ready') { break }
                Start-Sleep -Milliseconds 200
            }
            Start-Sleep -Seconds $SettleSeconds
            [void](Set-BenchForeground $hwnd)

            # 4) 回显核对：确认这一轮真的跑在指定的档位与负载上
            $appText = Read-TextShared $logOut
            if ($appText -notmatch "\[bench\] config bar=$cfg") {
                Write-Warning "[$tag] 压测页回显的档位与请求不一致，务必人工核对 $logOut"
            }
            $fieldLine = ''
            if ($appText -match '\[bench\] field [^\r\n]*') { $fieldLine = $Matches[0] }
            $viewLine = ''
            if ($appText -match '\[bench\] view [^\r\n]*') { $viewLine = $Matches[0] }
            Write-Host "          $viewLine"
            Write-Host "          $fieldLine"

            # 采样前留证截图：必须在 python 清空时间线**之前**完成，否则它的停顿会落进采样窗口
            [void](Save-BenchScreenshot -Hwnd $hwnd -Path (Join-Path $OutDir "shot-$tag-before.png"))

            # 5) 前台稳定等待：别的线（构建/截图/起 App）可能正好在这时抢前台。实测有两轮开局被抢
            #    到过 70%/84% 前台，P99 立刻从 5.9ms 恶化到 19.7ms。所以要求"连续 1.5 秒都在前台"
            #    才开始采样；等不到就照采并让前台占比把该轮标成不可比（不假装数据干净）。
            $stable = 0
            $stabSw = [System.Diagnostics.Stopwatch]::StartNew()
            while ($stable -lt 6 -and $stabSw.Elapsed.TotalSeconds -lt 15) {
                if ([BenchWin32]::GetForegroundWindow() -eq $hwnd) { $stable++ }
                else { $stable = 0; [void](Set-BenchForeground $hwnd) }
                Start-Sleep -Milliseconds 250
            }
            if ($stable -lt 6) { Write-Warning "[$tag] 前台迟迟不稳定（别的程序在抢），本轮很可能被污染" }

            # 6) 采样：python 在后台跑，本进程持续断言前台（窗口一被遮挡，数字就不是流畅度了）
            $pyArgs = @($measure, '--vm-service', $uri, '--seconds', $Seconds,
                        '--samples', $Samples, '--refresh-hz', $RefreshHz,
                        '--label', $label, '--json', $json)
            $py = Start-Process -FilePath $pythonExe -ArgumentList $pyArgs -NoNewWindow `
                -RedirectStandardOutput $pyOut -RedirectStandardError $pyErr -PassThru

            $fgHits = 0; $fgChecks = 0; $shotDuring = $false
            $sampleSw = [System.Diagnostics.Stopwatch]::StartNew()
            while ($true) {
                $py.Refresh()
                if ($py.HasExited) { break }
                $fgChecks++
                if ([BenchWin32]::GetForegroundWindow() -eq $hwnd) { $fgHits++ }
                else { [void](Set-BenchForeground $hwnd) }
                # 实测教训：PrintWindow 会让被采样进程停一帧以上（把该轮最大帧间隔拉到 ~1.2 秒），
                # 所以默认**不在采样窗口内截图**；要留"采样进行中"的证据时加 -MidShot，
                # 此时报告会标注该轮的尾部数据不可比。
                if ($MidShot -and -not $shotDuring -and $sampleSw.Elapsed.TotalSeconds -ge ($Seconds * 0.5)) {
                    [void](Save-BenchScreenshot -Hwnd $hwnd -Path (Join-Path $OutDir "shot-$tag-during.png"))
                    $shotDuring = $true
                }
                Start-Sleep -Milliseconds 250
            }
            $py.WaitForExit()
            $sampleSw.Stop()
            $fgRatio = if ($fgChecks -gt 0) { [math]::Round(100.0 * $fgHits / $fgChecks, 1) } else { 0 }

            # 采样后留证截图（证明采样期间窗口一直在渲染；同样不落在采样窗口内）
            [void](Save-BenchScreenshot -Hwnd $hwnd -Path (Join-Path $OutDir "shot-$tag-after.png"))

            # 坑：Start-Process -PassThru 的 Process 对象有时取不到 ExitCode（$null），
            # 而 PowerShell 里 `$null -ne 0` 为 **真** —— 判成功只能以 JSON 是否产出为准。
            $pyCode = $null
            try { if ($py.HasExited) { $pyCode = $py.ExitCode } } catch { $pyCode = $null }
            if (-not (Test-Path $json)) {
                Write-Warning "[$tag] measure_fps.py 没产出 JSON（exit=$(if ($null -eq $pyCode) { 'n/a' } else { $pyCode })）；看 $pyOut / $pyErr"
                if (-not $KeepWindow) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
                continue
            }
            if ($null -ne $pyCode -and $pyCode -ne 0) {
                Write-Warning "[$tag] measure_fps.py 退出码 $pyCode（JSON 已产出，照常采用）"
            }

            $rep = Get-Content $json -Raw -Encoding UTF8 | ConvertFrom-Json
            $rows += [pscustomobject]@{
                config    = $cfg
                label     = $label
                run       = $run
                uri       = $uri
                frames    = [int]$rep.frames
                spanS     = [double]$rep.span_s
                fps       = [double]$rep.fps
                median    = [double]$rep.frame_interval_ms.median
                p90       = [double]$rep.frame_interval_ms.p90
                p99       = [double]$rep.frame_interval_ms.p99
                max       = [double]$rep.frame_interval_ms.max
                totalP90  = if ($rep.frame_total_ms.p90) { [double]$rep.frame_total_ms.p90 } else { $null }
                janky     = if ($rep.janky_ratio -ne $null) { [double]$rep.janky_ratio } else { $null }
                occluded  = [bool]$rep.suspected_occluded_or_unthrottled
                valid     = [bool]$rep.valid_as_smoothness_metric
                fgRatio   = $fgRatio
                sampleS   = [math]::Round($sampleSw.Elapsed.TotalSeconds, 1)
                midShot   = [bool]$shotDuring
                pyCode    = $pyCode
                field     = $fieldLine
                view      = $viewLine
                json      = $json
            }
            Write-Host ("          [$tag] 帧 {0} / 窗口 {1:N2}s / 帧间隔中位 {2:N2}ms / P90 {3:N2}ms / 前台占比 {4}% / 遮挡自检 {5}" -f `
                $rep.frames, $rep.span_s, $rep.frame_interval_ms.median, $rep.frame_interval_ms.p90, $fgRatio,
                $(if ($rep.suspected_occluded_or_unthrottled) { '⚠ 未节流' } else { 'OK' })) `
                -ForegroundColor $(if ($rep.suspected_occluded_or_unthrottled) { 'Yellow' } else { 'Gray' })

            # 6) 收尾：撤置顶并正常关窗（下一轮从干净进程开始，所以轮间差异就是"启动噪声"）
            [void][BenchWin32]::SetWindowPos($hwnd, $HWND_NOTOPMOST, 0, 0, 0, 0, $SWP_FLAGS)
            if (-not $KeepWindow) {
                $proc.Refresh()
                if (-not $proc.HasExited) {
                    [void]$proc.CloseMainWindow()
                    if (-not $proc.WaitForExit(5000)) { $proc.Kill() }
                }
            } else {
                Write-Host "[suite] -KeepWindow：压测页保持打开（按 G / S 可人工切档对比）" -ForegroundColor DarkGray
            }
        }
    }
} finally {
    # 无论采样成功、失败还是抛异常，都要把锁还回去（否则别人要等到超时）
    if ($lockHeld) { & $lockScript -Release -Owner $LockOwner }
    if ($null -eq $prevImpeller) { Remove-Item Env:POC_IMPELLER -ErrorAction SilentlyContinue }
    else { $env:POC_IMPELLER = $prevImpeller }
}

if ($rows.Count -eq 0) { throw "一轮都没采到数据，看 $OutDir 下的 app-*.log" }

# ── 汇总：对比表 + 显著性判断 ─────────────────────────────────────────
function Get-Stat {
    param([double[]]$Values)
    $m = $Values | Measure-Object -Average -Minimum -Maximum
    return [pscustomobject]@{
        mean = [math]::Round($m.Average, 2)
        min  = [math]::Round($m.Minimum, 2)
        max  = [math]::Round($m.Maximum, 2)
        range = [math]::Round($m.Maximum - $m.Minimum, 2)
    }
}

$perConfig = @{}
# 前台占比不达标的轮次先排除：外部程序抢前台会同时抬高 P99 与中位数，混进来会污染判定
$excludedRows = @($rows | Where-Object { $_.fgRatio -lt $MinForegroundPct })
$cmpRows = @($rows | Where-Object { $_.fgRatio -ge $MinForegroundPct })
if ($excludedRows.Count -gt 0) {
    Write-Warning ("有 {0} 轮因前台占比 <{1}% 被排除出汇总与判定：{2}" -f `
        $excludedRows.Count, $MinForegroundPct,
        (($excludedRows | ForEach-Object { "$($_.config)-$($_.run)($($_.fgRatio)%)" }) -join ', '))
}
if ($cmpRows.Count -eq 0) { $cmpRows = $rows; Write-Warning '所有轮次前台占比都不达标，退回用全部轮次汇总（结论不可信）' }
foreach ($cfg in ($cmpRows | Select-Object -ExpandProperty config | Sort-Object -Unique)) {
    $subset = @($cmpRows | Where-Object { $_.config -eq $cfg })
    $perConfig[$cfg] = [pscustomobject]@{
        label       = $subset[0].label
        rounds      = $subset.Count
        median      = Get-Stat (@($subset | ForEach-Object { $_.median }))
        p90         = Get-Stat (@($subset | ForEach-Object { $_.p90 }))
        fps         = Get-Stat (@($subset | ForEach-Object { $_.fps }))
        allValid    = -not ($subset | Where-Object { -not $_.valid })
        minFgRatio  = ($subset | Measure-Object -Property fgRatio -Minimum).Minimum
    }
}

$verdict = '只有一档数据，无法对比'
if ($perConfig.ContainsKey('glass') -and $perConfig.ContainsKey('solid')) {
    $g = $perConfig['glass']; $s = $perConfig['solid']
    $gap = [math]::Round([math]::Abs($g.median.mean - $s.median.mean), 2)
    $noise = [math]::Max($g.median.range, $s.median.range)
    if ($g.rounds -lt 2 -or $s.rounds -lt 2) {
        $verdict = "轮数不足 2，没有轮间噪声带，不能判定显著性（中位差 $gap ms）"
    } elseif ($gap -gt $noise) {
        $verdict = "帧间隔中位数差 $gap ms > 轮间极差 $noise ms → **差异显著**"
    } else {
        $verdict = "帧间隔中位数差 $gap ms ≤ 轮间极差 $noise ms → **差异不显著（落在噪声内）**"
    }
    if ($g.minFgRatio -lt 100 -or $s.minFgRatio -lt 100) {
        $verdict += "；注意：参与汇总的轮次里最低前台占比 $([math]::Min($g.minFgRatio, $s.minFgRatio))%，该轮仍可能有轻微外部干扰"
    }
    if ($excludedRows.Count -gt 0) {
        $verdict += "；已排除 $($excludedRows.Count) 轮前台占比 <$MinForegroundPct% 的轮次（明细表标了 ⚠）"
    }
    if (-not $g.allValid -or -not $s.allValid) {
        $verdict += '；⚠ 有轮次被 measure_fps.py 判为"未按 vsync 节流"，该轮数字只能读作引擎帧产出能力'
    }
}

$tableLines = @()
$tableLines += '| 配置 | 轮次 | 帧数 | 有效窗口(s) | 聚合FPS | 帧间隔中位(ms) | 帧间隔P90(ms) | 帧间隔P99(ms) | 帧总耗时P90(ms) | 超预算帧占比 | 前台占比 | 遮挡自检 |'
$tableLines += '|---|---|---|---|---|---|---|---|---|---|---|---|'
foreach ($r in $rows) {
    $fgText = if ($r.fgRatio -lt $MinForegroundPct) { '{0}% ⚠排除' -f $r.fgRatio } else { '{0}%' -f $r.fgRatio }
    $tableLines += ('| {0} | {1} | {2} | {3:N2} | {4:N1} | {5:N2} | {6:N2} | {7:N2} | {8} | {9} | {10} | {11} |' -f `
        $r.label, $r.run, $r.frames, $r.spanS, $r.fps, $r.median, $r.p90, $r.p99,
        $(if ($r.totalP90) { '{0:N2}' -f $r.totalP90 } else { '—' }),
        $(if ($r.janky -ne $null) { '{0:P1}' -f $r.janky } else { '—' }),
        $fgText, $(if ($r.occluded) { '⚠ 未节流' } else { 'OK' }))
}
$aggLines = @()
$aggLines += '| 配置 | 轮数 | 中位(均值) | 中位(轮间极差) | P90(均值) | P90(轮间极差) | 聚合FPS(均值) | 全部轮次有效 |'
$aggLines += '|---|---|---|---|---|---|---|---|'
foreach ($cfg in ($perConfig.Keys | Sort-Object)) {
    $c = $perConfig[$cfg]
    $aggLines += ('| {0} | {1} | {2:N2} ms | {3:N2} ms | {4:N2} ms | {5:N2} ms | {6:N1} | {7} |' -f `
        $c.label, $c.rounds, $c.median.mean, $c.median.range, $c.p90.mean, $c.p90.range, $c.fps.mean,
        $(if ($c.allValid) { '是' } else { '⚠ 否' }))
}

$summary = [pscustomobject]@{
    generatedAt = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    mode = $Mode; runs = $Runs; seconds = $Seconds; samples = $Samples
    danmaku = $Danmaku; rate = $Rate; seed = $Seed
    configuration = $Configuration
    renderer = 'POC_IMPELLER=0 → Skia'
    outDir = $OutDir
    machine = "$env:COMPUTERNAME / refresh ${RefreshHz}Hz 假定"
    rows = $rows
    aggregates = $perConfig
    excludedRounds = @($excludedRows | ForEach-Object { "$($_.config)-$($_.run)" })
    minForegroundPct = $MinForegroundPct
    midShotRounds = @($rows | Where-Object { $_.midShot }).Count
    verdict = $verdict
}
$summary | ConvertTo-Json -Depth 6 | Out-File -FilePath (Join-Path $OutDir 'bench-summary.json') -Encoding utf8

$md = @()
$md += "# 弹幕 × 玻璃压测结果（$($summary.generatedAt)）"
$md += ''
$md += "- 构建：**$Configuration**（$($summary.renderer)）｜ 负载：同屏 $Danmaku 条弹幕 / $Rate 条每秒 ｜ 种子 $Seed"
$md += "- 每档 $Runs 轮，每轮 $Seconds 秒、$Samples 次时间线快照（每轮都是**全新进程**）"
$md += "- 注意：快照 RPC 自身约 0.6 秒/次，所以 ``--samples $Samples`` 时**实际采样窗口大于 $Seconds 秒**（以逐轮明细里的`"有效窗口`"为准）"
if ($excludedRows.Count -gt 0) {
    $md += "- ⚠ 已排除 $($excludedRows.Count) 轮（前台占比 <$MinForegroundPct%，外部程序抢前台会同时抬高 P99）：$(($excludedRows | ForEach-Object { "$($_.label) 第$($_.run)轮 $($_.fgRatio)%" }) -join '、')"
}
if (@($rows | Where-Object { $_.midShot }).Count -gt 0) {
    $md += '- ⚠ 本次运行带了 `-MidShot`：采样窗口内截过图（PrintWindow 会让被采样进程停顿一帧以上），'
    $md += '  这些轮的 P99/最大帧间隔含截图干扰，只有帧间隔中位数与 P90 可比。'
}
$md += "- 产物目录：``$OutDir``"
$md += ''
$md += '## 逐轮明细'
$md += ''
$md += $tableLines
$md += ''
$md += '## 分档汇总'
$md += ''
$md += $aggLines
$md += ''
$md += "**判定：$verdict**"
$md += ''
$md += '> 读法（口径见 docs/性能压测.md）：帧间隔中位数 = 常态流畅度；P90/P99 = 尾部停顿。'
$md += '> 聚合 FPS 只在"持续动画"场景成立；若遮挡自检为 ⚠，该轮只能读作引擎帧产出能力。'
$md | Out-File -FilePath (Join-Path $OutDir 'bench-summary.md') -Encoding utf8

$suiteSw.Stop()
Write-Host ''
Write-Host '================= 弹幕 × 玻璃 对比表 =================' -ForegroundColor Cyan
$tableLines | ForEach-Object { Write-Host $_ }
Write-Host ''
$aggLines | ForEach-Object { Write-Host $_ }
Write-Host ''
Write-Host "判定：$verdict" -ForegroundColor Yellow
Write-Host ''
Write-Host "产物目录：$OutDir"
Write-Host ("总耗时：{0:N1} 秒（含构建）" -f $suiteSw.Elapsed.TotalSeconds)