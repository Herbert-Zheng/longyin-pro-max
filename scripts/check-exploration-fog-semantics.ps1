param(
    [string]$SourcePath = (Join-Path $PSScriptRoot '..\mod-src\LongYinStaminaLock\LongYinStaminaLock.cs'),
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\dist\BepInEx\config\codex.longyin.staminalock.cfg')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Require-Match {
    param(
        [string]$Text,
        [string]$Pattern,
        [string]$Message
    )

    if ($Text -notmatch $Pattern) {
        throw $Message
    }
}

$source = Get-Content -LiteralPath $SourcePath -Raw -Encoding UTF8
$config = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8

Require-Match $source 'Config\.Bind\("Exploration",\s*"RevealAllOnStepTile",\s*false,' 'RevealAllOnStepTile must default to false in the plugin.'
Require-Match $source 'if\s*\(\s*!_revealAllOnStepTile\.Value\s*\|\|\s*_exploreFullRevealConsumed\s*\)' 'Full-map reveal must remain guarded by the user setting.'
Require-Match $source 'controller\.SeeAllTile\(\);' 'The guarded full-map reveal implementation is missing.'
Require-Match $config '# Default value: false\s*\r?\nRevealAllOnStepTile = false' 'The packaged config must default RevealAllOnStepTile to false.'

$seeAllTileCalls = [regex]::Matches($source, '\.SeeAllTile\(\);').Count
if ($seeAllTileCalls -ne 1) {
    throw "Expected exactly one controlled SeeAllTile call, found $seeAllTileCalls."
}

Write-Host 'PASS: exploration full-map reveal is opt-in and remains guarded.'
