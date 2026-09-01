[CmdletBinding(SupportsShouldProcess = $true)]
param(
  [string]$RepoRoot = '',
  [switch]$SkipBuild,
  [switch]$PushTag
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
  $RepoRoot = Join-Path $PSScriptRoot '..'
}
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

function Invoke-Git {
  param(
    [Parameter(Mandatory = $true)][string[]]$Arguments,
    [switch]$AllowFailure
  )

  $output = & git -C $RepoRoot @Arguments 2>&1
  $exitCode = $LASTEXITCODE
  if ($exitCode -ne 0 -and -not $AllowFailure) {
    throw "git $($Arguments -join ' ') 失败：`n$($output -join "`n")"
  }
  return [pscustomobject]@{
    ExitCode = $exitCode
    Output = ($output -join "`n").Trim()
  }
}

$branch = (Invoke-Git @('branch', '--show-current')).Output
if ($branch -ne 'main') {
  throw "正式版本只能从 main 准备；当前分支为 $branch。"
}

$status = (Invoke-Git @('status', '--porcelain')).Output
if ($status) {
  throw "准备正式版本前工作树必须干净：`n$status"
}

Invoke-Git @('fetch', 'origin', 'main', '--tags') | Out-Null
$headCommit = (Invoke-Git @('rev-parse', 'HEAD')).Output
$originMainCommit = (Invoke-Git @('rev-parse', 'origin/main')).Output
if ($headCommit -ne $originMainCommit) {
  throw "本地 main 必须与 origin/main 完全同步：HEAD=$headCommit, origin/main=$originMainCommit"
}

$packageJson = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'electron-app\package.json') | ConvertFrom-Json
$packageLock = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'electron-app\package-lock.json') | ConvertFrom-Json -AsHashtable
$version = [string]$packageJson.version
if ($version -notmatch '^[0-9]+\.[0-9]+\.[0-9]+$') {
  throw "package.json.version 必须符合 X.Y.Z：$version"
}

$lockRoot = $packageLock['packages']['']
if ([string]$packageLock['version'] -ne $version -or [string]$lockRoot['version'] -ne $version) {
  throw "package.json 与 package-lock.json 版本不一致。"
}

$tagName = "v$version"
if (-not $SkipBuild) {
  & (Join-Path $PSScriptRoot 'build-and-verify-release.ps1') -RepoRoot $RepoRoot
  if ($LASTEXITCODE -ne 0) {
    throw '本地发布预检失败。'
  }
}

$postBuildStatus = (Invoke-Git @('status', '--porcelain')).Output
if ($postBuildStatus) {
  throw "预检后工作树发生变化。请审查并提交可维护 payload，再从干净 main 重试：`n$postBuildStatus"
}

$localTag = Invoke-Git @('rev-list', '-n', '1', $tagName) -AllowFailure
if ($localTag.ExitCode -eq 0 -and $localTag.Output) {
  if ($localTag.Output -ne $headCommit) {
    throw "本地 tag $tagName 已指向其他 commit：$($localTag.Output)"
  }
}
elseif ($PSCmdlet.ShouldProcess($headCommit, "创建 tag $tagName")) {
  Invoke-Git @('tag', '-a', $tagName, '-m', "龙胤立志传 Pro Max $tagName") | Out-Null
}

if ($PushTag) {
  $remoteTag = Invoke-Git @('ls-remote', '--tags', 'origin', "refs/tags/$tagName^{}") -AllowFailure
  if (-not $remoteTag.Output) {
    $remoteTag = Invoke-Git @('ls-remote', '--tags', 'origin', "refs/tags/$tagName") -AllowFailure
  }

  if ($remoteTag.Output) {
    $remoteCommit = ($remoteTag.Output -split '\s+' | Select-Object -First 1).Trim()
    if ($remoteCommit -ne $headCommit) {
      throw "远端 tag $tagName 已指向其他 commit：$remoteCommit"
    }
    Write-Host "Remote tag already matches HEAD: $tagName" -ForegroundColor Green
  }
  elseif ($PSCmdlet.ShouldProcess('origin', "推送 tag $tagName 并触发 GitHub Release workflow")) {
    Invoke-Git @('push', 'origin', $tagName) | Out-Null
  }
}

Write-Host "Release source prepared: $tagName -> $headCommit" -ForegroundColor Green
if (-not $PushTag) {
  Write-Host "Tag 尚未推送。确认后运行：pwsh ./scripts/prepare-release.ps1 -SkipBuild -PushTag" -ForegroundColor Yellow
}
