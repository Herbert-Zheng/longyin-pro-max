[CmdletBinding()]
param(
  [string]$RepoRoot = '',
  [string]$LoaderRoot = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
  $RepoRoot = Join-Path $PSScriptRoot '..'
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$electronRoot = Join-Path $RepoRoot 'electron-app'
$releaseRoot = Join-Path $electronRoot 'release'
$buildCore = Join-Path $PSScriptRoot 'git-push-ota.ps1'
$restoreTools = Join-Path $PSScriptRoot 'restore-tools.ps1'

if (-not (Test-Path -LiteralPath $buildCore -PathType Leaf)) {
  throw "未找到发布构建校验器：$buildCore"
}
if (-not (Test-Path -LiteralPath $restoreTools -PathType Leaf)) {
  throw "未找到仓库工具恢复脚本：$restoreTools"
}

& $restoreTools -RepoRoot $RepoRoot
if ($LASTEXITCODE -ne 0) {
  throw "仓库工具恢复失败，退出代码：$LASTEXITCODE"
}

$expectedReleaseRoot = [System.IO.Path]::GetFullPath((Join-Path $RepoRoot 'electron-app\release'))
$resolvedReleaseRoot = [System.IO.Path]::GetFullPath($releaseRoot)
if (-not $resolvedReleaseRoot.Equals($expectedReleaseRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
  throw "拒绝清理非预期发布目录：$resolvedReleaseRoot"
}

if (Test-Path -LiteralPath $resolvedReleaseRoot -PathType Container) {
  Remove-Item -LiteralPath $resolvedReleaseRoot -Recurse -Force
}

$arguments = @(
  '-NoProfile',
  '-ExecutionPolicy', 'Bypass',
  '-File', $buildCore,
  '-RepoRoot', $RepoRoot
)

if (-not [string]::IsNullOrWhiteSpace($LoaderRoot)) {
  $arguments += @('-LoaderRoot', $LoaderRoot)
}

& powershell @arguments
if ($LASTEXITCODE -ne 0) {
  throw "发布构建与校验失败，退出代码：$LASTEXITCODE"
}

$packageJson = Get-Content -Raw -LiteralPath (Join-Path $electronRoot 'package.json') | ConvertFrom-Json
$zipName = "LongYinProMaxApp-$($packageJson.version)-win-x64.zip"
$zipPath = Join-Path $resolvedReleaseRoot $zipName
$manifestPath = Join-Path $resolvedReleaseRoot 'update-manifest.json'

if (-not (Test-Path -LiteralPath $zipPath -PathType Leaf)) {
  throw "构建完成后未找到预期 ZIP：$zipPath"
}
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
  throw "构建完成后未找到 OTA manifest：$manifestPath"
}

Write-Host "Verified release ZIP: $zipPath" -ForegroundColor Green
Write-Host "Verified OTA manifest: $manifestPath" -ForegroundColor Green
