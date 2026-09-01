param(
    [string]$SourcePath = (Join-Path $PSScriptRoot '..\mod-src\LongYinProMax\LongYinProMax.cs'),
    [string]$SaveSlotPath = (Join-Path $env:USERPROFILE 'AppData\LocalLow\TppStudio\LongYinLiZhiZhuan\Save_backup\SaveSlot0'),
    [string]$ResourcePath = 'C:\Program Files (x86)\Steam\steamapps\common\LongYinLiZhiZhuan\LongYinLiZhiZhuan_Data\resources.assets',
    [int]$ObservedAchievementProgress = 0
)

$ErrorActionPreference = 'Stop'

$resolvedSourcePath = (Resolve-Path -LiteralPath $SourcePath).Path
$resolvedSaveSlotPath = (Resolve-Path -LiteralPath $SaveSlotPath).Path
$resolvedResourcePath = (Resolve-Path -LiteralPath $ResourcePath).Path
$source = Get-Content -Raw -LiteralPath $resolvedSourcePath
$failures = [System.Collections.Generic.List[string]]::new()

function Require-Pattern {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Scope,
        [Parameter(Mandatory)][string]$Pattern,
        [Parameter(Mandatory)][string]$FailureMessage
    )

    if (-not [regex]::IsMatch($Scope, $Pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)) {
        $failures.Add($FailureMessage)
    }
}

function Reject-Pattern {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Scope,
        [Parameter(Mandatory)][string]$Pattern,
        [Parameter(Mandatory)][string]$FailureMessage
    )

    if ([regex]::IsMatch($Scope, $Pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)) {
        $failures.Add($FailureMessage)
    }
}

$achievementRow = & rg -a -m 1 -o '37,鸾凤和鸣,达成鸾凤和鸣结局,bool,1,同时拥有夫妻和4名情侣且好感均100，进入门派/自宅' $resolvedResourcePath
if ($LASTEXITCODE -ne 0 -or -not $achievementRow) {
    throw 'Could not verify the vanilla achievement 37 requirement in resources.assets.'
}

$save = Get-Content -Raw -LiteralPath (Join-Path $resolvedSaveSlotPath 'Save') | ConvertFrom-Json
$parsedHeroes = Get-Content -Raw -LiteralPath (Join-Path $resolvedSaveSlotPath 'Hero') | ConvertFrom-Json
$heroes = @($parsedHeroes | ForEach-Object { $_ })
if ($heroes.Count -eq 0) {
    throw 'The captured save has no Hero records.'
}

$player = $heroes[0]
$relationshipIds = @($player.PreLovers) |
    Where-Object { $_ -is [ValueType] -and $_ -ge 0 -and $_ -lt $heroes.Count } |
    Select-Object -Unique
$belowMaxFavor = @()
foreach ($relationshipIdValue in $relationshipIds) {
    $relationshipId = [int]$relationshipIdValue
    $relationshipHero = $heroes[$relationshipId]
    $favor = [double]$relationshipHero.favor
    if ($favor -lt 99.999) {
        $belowMaxFavor += $relationshipId
    }
}
$loverEndingTriggered = @($save.gameResultTriggered) -contains 9

if (-not $loverEndingTriggered) {
    $failures.Add('The captured save must contain lover-ending result index 9 so the stale achievement split can be replayed.')
}
if ($relationshipIds.Count -lt 5) {
    $failures.Add("The captured save must contain at least the vanilla spouse-plus-four relationship set; found $($relationshipIds.Count).")
}
if ($belowMaxFavor.Count -gt 0) {
    $failures.Add("The captured relationship set must all have 100 favor; below-cap IDs: $($belowMaxFavor -join ', ').")
}
if ($ObservedAchievementProgress -ne 0) {
    $failures.Add("This regression fixture represents the reported 0/1 achievement state; observed progress was $ObservedAchievementProgress.")
}

Require-Pattern $source 'const\s+int\s+LoverAchievementId\s*=\s*37\s*;' 'The repair must name the vanilla achievement ID 37 explicitly.'
Require-Pattern $source 'const\s+int\s+LoverEndingResultIndex\s*=\s*9\s*;' 'The repair must name the matching lover-ending result index 9 explicitly.'
Require-Pattern $source 'const\s+int\s+VanillaLoverAchievementRelationshipCount\s*=\s*4\s*;' 'The ending check must preserve the vanilla four-lover threshold independently from the configurable romance cap.'
Require-Pattern $source 'nameof\(GameController\.CheckGameResultTrigger\)[\s\S]*?nameof\(LoverAchievementCheckPrefix\)[\s\S]*?nameof\(LoverAchievementCheckFinalizer\)' 'The native game-result check must temporarily use the vanilla lover threshold and restore the configured cap even after exceptions.'
Require-Pattern $source 'RepairLoverAchievementProgressIfEndingTriggered\(' 'Existing saves whose lover ending already triggered must be reconciled.'
Require-Pattern $source 'HaveGameResultTriggered\(LoverEndingResultIndex\)' 'Reconciliation must require that lover-ending result index 9 was already recorded.'
Require-Pattern $source 'playerPrefData[\s\S]*?"ach"\s*\+\s*LoverAchievementId' 'Reconciliation must inspect the persisted ach37 progress.'
Require-Pattern $source 'ChangeAchStats\(LoverAchievementId' 'Reconciliation must update only achievement 37 through the native achievement API.'
Reject-Pattern $source 'nameof\(GameController\.MeetLoverResultRequire\)[^;]+nameof\(MeetLoverResultRequirePostfix\)' 'The mod must not force the native lover-ending predicate in a postfix; that split result state from achievement progress.'
Reject-Pattern $source 'private\s+static\s+void\s+MeetLoverResultRequirePostfix\s*\(' 'The legacy result-mutating postfix must be removed.'
Reject-Pattern $source '\[DEBUG-LFA37\]' 'Temporary lover-achievement diagnosis logging must be removed before release.'

Write-Host "Captured repro: resultIndex9=$loverEndingTriggered; relationshipCount=$($relationshipIds.Count); allFavor100=$($belowMaxFavor.Count -eq 0); ach37=$ObservedAchievementProgress/1"
Write-Host "Vanilla requirement: $achievementRow"

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ -ErrorAction Continue }
    exit 1
}

Write-Host "Lover achievement semantic checks passed: $resolvedSourcePath"
