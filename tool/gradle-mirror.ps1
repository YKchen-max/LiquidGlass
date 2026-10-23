# SPDX-License-Identifier: GPL-3.0-or-later
<#
.SYNOPSIS
    把 Gradle wrapper 的发行包下载切到国内镜像（本机 services.gradle.org 真实下载超时）。

.DESCRIPTION
    实测（2026-10-02）：`services.gradle.org/distributions/gradle-9.5.0-all.zip` 的 HEAD 能通，
    但 Gradle wrapper 下载（会重定向）在本机超时 → `flutter build apk` 直接失败。
    腾讯/华为镜像实测可用（两者都返回 240667887 字节）。

    只改 `android/gradle/wrapper/gradle-wrapper.properties` 里的 distributionUrl 一行，
    不动版本号；`-Restore` 用 git 还原该文件（它在上游是被跟踪的，无需备份文件）。

    ⚠️ 这是**对上游文件的本地偏离**（rebase 时注意）；GitHub Actions 上两个源都通，
    所以 CI 用不用镜像都可以。

.PARAMETER Mirror
    tencent（默认，mirrors.cloud.tencent.com/gradle）或 huawei（mirrors.huaweicloud.com/gradle）。

.PARAMETER Restore
    用 git 还原 distributionUrl 为上游原值。

.PARAMETER PreSeed
    额外把发行包下载到 Gradle wrapper 的哈希缓存目录，绕开 wrapper 自身的下载
    （实测 wrapper 从镜像下载会被 reset，curl 却能稳定跑满带宽）。

.EXAMPLE
    .\tool\gradle-mirror.ps1 -PreSeed      # 切腾讯镜像 + 预置发行包（推荐）
    .\tool\gradle-mirror.ps1 -Mirror huawei -PreSeed
    .\tool\gradle-mirror.ps1 -Restore
#>
param(
    [ValidateSet('tencent', 'huawei')]
    [string]$Mirror = 'tencent',
    [switch]$Restore,
    [switch]$PreSeed
)

$ErrorActionPreference = 'Stop'
$app = Split-Path $PSScriptRoot -Parent
$git = 'E:\dev\PortableGit\cmd\git.exe'
if (-not (Test-Path $git)) { $git = 'git' }

$rel = 'android/gradle/wrapper/gradle-wrapper.properties'
$props = Join-Path $app ($rel -replace '/', '\')
if (-not (Test-Path $props)) { throw "找不到 $props" }

if ($Restore) {
    & $git -C $app checkout -- $rel
    if ($LASTEXITCODE -ne 0) { throw "git 还原失败：$rel" }
    Write-Host "已还原为上游原值：" -NoNewline
    Write-Host ((Select-String -Path $props -Pattern '^distributionUrl').Line)
    exit 0
}

$bases = @{
    tencent = 'https://mirrors.cloud.tencent.com/gradle'
    huawei  = 'https://mirrors.huaweicloud.com/gradle'
}
$base = $bases[$Mirror]

$content = [System.IO.File]::ReadAllText($props, [System.Text.Encoding]::UTF8)
$m = [regex]::Match($content, 'distributionUrl=(?:https\\?:)?//[^\r\n]*?/(gradle-[\d\.]+-(?:all|bin)\.zip)')
if (-not $m.Success) { throw "无法从 distributionUrl 解析出 gradle 发行包名，请手动检查 $props" }
$zipName = $m.Groups[1].Value

$newUrl = "$base/$zipName"
$newContent = [regex]::Replace(
    $content,
    'distributionUrl=.*',
    ('distributionUrl=' + $newUrl.Replace(':', '\:'))
)
[System.IO.File]::WriteAllText($props, $newContent, (New-Object System.Text.UTF8Encoding($false)))

Write-Host "distributionUrl -> $newUrl" -ForegroundColor Green
Write-Host "还原：.\tool\gradle-mirror.ps1 -Restore" -ForegroundColor DarkGray

# ---------------------------------------------------------------- 预置发行包（绕过 Java 客户端下载）
# 实测：Gradle wrapper 自己下载时，腾讯/华为镜像都会被 reset（head 请求却正常）。
# 用 curl 下好、按 Gradle PathAssembler 的哈希目录放进 wrapper 缓存，wrapper 便直接解包、不再联网。
if ($PreSeed) {
    $gradleHome = if ($env:GRADLE_USER_HOME) { $env:GRADLE_USER_HOME } else { Join-Path $env:USERPROFILE '.gradle' }
    # Gradle: new BigInteger(1, MD5(distributionUrl)).toString(36)
    $md5 = [System.Security.Cryptography.MD5]::Create()
    $digest = $md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($newUrl))
    $hex = ($digest | ForEach-Object { $_.ToString('x2') }) -join ''
    $big = [System.Numerics.BigInteger]::Parse('0' + $hex, [System.Globalization.NumberStyles]::AllowHexSpecifier)
    $digits = '0123456789abcdefghijklmnopqrstuvwxyz'; $hash = ''
    while ($big -gt 0) { $hash = $digits[[int]($big % 36)] + $hash; $big = [System.Numerics.BigInteger]::Divide($big, 36) }
    if (-not $hash) { $hash = '0' }

    # Gradle 的布局：wrapper/dists/<发行包名去掉 .zip>/<url 的 base36 哈希>/<zip 文件>
    $distName = $zipName -replace '\.zip$', ''
    $distDir = Join-Path $gradleHome "wrapper/dists/$distName/$hash"
    New-Item -ItemType Directory -Path $distDir -Force | Out-Null
    $zipPath = Join-Path $distDir $zipName
    Write-Host "wrapper 缓存目录：$distDir"

    if (Test-Path $zipPath) {
        Write-Host "已存在 $zipName（$((Get-Item $zipPath).Length) 字节），跳过下载" -ForegroundColor Green
    } else {
        Remove-Item (Join-Path $distDir "$zipName.part") -Force -ErrorAction SilentlyContinue
        Write-Host "下载 $zipName ..." -ForegroundColor Cyan
        & curl.exe -L --no-progress-meter --retry 8 --retry-delay 3 --retry-all-errors --connect-timeout 20 -o $zipPath "$base/$zipName" 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $zipPath)) { throw "下载失败：$base/$zipName" }
        Write-Host "下载完成：$((Get-Item $zipPath).Length) 字节" -ForegroundColor Green
    }
    Write-Host "下次 flutter build 无需再下载 Gradle 发行包。" -ForegroundColor Green
}