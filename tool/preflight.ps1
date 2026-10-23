# SPDX-License-Identifier: GPL-3.0-or-later
<#
.SYNOPSIS
    LiquidGlass 本地门禁：把 CI（.github/workflows/liquidglass-ci.yml）里那几道关在本地跑一遍。

.DESCRIPTION
    顺序与 CI 一致，任一步失败即整体失败（退出码 1）：
      1. 环境前置    —— 补丁是否就位（本机最易被忽略：不打补丁 analyze 报 118 error）
      2. 依赖        —— flutter pub get
      3. 静态检查    —— flutter analyze（要求 0 error）
      4. 单测        —— 宿主 App 的 test/own + liquid_glass_kit 包
      5. 素材一致性  —— tool/build_fonts.py --check（清单 ↔ 字体 cmap ↔ 生成的 Dart 三方一致）
      6. 构建（可选）—— -Build windows|android|both

    为什么要有它：CI 的真实运行需要 GitHub 仓库与凭据（待定），本地门禁让「改完到底过不过」
    当场可知；#15 的上游 rebase 演练也用它验收。

    实现注意（踩过的坑）：
      * 步骤里**不能写 exit** —— 脚本块在当前作用域执行，exit 会把整个脚本结束掉；
        因此每个步骤用「返回布尔值」表达成败。
      * 外部命令（git/flutter）会往 stderr 写正常信息，必须保持 EAP=Continue 并只认退出码。

.PARAMETER Build
    额外跑构建：none（默认）/ windows / android / both

.PARAMETER SkipPubGet
    跳过 pub get（依赖没动时省几秒）

.EXAMPLE
    .\tool\preflight.ps1
    .\tool\preflight.ps1 -Build both
#>
param(
    [ValidateSet('none', 'windows', 'android', 'both')]
    [string]$Build = 'none',
    [switch]$SkipPubGet
)

$ErrorActionPreference = 'Continue'
$app = Split-Path $PSScriptRoot -Parent
$flutter = 'E:\dev\flutter\bin\flutter.bat'
if (-not (Test-Path $flutter)) { $flutter = 'flutter' }

$devEnv = Join-Path $PSScriptRoot 'dev-env.ps1'
if (Test-Path $devEnv) { . $devEnv | Out-Null }

$results = [System.Collections.Generic.List[object]]::new()

function Step([string]$name, [scriptblock]$body) {
    Write-Host "`n=== $name ===" -ForegroundColor Cyan
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $ok = $false
    $note = ''
    try {
        $ok = [bool](& $body)
    } catch {
        $ok = $false
        $note = "异常：$($_.Exception.Message)"
        Write-Host $note -ForegroundColor Red
    }
    $sw.Stop()
    if (-not $ok -and -not $note) { $note = '步骤返回失败' }
    Write-Host ("  → {0}（{1:N1}s）" -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $sw.Elapsed.TotalSeconds) `
        -ForegroundColor $(if ($ok) { 'Green' } else { 'Red' })
    $results.Add([pscustomobject]@{
        Step = $name; Ok = $ok; Seconds = [math]::Round($sw.Elapsed.TotalSeconds, 1); Note = $note
    })
}

function Show-Tail([string]$text, [int]$n = 5) {
    $lines = $text -split "`r?`n" | Where-Object { $_.Trim() -ne '' }
    Write-Host (($lines | Select-Object -Last $n) -join "`n")
}

# 1) 环境前置：补丁能力探测（只读）
Step '环境前置（SDK / material_ui 补丁）' {
    $s = & (Join-Path $PSScriptRoot 'patch-upstream.ps1') -Status 2>&1 | Out-String
    Show-Tail $s 8
    return ($s -notmatch '\[!!\]')
}

# 2) 依赖
if (-not $SkipPubGet) {
    Step 'flutter pub get' {
        Push-Location $app
        try {
            $out = & $flutter pub get 2>&1 | Out-String
            Show-Tail $out 3
            return ($out -match 'Got dependencies|Changed \d+ dependenc')
        } finally { Pop-Location }
    }
}

# 3) 静态检查（0 error）
Step 'flutter analyze（要求 0 error）' {
    Push-Location $app
    try {
        # 与 CI 同一口径：flutter analyze 默认对 info 也返回退出码 1（CI 上实测就因此误判），
        # 所以显式关掉 info/warning 的致命性，只让 error 拦人。
        $out = & $flutter analyze --no-fatal-infos --no-fatal-warnings 2>&1 | Out-String
        Show-Tail $out 4
        $ok = $LASTEXITCODE -eq 0
        if (-not $ok) { Write-Host '  （analyze 退出码非 0：存在 error 级问题）' -ForegroundColor Red }
        return $ok
    } finally { Pop-Location }
}

# 4) 单测
Step 'flutter test test/own（宿主自有测试）' {
    Push-Location $app
    try {
        $out = & $flutter test test\own 2>&1 | Out-String
        Show-Tail $out 3
        return ($out -match 'All tests passed!')
    } finally { Pop-Location }
}

Step 'flutter test（liquid_glass_kit）' {
    Push-Location (Join-Path $app 'packages\liquid_glass_kit')
    try {
        & $flutter pub get | Out-Null
        $out = & $flutter test 2>&1 | Out-String
        Show-Tail $out 3
        return ($out -match 'All tests passed!')
    } finally { Pop-Location }
}

# 5) 素材一致性（图标清单 ↔ 字体 ↔ Dart）
Step '字体/图标一致性（build_fonts --check）' {
    Push-Location $app
    try {
        $env:PYTHONIOENCODING = 'utf-8'   # 子进程输出统一 UTF-8，避免按 GBK 解码成乱码
        $out = & python -X utf8 tool\build_fonts.py --check 2>&1 | Out-String
        Show-Tail $out 4
        # 只认 ASCII 结果标记：跨 locale 时中文文本匹配不可靠（本门禁实际踩过）
        return ($out -match 'CHECK_RESULT=PASS')
    } finally { Pop-Location }
}

# 6) kit 包自身的静态检查（宿主 App 的 analyze 不覆盖 packages/ 下的包）
Step 'kit analyze（liquid_glass_kit，要求 0 issue）' {
    Push-Location (Join-Path $app 'packages\liquid_glass_kit')
    try {
        $out = & $flutter analyze --no-fatal-infos --no-fatal-warnings 2>&1 | Out-String
        Show-Tail $out 3
        # 用 ASCII 标记判定，别依赖中文文本（跨 locale 不可靠）
        return ($out -match 'No issues found!')
    } finally { Pop-Location }
}

# 7) 工具脚本语法自检
#    动机：本机是 PS 5.1，**含中文但无 BOM 的 .ps1 会整脚本解析失败**（今天实际踩了两次：
#    自研的 build-lock.ps1 被两位队友先后诊断出来）。这条把事故挡在门外，而不是靠人记。
#    覆盖范围：app/tool/**、<repo>/tools/**（含 ui-probe）、以及 <repo>/.probe/**
#    —— 最后一个是后补的：实测大部分临时采集脚本都写在 .probe/**，而它们曾从这条缝里漏过去
#    （6 个无 BOM 脚本的产物日志直接是乱码：tap 鍒嗗尯 …），故一并纳入。
Step '工具脚本语法自检（PS ParseFile + Python ast）' {
    $problems = @()
    $repoRoot = Split-Path $app -Parent
    $roots = @((Join-Path $app 'tool'), (Join-Path $repoRoot 'tools'), (Join-Path $repoRoot '.probe'))
    foreach ($root in $roots) {
        if (-not (Test-Path $root)) { continue }
        foreach ($ps1 in Get-ChildItem $root -Recurse -Filter '*.ps1' -ErrorAction SilentlyContinue) {
            $bytes = [System.IO.File]::ReadAllBytes($ps1.FullName)
            $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
            $text = [System.Text.Encoding]::UTF8.GetString($bytes)
            $nonAscii = [regex]::Matches($text, '[^\x00-\x7F]').Count

            # (a) 独立于语法的**编码安全**扫描：含非 ASCII 但无 BOM 的 .ps1 就是隐患，
            #     哪怕它能通过语法检查、也能跑对。实测反例（M1-C）：≈/Δ 落在注释里时
            #     语法自检全绿、脚本三次运行正常，但它与"整脚本解析失败"是同一颗种子
            #     ——落在字符串或语法相关位置时就会炸。故这里单独拦。
            if ($nonAscii -gt 0 -and -not $hasBom) {
                $problems += "$($ps1.Name): 含 $nonAscii 个非 ASCII 字符但没有 UTF-8 BOM"
                $problems += "    ↳ PS 5.1 会按 GBK 解码：轻则乱码、重则整脚本解析失败。"
                $problems += "    ↳ 改法二选一：写成 UTF-8 with BOM，或把非 ASCII 全换成 ASCII（推荐纯 ASCII + 英文注释）"
            }

            # (b) 语法检查（与编码无关，单独一层）
            $errors = $null
            [void][System.Management.Automation.Language.Parser]::ParseFile($ps1.FullName, [ref]$null, [ref]$errors)
            if ($errors -and $errors.Count -gt 0) {
                $first = $errors[0]
                $problems += "$($ps1.Name): $($errors.Count) 个语法错误，首个在第 $($first.Extent.StartLineNumber) 行 —— $($first.Message)"
            }
        }
        foreach ($py in Get-ChildItem $root -Recurse -Filter '*.py' -ErrorAction SilentlyContinue) {
            $env:PYTHONIOENCODING = 'utf-8'
            $out = & python -X utf8 -c "import ast,sys; ast.parse(open(sys.argv[1],encoding='utf-8-sig').read())" $py.FullName 2>&1 | Out-String
            if ($LASTEXITCODE -ne 0) {
                $problems += "$($py.Name): Python 语法错误 —— $(($out -split "`n" | Select-Object -Last 1).Trim())"
            }
        }
    }

    # (c) Dart 源码编码/乱码扫描（2026-10-06 加）：
    #     动机：外部会话把 lib/pages/video/view.dart 存成 **GBK 乱码＋吞引号**（'听音频' → '鍚棰?'）
    #     ⇒ 字符串未闭合 ⇒ **整棵树编译不过**，而发现者是"下一个跑测试的队友" ✗✓（task-122  home-glass 报）。
    #     与 .ps1 的 BOM 坑同源（CJK 写入管线损坏），这次落在 Dart 上 ⇒ 门禁必须自己看得见。
    #     签名（宁窄勿宽 ✗✓ 误报会拦死正常提交）：
    #       ① 严格 UTF-8 解码失败；② U+FFFD；③ "CJK 簇＋字面 ? ＋收口符 ) , ; :"（吞引号乱码的形状）；④ 锟斤拷。
    $env:PYTHONIOENCODING = 'utf-8'
    $dartScanPy = @'
import sys, pathlib, re
sig = re.compile('[\\u4e00-\\u9fff]{2,}\\?[\\),;:]|\\u951f\\u65a4\\u62f7|\\ufffd')
bad = []
for root in sys.argv[1:]:
    for p in pathlib.Path(root).rglob('*.dart'):
        try:
            t = p.read_bytes().decode('utf-8')
        except UnicodeDecodeError as e:
            bad.append('%s: UTF-8 严格解码失败 @byte %d' % (p, e.start)); continue
        for i, l in enumerate(t.splitlines(), 1):
            if sig.search(l):
                bad.append('%s:%d: %s' % (p, i, l.strip()[:60]))
print('\n'.join(bad))
'@
    $dartBad = & python -X utf8 -c $dartScanPy (Join-Path $app 'lib') (Join-Path $app 'test') 2>&1 | Out-String
    foreach ($line in ($dartBad -split "`n" | Where-Object { $_.Trim() })) {
        $problems += "Dart 编码/乱码签名 ⇒ $line"
        $problems += '    ↳ 多为 CJK 写入管线损坏（GBK 乱码/吞引号）；修法：从 HEAD 或上游取原字符串修回，别整文件回退 ✗'
    }
    if ($problems.Count -eq 0) {
        Write-Host '  Dart 编码扫描：0 命中 ✓' -ForegroundColor DarkGray
    }
    if ($problems.Count -gt 0) {
        foreach ($p in $problems) { Write-Host "  $p" -ForegroundColor Red }
        return $false
    }
    Write-Host '  所有 .ps1 / .py 语法自检通过' -ForegroundColor DarkGray
    return $true
}

# 7.5) shader asset shape scan
#   Why (docs/着色器分支普查与风险登记.md R1/R2/R4):
#     * poc/shaders-src NEVER deleted the platform y-flip branches. A plain rebuild
#       (compile-shaders.ps1 / the README recipe) puts them back into the GLES stages.
#       On this device the runtime backend is OpenGLES3, so the flip is ACTIVE and
#       mirrors screenUV / geometryUV: geometryUV mirror pushes alpha outside the shape
#       and the shader early-outs vec4(0) => the glass goes TRANSPARENT (not black).
#     * Even a dead `#ifdef` branch leaves a trace (one extra SPIR-V id), so the id
#       baseline below is the only zero-symptom early-warning probe.
#   Expectation: flip hits = 0 and preprocessor residue = 0 in the GLES3/GLES2 TEXT
#   sections of the four kit assets; text sections are found by decoding as Latin-1
#   (lossless byte<->char) and matching '#version' runs.
Step 'shader asset scan（GLES 段不得含平台 y 翻转）' {
    $sh = Join-Path $app 'packages\liquid_glass_kit\lib\assets\shaders'
    $files = @(
        'liquid_glass_final_render.iplr',
        'liquid_glass_geometry_blended.iplr',
        'liquid_glass_filter.iplr',
        'liquid_glass_arbitrary.iplr'
    )
    $latin1 = [System.Text.Encoding]::GetEncoding(28591)
    $flipRe = '\.y\s*=\s*1\.0\s*-|1\.0\s*-\s*\(_fragCoord\.y|1\.0\s*-\s*\(_\d+\.y\s*/'
    $cmRe   = '1\.0\s*-\s*\(\s*\w+\.y\s*/\s*uForegroundSize\.y\s*\)'
    $bad = @()
    $flipTotal = 0
    $sectionCount = 0
    $preprocTotal = 0
    foreach ($f in $files) {
        $p = Join-Path $sh $f
        if (-not (Test-Path $p)) { $bad += "$f : missing"; continue }
        $text = $latin1.GetString([System.IO.File]::ReadAllBytes($p))
        $secs = [regex]::Matches($text, '#version[^\x00]{200,}')
        if ($secs.Count -eq 0) { $bad += "$f : no GLES text section found (unexpected asset shape)"; continue }
        $sectionCount += $secs.Count
        $fHits = 0
        foreach ($s in $secs) {
            $v = $s.Value
            $fHits += ([regex]::Matches($v, $flipRe)).Count
            $preprocTotal += ([regex]::Matches($v, '#(if|ifdef|ifndef|define)')).Count
            if (([regex]::Matches($v, $cmRe)).Count -gt 0) { $bad += "$f : computeY-style flip retained (uForegroundSize.y)" }
            if ($v -match '#version 300 es' -and $v -notmatch 'in highp vec2 _fragCoord') {
                $bad += "$f : GLES3 section lost the '_fragCoord' attribute (backend branch changed?)"
            }
            if ($v -match 'gl_FragCoord') { $bad += "$f : 'gl_FragCoord' present (Skia backend branch?)" }
        }
        $flipTotal += $fHits
        Write-Host ("  {0,-32} sections={1} flip={2}" -f ($f -replace '\.iplr$', ''), $secs.Count, $fHits)
    }
    if ($flipTotal -gt 0) {
        $bad += "flip hits = $flipTotal (expected 0) -- a rebuild re-introduced the platform y-flip; glass would go TRANSPARENT"
    }
    if ($preprocTotal -gt 0) {
        $bad += "preprocessor residue = $preprocTotal (expected 0; only #extension is allowed)"
    }
    # R2: zero-symptom id baseline inside geometry_blended (dead branch still eats 1 id).
    $gb = Join-Path $sh 'liquid_glass_geometry_blended.iplr'
    if (Test-Path $gb) {
        $t2 = $latin1.GetString([System.IO.File]::ReadAllBytes($gb))
        if ($t2 -match 'if \(_498 == 0\)') {
            Write-Host '  id baseline: if (_498 == 0)  -> matches baseline' -ForegroundColor DarkGray
        } elseif ($t2 -match 'if \(_499 == 0\)') {
            $bad += 'id baseline became _499 -- macro state differs from baseline; assets must be re-verified'
        } else {
            $bad += 'id baseline not found -- geometry_blended shape changed; update the baseline in docs/着色器分支普查与风险登记.md'
        }
    }
    # R4: GLES2 hard requirement -- informational only.
    $g2 = 0
    foreach ($f in $files) {
        $p = Join-Path $sh $f
        if (-not (Test-Path $p)) { continue }
        $g2 += ([regex]::Matches($latin1.GetString([System.IO.File]::ReadAllBytes($p)), 'GL_OES_standard_derivatives\s*:\s*require')).Count
    }
    Write-Host ("  GLES2 'GL_OES_standard_derivatives: require' = {0} (informational)" -f $g2) -ForegroundColor DarkGray

    # Census requirement (3) / R3: geometry_blended is 0-flip in BOTH the repo-recipe build
    # and the current asset while their sha256 differ, so the flip scan cannot cover it.
    # Compare all four against committed golden fingerprints; an intentional change must
    # update app/tool/shader_asset_baseline.json in the same commit.
    $basePath = Join-Path $PSScriptRoot 'shader_asset_baseline.json'
    if (-not (Test-Path $basePath)) {
        $bad += "shader_asset_baseline.json missing at $basePath"
    } else {
        $base = Get-Content $basePath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($e in $base.expected) {
            $p = Join-Path $sh $e.file
            if (-not (Test-Path $p)) { $bad += "$($e.file) : missing (baseline)"; continue }
            $fi = Get-Item $p
            $sha = (Get-FileHash $p -Algorithm SHA256).Hash
            if (($fi.Length -eq [int]$e.bytes) -and $sha.StartsWith($e.sha256_prefix)) {
                Write-Host ("  baseline {0,-32} {1,7} B  {2}  OK" -f $e.file, $fi.Length, $e.sha256_prefix) -ForegroundColor DarkGray
            } else {
                $bad += ("baseline mismatch {0}: got {1} B / {2}, expected {3} B / {4}" -f `
                    $e.file, $fi.Length, $sha.Substring(0, 16), $e.bytes, $e.sha256_prefix)
                if ($sha.StartsWith($base.known_landmine.sha256_prefix)) {
                    $bad += "  ^^ KNOWN LANDMINE build: the repo recipe re-introduced the GLES y-flip"
                }
            }
        }
    }

    if ($bad.Count -gt 0) {
        foreach ($b in $bad) { Write-Host "  $b" -ForegroundColor Red }
        return $false
    }
    Write-Host ("  OK: {0} sections, flip=0, preprocessor residue=0, baseline 4/4" -f $sectionCount) -ForegroundColor DarkGray
    return $true
}

# 8) 构建（可选）
if ($Build -in @('windows', 'both')) {
    Step 'flutter build windows --debug' {
        Push-Location $app
        try {
            $out = & $flutter build windows --debug --no-pub 2>&1 | Out-String
            Show-Tail $out 3
            return ($out -match '√ Built')
        } finally { Pop-Location }
    }
}
if ($Build -in @('android', 'both')) {
    Step 'flutter build apk --debug' {
        Push-Location $app
        try {
            $out = & $flutter build apk --debug --no-pub 2>&1 | Out-String
            Show-Tail $out 3
            return ($out -match '√ Built')
        } finally { Pop-Location }
    }
}

Write-Host "`n======== 门禁结果 ========" -ForegroundColor Cyan
$results | Format-Table Step, @{n='结果'; e={ if ($_.Ok) { 'PASS' } else { 'FAIL' } }}, Seconds, Note -AutoSize
$failed = @($results | Where-Object { -not $_.Ok })
if ($failed.Count) {
    Write-Host "$($failed.Count) 项未通过：$($failed.Step -join '、')" -ForegroundColor Red
    exit 1
}
Write-Host '全部通过' -ForegroundColor Green
exit 0