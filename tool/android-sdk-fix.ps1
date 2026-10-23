# SPDX-License-Identifier: GPL-3.0-or-later
<#
.SYNOPSIS
    修正 Android SDK 的 API 37 平台目录名（Gradle 找 `android-37`，SDK 装的是 `android-37.0`）。

.DESCRIPTION
    实测（2026-10-02）：`flutter build apk` 到 `:app:compileDebugJavaWithJavac` 时失败：

        Failed to find target with hash string 'android-37' in: <sdk>

    原因：本项目 `android/app/build.gradle.kts` 里 `compileSdk = 37`，AGP 按 `android-37` 去
    `<sdk>/platforms` 找平台；而这一代的 SDK 仓库里该平台的包名/目录名是 **`android-37.0`**
    （`source.properties` 里 `AndroidVersion.ApiLevel=37.0`、`Platform.Version=17`），
    并且 `sdkmanager "platforms;android-37"` 会报 `Failed to find package`。

    处理：建一个**目录联接**（junction，免管理员）把名字对齐，SDK 与仓库文件都不改动。
    这也是本机唯一需要"骗一下"工具链的地方，故单独成脚本、留档说明。

.PARAMETER Revert
    删除该联接（回到未修正状态）。

.EXAMPLE
    .\tool\android-sdk-fix.ps1
    .\tool\android-sdk-fix.ps1 -Revert
#>
param(
    [string]$SdkRoot = 'E:\dev\android-sdk',
    [switch]$Revert
)

$ErrorActionPreference = 'Stop'
$platforms = Join-Path $SdkRoot 'platforms'
$link = Join-Path $platforms 'android-37'
$target = Join-Path $platforms 'android-37.0'

if ($Revert) {
    if (Test-Path $link) {
        # 只删联接本身，不动目标目录（junction 删除不会递归删除目标内容）
        [System.IO.Directory]::Delete($link, $false)
        Write-Host "已删除联接 $link"
    } else {
        Write-Host "联接不存在，无需回滚"
    }
    exit 0
}

if (-not (Test-Path $target)) {
    throw "找不到 $target —— 先跑一次 flutter build apk 让 Flutter 自动安装该平台，或手动 sdkmanager `"platforms;android-37.0`""
}
if (Test-Path $link) {
    Write-Host "联接已存在：$link"
    exit 0
}

New-Item -ItemType Junction -Path $link -Target $target | Out-Null
if (-not (Test-Path (Join-Path $link 'android.jar'))) {
    throw "联接建好了但看不到 android.jar，请检查 $target"
}
Write-Host "已创建联接：android-37 -> android-37.0（Gradle 现在能找到 compileSdk 37 的平台）" -ForegroundColor Green
Write-Host "回滚：.\tool\android-sdk-fix.ps1 -Revert" -ForegroundColor DarkGray