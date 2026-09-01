[CmdletBinding()]
param(
  [string]$RepoRoot = '',
  [string]$LoaderRoot = '',
  [switch]$SkipBuild
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Internal build/verification core retained under its historical filename.
# It has no push, tag, GitHub API, or Release asset write path.

function Write-Step([string]$Message) {
  Write-Host "==> $Message" -ForegroundColor Cyan
}

function Invoke-Npm {
  param(
    [Parameter(Mandatory = $true)]
    [string[]]$Arguments
  )

  Push-Location $ElectronRoot
  try {
    & npm @Arguments
    if ($LASTEXITCODE -ne 0) {
      throw "npm $($Arguments -join ' ') 失败。"
    }
  }
  finally {
    Pop-Location
  }
}

function Get-JsonFile([string]$Path) {
  return Get-Content -Path $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Assert-BuildPrereqs {
  $nodeModules = Join-Path $ElectronRoot 'node_modules'
  if (-not (Test-Path $nodeModules)) {
    throw "未找到 $nodeModules 。请先在 electron-app 目录执行 npm ci。"
  }
}

function Assert-FileExists {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path,
    [Parameter(Mandatory = $true)]
    [string]$Label
  )

  if (-not (Test-Path $Path)) {
    throw "未找到 $Label：$Path"
  }
}

function Get-Sha256Lower {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  Assert-FileExists -Path $Path -Label '文件'
  return (Get-FileHash -Path $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Resolve-LoaderRoot {
  param(
    [string]$Candidate
  )

  $selected = $Candidate
  $source = '命令行 -LoaderRoot'
  if (-not $selected -and $env:LONGYIN_LOADER_ROOT) {
    $selected = $env:LONGYIN_LOADER_ROOT
    $source = 'LONGYIN_LOADER_ROOT'
  }
  if (-not $selected) {
    $selected = Join-Path $RepoRoot 'dist'
    $source = '仓库 dist（默认的可发布 interop 基线）'
  }

  if (-not (Test-Path -LiteralPath $selected -PathType Container)) {
    throw "LoaderRoot 不存在（来源：$source）：$selected"
  }

  $resolved = (Resolve-Path -LiteralPath $selected).Path
  foreach ($requiredDirectory in @('BepInEx\core', 'BepInEx\interop')) {
    $requiredPath = Join-Path $resolved $requiredDirectory
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Container)) {
      throw "LoaderRoot 缺少 $requiredDirectory（来源：$source）：$resolved"
    }
  }

  Write-Step "LoaderRoot: $resolved（来源：$source）"
  return $resolved
}

function Get-PluginBuildProvenance {
  param(
    [Parameter(Mandatory = $true)]
    [string]$PluginName,
    [Parameter(Mandatory = $true)]
    [string]$PluginSource,
    [Parameter(Mandatory = $true)]
    [string]$StagedPlugin,
    [Parameter(Mandatory = $true)]
    [string]$ResolvedLoaderRoot
  )

  $metadataPath = "$StagedPlugin.build.json"
  Assert-FileExists -Path $PluginSource -Label "$PluginName 源文件"
  Assert-FileExists -Path $StagedPlugin -Label "暂存 $PluginName DLL"
  Assert-FileExists -Path $metadataPath -Label "$PluginName 构建元数据"

  try {
    $metadata = Get-JsonFile $metadataPath
  }
  catch {
    throw "$PluginName 构建元数据无效：$metadataPath`n$($_.Exception.Message)"
  }

  if ([int]$metadata.SchemaVersion -ne 1) {
    throw "不支持的插件构建元数据版本：$($metadata.SchemaVersion)"
  }
  if ([string]$metadata.PluginName -ne $PluginName) {
    throw "构建元数据插件名不一致：$($metadata.PluginName) vs $PluginName"
  }

  $sourceHash = Get-Sha256Lower -Path $PluginSource
  $stagedHash = Get-Sha256Lower -Path $StagedPlugin
  $loaderInterop = Join-Path $ResolvedLoaderRoot 'BepInEx\interop\Assembly-CSharp.dll'
  $distInterop = Join-Path $RepoRoot 'dist\BepInEx\interop\Assembly-CSharp.dll'
  Assert-FileExists -Path $loaderInterop -Label 'LoaderRoot Assembly-CSharp interop'
  Assert-FileExists -Path $distInterop -Label 'dist Assembly-CSharp interop'
  $loaderInteropHash = Get-Sha256Lower -Path $loaderInterop
  $distInteropHash = Get-Sha256Lower -Path $distInterop

  if ([string]$metadata.Source.Sha256 -ne $sourceHash) {
    throw "源码已在构建后变化：元数据 $($metadata.Source.Sha256) vs 当前 $sourceHash"
  }
  if ([string]$metadata.Artifact.Sha256 -ne $stagedHash) {
    throw "暂存 DLL 与构建元数据不一致：$($metadata.Artifact.Sha256) vs $stagedHash"
  }
  if ([string]$metadata.Interop.AssemblyCSharpSha256 -ne $loaderInteropHash) {
    throw "LoaderRoot interop 与构建元数据不一致：$($metadata.Interop.AssemblyCSharpSha256) vs $loaderInteropHash"
  }
  if ($loaderInteropHash -ne $distInteropHash) {
    throw "LoaderRoot interop 与 OTA dist interop 不一致，禁止发布：$loaderInteropHash vs $distInteropHash"
  }

  return [pscustomobject]@{
    MetadataPath = $metadataPath
    Metadata     = $metadata
    SourceHash   = $sourceHash
    ArtifactHash = $stagedHash
    InteropHash  = $loaderInteropHash
    DistInteropPath = $distInterop
  }
}

function Sync-PluginPayload {
  param(
    [Parameter(Mandatory = $true)]
    [string]$PluginName,
    [Parameter(Mandatory = $true)]
    [string]$PluginSourceRelativePath,
    [Parameter(Mandatory = $true)]
    [string]$ResolvedLoaderRoot
  )

  $pluginSource = Join-Path $RepoRoot $PluginSourceRelativePath
  $pluginStaged = Join-Path $RepoRoot "_codex_staged_updates\BepInEx\plugins\$PluginName.dll"
  $pluginPending = "$pluginStaged.pending"
  $distPlugin = Join-Path $RepoRoot "dist\BepInEx\plugins\$PluginName.dll"
  $buildScript = Join-Path $RepoRoot 'mod-src\build-il2cpp-plugin.ps1'

  Assert-FileExists -Path $pluginSource -Label "$PluginName 源文件"
  Assert-FileExists -Path $buildScript -Label 'IL2CPP 插件构建脚本'

  $distDir = Split-Path -Parent $distPlugin
  if (-not (Test-Path $distDir)) {
    New-Item -ItemType Directory -Path $distDir | Out-Null
  }

  Write-Step "构建 $PluginName 插件"
  $buildOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $buildScript `
    -Source $pluginSource `
    -StagedPluginOutput $pluginStaged `
    -LoaderRoot $ResolvedLoaderRoot 2>&1

  $buildExitCode = $LASTEXITCODE
  if ($buildOutput) {
    $buildOutput | ForEach-Object { Write-Host $_ }
  }

  if ($buildExitCode -ne 0) {
    throw "$PluginName 插件构建失败。"
  }

  Assert-FileExists -Path $pluginPending -Label "$PluginName pending 标记"
  $provenance = Get-PluginBuildProvenance `
    -PluginName $PluginName `
    -PluginSource $pluginSource `
    -StagedPlugin $pluginStaged `
    -ResolvedLoaderRoot $ResolvedLoaderRoot

  Write-Step "同步 $PluginName 到 OTA payload(dist)"
  Copy-Item -Path $pluginStaged -Destination $distPlugin -Force

  $distHash = Get-Sha256Lower -Path $distPlugin
  if ($provenance.ArtifactHash -ne $distHash) {
    throw "$PluginName 暂存产物与 dist payload 不一致：$($provenance.ArtifactHash) vs $distHash"
  }

  Write-Step "$PluginName payload 已同步: $($provenance.ArtifactHash)"
  Write-Step "$PluginName 构建基线: source=$($provenance.SourceHash), interop=$($provenance.InteropHash)"
  return [pscustomobject]@{
    PluginName   = $PluginName
    ArtifactPath = $pluginStaged
    DistPath     = $distPlugin
    ZipEntrySuffix = "resources\payload\BepInEx\plugins\$PluginName.dll"
    MetadataPath = $provenance.MetadataPath
    ArtifactHash = $provenance.ArtifactHash
    DistHash     = $distHash
    SourceHash   = $provenance.SourceHash
    InteropHash  = $provenance.InteropHash
    DistInteropPath = $provenance.DistInteropPath
  }
}

function Get-ZipEntrySha256 {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ZipPath,
    [Parameter(Mandatory = $true)]
    [string]$EntrySuffix
  )

  Add-Type -AssemblyName System.IO.Compression
  Add-Type -AssemblyName System.IO.Compression.FileSystem

  $zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
  try {
    $entry = $zip.Entries | Where-Object { $_.FullName.Replace('/', '\').EndsWith($EntrySuffix, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1
    if (-not $entry) {
      throw "ZIP 内未找到目标条目：$EntrySuffix"
    }

    $stream = $entry.Open()
    try {
      $sha = [System.Security.Cryptography.SHA256]::Create()
      try {
        return ([System.BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '').ToLowerInvariant()
      }
      finally {
        $sha.Dispose()
      }
    }
    finally {
      $stream.Dispose()
    }
  }
  finally {
    $zip.Dispose()
  }
}

if (-not $RepoRoot) {
  $RepoRoot = Join-Path $PSScriptRoot '..'
}

function Assert-ZipEntryAbsent {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ZipPath,
    [Parameter(Mandatory = $true)]
    [string]$EntrySuffix,
    [Parameter(Mandatory = $true)]
    [string]$Label
  )

  Add-Type -AssemblyName System.IO.Compression
  Add-Type -AssemblyName System.IO.Compression.FileSystem

  $zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
  try {
    $legacyEntry = $zip.Entries | Where-Object {
      $_.FullName.Replace('/', '\').EndsWith($EntrySuffix, [System.StringComparison]::OrdinalIgnoreCase)
    } | Select-Object -First 1
    if ($legacyEntry) {
      throw "$Label 不应出现在 ZIP 中：$($legacyEntry.FullName)"
    }
  }
  finally {
    $zip.Dispose()
  }
}
$RepoRoot = (Resolve-Path $RepoRoot).Path
$ElectronRoot = Join-Path $RepoRoot 'electron-app'
$ReleaseRoot = Join-Path $ElectronRoot 'release'

if (-not (Test-Path (Join-Path $RepoRoot '.git'))) {
  throw "RepoRoot 不是 Git 仓库：$RepoRoot"
}

if (-not (Test-Path $ElectronRoot)) {
  throw "未找到 electron-app 目录：$ElectronRoot"
}

$resolvedLoaderRoot = Resolve-LoaderRoot -Candidate $LoaderRoot
$packageJsonPath = Join-Path $ElectronRoot 'package.json'
$packageJson = Get-JsonFile $packageJsonPath
$version = [string]$packageJson.version
$zipName = "LongYinProMaxApp-$version-win-x64.zip"
$zipPath = Join-Path $ReleaseRoot $zipName
$manifestPath = Join-Path $ReleaseRoot 'update-manifest.json'
$payloadInteropRelativePath = 'resources\payload\BepInEx\interop\Assembly-CSharp.dll'
$legacyPrimaryPluginRelativePath = 'BepInEx\plugins\LongYinStaminaLock.dll'
$legacyPrimaryPluginDistPath = Join-Path $RepoRoot "dist\$legacyPrimaryPluginRelativePath"
$legacyPrimaryPluginZipSuffix = "resources\payload\$legacyPrimaryPluginRelativePath"
$pluginBuildSpecs = @(
  [pscustomobject]@{
    Name = 'LongYinProMax'
    SourceRelativePath = 'mod-src\LongYinProMax\LongYinProMax.cs'
  },
  [pscustomobject]@{
    Name = 'LongYinBattleTurbo'
    SourceRelativePath = 'mod-src\LongYinBattleTurbo\LongYinBattleTurbo.cs'
  },
  [pscustomobject]@{
    Name = 'LongYinHorseStaminaMultiplier'
    SourceRelativePath = 'mod-src\LongYinHorseStaminaMultiplier\LongYinHorseStaminaMultiplier.cs'
  },
  [pscustomobject]@{
    Name = 'LongYinSkipIntro'
    SourceRelativePath = 'mod-src\LongYinSkipIntro\LongYinSkipIntro.cs'
  }
)
Write-Step "仓库: $RepoRoot"
Write-Step "版本: $version"

$payloadSyncs = @()
if (Test-Path -LiteralPath $legacyPrimaryPluginDistPath -PathType Leaf) {
  throw "dist 中仍存在旧主插件，禁止打包新旧 DLL：$legacyPrimaryPluginDistPath"
}

if (-not $SkipBuild) {
  Assert-BuildPrereqs
  foreach ($pluginSpec in $pluginBuildSpecs) {
    $payloadSyncs += Sync-PluginPayload `
      -PluginName $pluginSpec.Name `
      -PluginSourceRelativePath $pluginSpec.SourceRelativePath `
      -ResolvedLoaderRoot $resolvedLoaderRoot
  }
  Write-Step '执行 npm run typecheck'
  Invoke-Npm @('run', 'typecheck')
  Write-Step '执行 npm run build'
  Invoke-Npm @('run', 'build')
}
else {
  Write-Step '已跳过构建步骤。'
  foreach ($pluginSpec in $pluginBuildSpecs) {
    $pluginSource = Join-Path $RepoRoot $pluginSpec.SourceRelativePath
    $pluginStaged = Join-Path $RepoRoot "_codex_staged_updates\BepInEx\plugins\$($pluginSpec.Name).dll"
    $provenance = Get-PluginBuildProvenance `
      -PluginName $pluginSpec.Name `
      -PluginSource $pluginSource `
      -StagedPlugin $pluginStaged `
      -ResolvedLoaderRoot $resolvedLoaderRoot
    $payloadSyncs += [pscustomobject]@{
      PluginName   = $pluginSpec.Name
      ArtifactPath = $pluginStaged
      DistPath     = Join-Path $RepoRoot "dist\BepInEx\plugins\$($pluginSpec.Name).dll"
      ZipEntrySuffix = "resources\payload\BepInEx\plugins\$($pluginSpec.Name).dll"
      MetadataPath = $provenance.MetadataPath
      ArtifactHash = $provenance.ArtifactHash
      SourceHash   = $provenance.SourceHash
      InteropHash  = $provenance.InteropHash
      DistInteropPath = $provenance.DistInteropPath
    }
    Write-Step "$($pluginSpec.Name) 已验证现有构建来源: source=$($provenance.SourceHash), interop=$($provenance.InteropHash), artifact=$($provenance.ArtifactHash)"
  }
}

if ($payloadSyncs.Count -ne $pluginBuildSpecs.Count) {
  throw "可维护插件构建数量不完整：$($payloadSyncs.Count) vs $($pluginBuildSpecs.Count)"
}

$compatibilityCheck = Join-Path $RepoRoot 'scripts\check-runtime-compatibility.ps1'
Assert-FileExists -Path $compatibilityCheck -Label '运行时兼容性检查脚本'
Write-Step '执行维护插件静态兼容性检查'
& powershell -NoProfile -ExecutionPolicy Bypass -File $compatibilityCheck `
  -RepoRoot $RepoRoot `
  -InteropAssembly (Join-Path $RepoRoot 'dist\BepInEx\interop\Assembly-CSharp.dll') `
  -SkipRuntimeLog
if ($LASTEXITCODE -ne 0) {
  throw '维护插件静态兼容性检查失败。'
}

$auctionEventCheck = Join-Path $RepoRoot 'scripts\check-auction-event-semantics.ps1'
Assert-FileExists -Path $auctionEventCheck -Label '拍卖会等级语义检查脚本'
Write-Step '执行拍卖会等级语义检查'
& powershell -NoProfile -ExecutionPolicy Bypass -File $auctionEventCheck
if ($LASTEXITCODE -ne 0) {
  throw '拍卖会等级语义检查失败。'
}

$auctionPreviewCheck = Join-Path $RepoRoot 'scripts\check-auction-preview-semantics.ps1'
Assert-FileExists -Path $auctionPreviewCheck -Label '拍卖预览刷新语义检查脚本'
Write-Step '执行拍卖预览刷新语义检查'
& powershell -NoProfile -ExecutionPolicy Bypass -File $auctionPreviewCheck
if ($LASTEXITCODE -ne 0) {
  throw '拍卖预览刷新语义检查失败。'
}

$yellowCraneRefreshCheck = Join-Path $RepoRoot 'scripts\check-yellow-crane-refresh-semantics.ps1'
Assert-FileExists -Path $yellowCraneRefreshCheck -Label '黄鹤楼候选人刷新语义检查脚本'
Write-Step '执行黄鹤楼候选人刷新语义检查'
& powershell -NoProfile -ExecutionPolicy Bypass -File $yellowCraneRefreshCheck
if ($LASTEXITCODE -ne 0) {
  throw '黄鹤楼候选人刷新语义检查失败。'
}

$bountyRefreshCheck = Join-Path $RepoRoot 'scripts\check-bounty-refresh-semantics.ps1'
Assert-FileExists -Path $bountyRefreshCheck -Label '委托刷新语义检查脚本'
Write-Step '执行委托刷新语义检查'
& powershell -NoProfile -ExecutionPolicy Bypass -File $bountyRefreshCheck
if ($LASTEXITCODE -ne 0) {
  throw '委托刷新语义检查失败。'
}

if (-not (Test-Path $zipPath)) {
  throw "未找到 OTA ZIP：$zipPath"
}

if (-not (Test-Path $manifestPath)) {
  throw "未找到 OTA manifest：$manifestPath"
}

$manifest = Get-JsonFile $manifestPath
if ([string]$manifest.version -ne $version) {
  throw "manifest.version 与 package.json.version 不一致：$($manifest.version) vs $version"
}

if ([string]$manifest.zipAsset -ne $zipName) {
  throw "manifest.zipAsset 与预期 ZIP 名称不一致：$($manifest.zipAsset) vs $zipName"
}

$zipHash = (Get-FileHash -Path $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ([string]$manifest.sha256 -ne $zipHash) {
  throw "manifest.sha256 与 ZIP 实际 SHA256 不一致。"
}

foreach ($payloadSync in $payloadSyncs) {
  Assert-FileExists -Path $payloadSync.DistPath -Label "dist payload $($payloadSync.PluginName)"
  $distPluginHash = Get-Sha256Lower -Path $payloadSync.DistPath
  $zipPluginHash = Get-ZipEntrySha256 -ZipPath $zipPath -EntrySuffix $payloadSync.ZipEntrySuffix
  if ($distPluginHash -ne $zipPluginHash) {
    throw "ZIP 内 $($payloadSync.PluginName).dll 与 dist payload 不一致：$distPluginHash vs $zipPluginHash"
  }
  if ($payloadSync.ArtifactHash -ne $zipPluginHash) {
    throw "ZIP 内 $($payloadSync.PluginName).dll 与构建产物不一致：$($payloadSync.ArtifactHash) vs $zipPluginHash"
  }
}

Assert-ZipEntryAbsent `
  -ZipPath $zipPath `
  -EntrySuffix $legacyPrimaryPluginZipSuffix `
  -Label '旧主插件 LongYinStaminaLock.dll'

$interopHashes = @($payloadSyncs | ForEach-Object { $_.InteropHash } | Select-Object -Unique)
if ($interopHashes.Count -ne 1) {
  throw "插件不是基于同一份 Assembly-CSharp interop 构建：$($interopHashes -join ', ')"
}
$distInteropHash = Get-Sha256Lower -Path $payloadSyncs[0].DistInteropPath
$zipInteropHash = Get-ZipEntrySha256 -ZipPath $zipPath -EntrySuffix $payloadInteropRelativePath
if ($distInteropHash -ne $zipInteropHash) {
  throw "ZIP 内 Assembly-CSharp interop 与 dist payload 不一致：$distInteropHash vs $zipInteropHash"
}
if ($interopHashes[0] -ne $zipInteropHash) {
  throw "ZIP 内 Assembly-CSharp interop 与插件构建基线不一致：$($interopHashes[0]) vs $zipInteropHash"
}

Write-Step "已校验 OTA 资产: $zipName + update-manifest.json"
foreach ($payloadSync in $payloadSyncs) {
  Write-Step "$($payloadSync.PluginName) 可追溯校验: source=$($payloadSync.SourceHash), interop=$($payloadSync.InteropHash), artifact=$($payloadSync.ArtifactHash)"
}

Write-Step '发布构建与 OTA 资产校验完成；本脚本不会 push、创建 tag 或写入 GitHub Release。'
