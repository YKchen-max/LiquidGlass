# SPDX-License-Identifier: GPL-3.0-or-later
<#
.SYNOPSIS
    为 LiquidGlass for Bilibili 注入本机可用的构建环境变量（镜像 / GitHub 代理）。

.DESCRIPTION
    本机（LAPTOP-RUEODJE0）实测结论：
      * pub.dev 直连不稳 → 走 pub.flutter-io.cn / storage.flutter-io.cn；
      * git clone github.com:443 直连超时 → 必须经前缀代理，ghfast.top 与 gh-proxy.com 实测可用；
      * 代理以 GIT_CONFIG_COUNT/KEY_0/VALUE_0 注入**当前进程树**，
        因此 flutter → dart → git 子进程都能继承，且**不修改用户全局 git 配置**。

    用法（必须 dot-source 才能影响当前会话）：
        . .\tool\dev-env.ps1
        . .\tool\dev-env.ps1 -GitHubProxy gh-proxy
        . .\tool\dev-env.ps1 -GitHubProxy none      # 走直连（仅当已挂系统代理时）

.PARAMETER GitHubProxy
    GitHub 克隆加速通道：ghfast（默认）/ gh-proxy / none。
#>
param(
    [ValidateSet('ghfast', 'gh-proxy', 'none')]
    [string]$GitHubProxy = 'ghfast'
)

$env:PUB_HOSTED_URL = 'https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL = 'https://storage.flutter-io.cn'
$env:GIT_TERMINAL_PROMPT = '0'   # 无凭据时立刻失败，不要挂住等输入

# git 侧的两项本机必需配置（都以进程级 GIT_CONFIG_* 注入，不改用户全局 git 配置）：
#   1) url.<代理>.insteadOf —— github.com 直连超时，git 依赖拉不下来；
#   2) core.longpaths=true —— pub 缓存里的插件源码路径超过 Windows 260 字符上限，
#      否则 git 检出会静默漏文件（flutter_inappwebview 就因此缺了 12 个 .java，
#      表现为 Java 编译报 cannot find symbol，很难往"路径太长"上想）。
$gitConfigs = @()
switch ($GitHubProxy) {
    'ghfast' {
        $gitConfigs += , @('url.https://ghfast.top/https://github.com/.insteadOf', 'https://github.com/')
    }
    'gh-proxy' {
        $gitConfigs += , @('url.https://gh-proxy.com/https://github.com/.insteadOf', 'https://github.com/')
    }
    'none' { }
}
$gitConfigs += , @('core.longpaths', 'true')

#   3) TLS 后端与 CA：本机 Schannel 连不上 CRL 服务器，git 走 https 会报
#      CRYPT_E_NO_REVOCATION_CHECK；PortableGit 自带的 CA 包又缺本网络所用根证书。
#      处置：改用 openssl 后端 + 从 Windows 根证书库导出的 PEM（**证书校验保持开启**，
#      不使用 GIT_SSL_NO_VERIFY）。导出文件放在工作区外（E:\dev\certs），不随仓库分发。
$caBundle = 'E:\dev\certs\windows-roots.pem'
if (-not (Test-Path $caBundle)) {
    $dir = Split-Path $caBundle -Parent
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $sb = New-Object System.Text.StringBuilder
    foreach ($store in @('Cert:\LocalMachine\Root', 'Cert:\CurrentUser\Root')) {
        foreach ($cert in Get-ChildItem $store -ErrorAction SilentlyContinue) {
            if ($cert.RawData -and $cert.RawData.Length -gt 0) {
                [void]$sb.AppendLine('# ' + $cert.Subject)
                [void]$sb.AppendLine('-----BEGIN CERTIFICATE-----')
                [void]$sb.AppendLine([Convert]::ToBase64String($cert.RawData, 'InsertLineBreaks'))
                [void]$sb.AppendLine('-----END CERTIFICATE-----')
            }
        }
    }
    [System.IO.File]::WriteAllText($caBundle, $sb.ToString(), [System.Text.Encoding]::ASCII)
    Write-Host "[dev-env] 已导出 Windows 根证书 → $caBundle" -ForegroundColor DarkGray
}
if (Test-Path $caBundle) {
    $gitConfigs += , @('http.sslBackend', 'openssl')
    $gitConfigs += , @('http.sslCAInfo', $caBundle.Replace('\', '/'))
}

foreach ($k in @('GIT_CONFIG_COUNT', 'GIT_CONFIG_KEY_0', 'GIT_CONFIG_VALUE_0',
                 'GIT_CONFIG_KEY_1', 'GIT_CONFIG_VALUE_1', 'GIT_CONFIG_KEY_2', 'GIT_CONFIG_VALUE_2',
                 'GIT_CONFIG_KEY_3', 'GIT_CONFIG_VALUE_3', 'GIT_CONFIG_KEY_4', 'GIT_CONFIG_VALUE_4')) {
    Remove-Item "Env:$k" -ErrorAction SilentlyContinue
}
$env:GIT_CONFIG_COUNT = "$($gitConfigs.Count)"
for ($i = 0; $i -lt $gitConfigs.Count; $i++) {
    Set-Item "Env:GIT_CONFIG_KEY_$i" $gitConfigs[$i][0]
    Set-Item "Env:GIT_CONFIG_VALUE_$i" $gitConfigs[$i][1]
}

# 本机 SDK 位置（若系统级环境变量缺失则补上）
if (-not $env:JAVA_HOME) { $env:JAVA_HOME = 'E:\dev\jdk-17' }
if (-not $env:ANDROID_HOME) { $env:ANDROID_HOME = 'E:\dev\android-sdk' }

# pub 缓存放到 E:（与工程同盘、路径更短），一举解决两类 Windows 环境故障：
#   1) C:\Users\<用户>\AppData\Local\Pub\Cache\git\<长仓库名>\... 超过 260 字符 →
#      git 检出静默漏文件（flutter_inappwebview 曾缺 12 个 .java，报 cannot find symbol）；
#   2) 插件源码在 C:、工程在 E: → Kotlin 增量编译报
#      "this and base files have different roots"。
# 首次切换需重新下载依赖（约 1GB，走镜像很快），并重跑 tool/patch-upstream.ps1 打补丁。
if (-not $env:PUB_CACHE) { $env:PUB_CACHE = 'E:\dev\pub-cache' }

# nuget.exe：Windows 端 flutter_inappwebview_windows 插件在 CMake 阶段要调 `nuget install`
# 拉 WebView2 / WIL / nlohmann.json，缺了会以 MSB3073 + 退出码 9009 失败。
$nugetDir = 'E:\dev\nuget'
if ((Test-Path "$nugetDir\nuget.exe") -and (($env:PATH -split ';') -notcontains $nugetDir)) {
    $env:PATH = "$nugetDir;$env:PATH"
}

Write-Host "[dev-env] PUB_HOSTED_URL=$env:PUB_HOSTED_URL" -ForegroundColor DarkGray
Write-Host "[dev-env] FLUTTER_STORAGE_BASE_URL=$env:FLUTTER_STORAGE_BASE_URL" -ForegroundColor DarkGray
Write-Host "[dev-env] PUB_CACHE=$env:PUB_CACHE" -ForegroundColor DarkGray
Write-Host "[dev-env] GitHub clone 通道: $GitHubProxy ；git 长路径: 已启用" -ForegroundColor DarkGray
if (Test-Path "$nugetDir\nuget.exe") { Write-Host "[dev-env] nuget: $nugetDir\nuget.exe 已在 PATH" -ForegroundColor DarkGray }