[CmdletBinding()]
param(
  [string]$RepoRoot = '',
  [string]$ReleaseRoot = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
  $RepoRoot = Join-Path $PSScriptRoot '..'
}
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

if ([string]::IsNullOrWhiteSpace($ReleaseRoot)) {
  $ReleaseRoot = Join-Path $RepoRoot 'electron-app\release'
}
$ReleaseRoot = (Resolve-Path -LiteralPath $ReleaseRoot).Path

function Assert-File([string]$Path, [string]$Label) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "未找到$Label：$Path"
  }
}

function Get-Sha256Lower([string]$Path) {
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$packageJson = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'electron-app\package.json') | ConvertFrom-Json
$version = [string]$packageJson.version
$zipName = "LongYinProMaxApp-$version-win-x64.zip"
$installerName = "LongYinProMaxSetup-$version-win-x64.exe"
$manifestName = 'update-manifest.json'

$zipPath = Join-Path $ReleaseRoot $zipName
$installerPath = Join-Path $ReleaseRoot $installerName
$manifestPath = Join-Path $ReleaseRoot $manifestName
Assert-File -Path $zipPath -Label 'OTA ZIP'
Assert-File -Path $installerPath -Label 'Windows 安装器 EXE'
Assert-File -Path $manifestPath -Label 'OTA manifest'

$manifest = Get-Content -Raw -LiteralPath $manifestPath -Encoding UTF8 | ConvertFrom-Json
$zipSha256 = Get-Sha256Lower -Path $zipPath
$installerSha256 = Get-Sha256Lower -Path $installerPath
if ([string]$manifest.version -ne $version) {
  throw "manifest.version 不匹配：$($manifest.version) vs $version"
}
if ([string]$manifest.zipAsset -ne $zipName -or [string]$manifest.sha256 -ne $zipSha256) {
  throw 'manifest 中的 OTA ZIP 名称或 SHA-256 不匹配。'
}
if ([string]$manifest.installerAsset -ne $installerName -or [string]$manifest.installerSha256 -ne $installerSha256) {
  throw 'manifest 中的 Windows 安装器名称或 SHA-256 不匹配。'
}

$staleZipNames = @(Get-ChildItem -LiteralPath $ReleaseRoot -File -Filter 'LongYinProMaxApp-*-win-x64.zip' |
    Where-Object Name -ne $zipName |
    Select-Object -ExpandProperty Name)
$staleInstallerNames = @(Get-ChildItem -LiteralPath $ReleaseRoot -File -Filter 'LongYinProMaxSetup-*-win-x64.exe' |
    Where-Object Name -ne $installerName |
    Select-Object -ExpandProperty Name)
if ($staleZipNames.Count -gt 0 -or $staleInstallerNames.Count -gt 0) {
  throw "release 目录包含陈旧产物：$(@($staleZipNames + $staleInstallerNames) -join ', ')"
}

[pscustomobject]@{
  Version = $version
  InstallerAsset = $installerName
  InstallerSha256 = $installerSha256
  ZipAsset = $zipName
  ZipSha256 = $zipSha256
}
