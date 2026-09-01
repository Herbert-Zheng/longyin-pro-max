param(
    [string]$SourcePath = (Join-Path $PSScriptRoot '..\mod-src\LongYinProMax\LongYinProMax.cs'),
    [string]$ElectronRoot = (Join-Path $PSScriptRoot '..\electron-app\src')
)

$ErrorActionPreference = 'Stop'

$resolvedSourcePath = (Resolve-Path -LiteralPath $SourcePath).Path
$resolvedElectronRoot = (Resolve-Path -LiteralPath $ElectronRoot).Path
$source = Get-Content -Raw -LiteralPath $resolvedSourcePath
$typesSource = Get-Content -Raw -LiteralPath (Join-Path $resolvedElectronRoot 'shared\types.ts')
$visibleSettingsSource = Get-Content -Raw -LiteralPath (Join-Path $resolvedElectronRoot 'shared\visible-settings.ts')
$configSource = Get-Content -Raw -LiteralPath (Join-Path $resolvedElectronRoot 'shared\config.ts')
$expTalentSource = Get-Content -Raw -LiteralPath (Join-Path $resolvedElectronRoot 'renderer\settings\ExpTalentSettingsPage.tsx')
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
$buildingPrefix = Get-CSharpMethodText 'MogaoBuildingForgetPrefix'
$pickerMethod = Get-CSharpMethodText 'TryShowMogaoTargetPicker'
$candidateMethod = Get-CSharpMethodText 'BuildMogaoForgetTargetList'
$authorizationMethod = Get-CSharpMethodText 'CanPlayerManageMogaoTarget'
$leaderMethod = Get-CSharpMethodText 'IsPlayerSectLeader'
$pickerCallbackMethod = Get-CSharpMethodText 'IsCurrentMogaoPickerCallback'
$pickerCancelledPostfix = Get-CSharpMethodText 'MogaoPickerCancelledPostfix'
$worldPlayerPostfix = Get-CSharpMethodText 'MogaoPlayerPostfix'
$scopeBegin = Get-CSharpMethodText 'BeginMogaoPlayerOverride'
$finishPostfix = Get-CSharpMethodText 'MogaoForgetFinishPostfix'
$scopeFinalizer = Get-CSharpMethodText 'MogaoForgetScopeFinalizer'

Require-Pattern $source 'ConfigEntry<bool>\s+_mogaoDiscipleForgettingEnabled\b' 'Mogao disciple forgetting must expose a persisted enabled switch.'
Require-Pattern $source 'Config\.Bind\s*\(\s*"Mogao"\s*,\s*"DiscipleForgettingEnabled"\s*,\s*true\b' 'Mogao disciple forgetting must be enabled by default in the Mogao section.'

$requiredPatchTargets = @(
    'WorldData\),\s*nameof\(WorldData\.Player\)',
    'BuildingUIController\),\s*nameof\(BuildingUIController\.SpeRemoveSkill\)',
    'BuildingUIController\),\s*nameof\(BuildingUIController\.SpeRemoveTag\)',
    'BuildingUIController\),\s*nameof\(BuildingUIController\.GetSpeRemoveSkillCost\)',
    'BuildingUIController\),\s*nameof\(BuildingUIController\.GetSpeRemoveTagCost\)',
    'PlotController\),\s*nameof\(PlotController\.SpeRemoveSkillChoose\)',
    'PlotController\),\s*nameof\(PlotController\.SpeRemoveSkillChoosen\)',
    'PlotController\),\s*nameof\(PlotController\.SpeRemoveSkillStart\)',
    'PlotController\),\s*nameof\(PlotController\.SpeRemoveSkillFinish\)',
    'PlotController\),\s*nameof\(PlotController\.SpeRemoveTagChoose\)',
    'PlotController\),\s*nameof\(PlotController\.SpeRemoveTagStart\)',
    'PlotController\),\s*nameof\(PlotController\.SpeRemoveTagFinish\)',
    'ChooseController\),\s*nameof\(ChooseController\.UnshowChoosePanel\)'
)
foreach ($targetPattern in $requiredPatchTargets) {
    Require-Pattern $loadMethod "PatchMethod\(typeof\($targetPattern" "Missing Mogao vanilla-flow patch registration: $targetPattern"
}

Require-Pattern $loadMethod '_mogaoDiscipleForgetHooksReady\s*=\s*mogaoForgetPatches\.All\(patched\s*=>\s*patched\)' 'The feature must require the complete hook set before enabling disciple targeting.'
Require-Pattern $loadMethod 'if\s*\(\s*!_mogaoDiscipleForgetHooksReady\s*\)[\s\S]*?ResetMogaoForgetState\(\)' 'A partial hook set must reset and safely disable the target override.'

Require-Pattern $buildingPrefix '!_mogaoDiscipleForgettingEnabled\.Value\s*\|\|\s*!_mogaoDiscipleForgetHooksReady[\s\S]*?ResetMogaoForgetState\(\)[\s\S]*?return\s+true' 'The building entry must preserve vanilla behavior and clear state when the feature is disabled or compatibility hooks are unavailable.'
Require-Pattern $buildingPrefix '!IsPlayerSectLeader\(player\)[\s\S]*?ResetMogaoForgetState\(\)[\s\S]*?return\s+true' 'A non-leader must remain on the vanilla self-only path and must not retain a disciple target.'
Require-Pattern $buildingPrefix '!IsCurrentMogaoPickerCallback\(__instance,\s*__originalMethod\.Name\)[\s\S]*?ResetMogaoForgetState\(\)' 'A pending target must only be accepted from the exact active Mogao picker callback.'
Require-Pattern $buildingPrefix 'CanPlayerManageMogaoTarget\(player,\s*selectedTarget\)[\s\S]*?_mogaoForgetTarget\s*=\s*selectedTarget[\s\S]*?BeginMogaoPlayerOverride' 'A picker result must be re-authorized before entering the vanilla forget flow.'
Require-Pattern $buildingPrefix 'return\s+!TryShowMogaoTargetPicker' 'The first leader click must only suppress vanilla execution when the target picker was actually shown.'

Require-Pattern $pickerMethod 'candidates\.Count\s*<=\s*1[\s\S]*?return\s+false' 'The picker must fall back to vanilla self-only behavior when there are no eligible disciples.'
Require-Pattern $pickerMethod 'chooseController\.targetHero\s*=\s*null[\s\S]*?ChooseType\.Hero[\s\S]*?callbackName[\s\S]*?ChooseFilterType\.None' 'The leader picker must clear stale selection and use the native hero chooser callback.'
Require-Pattern $pickerCallbackMethod 'chooseController\.chooseType\s*==\s*ChooseType\.Hero[\s\S]*?chooseController\.sendResultFucTarget\s*==\s*controller\.gameObject[\s\S]*?string\.Equals\(chooseController\.sendResultFuc,\s*callbackName' 'Picker callback validation must bind the result to the exact Mogao chooser target and callback.'
Require-Pattern $pickerCancelledPostfix '_mogaoPendingTargetMode\s*!=\s*MogaoForgetMode\.None[\s\S]*?ResetMogaoForgetState\(\)' 'Cancelling the native hero chooser must invalidate the pending Mogao session.'
Require-Pattern $candidateMethod 'candidates\.Add\(player\)[\s\S]*?player\.GetForce\(false\)\?\.GetOwnHeros\(\)' 'The target list must preserve self-forgetting and source disciples from the player sect roster.'
Require-Pattern $candidateMethod 'hero\.dead\s*\|\|\s*hero\.inPrison[\s\S]*?!CanPlayerManageMogaoTarget' 'Dead, imprisoned, or unauthorized roster entries must not be selectable.'

Require-Pattern $leaderMethod 'player\.PlayerLeadForce\(\)' 'Leader authorization must use the game-native PlayerLeadForce check.'
Require-Pattern $authorizationMethod 'player\s*==\s*target[\s\S]*?return\s+true' 'The original player target must always remain valid.'
Require-Pattern $authorizationMethod 'IsPlayerSectLeader\(player\)[\s\S]*?player\.belongForceID\s*>=\s*0[\s\S]*?target\.belongForceID\s*==\s*player\.belongForceID' 'Disciple authorization must require current leadership and exact same-sect membership.'

Require-Pattern $scopeBegin '!_mogaoDiscipleForgettingEnabled\.Value[\s\S]*?_mogaoActiveMode\s*!=\s*mode[\s\S]*?return\s+false[\s\S]*?_mogaoPlayerOverrideDepth\+\+' 'Only an enabled, matching active skill/talent flow may enter the player override scope.'
Require-Pattern $worldPlayerPostfix '_mogaoPlayerOverrideDepth\s*<=\s*0[\s\S]*?_mogaoForgetTarget\s*==\s*null[\s\S]*?return' 'WorldData.Player must remain untouched outside a narrow Mogao override scope.'
Require-Pattern $worldPlayerPostfix '_mogaoPlayerOverrideFrame\s*!=\s*Time\.frameCount[\s\S]*?ResetMogaoForgetState\(\)' 'A leaked override scope must fully invalidate its target session outside the originating frame.'
Require-Pattern $worldPlayerPostfix 'CanPlayerManageMogaoTarget\(actualPlayer,\s*_mogaoForgetTarget\)[\s\S]*?ResetMogaoForgetState\(\)[\s\S]*?__result\s*=\s*_mogaoForgetTarget' 'Every player substitution must re-check live leader and same-sect authorization.'
Require-Pattern $finishPostfix 'EndMogaoPlayerOverride\(__state\)[\s\S]*?ResetMogaoForgetState\(\)' 'Completing either vanilla forget flow must clear the selected disciple session.'
Require-Pattern $loadMethod 'nameof\(MogaoForgetScopeFinalizer\)' 'Every scoped vanilla Mogao hook must register exception-safe cleanup.'
Require-Pattern $scopeFinalizer '__exception\s*!=\s*null[\s\S]*?EndMogaoPlayerOverride\(__state\)[\s\S]*?ResetMogaoForgetState\(\)[\s\S]*?return\s+__exception' 'The Harmony finalizer must fully clean leaked scopes while preserving the original exception.'

Reject-Pattern $source '_mogaoForgetTarget\?\.LoseSkill|_mogaoForgetTarget\?\.RemoveTag|_mogaoForgetTarget\.LoseSkill|_mogaoForgetTarget\.RemoveTag' 'The mod must not reimplement removal; it must reuse the complete vanilla validation, cost, time, and mutation flow.'

Require-Pattern $typesSource 'mogaoDiscipleForgettingEnabled:\s*boolean;' 'Electron settings must carry the Mogao disciple-forgetting switch.'
Require-Pattern $visibleSettingsSource 'mogaoDiscipleForgettingEnabled:\s*true' 'Electron must enable the Mogao disciple-forgetting switch by default.'
Require-Pattern $configSource '\[Mogao\][\s\S]*?DiscipleForgettingEnabled\s*=\s*\$\{boolText\(settings\.mogaoDiscipleForgettingEnabled\)\}' 'Electron must write the Mogao switch in generated configs.'
Require-Pattern $configSource 'getIniSectionBody\(text,\s*''Mogao''\)[\s\S]*?readBool\(\s*mogaoSection,\s*''DiscipleForgettingEnabled''' 'Electron must read the Mogao switch only from its owning section.'
Require-Pattern $configSource 'upsertIniSectionValue\(\s*nextMain,\s*''Mogao'',\s*''DiscipleForgettingEnabled'',\s*boolText\(normalized\.mogaoDiscipleForgettingEnabled\)' 'Electron must persist edits to the Mogao switch.'
Require-Pattern $expTalentSource 'label="掌门可为本门弟子遗忘武学与天赋"[\s\S]*?onSettingChange\(''mogaoDiscipleForgettingEnabled'', value\)[\s\S]*?非掌门仍只能为自己操作' 'Electron must expose a clearly described Mogao disciple-forgetting checkbox.'

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) {
        Write-Error $failure
    }

    exit 1
}

Write-Host "Mogao disciple forget semantic checks passed: $resolvedSourcePath"
