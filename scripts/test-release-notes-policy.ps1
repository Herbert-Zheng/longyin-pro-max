[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$extractor = Join-Path $PSScriptRoot 'get-release-notes.ps1'
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("longyin-release-notes-test-{0}" -f [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null

function Assert-Equal([string]$Expected, [string]$Actual, [string]$CaseName) {
  if ($Expected -cne $Actual) {
    throw "$CaseName 失败。期望：<$Expected>，实际：<$Actual>"
  }
}

function Invoke-Extract([string]$Fixture, [string]$TagName = 'v1.2.3') {
  $fixturePath = Join-Path $testRoot 'CHANGELOG.md'
  [System.IO.File]::WriteAllText($fixturePath, $Fixture, [System.Text.UTF8Encoding]::new($false))
  return & $extractor -TagName $TagName -ChangelogPath $fixturePath
}

function Assert-Fails([string]$Fixture, [string]$ExpectedMessage, [string]$CaseName) {
  try {
    Invoke-Extract -Fixture $Fixture | Out-Null
  }
  catch {
    if ($_.Exception.Message -notlike "*$ExpectedMessage*") {
      throw "$CaseName 返回了错误的失败原因：$($_.Exception.Message)"
    }
    return
  }
  throw "$CaseName 应失败但成功。"
}

try {
  $normal = Invoke-Extract "# Changelog`n`n## v1.2.3`n`n- 新功能`n- 修复问题`n`n## v1.2.2`n`n- 旧变化`n"
  Assert-Equal "- 新功能`n- 修复问题" $normal '正常提取'

  Assert-Fails "# Changelog`n`n## v1.2.2`n- 旧变化`n" '缺少精确版本标题' '缺失版本'
  Assert-Fails "## v1.2.3`n- 一`n## v1.2.3`n- 二`n" '重复版本标题' '重复版本'
  Assert-Fails "## v1.2.3`n `t `n## v1.2.2`n- 旧变化`n" '版本段为空' '空版本段'

  $adjacent = Invoke-Extract "## v1.2.3`n- 当前`n## v1.2.2`n- 不应包含`n"
  Assert-Equal '- 当前' $adjacent '相邻版本边界'

  $nonVersionBoundary = Invoke-Extract "## v1.2.3`n- 当前`n## 迁移前记录`n- 不应包含`n## v1.2.2`n- 旧变化`n"
  Assert-Equal '- 当前' $nonVersionBoundary '非版本二级标题边界'

  $crlf = Invoke-Extract ("## v1.2.3`r`n`r`n- 第一项   `r`n`r`n- 第二项`t`r`n`r`n## v1.2.2`r`n- 旧变化`r`n")
  Assert-Equal "- 第一项`n`n- 第二项" $crlf 'CRLF 与尾空白规范化'

  $outputPath = Join-Path $testRoot 'notes.md'
  $fixturePath = Join-Path $testRoot 'CHANGELOG.md'
  [System.IO.File]::WriteAllText($fixturePath, "## v1.2.3`n- 文件输出`n", [System.Text.UTF8Encoding]::new($false))
  & $extractor -TagName v1.2.3 -ChangelogPath $fixturePath -OutputPath $outputPath
  Assert-Equal "- 文件输出`n" ([System.IO.File]::ReadAllText($outputPath)) 'notes 文件输出'

  $repoRoot = Split-Path -Parent $PSScriptRoot
  $legacyNotes = @(Get-ChildItem -LiteralPath $repoRoot -File -Filter 'release-notes-v*.md')
  if ($legacyNotes.Count -gt 0) {
    throw "仓库根目录不得保留 release-notes-v*.md：$($legacyNotes.Name -join ', ')"
  }

  $package = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'electron-app\package.json') | ConvertFrom-Json
  & $extractor -TagName "v$($package.version)" -ChangelogPath (Join-Path $repoRoot 'CHANGELOG.md') | Out-Null

  Write-Host 'Release notes policy tests passed.' -ForegroundColor Green
}
finally {
  if (Test-Path -LiteralPath $testRoot) {
    Remove-Item -LiteralPath $testRoot -Recurse -Force
  }
}
