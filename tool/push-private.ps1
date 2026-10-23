# SPDX-License-Identifier: GPL-3.0-or-later
<#
.SYNOPSIS
    推送到私有仓库（带 token），绕开 dev-env 里的 GitHub 公共代理重写。

.DESCRIPTION
    本机为了拉取 20+ 个 GitHub 公网依赖，在 tool/dev-env.ps1 里用
    `url.https://ghfast.top/https://github.com/.insteadOf = https://github.com/` 做了前缀代理。
    这条规则对**公有仓库**有效，但 ghfast 无法访问**私有仓库** —— 于是：
      * `git ls-remote https://github.com/<owner>/<repo>.git` → Repository not found（被改写后走代理）
      * `git push https://x-access-token:<TOKEN>@github.com/...` → 正常（前缀不同，不被改写）

    所以私有仓库的推送统一用本脚本：token 只出现在命令行 URL 里，**不写入任何配置文件**。

.PARAMETER Token
    GitHub PAT（需 repo 权限）。也可用环境变量 GITHUB_TOKEN。

.PARAMETER Remote
    仓库地址（默认本项目私有仓库）。可换成任意私有仓库 URL。

.PARAMETER Branch
    分支名，默认 main。

.PARAMETER Force
    强制推送（仅在你确认远端历史可以覆盖时使用）。

.EXAMPLE
    .\tool\push-private.ps1 -Token ghp_xxx
    $env:GITHUB_TOKEN='ghp_xxx'; .\tool\push-private.ps1
#>
param(
    [string]$Token = $env:GITHUB_TOKEN,
    [string]$Remote = 'https://github.com/YKchen-max/1.git',
    [string]$Branch = 'main',
    [switch]$Force
)

$ErrorActionPreference = 'Continue'
if (-not $Token) { throw '缺少 token：用 -Token 传入，或先设置环境变量 GITHUB_TOKEN' }

$app = Split-Path $PSScriptRoot -Parent
$git = 'E:\dev\PortableGit\cmd\git.exe'
if (-not (Test-Path $git)) { $git = 'git' }

$env:GIT_TERMINAL_PROMPT = '0'
$authUrl = $Remote -replace '^https://', "https://x-access-token:$Token@"

Write-Host "推送 $Branch → $($Remote -replace '://.*@', '://')" -ForegroundColor Cyan
# 注意：不要用 $args（PowerShell 自动变量），避免踩坑
$pushArgs = @('-C', $app, 'push', $authUrl, $Branch)
if ($Force) { $pushArgs += '--force' }
$out = & $git @pushArgs 2>&1 | Out-String
Write-Host $out.Trim()

if ($LASTEXITCODE -ne 0) {
    Write-Host '推送失败：请检查 token 权限（需 repo）、仓库是否存在、分支是否受保护。' -ForegroundColor Red
    exit 1
}
$head = (& $git -C $app rev-parse --short HEAD)
Write-Host "完成：本地 HEAD $head 已同步" -ForegroundColor Green
Write-Host "Actions：$($Remote -replace '\.git$','')/actions" -ForegroundColor DarkGray
exit 0