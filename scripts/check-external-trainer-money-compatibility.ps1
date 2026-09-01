param(
    [string]$SourcePath = (Join-Path $PSScriptRoot '..\mod-src\LongYinProMax\LongYinProMax.cs')
)

$ErrorActionPreference = 'Stop'
$source = Get-Content -Raw -LiteralPath (Resolve-Path -LiteralPath $SourcePath)
$failures = [System.Collections.Generic.List[string]]::new()

function Require([string]$pattern, [string]$message) {
    if (-not [regex]::IsMatch($source, $pattern, 'Singleline')) { $failures.Add($message) }
}

function Reject([string]$pattern, [string]$message) {
    if ([regex]::IsMatch($source, $pattern, 'Singleline')) { $failures.Add($message) }
}

Reject 'PatchMethod\(typeof\(HeroData\),\s*nameof\(HeroData\.ChangeMoney\)' 'HeroData.ChangeMoney must keep its vanilla entry bytes because the supported external trainer resolves and patches that money routine directly.'
Reject 'HarmonyPatch[^\r\n]*HeroData[^\r\n]*ChangeMoney' 'HeroData.ChangeMoney must not be patched through an attribute either.'
Require 'TryObservePlayerMoneyChange' 'Lucky-money behavior must move to a non-invasive observer instead of patching the trainer-sensitive money method.'
Require 'GameControllerUpdatePostfix[\s\S]*?TryObservePlayerMoneyChange' 'The non-invasive money observer must run from the already-patched game update hook.'

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ -ErrorAction Continue }
    exit 1
}

Write-Host 'External trainer money compatibility checks passed.'
