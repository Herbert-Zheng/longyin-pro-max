[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$TagName,
  [Parameter(Mandatory = $true)][string]$AssetsRoot,
  [string]$RepoRoot = '',
  [string]$Repository = $env:GITHUB_REPOSITORY
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($env:GITHUB_ACTIONS -ne 'true') {
  throw '正式 GitHub Release 只能由 GitHub Actions 发布。'
}
if ([string]::IsNullOrWhiteSpace($env:GH_TOKEN)) {
  throw 'GitHub Actions publish job 缺少 GH_TOKEN。'
}
if ([string]::IsNullOrWhiteSpace($Repository)) {
  throw '未提供 GitHub repository。'
}
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
  $RepoRoot = Join-Path $PSScriptRoot '..'
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$AssetsRoot = (Resolve-Path -LiteralPath $AssetsRoot).Path
$packageJson = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'electron-app\package.json') | ConvertFrom-Json
$version = [string]$packageJson.version
$expectedTag = "v$version"
if ($TagName -ne $expectedTag) {
  throw "tag 与 package.json.version 不一致：$TagName vs $expectedTag"
}

$zipName = "LongYinProMaxApp-$version-win-x64.zip"
$zipPath = Join-Path $AssetsRoot $zipName
$manifestPath = Join-Path $AssetsRoot 'update-manifest.json'
foreach ($path in @($zipPath, $manifestPath)) {
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "发布资产不存在：$path"
  }
}

$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
$zipHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ([string]$manifest.version -ne $version -or [string]$manifest.zipAsset -ne $zipName -or [string]$manifest.sha256 -ne $zipHash) {
  throw '下载到 publish job 的 ZIP 与 update-manifest.json 不一致。'
}

function Invoke-Gh {
  param(
    [Parameter(Mandatory = $true)][string[]]$Arguments,
    [switch]$AllowFailure
  )

  $output = & gh @Arguments 2>&1
  $exitCode = $LASTEXITCODE
  if ($exitCode -ne 0 -and -not $AllowFailure) {
    throw "gh $($Arguments -join ' ') 失败：`n$($output -join "`n")"
  }
  return [pscustomobject]@{
    ExitCode = $exitCode
    Output = ($output -join "`n").Trim()
  }
}

function Get-Release {
  $result = Invoke-Gh @('release', 'view', $TagName, '--repo', $Repository, '--json', 'isDraft,url,assets') -AllowFailure
  if ($result.ExitCode -ne 0) {
    return $null
  }
  return $result.Output | ConvertFrom-Json
}

$release = Get-Release
if ($null -eq $release) {
  $releaseNotesPath = Join-Path $RepoRoot "release-notes-$TagName.md"
  $createArguments = @(
    'release', 'create', $TagName,
    '--repo', $Repository,
    '--verify-tag',
    '--draft',
    '--title', "龙胤立志传 Pro Max $TagName"
  )
  if (Test-Path -LiteralPath $releaseNotesPath -PathType Leaf) {
    $createArguments += @('--notes-file', $releaseNotesPath)
  }
  else {
    $createArguments += '--generate-notes'
  }
  Invoke-Gh $createArguments | Out-Null
  $release = Get-Release
  if ($null -eq $release) {
    throw "创建 draft Release 后无法重新读取：$TagName"
  }
}

$expectedAssets = [ordered]@{
  $zipName = $zipPath
  'update-manifest.json' = $manifestPath
}
$releaseAssetNames = @($release.assets | ForEach-Object { [string]$_.name })
$unexpectedAssets = @($releaseAssetNames | Where-Object { -not $expectedAssets.Contains($_) })
if ($unexpectedAssets.Count -gt 0) {
  throw "Release 中存在非预期资产，拒绝自动发布：$($unexpectedAssets -join ', ')"
}

$runnerTemp = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [System.IO.Path]::GetTempPath() }
$verificationRoot = [System.IO.Path]::GetFullPath((Join-Path $runnerTemp "longyin-release-$TagName"))
$runnerTempFull = [System.IO.Path]::GetFullPath($runnerTemp).TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
if (-not ($verificationRoot + [System.IO.Path]::DirectorySeparatorChar).StartsWith($runnerTempFull, [System.StringComparison]::OrdinalIgnoreCase)) {
  throw "拒绝使用 RUNNER_TEMP 之外的校验目录：$verificationRoot"
}
if (Test-Path -LiteralPath $verificationRoot -PathType Container) {
  Remove-Item -LiteralPath $verificationRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $verificationRoot | Out-Null

foreach ($entry in $expectedAssets.GetEnumerator()) {
  $assetName = [string]$entry.Key
  $localPath = [string]$entry.Value
  $remoteAsset = @($release.assets | Where-Object { [string]$_.name -eq $assetName }) | Select-Object -First 1

  if ($null -eq $remoteAsset) {
    if (-not $release.isDraft) {
      throw "已发布 Release 缺少资产，禁止原地修改：$assetName"
    }
    Invoke-Gh @('release', 'upload', $TagName, $localPath, '--repo', $Repository) | Out-Null
    $release = Get-Release
  }

  $assetVerificationDir = Join-Path $verificationRoot ([System.IO.Path]::GetFileNameWithoutExtension($assetName))
  New-Item -ItemType Directory -Path $assetVerificationDir | Out-Null
  Invoke-Gh @('release', 'download', $TagName, '--repo', $Repository, '--pattern', $assetName, '--dir', $assetVerificationDir, '--clobber') | Out-Null
  $downloadedPath = Join-Path $assetVerificationDir $assetName
  if (-not (Test-Path -LiteralPath $downloadedPath -PathType Leaf)) {
    throw "无法下载并验证 Release 资产：$assetName"
  }
  $localHash = (Get-FileHash -LiteralPath $localPath -Algorithm SHA256).Hash.ToLowerInvariant()
  $remoteHash = (Get-FileHash -LiteralPath $downloadedPath -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($localHash -ne $remoteHash) {
    throw "Release 资产与已验证构建产物不一致，禁止覆盖：$assetName"
  }
}

$release = Get-Release
$finalNames = @($release.assets | ForEach-Object { [string]$_.name })
foreach ($assetName in $expectedAssets.Keys) {
  if ($finalNames -notcontains $assetName) {
    throw "Release 资产不完整：$assetName"
  }
}

if ($release.isDraft) {
  Invoke-Gh @('release', 'edit', $TagName, '--repo', $Repository, '--draft=false', '--latest') | Out-Null
  $release = Get-Release
}
if ($release.isDraft) {
  throw "Release 仍处于 draft 状态：$TagName"
}

Write-Host "Published verified Release: $($release.url)" -ForegroundColor Green
