[CmdletBinding()]
param(
  [string]$RepoRoot = '',
  [string]$ReleaseRoot = '',
  [switch]$RequireValidSignature
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

function Assert-ValidAuthenticodeSignature([string]$Path, [string]$Label) {
  Assert-File -Path $Path -Label $Label
  $signature = Get-AuthenticodeSignature -LiteralPath $Path
  if ($signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid -or -not $signature.SignerCertificate) {
    throw "$Label 必须带可信 Authenticode 签名；当前状态：$($signature.Status)"
  }
  return $signature.SignerCertificate.Thumbprint
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

$signerThumbprint = $null
if ($RequireValidSignature) {
  $unpackedRoot = Join-Path $ReleaseRoot 'win-unpacked'
  if (-not (Test-Path -LiteralPath $unpackedRoot -PathType Container)) {
    throw "未找到打包目录：$unpackedRoot"
  }
  $packagedExecutables = @(Get-ChildItem -LiteralPath $unpackedRoot -Recurse -File -Filter '*.exe')
  if ($packagedExecutables.Count -eq 0) {
    throw "打包目录中没有可执行文件：$unpackedRoot"
  }
  $thumbprints = @(
    Assert-ValidAuthenticodeSignature -Path $installerPath -Label 'Windows 安装器 EXE'
    $packagedExecutables | ForEach-Object {
      $relativePath = [System.IO.Path]::GetRelativePath($unpackedRoot, $_.FullName)
      Assert-ValidAuthenticodeSignature -Path $_.FullName -Label "打包后的 $relativePath"
    }
  ) | Sort-Object -Unique
  if ($thumbprints.Count -ne 1) {
    throw "Windows 发布 EXE 必须由同一个证书签名；当前签名证书数量：$($thumbprints.Count)"
  }
  $signerThumbprint = $thumbprints[0]
}

[pscustomobject]@{
  Version = $version
  InstallerAsset = $installerName
  InstallerSha256 = $installerSha256
  ZipAsset = $zipName
  ZipSha256 = $zipSha256
  SignatureRequired = [bool]$RequireValidSignature
  SignerThumbprint = $signerThumbprint
}
