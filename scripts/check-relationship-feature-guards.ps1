param(
    [string]$SourcePath = (Join-Path $PSScriptRoot '..\mod-src\LongYinProMax\LongYinProMax.cs')
)

$ErrorActionPreference = 'Stop'

$resolvedSourcePath = (Resolve-Path -LiteralPath $SourcePath).Path
$source = Get-Content -Raw -LiteralPath $resolvedSourcePath
$failures = [System.Collections.Generic.List[string]]::new()

function Get-CSharpMethodText {
    param([Parameter(Mandatory)][string]$Name)

    $escapedName = [System.Text.RegularExpressions.Regex]::Escape($Name)
    $methodMatch = [System.Text.RegularExpressions.Regex]::Match(
        $source,
        "(?m)^    (?:public|private|internal|protected)(?: static)?[^\r\n]*\b$escapedName\s*\(")
    if (-not $methodMatch.Success) {
        $failures.Add("Could not locate C# method: $Name")
        return ''
    }

    $nextMethodRegex = [System.Text.RegularExpressions.Regex]::new(
        '(?m)^    (?:public|private|internal|protected)(?: static)?[^\r\n]*\b[A-Za-z_][A-Za-z0-9_]*\s*\(')
    $nextMethodMatch = $nextMethodRegex.Match(
        $source,
        $methodMatch.Index + $methodMatch.Length)
    $endIndex = if ($nextMethodMatch.Success) { $nextMethodMatch.Index } else { $source.Length }
    return $source.Substring($methodMatch.Index, $endIndex - $methodMatch.Index)
}

function Get-CSharpBraceBlockText {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Scope,
        [Parameter(Mandatory)][string]$StartPattern,
        [Parameter(Mandatory)][string]$Label
    )

    $startMatch = [System.Text.RegularExpressions.Regex]::Match(
        $Scope,
        $StartPattern,
        [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if (-not $startMatch.Success) {
        $failures.Add("Could not locate C# brace block: $Label")
        return ''
    }

    $openingBraceIndex = $Scope.IndexOf('{', $startMatch.Index + $startMatch.Length)
    if ($openingBraceIndex -lt 0) {
        $failures.Add("Could not locate opening brace for C# block: $Label")
        return ''
    }

    $depth = 0
    for ($index = $openingBraceIndex; $index -lt $Scope.Length; $index++) {
        switch ($Scope[$index]) {
            '{' { $depth++ }
            '}' {
                $depth--
                if ($depth -eq 0) {
                    return $Scope.Substring($openingBraceIndex, $index - $openingBraceIndex + 1)
                }
            }
        }
    }

    $failures.Add("Could not locate closing brace for C# block: $Label")
    return ''
}

function Require-Pattern {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Scope,
        [Parameter(Mandatory)][string]$Pattern,
        [Parameter(Mandatory)][string]$FailureMessage
    )

    if (-not [System.Text.RegularExpressions.Regex]::IsMatch(
        $Scope,
        $Pattern,
        [System.Text.RegularExpressions.RegexOptions]::Singleline)) {
        $failures.Add($FailureMessage)
    }
}

function Reject-Pattern {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Scope,
        [Parameter(Mandatory)][string]$Pattern,
        [Parameter(Mandatory)][string]$FailureMessage
    )

    if ([System.Text.RegularExpressions.Regex]::IsMatch(
        $Scope,
        $Pattern,
        [System.Text.RegularExpressions.RegexOptions]::Singleline)) {
        $failures.Add($FailureMessage)
    }
}

Require-Pattern $source 'Config\.Bind\("Relationship",\s*"FeaturesEnabled",\s*false,' 'Relationship.FeaturesEnabled must exist and default to false.'
Require-Pattern $source 'Config\.Bind\("Relationship",\s*"BlockOverflowLoverHomeBattle",\s*true,' 'Relationship.BlockOverflowLoverHomeBattle must exist and preserve the prior enabled behavior behind the master switch.'
Require-Pattern $source 'Config\.Bind\("Relationship",\s*"TeamFameShareEnabled",\s*true,' 'Relationship.TeamFameShareEnabled must exist and preserve the prior enabled behavior behind the master switch.'
Require-Pattern $source 'Config\.Bind\("Relationship",\s*"TeamFameSharePercent",\s*30f,' 'Relationship.TeamFameSharePercent must exist and default to 30 percent.'
Require-Pattern $source 'Config\.Bind\("Debug",\s*"CharacterDataTestHotkeyEnabled",\s*false,' 'The character-data test hotkey must exist and default to disabled.'
Reject-Pattern $source '\bViewedHeroFavorTestHotkey\b|\bApplyViewedHeroFavorTest\b|\bTeamFameShareRatio\b' 'Legacy misleading test names and the hard-coded fame-share ratio must be removed.'
Reject-Pattern $source 'Viewed hero (?:reputation|fame) test' 'Legacy viewed-hero test wording must be replaced with the Character-data test name.'
Reject-Pattern $source 'PatchMethod\(typeof\(HeroDetailController\)' 'HeroDetailController methods must never be Harmony patched because external trainers assert and replace their original entry bytes.'
Reject-Pattern $source '\bPatchViewedHeroMethods\b|\bHeroDetailViewedHeroPostfix\b|\bHeroDetailHiddenPostfix\b|\bCacheActiveHeroDetailHero\b|\b_activeHeroDetailHero(?:Id)?\b' 'Legacy HeroDetailController tracking hooks and caches must be removed.'
Require-Pattern $source 'Character-data test uses on-demand HeroDetailController reads; methods left unpatched\.' 'Startup compatibility logging must explain that character-detail reads are on demand and unpatched.'

$loadMethod = Get-CSharpMethodText 'Load'
Require-Pattern $loadMethod 'if\s*\(_relationshipFeaturesEnabled\.Value\)[\s\S]*?changeFavorPatched\s*=\s*PatchMethod\(typeof\(HeroData\),\s*nameof\(HeroData\.ChangeFavor\)[\s\S]*?PatchHeroChangeFameMethod\(\);[\s\S]*?PatchMethod\(typeof\(PlotController\),\s*nameof\(PlotController\.ManageTeachSkill\)' 'Relationship-specific ChangeFavor, ChangeFame, and ManageTeachSkill hooks must only be registered behind the master switch.'
Require-Pattern $loadMethod 'nameof\(PlotController\.LoverInteractWithNPC\)[\s\S]*?nameof\(PlotController\.FinishHeroToLover\)[\s\S]*?nameof\(PlotController\.CheckChoiceMeetRequire\)[\s\S]*?if\s*\(_relationshipFeaturesEnabled\.Value\s*&&\s*_blockOverflowLoverHomeBattle\.Value\)' 'MaxLoverCount hooks must remain registered independently before the lover home-battle hook gate.'

$loverBattleRegistrationBlock = Get-CSharpBraceBlockText `
    -Scope $loadMethod `
    -StartPattern 'if\s*\(_relationshipFeaturesEnabled\.Value\s*&&\s*_blockOverflowLoverHomeBattle\.Value\)\s*' `
    -Label 'relationship master plus lover home-battle blocker registration gate'
Reject-Pattern $loverBattleRegistrationBlock 'MaxLoverCountSyncPrefix|CheckChoiceMeetRequirePostfix|MeetLoverResultRequirePostfix' 'MaxLoverCount hooks must remain outside the lover home-battle registration gate.'

$dedicatedLoverBattlePatchPatterns = @(
    'PatchMethod\(typeof\(PlotController\),\s*nameof\(PlotController\.PlotStartLoverResultFight\),',
    'PatchMethod\(typeof\(PlotController\),\s*nameof\(PlotController\.PlotStartLoverResultFightResult\),',
    'PatchMethod\(typeof\(BattleController\),\s*nameof\(BattleController\.PrepareBattleMap\),[^;]+nameof\(LoverBattlePrepareBattleMapDirectPrefix\),',
    'PatchMethod\(typeof\(BattleController\),\s*nameof\(BattleController\.PrepareBattleMap\),[^;]+nameof\(LoverBattlePrepareBattleMapGroupedPrefix\),',
    'PatchMethod\(typeof\(BattleController\),\s*nameof\(BattleController\.BattleTeamPrepare\),[^;]+nameof\(LoverBattleTeamPreparePrefix\),'
)
foreach ($patchPattern in $dedicatedLoverBattlePatchPatterns) {
    $loadRegistrationCount = [System.Text.RegularExpressions.Regex]::Matches(
        $loadMethod,
        $patchPattern,
        [System.Text.RegularExpressions.RegexOptions]::Singleline).Count
    $guardedRegistrationCount = [System.Text.RegularExpressions.Regex]::Matches(
        $loverBattleRegistrationBlock,
        $patchPattern,
        [System.Text.RegularExpressions.RegexOptions]::Singleline).Count
    if ($loadRegistrationCount -ne 1 -or $guardedRegistrationCount -ne 1) {
        $failures.Add("Each dedicated lover home-battle hook must have exactly one registration site and it must be inside the combined guard block; pattern '$patchPattern' matched $loadRegistrationCount time(s) in Load and $guardedRegistrationCount time(s) in the guard block.")
    }
}

Require-Pattern $loadMethod 'LogCompatibilitySummary\(\s*loverBattlePlotStartPatched,\s*loverBattlePlotResultPatched,\s*battlePrepareDirectPatched,\s*battlePrepareGroupedPatched,\s*battleTeamPreparePatched,\s*battleSpeedPatched,' 'LogCompatibilitySummary must receive the five lover-battle hook results in order, followed by the independent battle-speed result.'

$compatibilitySummary = Get-CSharpMethodText 'LogCompatibilitySummary'
Require-Pattern $compatibilitySummary 'LogCompatibilitySummary\(\s*bool\s+loverBattlePlotStartPatched,\s*bool\s+loverBattlePlotResultPatched,\s*bool\s+battlePrepareDirectPatched,\s*bool\s+battlePrepareGroupedPatched,\s*bool\s+battleTeamPreparePatched,\s*bool\s+battleSpeedPatched,' 'LogCompatibilitySummary parameters must map the five lover-battle hook results in order, followed by battle speed.'
$loverBattleCountBlock = Get-CSharpBraceBlockText `
    -Scope $compatibilitySummary `
    -StartPattern 'var\s+loverBattleHookCount\s*=\s*new\[\]\s*' `
    -Label 'lover-battle compatibility count initializer'
Require-Pattern $loverBattleCountBlock '^\{\s*loverBattlePlotStartPatched,\s*loverBattlePlotResultPatched,\s*battlePrepareDirectPatched,\s*battlePrepareGroupedPatched,\s*battleTeamPreparePatched\s*\}$' 'The lover-battle compatibility count must contain exactly the five dedicated hook results in registration order.'
Reject-Pattern $loverBattleCountBlock '\bbattleSpeedPatched\b' 'The general battle-speed hook must not be counted as a lover home-battle blocker hook.'
Require-Pattern $compatibilitySummary 'loverBattleHookCount\s*==\s*5' 'The lover-battle compatibility state must require all five dedicated hooks.'
Require-Pattern $compatibilitySummary '\{loverBattleHookCount\}/5\s+dedicated targets patched' 'The lover-battle compatibility log must report a five-target denominator.'
Require-Pattern $compatibilitySummary 'Battle speed hook:\s*\{\(battleSpeedPatched\s*\?\s*"ENABLED"\s*:\s*"DEGRADED"\)\}' 'Battle speed compatibility must be reported independently from lover home-battle hooks.'

$viewedHeroReader = Get-CSharpMethodText 'TryGetViewedHeroDetailHero'
Require-Pattern $viewedHeroReader '!heroDetailController\.gameObject\.activeInHierarchy[\s\S]*?return\s+null' 'The on-demand viewed-hero reader must ignore inactive character-detail UI state.'
Require-Pattern $viewedHeroReader '"nowShowHero",\s*"targetHero",\s*"mainShowHero",\s*"nowChooseHero"[\s\S]*?return\s+hero' 'The on-demand viewed-hero reader must return a live reflected hero directly.'
Reject-Pattern $viewedHeroReader 'TryGetPlayerHero\(' 'The viewed-hero reader must never fall back to the player when the current detail target cannot be resolved.'

$characterDataTest = Get-CSharpMethodText 'ApplyViewedHeroCharacterDataTest'
Require-Pattern $characterDataTest 'viewedHero\s*==\s*null[\s\S]*?current character-detail target could not be resolved[\s\S]*?未修改任何人物数据[\s\S]*?return' 'An unresolved character-detail target must produce a clear message and stop before any data write.'

$masterGuardedMethods = @(
    'ChangeFavorPrefix',
    'ChangeFavorPostfix',
    'ChangeFamePrefix',
    'ChangeFamePostfix',
    'HandleTeamAutoFavorDateProgress',
    'TryApplyTeamAutoFavor',
    'TryApplyAutoFavorGain',
    'TryApplyTeamFameShare',
    'TryApplySharedFameGain',
    'ManageTeachSkillPrefix',
    'ManageTeachSkillPostfix',
    'ApplyTeachSkillSameSectAreaShare',
    'TryBypassOverflowLoverHomeBattle',
    'GrantTeamIntelligenceMoneyTest',
    'ApplyViewedHeroCharacterDataTest'
)

foreach ($methodName in $masterGuardedMethods) {
    $methodText = Get-CSharpMethodText $methodName
    Require-Pattern $methodText '_relationshipFeaturesEnabled\.Value' "$methodName must be guarded by the relationship master switch."
}

$updatePostfix = Get-CSharpMethodText 'GameControllerUpdatePostfix'
Require-Pattern $updatePostfix '_relationshipFeaturesEnabled\.Value\s*&&\s*_characterDataTestHotkeyEnabled\.Value[\s\S]*?Input\.GetKeyDown\(CharacterDataTestHotkey\)' 'The character-data test hotkey must require both the master and debug switches.'

$fameShareMethod = Get-CSharpMethodText 'TryApplyTeamFameShare'
Require-Pattern $fameShareMethod 'Mathf\.Clamp\(_teamFameSharePercent\.Value,\s*0f,\s*100f\)\s*/\s*100f' 'Team fame sharing must use the clamped configured percentage.'

$maxLoverApplyMethod = Get-CSharpMethodText 'ApplyConfiguredMaxLoverCount'
$maxLoverSyncMethod = Get-CSharpMethodText 'MaxLoverCountSyncPrefix'
Reject-Pattern $maxLoverApplyMethod '_relationshipFeaturesEnabled' 'MaxLoverCount must remain independent from the relationship master switch.'
Reject-Pattern $maxLoverSyncMethod '_relationshipFeaturesEnabled' 'MaxLoverCount synchronization must remain independent from the relationship master switch.'

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ -ErrorAction Continue }
    exit 1
}

Write-Host "Relationship feature guard checks passed: $resolvedSourcePath"
