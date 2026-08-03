[CmdletBinding()]
param(
  [string]$RepoRoot = '',
  [string]$LoaderRoot = '',
  [string]$ReleaseNotesPath,
  [switch]$SkipBuild,
  [switch]$SkipPublish,
  [switch]$SkipPush,
  [switch]$DryRun,
  [switch]$AllowDirty
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$CanonicalReleaseRepo = 'G:\Steam\steamapps\common\longyin_plus_repo'
$ExpectedGitHubOwner = 'Herbert-Zheng'
$ExpectedGitHubRepo = 'longyin_plus'

function Write-Step([string]$Message) {
  Write-Host "==> $Message" -ForegroundColor Cyan
}

function Invoke-Git {
  param(
    [Parameter(Mandatory = $true)]
    [string[]]$Arguments
  )

  $output = & git -C $RepoRoot @Arguments 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw "git $($Arguments -join ' ') 失败：`n$output"
  }

  return ($output -join "`n").Trim()
}

function Invoke-GitAllowFailure {
  param(
    [Parameter(Mandatory = $true)]
    [string[]]$Arguments
  )

  $output = & git -C $RepoRoot @Arguments 2>&1
  return [pscustomobject]@{
    ExitCode = $LASTEXITCODE
    Output = ($output -join "`n").Trim()
  }
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
    throw "未找到 $nodeModules 。请先在 electron-app 目录执行 npm install，再执行 git push ota。"
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

function Get-GitHubToken {
  if ($env:GITHUB_TOKEN) {
    return $env:GITHUB_TOKEN
  }

  if ($env:GH_TOKEN) {
    return $env:GH_TOKEN
  }

  $credentialInput = "protocol=https`nhost=github.com`n`n"
  $credentialResponse = $credentialInput | git credential fill 2>$null

  if (-not $credentialResponse) {
    throw '未找到 GitHub 凭据。请先设置 GITHUB_TOKEN，或确保 git credential manager 已登录 github.com。'
  }

  $passwordLine = $credentialResponse | Where-Object { $_ -like 'password=*' } | Select-Object -First 1
  if (-not $passwordLine) {
    throw 'git credential fill 未返回 GitHub password/token。'
  }

  return ($passwordLine -replace '^password=', '').Trim()
}

function Parse-OriginRepo {
  $origin = Invoke-Git @('remote', 'get-url', 'origin')

  if ($origin -match 'github\.com[:/](?<owner>[^/]+)/(?<repo>[^/.]+?)(?:\.git)?$') {
    return [pscustomobject]@{
      Owner = $Matches.owner
      Repo = $Matches.repo
      Origin = $origin
    }
  }

  throw "无法从 origin 解析 GitHub 仓库：$origin"
}

function New-ReleaseNotes {
  param(
    [string]$Version,
    [string]$Branch,
    [string]$PreviousTag
  )

  if ($ReleaseNotesPath) {
    if (-not (Test-Path $ReleaseNotesPath)) {
      throw "未找到 Release notes 文件：$ReleaseNotesPath"
    }

    return (Get-Content -Path $ReleaseNotesPath -Raw -Encoding UTF8).Trim()
  }

  $range = if ($PreviousTag) { "$PreviousTag..HEAD" } else { 'HEAD' }
  $commitLines = Invoke-GitAllowFailure @('log', '--pretty=format:%s', $range)
  $subjects = @()

  if ($commitLines.ExitCode -eq 0 -and $commitLines.Output) {
    $subjects = @($commitLines.Output -split "`r?`n" | Where-Object { $_.Trim() })
  }

  if ($subjects.Count -eq 0) {
    $subjects = @('本次版本没有检测到新的提交说明，请按需补充发布说明。')
  }

  $bulletLines = $subjects | ForEach-Object { "- $($_.Trim())" }

  return @(
    '## 本次更新'
    $bulletLines
    ''
    '## 发布信息'
    "- 版本：v$Version"
    "- 分支：$Branch"
    if ($PreviousTag) { "- 变更范围：$PreviousTag..HEAD" } else { '- 变更范围：仓库初始发布范围' }
  ) -join "`n"
}

function Invoke-GitHubApi {
  param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('GET', 'POST', 'PATCH', 'DELETE')]
    [string]$Method,
    [Parameter(Mandatory = $true)]
    [string]$Url,
    $Body
  )

  $headers = @{
    Accept                 = 'application/vnd.github+json'
    Authorization          = "Bearer $GitHubToken"
    'User-Agent'           = 'longyin-pro-max-ota-script'
    'X-GitHub-Api-Version' = '2022-11-28'
  }

  $invokeParams = @{
    Method      = $Method
    Uri         = $Url
    Headers     = $headers
    ErrorAction = 'Stop'
  }

  if ($null -ne $Body) {
    $invokeParams.ContentType = 'application/json; charset=utf-8'
    $invokeParams.Body = ($Body | ConvertTo-Json -Depth 8)
  }

  return Invoke-RestMethod @invokeParams
}

function Invoke-GitHubUpload {
  param(
    [Parameter(Mandatory = $true)]
    [string]$UploadUrl,
    [Parameter(Mandatory = $true)]
    [string]$FilePath,
    [Parameter(Mandatory = $true)]
    [string]$AssetName
  )

  $headers = @{
    Accept                 = 'application/vnd.github+json'
    Authorization          = "Bearer $GitHubToken"
    'User-Agent'           = 'longyin-pro-max-ota-script'
    'X-GitHub-Api-Version' = '2022-11-28'
  }

  $targetUrl = $UploadUrl + '?name=' + [uri]::EscapeDataString($AssetName)
  Invoke-RestMethod -Method Post -Uri $targetUrl -Headers $headers -InFile $FilePath -ContentType 'application/octet-stream' -ErrorAction Stop | Out-Null
}

if (-not $RepoRoot) {
  $RepoRoot = Join-Path $PSScriptRoot '..'
}
$RepoRoot = (Resolve-Path $RepoRoot).Path
$ElectronRoot = Join-Path $RepoRoot 'electron-app'
$ReleaseRoot = Join-Path $ElectronRoot 'release'

if (-not $DryRun) {
  if (-not (Test-Path -LiteralPath $CanonicalReleaseRepo -PathType Container)) {
    throw "唯一 OTA 发布仓库不存在：$CanonicalReleaseRepo"
  }
  $canonicalRepoPath = (Resolve-Path -LiteralPath $CanonicalReleaseRepo).Path
  if (-not $RepoRoot.Equals($canonicalRepoPath, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "OTA 构建、tag、push 和 Release 只能从 $canonicalRepoPath 执行；当前为 $RepoRoot。"
  }
}

if (-not (Test-Path (Join-Path $RepoRoot '.git'))) {
  throw "RepoRoot 不是 Git 仓库：$RepoRoot"
}

if (-not (Test-Path $ElectronRoot)) {
  throw "未找到 electron-app 目录：$ElectronRoot"
}

$resolvedLoaderRoot = Resolve-LoaderRoot -Candidate $LoaderRoot
$repoInfo = Parse-OriginRepo
if (-not $repoInfo.Owner.Equals($ExpectedGitHubOwner, [System.StringComparison]::OrdinalIgnoreCase) -or
    -not $repoInfo.Repo.Equals($ExpectedGitHubRepo, [System.StringComparison]::OrdinalIgnoreCase)) {
  throw "origin 不是预期 OTA 仓库：$($repoInfo.Origin)；期望 $ExpectedGitHubOwner/$ExpectedGitHubRepo。"
}
$packageJsonPath = Join-Path $ElectronRoot 'package.json'
$packageJson = Get-JsonFile $packageJsonPath
$version = [string]$packageJson.version
$tagName = "v$version"
$releaseName = "龙胤立志传 Pro Max $tagName"
$zipName = "LongYinProMaxApp-$version-win-x64.zip"
$zipPath = Join-Path $ReleaseRoot $zipName
$manifestPath = Join-Path $ReleaseRoot 'update-manifest.json'
$payloadInteropRelativePath = 'resources\payload\BepInEx\interop\Assembly-CSharp.dll'
$pluginBuildSpecs = @(
  [pscustomobject]@{
    Name = 'LongYinStaminaLock'
    SourceRelativePath = 'mod-src\LongYinStaminaLock\LongYinStaminaLock.cs'
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
$branch = Invoke-Git @('branch', '--show-current')
$statusPorcelain = Invoke-Git @('status', '--porcelain')
$tagList = Invoke-GitAllowFailure @('tag', '--sort=-creatordate')
$allTags = if ($tagList.Output) { $tagList.Output -split "`r?`n" | Where-Object { $_.Trim() } } else { @() }
$previousTag = $allTags | Where-Object { $_ -ne $tagName } | Select-Object -First 1
$releaseNotes = New-ReleaseNotes -Version $version -Branch $branch -PreviousTag $previousTag

Write-Step "仓库: $RepoRoot"
Write-Step "版本: $version"
Write-Step "分支: $branch"
Write-Step "origin: $($repoInfo.Origin)"
if ($previousTag) {
  Write-Step "上一个发布 tag: $previousTag"
}
else {
  Write-Step '未找到更早的发布 tag，将按首次发布处理。'
}

$statusSummary = if ($statusPorcelain) { $statusPorcelain } else { '工作树干净。' }
Write-Host $statusSummary

if ($statusPorcelain) {
  if (-not $DryRun) {
    throw "正式 OTA 发布要求工作树完全干净；-AllowDirty 仅供 -DryRun 验证使用。"
  }
  if (-not $AllowDirty) {
    throw "工作树不是干净状态。DryRun 如需验证当前改动，请显式添加 -AllowDirty。"
  }
}

$payloadSyncs = @()
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

$releaseNotesPreview = $releaseNotes -split "`r?`n" | Select-Object -First 12
Write-Step '发布说明预览'
$releaseNotesPreview | ForEach-Object { Write-Host $_ }

$postBuildStatus = Invoke-Git @('status', '--porcelain')
if ($postBuildStatus -and -not $DryRun) {
  throw "构建后工作树出现变化，资产与 HEAD 不一致。请提交构建产物后重新执行发布。`n$postBuildStatus"
}

if ($DryRun) {
  Write-Step 'DryRun 模式：到此为止，不推送代码、不发布 Release。'
  return
}

if ($SkipPush) {
  Write-Step '已跳过 git push。'
}
else {
  Write-Step "推送分支 origin/$branch"
  & git -C $RepoRoot push origin $branch
  if ($LASTEXITCODE -ne 0) {
    throw 'git push origin 分支失败。'
  }

  $tagExists = [bool](Invoke-GitAllowFailure @('rev-parse', '-q', '--verify', "refs/tags/$tagName")).Output
  if (-not $tagExists) {
    Write-Step "创建 tag $tagName"
    & git -C $RepoRoot tag -a $tagName -m $releaseName
    if ($LASTEXITCODE -ne 0) {
      throw "创建 tag $tagName 失败。"
    }
  }
  else {
    $tagCommit = Invoke-Git @('rev-list', '-n', '1', $tagName)
    $headCommit = Invoke-Git @('rev-parse', 'HEAD')
    if ($tagCommit -ne $headCommit) {
      throw "tag $tagName 已存在，但不在当前 HEAD 上。请先处理 tag，再执行发布。"
    }
  }

  Write-Step "推送 tag $tagName"
  & git -C $RepoRoot push origin $tagName
  if ($LASTEXITCODE -ne 0) {
    throw "git push origin $tagName 失败。"
  }
}

if ($SkipPublish) {
  Write-Step '已跳过 GitHub Release 发布。'
  return
}

$headCommit = Invoke-Git @('rev-parse', 'HEAD')
$remoteTagResult = Invoke-GitAllowFailure @('ls-remote', '--tags', 'origin', "refs/tags/$tagName^{}")
if ($remoteTagResult.ExitCode -ne 0 -or -not $remoteTagResult.Output) {
  $remoteTagResult = Invoke-GitAllowFailure @('ls-remote', '--tags', 'origin', "refs/tags/$tagName")
}
$remoteTagCommit = if ($remoteTagResult.Output) {
  ($remoteTagResult.Output -split "\s+" | Select-Object -First 1).Trim()
} else {
  ''
}
if ($remoteTagResult.ExitCode -ne 0 -or $remoteTagCommit -ne $headCommit) {
  throw "远端 tag $tagName 未指向当前 HEAD，禁止上传 Release 资产：remote=$remoteTagCommit, HEAD=$headCommit"
}

$GitHubToken = Get-GitHubToken
$apiRoot = "https://api.github.com/repos/$($repoInfo.Owner)/$($repoInfo.Repo)"
$releaseLookup = $null

try {
  $releaseLookup = Invoke-GitHubApi -Method GET -Url "$apiRoot/releases/tags/$tagName"
}
catch {
  $response = $_.Exception.Response
  $statusCode = if ($response) { [int]$response.StatusCode } else { 0 }
  if ($statusCode -ne 404) {
    throw
  }
}

$releaseBodyPayload = @{
  tag_name         = $tagName
  target_commitish = $branch
  name             = $releaseName
  body             = $releaseNotes
  draft            = $false
  prerelease       = $false
}

if ($releaseLookup) {
  Write-Step "更新现有 GitHub Release: $tagName"
  $release = Invoke-GitHubApi -Method PATCH -Url "$apiRoot/releases/$($releaseLookup.id)" -Body $releaseBodyPayload
}
else {
  Write-Step "创建新的 GitHub Release: $tagName"
  $release = Invoke-GitHubApi -Method POST -Url "$apiRoot/releases" -Body $releaseBodyPayload
}

$existingAssets = @($release.assets)
$assetNames = @($zipName, 'update-manifest.json')
foreach ($assetName in $assetNames) {
  foreach ($asset in @($existingAssets | Where-Object { $_.name -eq $assetName })) {
    Write-Step "删除旧资产: $assetName"
    Invoke-GitHubApi -Method DELETE -Url "$apiRoot/releases/assets/$($asset.id)" | Out-Null
  }
}

$cleanUploadUrl = [string]$release.upload_url -replace '\{\?name,label\}$', ''
Write-Step "上传资产: $zipName"
Invoke-GitHubUpload -UploadUrl $cleanUploadUrl -FilePath $zipPath -AssetName $zipName
Write-Step '上传资产: update-manifest.json'
Invoke-GitHubUpload -UploadUrl $cleanUploadUrl -FilePath $manifestPath -AssetName 'update-manifest.json'

$finalRelease = Invoke-GitHubApi -Method GET -Url "$apiRoot/releases/tags/$tagName"
$finalAssets = @($finalRelease.assets | ForEach-Object { $_.name })

if ($finalAssets -notcontains $zipName -or $finalAssets -notcontains 'update-manifest.json') {
  throw 'GitHub Release 已创建，但 OTA 资产不完整。'
}

Write-Step 'OTA 发布完成。'
Write-Host "Release: $($finalRelease.html_url)" -ForegroundColor Green
Write-Host "Assets: $($finalAssets -join ', ')" -ForegroundColor Green
