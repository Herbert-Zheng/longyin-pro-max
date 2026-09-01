[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$TagName,
  [string]$RepoRoot = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
  $RepoRoot = Join-Path $PSScriptRoot '..'
}
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

function Invoke-Git {
  param([Parameter(Mandatory = $true)][string[]]$Arguments)

  $output = & git -C $RepoRoot @Arguments 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw "git $($Arguments -join ' ') 失败：`n$($output -join "`n")"
  }
  return ($output -join "`n").Trim()
}

if ($TagName -notmatch '^v(?<version>[0-9]+\.[0-9]+\.[0-9]+)$') {
  throw "正式发布 tag 必须符合 vX.Y.Z：$TagName"
}
$tagVersion = $Matches.version

$packageJson = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'electron-app\package.json') | ConvertFrom-Json
$packageLock = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'electron-app\package-lock.json') | ConvertFrom-Json -AsHashtable
$lockRoot = $packageLock['packages']['']

foreach ($candidate in @(
  [pscustomobject]@{ Label = 'package.json'; Version = [string]$packageJson.version },
  [pscustomobject]@{ Label = 'package-lock.json'; Version = [string]$packageLock['version'] },
  [pscustomobject]@{ Label = 'package-lock.json packages root'; Version = [string]$lockRoot['version'] }
)) {
  if ($candidate.Version -ne $tagVersion) {
    throw "$($candidate.Label) 版本与 tag 不一致：$($candidate.Version) vs $tagVersion"
  }
}

Invoke-Git @('fetch', 'origin', 'main:refs/remotes/origin/main', '--no-tags') | Out-Null
$headCommit = Invoke-Git @('rev-parse', 'HEAD')
$tagObjectType = Invoke-Git @('cat-file', '-t', "refs/tags/$TagName")
if ($tagObjectType -ne 'tag') {
  throw "正式发布必须使用 annotated tag：$TagName"
}
$tagCommit = Invoke-Git @('rev-list', '-n', '1', $TagName)
if ($tagCommit -ne $headCommit) {
  throw "tag $TagName 未指向当前 checkout：tag=$tagCommit, HEAD=$headCommit"
}

& git -C $RepoRoot merge-base --is-ancestor $headCommit 'origin/main'
if ($LASTEXITCODE -ne 0) {
  throw "tag $TagName 指向的 commit 不属于 origin/main，禁止发布：$headCommit"
}

Write-Host "Verified release source: $TagName -> $headCommit (origin/main)" -ForegroundColor Green
Write-Host "Verified version: $tagVersion" -ForegroundColor Green
