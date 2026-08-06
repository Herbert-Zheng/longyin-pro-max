param(
    [string]$SourcePath = (Join-Path $PSScriptRoot '..\mod-src\LongYinStaminaLock\LongYinStaminaLock.cs')
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
