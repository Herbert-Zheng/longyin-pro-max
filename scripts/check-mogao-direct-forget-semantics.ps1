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
    $nextMethodMatch = $nextMethodRegex.Match($source, $methodMatch.Index + $methodMatch.Length)
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

$loadMethod = Get-CSharpMethodText 'Load'
$skillChoosePrefix = Get-CSharpMethodText 'MogaoSkillChoosePrefix'
$skillChooser = Get-CSharpMethodText 'ShowMogaoSkillForgetChooser'
$skillStartPrefix = Get-CSharpMethodText 'MogaoSkillStartPrefix'
$tagStartPrefix = Get-CSharpMethodText 'MogaoTagStartPrefix'
$directEntry = Get-CSharpMethodText 'TryStartMogaoDiscipleForget'
$directTalent = Get-CSharpMethodText 'ApplyMogaoDiscipleTalentForget'
$directSkill = Get-CSharpMethodText 'ApplyMogaoDiscipleSkillForget'
$finishPrefix = Get-CSharpMethodText 'MogaoSkillFinishPrefix'
$finishPostfix = Get-CSharpMethodText 'MogaoSkillFinishPostfix'
$talentPointReward = Get-CSharpMethodText 'GetMogaoSkillTalentPointReward'
$configuredTalentPointReward = Get-CSharpMethodText 'GetConfiguredSkillTalentGrantReward'
$skillTalentGrantSettings = Get-CSharpMethodText 'TryGetSkillTalentGrantSettings'
$rollback = Get-CSharpMethodText 'RollbackMogaoSkillLevelReward'

Require-Pattern $loadMethod 'ChooseController\),\s*nameof\(ChooseController\.ChooseObj\)[\s\S]*?MogaoPickerChoosePrefix[\s\S]*?MogaoPickerChoosePostfix' 'The native hero chooser result must be intercepted directly instead of relying on its broken building-method callback.'
Require-Pattern $loadMethod 'PlotController\),\s*nameof\(PlotController\.SpeRemoveSkillChoose\)[\s\S]*?nameof\(MogaoSkillChoosePrefix\)' 'The martial-skill chooser must be replaced for an active leader-managed target so non-zero skills can be listed.'
Require-Pattern $skillChoosePrefix '_mogaoActiveMode\s*==\s*MogaoForgetMode\.Skill[\s\S]*?CanPlayerManageMogaoTarget[\s\S]*?ShowMogaoSkillForgetChooser[\s\S]*?return\s+false' 'An authorized active martial-skill target must use the expanded chooser instead of the vanilla zero-level-only chooser.'
Require-Pattern $skillChooser 'BoxMogaoChooseInt\(0\)[\s\S]*?BoxMogaoChooseInt\(10\)[\s\S]*?ChooseType\.HeroSkill[\s\S]*?nameof\(PlotController\.SpeRemoveSkillChoosen\)' 'The expanded chooser must keep native skill selection while widening the accepted learned-level range from 0 through 10.'
Require-Pattern $skillStartPrefix 'IsActiveMogaoDiscipleForget\(MogaoForgetMode\.Skill[\s\S]*?TryStartMogaoDiscipleForget[\s\S]*?return\s+false[\s\S]*?BeginMogaoPlayerOverride[\s\S]*?return\s+true' 'Disciple skill forgetting must suppress working time, while self forgetting must retain the vanilla timed start.'
Require-Pattern $tagStartPrefix 'IsActiveMogaoDiscipleForget\(MogaoForgetMode\.Talent[\s\S]*?TryStartMogaoDiscipleForget[\s\S]*?return\s+false[\s\S]*?BeginMogaoPlayerOverride[\s\S]*?return\s+true' 'Disciple talent forgetting must suppress working time, while self forgetting must retain the vanilla timed start.'
Require-Pattern $directEntry 'ApplyMogaoDiscipleSkillForget[\s\S]*?ApplyMogaoDiscipleTalentForget[\s\S]*?HideInteractUI\(' 'The direct disciple entry must apply the selected operation and close the original interaction without scheduling work.'
Reject-Pattern $directEntry 'StartWorking|ChangeDay|ChangeHour' 'The direct disciple entry must not start or emulate the vanilla time-consuming task.'

Require-Pattern $directTalent 'FindTag\(tagId\)[\s\S]*?RemoveTag\(tagId,\s*true\)[\s\S]*?FindTag\(tagId\)\s*==\s*null' 'Disciple talent forgetting must validate and directly remove the selected talent.'
Require-Pattern $directSkill 'FindSkill\(selectedSkill\.skillID\)[\s\S]*?talentPointReward\s*=\s*GetMogaoSkillTalentPointReward\(target,\s*skill\)[\s\S]*?talentPointsBefore\s*=\s*target\.heroTagPoint[\s\S]*?LoseSkill\(skill\)[\s\S]*?RollbackMogaoSkillLevelReward\(target,\s*talentPointReward,\s*talentPointsBefore\)' 'Disciple skill forgetting must let native LoseSkill roll back training gains once, then deduct the exact talent-point reward earned by that hero and skill.'
Reject-Pattern $directSkill 'ChangeAttriAndSkill' 'Disciple forgetting must not duplicate the attribute and potential rollback already performed by native LoseSkill.'

Require-Pattern $finishPrefix 'TryGetPlayerHero\(\)[\s\S]*?BeginMogaoPlayerOverride[\s\S]*?FindSkill\(skillId\)[\s\S]*?TalentPointReward\s*=\s*target\s*==\s*null\s*\?\s*0f\s*:\s*GetMogaoSkillTalentPointReward\(target,\s*skill\)[\s\S]*?TalentPointsBefore\s*=\s*target\s*==\s*null\s*\?\s*0f\s*:\s*target\.heroTagPoint' 'The vanilla self flow must capture the selected hero and skill''s exact talent-point reward and the balance before delayed removal.'
Require-Pattern $finishPostfix 'CompleteMogaoSkillRollback\(__state\)[\s\S]*?ResetMogaoForgetState\(\)' 'The delayed vanilla self flow must roll back training gains after successful removal and then clear state.'

Require-Pattern $talentPointReward 'HeroData[\s\S]*?KungfuSkillLvData[\s\S]*?DataBase\(\)[\s\S]*?rareLv[\s\S]*?skill\.lv\s*>=\s*10\s*\?\s*Mathf\.Pow\(2f,\s*rareLv\)\s*:\s*0f[\s\S]*?GetConfiguredSkillTalentGrantReward\(target,\s*skill,\s*rareLv\)' 'Talent-point rollback must include the native completion reward (2 raised to rarity at level 10) and the configured extra grant.'
Require-Pattern $configuredTalentPointReward 'TryGetSkillTalentGrantSettings[\s\S]*?!enabled[\s\S]*?levelThreshold\s*<=\s*0[\s\S]*?skill\.lv\s*<\s*levelThreshold[\s\S]*?playerOnly[\s\S]*?TryGetHeroId[\s\S]*?skillTier\s*=\s*Math\.Max\(1,\s*rareLv\)[\s\S]*?Mathf\.Round\(Mathf\.Max\(1f,\s*skillTier\s*\*\s*Mathf\.Max\(0f,\s*tierPointMultiplier\)\)\)' 'Extra talent rollback must mirror LongYinSkillTalentGrant eligibility and its rounded tier-times-multiplier formula.'
Require-Pattern $skillTalentGrantSettings 'AppDomain\.CurrentDomain\.GetAssemblies\(\)[\s\S]*?LongYinSkillTalentGrantPlugin[\s\S]*?_enabled[\s\S]*?_levelThreshold[\s\S]*?_tierPointMultiplier[\s\S]*?_playerOnly' 'Extra talent rollback must read the loaded grant plugin''s effective runtime settings instead of assuming defaults.'
Require-Pattern $rollback 'talentPointReward\s*<=\s*0f[\s\S]*?return[\s\S]*?target\.heroTagPoint\s*=\s*talentPointsBefore\s*-\s*talentPointReward' 'Forgetting must subtract the exact earned talent-point reward and allow the resulting balance to become negative.'
Reject-Pattern $rollback 'talentPointsBefore\s*-\s*1f' 'Talent-point rollback must not hard-code one point for every completed skill.'
Reject-Pattern $rollback 'ChangeAttriAndSkill|upgradeAddData' 'The custom level-reward rollback must stay separate from native martial-training rollback.'
Reject-Pattern $rollback 'Math\.Max\([^\r\n]*heroTagPoint|heroTagPoint\s*=\s*Math' 'Talent-point rollback must never clamp the result at zero.'

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) {
        Write-Error $failure
    }

    exit 1
}

Write-Host "Mogao direct-forget semantic checks passed: $resolvedSourcePath"
