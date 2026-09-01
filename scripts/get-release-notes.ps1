[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidatePattern('^v\d+\.\d+\.\d+$')]
  [string]$TagName,

  [string]$ChangelogPath = '',
  [string]$OutputPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ChangelogPath)) {
  $ChangelogPath = Join-Path $PSScriptRoot '..\CHANGELOG.md'
}
if (-not (Test-Path -LiteralPath $ChangelogPath -PathType Leaf)) {
  throw "找不到 CHANGELOG：$ChangelogPath"
}

$source = Get-Content -Raw -LiteralPath $ChangelogPath -Encoding UTF8
$headerPattern = '(?m)^## (?<tag>v\d+\.\d+\.\d+)[ \t]*\r?$'
$headers = [regex]::Matches($source, $headerPattern)
$matches = @($headers | Where-Object { $_.Groups['tag'].Value -eq $TagName })
if ($matches.Count -eq 0) {
  throw "CHANGELOG 缺少精确版本标题：## $TagName"
}
if ($matches.Count -gt 1) {
  throw "CHANGELOG 包含重复版本标题：## $TagName"
}

$target = $matches[0]
$contentStart = $target.Index + $target.Length
$sectionHeaderPattern = [regex]::new('(?m)^## .+[ \t]*\r?$')
$nextHeader = $sectionHeaderPattern.Match($source, $contentStart)
$contentEnd = if ($nextHeader.Success) { $nextHeader.Index } else { $source.Length }
$content = $source.Substring($contentStart, $contentEnd - $contentStart)

# Release 正文统一使用 LF；移除每行尾空白和段落首尾空行，但保留正文结构。
$normalizedLines = @($content -replace "`r`n?", "`n" -split "`n" | ForEach-Object { $_.TrimEnd() })
while ($normalizedLines.Count -gt 0 -and [string]::IsNullOrWhiteSpace($normalizedLines[0])) {
  $normalizedLines = @($normalizedLines | Select-Object -Skip 1)
}
while ($normalizedLines.Count -gt 0 -and [string]::IsNullOrWhiteSpace($normalizedLines[-1])) {
  $normalizedLines = @($normalizedLines | Select-Object -First ($normalizedLines.Count - 1))
}
$notes = $normalizedLines -join "`n"
if ([string]::IsNullOrWhiteSpace($notes)) {
  throw "CHANGELOG 的 $TagName 版本段为空。"
}

if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
  $parent = Split-Path -Parent $OutputPath
  if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
  }
  [System.IO.File]::WriteAllText([System.IO.Path]::GetFullPath($OutputPath), $notes + "`n", [System.Text.UTF8Encoding]::new($false))
}
else {
  Write-Output -NoEnumerate $notes
}
