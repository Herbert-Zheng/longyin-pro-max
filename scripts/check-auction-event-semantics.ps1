param(
    [string]$SourcePath = (Join-Path $PSScriptRoot '..\mod-src\LongYinStaminaLock\LongYinStaminaLock.cs')
)

$ErrorActionPreference = 'Stop'

$resolvedSourcePath = (Resolve-Path -LiteralPath $SourcePath).Path
$source = Get-Content -Raw -LiteralPath $resolvedSourcePath
$failures = [System.Collections.Generic.List[string]]::new()

function Get-CSharpMethodText {
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $escapedName = [System.Text.RegularExpressions.Regex]::Escape($Name)
    $methodPattern = "(?m)^    private static[^\r\n]*\b$escapedName\s*\("
    $methodMatch = [System.Text.RegularExpressions.Regex]::Match($source, $methodPattern)
    if (-not $methodMatch.Success) {
        $failures.Add("Could not locate C# method: $Name")
        return ''
    }

    $nextMethodRegex = [System.Text.RegularExpressions.Regex]::new(
        '(?m)^    private static[^\r\n]*\b[A-Za-z_][A-Za-z0-9_]*\s*\(')
    $nextMethodMatch = $nextMethodRegex.Match($source, $methodMatch.Index + $methodMatch.Length)
    $endIndex = if ($nextMethodMatch.Success) { $nextMethodMatch.Index } else { $source.Length }
    return $source.Substring($methodMatch.Index, $endIndex - $methodMatch.Index)
}

function Require-SourcePattern {
    param(
        [Parameter(Mandatory)]
        [string]$Pattern,

        [Parameter(Mandatory)]
        [string]$FailureMessage
    )

    if (-not [System.Text.RegularExpressions.Regex]::IsMatch(
        $source,
        $Pattern,
        [System.Text.RegularExpressions.RegexOptions]::Singleline)) {
        $failures.Add($FailureMessage)
    }
}

Require-SourcePattern `
    'private const float AuctionRedEventDifficulty\s*=\s*10f\s*;' `
    'The verified red event grade must be represented by the named difficulty-10 constant.'
Require-SourcePattern `
    'Config\.Bind\(\s*"Auction"\s*,\s*"EventAlwaysRedEnabled"\s*,\s*true\s*,' `
    'The mod must expose [Auction] EventAlwaysRedEnabled with a default value of true.'
Require-SourcePattern `
    'PatchMethod\(typeof\(WorldEventController\),\s*nameof\(WorldEventController\.GetWorldEventRandomDifficulty\),\s*new\[\]\s*\{\s*typeof\(WorldEventDataBase\)\s*\},\s*nameof\(AuctionWorldEventDifficultyPrefix\),\s*null\)' `
    'World-event difficulty generation must be patched so the auction is born at the red tier.'

$matcher = Get-CSharpMethodText 'IsAuctionWorldEvent'
if ($matcher.IndexOf('targetWorldEventDataBase.name', [System.StringComparison]::Ordinal) -lt 0 -or
    $matcher.IndexOf('targetWorldEventDataBase.eventData?.eventName', [System.StringComparison]::Ordinal) -lt 0 -or
    $matcher.IndexOf('"拍卖大会"', [System.StringComparison]::Ordinal) -lt 0) {
    $failures.Add('Auction matching must use the world-event template name and embedded event name.')
}

$difficultyPrefix = Get-CSharpMethodText 'AuctionWorldEventDifficultyPrefix'
if ($difficultyPrefix.IndexOf('_auctionEventAlwaysRedEnabled.Value', [System.StringComparison]::Ordinal) -lt 0 -or
    $difficultyPrefix.IndexOf('IsAuctionWorldEvent(targetWorldEventDataBase)', [System.StringComparison]::Ordinal) -lt 0) {
    $failures.Add('The auction generation-difficulty prefix must honor the toggle and auction matcher.')
}
if ($difficultyPrefix.IndexOf('__result = AuctionRedEventDifficulty;', [System.StringComparison]::Ordinal) -lt 0 -or
    $difficultyPrefix.IndexOf('return false;', [System.StringComparison]::Ordinal) -lt 0) {
    $failures.Add('The matching auction must return difficulty 10 and skip the original random difficulty generator.')
}
if ($source -match '\[DEBUG-auction-(?:event|difficulty)') {
    $failures.Add('Temporary auction event/difficulty probes must be removed from production source.')
}
if ($source -match 'PatchMethod\(typeof\(EventData\),\s*nameof\(EventData\.GetEventRareLv\)') {
    $failures.Add('The obsolete color-only EventData.GetEventRareLv hook must be removed.')
}
if ($source -match 'PatchMethod\(typeof\(WorldEventController\),\s*nameof\(WorldEventController\.CreateWorldEvent\)') {
    $failures.Add('The red-grade override should stay at the random-difficulty seam instead of mutating a completed event.')
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host "Auction event semantic checks passed: $resolvedSourcePath"
