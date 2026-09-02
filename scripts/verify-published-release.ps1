[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidatePattern('^v\d+\.\d+\.\d+$')]
  [string]$TagName,

  [string]$Repository = 'Herbert-Zheng/longyin-pro-max',
  [string]$DownloadRoot = '',
  [string]$ReleaseNotesChangelogPath = '',
  [ValidateRange(1, 30)]
  [int]$LatestRetryCount = 12,
  [ValidateRange(10, 120)]
  [int]$SmokeTimeoutSeconds = 45,
  [switch]$KeepDownloaded
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step([string]$Message) {
  Write-Host "==> $Message" -ForegroundColor Cyan
}

function Get-GitHubHeaders {
  $headers = @{
    Accept = 'application/vnd.github+json'
    'X-GitHub-Api-Version' = '2022-11-28'
    'User-Agent' = 'longyin-pro-max-release-verifier'
  }
  if ($env:GH_TOKEN) {
    $headers.Authorization = "Bearer $env:GH_TOKEN"
  }
  return $headers
}

function Get-Sha256Lower([string]$Path) {
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Assert-File([string]$Path, [string]$Label) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "未找到$Label：$Path"
  }
}

function Normalize-ReleaseBody([string]$Body) {
  $lines = @(($Body -replace "`r`n?", "`n") -split "`n" | ForEach-Object { $_.TrimEnd() })
  while ($lines.Count -gt 0 -and [string]::IsNullOrWhiteSpace($lines[0])) {
    $lines = @($lines | Select-Object -Skip 1)
  }
  while ($lines.Count -gt 0 -and [string]::IsNullOrWhiteSpace($lines[-1])) {
    $lines = @($lines | Select-Object -First ($lines.Count - 1))
  }
  return $lines -join "`n"
}

function Remove-OwnedVerificationRoot([string]$Path) {
  $fullPath = [System.IO.Path]::GetFullPath($Path)
  $tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
  $leafName = [System.IO.Path]::GetFileName($fullPath.TrimEnd('\', '/'))
  if (-not $fullPath.StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
      -not $leafName.StartsWith('longyin-pro-max-release-verify-', [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "拒绝清理不受本脚本所有的目录：$fullPath"
  }
  if (Test-Path -LiteralPath $fullPath) {
    Remove-Item -LiteralPath $fullPath -Recurse -Force
  }
}

$version = $TagName.Substring(1)
$expectedZipName = "LongYinProMaxApp-$version-win-x64.zip"
$expectedManifestName = 'update-manifest.json'
$headers = Get-GitHubHeaders
$ownsDownloadRoot = -not $DownloadRoot
if ($ownsDownloadRoot) {
  $DownloadRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("longyin-pro-max-release-verify-{0}" -f [guid]::NewGuid().ToString('N'))
}
$DownloadRoot = [System.IO.Path]::GetFullPath($DownloadRoot)
$extractRoot = Join-Path $DownloadRoot 'extracted'
$smokeUserDataRoot = Join-Path $DownloadRoot 'smoke-user-data'

try {
  New-Item -ItemType Directory -Path $DownloadRoot -Force | Out-Null

  Write-Step "读取 GitHub latest Release：$Repository"
  $release = $null
  for ($attempt = 1; $attempt -le $LatestRetryCount; $attempt++) {
    try {
      $candidate = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repository/releases/latest" -Headers $headers
      if ([string]$candidate.tag_name -eq $TagName) {
        $release = $candidate
        break
      }
      Write-Host "latest 当前为 $($candidate.tag_name)，等待 $TagName（$attempt/$LatestRetryCount）。"
    }
    catch {
      Write-Host "latest 尚不可读，等待发布传播（$attempt/$LatestRetryCount）：$($_.Exception.Message)"
    }
    if ($attempt -lt $LatestRetryCount) {
      Start-Sleep -Seconds 5
    }
  }
  if (-not $release) {
    throw "GitHub latest Release 未在重试窗口内指向 $TagName。"
  }
  if ($release.draft -or $release.prerelease) {
    throw "$TagName 必须是已发布的稳定 Release。"
  }
  if ([string]::IsNullOrWhiteSpace([string]$release.body)) {
    throw "$TagName Release body 为空，OTA 更新历史不可用。"
  }
  $repoRoot = Split-Path -Parent $PSScriptRoot
  if ([string]::IsNullOrWhiteSpace($ReleaseNotesChangelogPath)) {
    $resolvedReleaseNotesChangelogPath = Join-Path $DownloadRoot 'tag-CHANGELOG.md'
    $tagChangelogLines = & git -C $repoRoot show "${TagName}:CHANGELOG.md" 2>&1
    if ($LASTEXITCODE -ne 0) {
      throw "无法从 $TagName 读取 CHANGELOG.md：`n$($tagChangelogLines -join "`n")"
    }
    [System.IO.File]::WriteAllText($resolvedReleaseNotesChangelogPath, ($tagChangelogLines -join "`n") + "`n", [System.Text.UTF8Encoding]::new($false))
  }
  else {
    $resolvedReleaseNotesChangelogPath = (Resolve-Path -LiteralPath $ReleaseNotesChangelogPath -ErrorAction Stop).Path
    Assert-File -Path $resolvedReleaseNotesChangelogPath -Label '显式指定的 Release notes CHANGELOG'
    Write-Step "使用显式 Release notes 来源校验历史正文：$resolvedReleaseNotesChangelogPath"
  }
  $expectedReleaseBody = & (Join-Path $PSScriptRoot 'get-release-notes.ps1') -TagName $TagName -ChangelogPath $resolvedReleaseNotesChangelogPath
  if ((Normalize-ReleaseBody ([string]$release.body)) -cne (Normalize-ReleaseBody ([string]$expectedReleaseBody))) {
    throw "$TagName Release body 与指定 CHANGELOG 的对应段落不一致。"
  }

  $assets = @($release.assets)
  $manifestAsset = $assets | Where-Object { $_.name -eq $expectedManifestName } | Select-Object -First 1
  if (-not $manifestAsset.browser_download_url) {
    throw 'Release 缺少可下载的 update-manifest.json。'
  }

  $manifestPath = Join-Path $DownloadRoot $expectedManifestName
  Write-Step '从 Release browser_download_url 下载 manifest'
  Invoke-WebRequest -Uri $manifestAsset.browser_download_url -Headers $headers -OutFile $manifestPath
  Assert-File -Path $manifestPath -Label '下载后的 update-manifest.json'

  $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
  if ([string]$manifest.version -ne $version) {
    throw "manifest.version 不匹配：$($manifest.version) vs $version"
  }
  if ([string]$manifest.zipAsset -ne $expectedZipName) {
    throw "manifest.zipAsset 不匹配：$($manifest.zipAsset) vs $expectedZipName"
  }

  $hasInstallerAsset = $manifest.PSObject.Properties.Name -contains 'installerAsset'
  $hasInstallerSha256 = $manifest.PSObject.Properties.Name -contains 'installerSha256'
  if ($hasInstallerAsset -ne $hasInstallerSha256) {
    throw 'manifest 必须同时提供 installerAsset 与 installerSha256。'
  }
  $expectedInstallerName = $null
  if ($hasInstallerAsset) {
    $expectedInstallerName = "LongYinProMaxSetup-$version-win-x64.exe"
    if ([string]$manifest.installerAsset -ne $expectedInstallerName -or [string]::IsNullOrWhiteSpace([string]$manifest.installerSha256)) {
      throw 'manifest 中的 Windows 安装器名称或 SHA-256 无效。'
    }
  }

  $actualAssetNames = @($assets | ForEach-Object { [string]$_.name } | Sort-Object)
  $expectedAssetNames = @($expectedManifestName, $expectedZipName)
  if ($expectedInstallerName) {
    $expectedAssetNames += $expectedInstallerName
  }
  $expectedAssetNames = @($expectedAssetNames | Sort-Object)
  $assetDifference = @(Compare-Object -ReferenceObject $expectedAssetNames -DifferenceObject $actualAssetNames)
  if ($assetDifference.Count -ne 0) {
    throw "Release 资产集合不符合预期：$($actualAssetNames -join ', ')"
  }

  $zipAsset = $assets | Where-Object { $_.name -eq $expectedZipName } | Select-Object -First 1
  $installerAsset = if ($expectedInstallerName) {
    $assets | Where-Object { $_.name -eq $expectedInstallerName } | Select-Object -First 1
  } else {
    $null
  }
  if (-not $zipAsset.browser_download_url -or ($expectedInstallerName -and -not $installerAsset.browser_download_url)) {
    throw 'Release 资产缺少 browser_download_url。'
  }

  $zipPath = Join-Path $DownloadRoot $expectedZipName
  $installerPath = if ($expectedInstallerName) { Join-Path $DownloadRoot $expectedInstallerName } else { $null }
  Write-Step '从 Release browser_download_url 重新下载 OTA ZIP 与用户安装器'
  Invoke-WebRequest -Uri $zipAsset.browser_download_url -Headers $headers -OutFile $zipPath
  if ($expectedInstallerName) {
    Invoke-WebRequest -Uri $installerAsset.browser_download_url -Headers $headers -OutFile $installerPath
  }
  Assert-File -Path $zipPath -Label '下载后的 Release ZIP'
  $zipSha256 = Get-Sha256Lower -Path $zipPath
  if ([string]$manifest.sha256 -ne $zipSha256) {
    throw "下载 ZIP 的 SHA256 与 manifest 不一致：$zipSha256 vs $($manifest.sha256)"
  }
  $installerSha256 = $null
  if ($expectedInstallerName) {
    Assert-File -Path $installerPath -Label '下载后的 Windows 安装器'
    $installerSha256 = Get-Sha256Lower -Path $installerPath
    if ([string]$manifest.installerSha256 -ne $installerSha256) {
      throw "下载 Windows 安装器的 SHA256 与 manifest 不一致：$installerSha256 vs $($manifest.installerSha256)"
    }
  }

  Write-Step '检查 ZIP 路径安全、布局和解压体积'
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $archive = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
  try {
    $normalizedEntries = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    [long]$totalUncompressedBytes = 0
    foreach ($entry in $archive.Entries) {
      $entryName = $entry.FullName.Replace('\', '/')
      if (-not $entryName) {
        throw 'ZIP 包含空路径条目。'
      }
      if ($entryName.StartsWith('/') -or $entryName -match '^[A-Za-z]:') {
        throw "ZIP 包含不安全路径：$entryName"
      }
      $trimmedEntryName = $entryName.TrimEnd('/')
      $entrySegments = @($trimmedEntryName.Split('/'))
      if (-not $trimmedEntryName -or @($entrySegments | Where-Object { -not $_ -or $_ -eq '.' -or $_ -eq '..' }).Count -gt 0) {
        throw "ZIP 包含不安全或非规范路径：$entryName"
      }
      $canonicalEntryName = $entrySegments -join '/'
      if (-not $normalizedEntries.Add($canonicalEntryName)) {
        throw "ZIP 包含重复规范化路径：$entryName -> $canonicalEntryName"
      }
      $totalUncompressedBytes += $entry.Length
      if ($entry.Length -gt 1GB) {
        throw "ZIP 单文件解压尺寸异常：$entryName ($($entry.Length))"
      }
    }
    if ($totalUncompressedBytes -gt 2GB) {
      throw "ZIP 总解压尺寸超过 2 GiB：$totalUncompressedBytes"
    }

    $requiredEntries = @(
      'LongYinProMax.exe',
      'resources/app.asar',
      'resources/updater/LongYinUpdater.exe',
      'resources/payload/BepInEx/interop/Assembly-CSharp.dll',
      'resources/payload/BepInEx/plugins/LongYinProMax.dll',
      'resources/payload/BepInEx/plugins/LongYinBattleTurbo.dll',
      'resources/payload/BepInEx/plugins/LongYinHorseStaminaMultiplier.dll',
      'resources/payload/BepInEx/plugins/LongYinSkipIntro.dll'
    )
    foreach ($requiredEntry in $requiredEntries) {
      if (-not $normalizedEntries.Contains($requiredEntry)) {
        throw "ZIP 缺少必要条目：$requiredEntry"
      }
    }
    if ($normalizedEntries.Contains('resources/payload/BepInEx/plugins/LongYinStaminaLock.dll')) {
      throw 'ZIP 仍包含已淘汰的 LongYinStaminaLock.dll。'
    }
  }
  finally {
    $archive.Dispose()
  }

  [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $extractRoot)
  $appExe = Join-Path $extractRoot 'LongYinProMax.exe'
  $updaterExe = Join-Path $extractRoot 'resources\updater\LongYinUpdater.exe'
  $publishedInterop = Join-Path $extractRoot 'resources\payload\BepInEx\interop\Assembly-CSharp.dll'
  Assert-File -Path $appExe -Label '解压后的 LongYinProMax.exe'
  Assert-File -Path $updaterExe -Label '解压后的 LongYinUpdater.exe'
  Assert-File -Path $publishedInterop -Label '解压后的 Assembly-CSharp.dll'

  $repoInterop = Join-Path $repoRoot 'dist\BepInEx\interop\Assembly-CSharp.dll'
  Assert-File -Path $repoInterop -Label '仓库 Assembly-CSharp.dll 基线'
  foreach ($pluginName in @('LongYinProMax', 'LongYinBattleTurbo', 'LongYinHorseStaminaMultiplier', 'LongYinSkipIntro')) {
    $publishedPlugin = Join-Path $extractRoot "resources\payload\BepInEx\plugins\$pluginName.dll"
    $repoPlugin = Join-Path $repoRoot "dist\BepInEx\plugins\$pluginName.dll"
    Assert-File -Path $publishedPlugin -Label "解压后的 $pluginName.dll"
    Assert-File -Path $repoPlugin -Label "仓库 $pluginName.dll 基线"
    if ((Get-Sha256Lower $publishedPlugin) -ne (Get-Sha256Lower $repoPlugin)) {
      throw "Release ZIP 中 $pluginName.dll 与 tag 源码树的 dist 基线不一致。"
    }
  }
  if ((Get-Sha256Lower $publishedInterop) -ne (Get-Sha256Lower $repoInterop)) {
    throw 'Release ZIP 中 Assembly-CSharp.dll 与 tag 源码树的 dist 基线不一致。'
  }

  Write-Step '在隔离 user-data 下运行已下载 EXE 的 renderer smoke test'
  New-Item -ItemType Directory -Path $smokeUserDataRoot -Force | Out-Null
  $previousUserDataRoot = $env:LONGYIN_USER_DATA_ROOT
  $env:LONGYIN_USER_DATA_ROOT = $smokeUserDataRoot
  try {
    $smokeProcess = Start-Process -FilePath $appExe -ArgumentList @('--smoke-test', '--disable-gpu') -WorkingDirectory $extractRoot -WindowStyle Hidden -PassThru
    $deadline = [DateTime]::UtcNow.AddSeconds($SmokeTimeoutSeconds)
    while (-not $smokeProcess.HasExited -and [DateTime]::UtcNow -lt $deadline) {
      Start-Sleep -Milliseconds 250
      $smokeProcess.Refresh()
    }
    if (-not $smokeProcess.HasExited) {
      & taskkill.exe /PID $smokeProcess.Id /T /F 2>$null | Out-Null
      $smokeProcess.WaitForExit(5000) | Out-Null
      throw "LongYinProMax.exe smoke test 超过 $SmokeTimeoutSeconds 秒。"
    }
    if ($smokeProcess.ExitCode -ne 0) {
      throw "LongYinProMax.exe smoke test 退出码为 $($smokeProcess.ExitCode)。"
    }
  }
  finally {
    $env:LONGYIN_USER_DATA_ROOT = $previousUserDataRoot
  }

  $smokeLogPath = Join-Path $smokeUserDataRoot 'startup.log'
  Assert-File -Path $smokeLogPath -Label 'smoke test 启动日志'
  $smokeLog = Get-Content -LiteralPath $smokeLogPath -Raw -Encoding UTF8
  $smokeMatch = [regex]::Match($smokeLog, 'Smoke test passed:\s*(?<result>\{[^\r\n]+\})')
  if (-not $smokeMatch.Success) {
    throw 'smoke test 日志未记录 renderer 成功状态。'
  }
  $smokeResult = $smokeMatch.Groups['result'].Value | ConvertFrom-Json
  if ([string]$smokeResult.appVersion -ne $version) {
    throw "打包应用报告的版本不匹配：$($smokeResult.appVersion) vs $version"
  }

  Write-Step "已验证发布：$TagName / $zipSha256"
  [pscustomobject]@{
    TagName = $TagName
    ReleaseUrl = [string]$release.html_url
    InstallerAsset = $expectedInstallerName
    InstallerSha256 = $installerSha256
    ZipAsset = $expectedZipName
    ZipSha256 = $zipSha256
    AppVersion = [string]$smokeResult.appVersion
    SmokeTest = 'passed'
    DownloadRoot = $DownloadRoot
  }
}
finally {
  if ($ownsDownloadRoot -and -not $KeepDownloaded) {
    Remove-OwnedVerificationRoot -Path $DownloadRoot
  }
}
