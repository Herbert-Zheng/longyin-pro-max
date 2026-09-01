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

$loadMethod = Get-CSharpMethodText 'Load'
$buildingPrefix = Get-CSharpMethodText 'MogaoBuildingForgetPrefix'
$pickerMethod = Get-CSharpMethodText 'TryShowMogaoTargetPicker'
$pickerChoosePrefix = Get-CSharpMethodText 'MogaoPickerChoosePrefix'
$pickerChoosePostfix = Get-CSharpMethodText 'MogaoPickerChoosePostfix'
$pickerUnshowPrefix = Get-CSharpMethodText 'MogaoPickerUnshowPrefix'
$pickerTargetMethod = Get-CSharpMethodText 'TryGetMogaoPickerHero'
$pickerCancelledPostfix = Get-CSharpMethodText 'MogaoPickerCancelledPostfix'
$candidateMethod = Get-CSharpMethodText 'BuildMogaoForgetTargetList'
$authorizationMethod = Get-CSharpMethodText 'CanPlayerManageMogaoTarget'
$leaderMethod = Get-CSharpMethodText 'IsPlayerSectLeader'
$worldPlayerPostfix = Get-CSharpMethodText 'MogaoPlayerPostfix'
$scopeBegin = Get-CSharpMethodText 'BeginMogaoPlayerOverride'
$resetMethod = Get-CSharpMethodText 'ResetMogaoForgetState'

Require-Pattern $source 'ConfigEntry<bool>\s+_mogaoDiscipleForgettingEnabled\b' 'Mogao disciple forgetting must expose a persisted enabled switch.'
Require-Pattern $source 'Config\.Bind\s*\(\s*"Mogao"\s*,\s*"DiscipleForgettingEnabled"\s*,\s*true\b' 'Mogao disciple forgetting must be enabled by default.'

$requiredPatchTargets = @(
    'WorldData\),\s*nameof\(WorldData\.Player\)',
    'BuildingUIController\),\s*nameof\(BuildingUIController\.SpeRemoveSkill\)',
    'BuildingUIController\),\s*nameof\(BuildingUIController\.SpeRemoveTag\)',
    'PlotController\),\s*nameof\(PlotController\.SpeRemoveSkillStart\)',
    'PlotController\),\s*nameof\(PlotController\.SpeRemoveSkillFinish\)',
    'PlotController\),\s*nameof\(PlotController\.SpeRemoveTagStart\)',
    'PlotController\),\s*nameof\(PlotController\.SpeRemoveTagFinish\)',
    'ChooseController\),\s*nameof\(ChooseController\.ChooseObj\)',
    'ChooseController\),\s*nameof\(ChooseController\.UnshowChoosePanel\)'
)
foreach ($targetPattern in $requiredPatchTargets) {
    Require-Pattern $loadMethod "PatchMethod\(typeof\($targetPattern" "Missing Mogao patch registration: $targetPattern"
}

Require-Pattern $loadMethod '_mogaoDiscipleForgetHooksReady\s*=\s*mogaoForgetPatches\.All\(patched\s*=>\s*patched\)' 'The feature must require its complete hook set.'
Require-Pattern $buildingPrefix '!IsPlayerSectLeader\(player\)[\s\S]*?ResetMogaoForgetState\(\)[\s\S]*?return\s+true' 'Non-leaders must remain on the vanilla self-only path.'
Require-Pattern $buildingPrefix '_mogaoPickerSelectionInProgress[\s\S]*?return\s+false' 'The broken building callback must be suppressed while the native picker is finalizing a selection.'
Require-Pattern $buildingPrefix '_mogaoContinueOriginalEntry[\s\S]*?BeginMogaoPlayerOverride[\s\S]*?return\s+true' 'An explicitly continued selection must enter the original chooser under a narrow target scope.'
Require-Pattern $buildingPrefix 'return\s+!TryShowMogaoTargetPicker' 'The first leader click must show the target picker and suppress the original entry only when it succeeds.'

Require-Pattern $pickerMethod 'candidates\.Count\s*<=\s*1[\s\S]*?return\s+false' 'The picker must fall back to vanilla when there are no eligible disciples.'
Require-Pattern $pickerMethod '_mogaoBuildingController\s*=\s*controller[\s\S]*?chooseController\.targetHero\s*=\s*null[\s\S]*?ChooseType\.Hero' 'The picker must retain its controller and clear stale hero selection.'
Require-Pattern $pickerChoosePrefix '_mogaoPendingTargetMode\s*!=\s*MogaoForgetMode\.None[\s\S]*?_mogaoPickerSelectedHero\s*=\s*TryGetMogaoPickerHero\(targetObj\)[\s\S]*?_mogaoPickerSelectionInProgress\s*=\s*true' 'Native chooser selection must capture the hero directly from the clicked card before vanilla chooser cleanup.'
Require-Pattern $pickerUnshowPrefix '_mogaoPickerSelectionInProgress[\s\S]*?__instance\.targetHero[\s\S]*?_mogaoPickerSelectedHero\s*=' 'The selected hero must be captured before the vanilla chooser closes and clears targetHero.'
Require-Pattern $pickerTargetMethod 'GetComponent<HeroIconController>\(\)[\s\S]*?heroData' 'The clicked native hero card must resolve its HeroData through HeroIconController.'
Require-Pattern $pickerChoosePostfix '_mogaoPickerSelectedHero\s*\?\?\s*TryGetMogaoSelectedHero\(\)[\s\S]*?CanPlayerManageMogaoTarget[\s\S]*?_mogaoForgetTarget\s*=\s*selectedTarget[\s\S]*?ContinueMogaoSelectedTargetFlow' 'The native chooser result must use the pre-close capture, then be re-authorized and explicitly continued.'
Require-Pattern $pickerCancelledPostfix '!_mogaoPickerSelectionInProgress[\s\S]*?ResetMogaoForgetState\(\)' 'Cancelling the picker must clear pending state without erasing an in-flight selection.'

Require-Pattern $candidateMethod 'candidates\.Add\(player\)[\s\S]*?player\.GetForce\(false\)\?\.GetOwnHeros\(\)' 'The target list must include self and source disciples from the player sect.'
Require-Pattern $candidateMethod 'hero\.dead\s*\|\|\s*hero\.inPrison[\s\S]*?!CanPlayerManageMogaoTarget' 'Dead, imprisoned, and unauthorized disciples must be excluded.'
Require-Pattern $leaderMethod 'player\.PlayerLeadForce\(\)' 'Leader authorization must use the game-native leadership check.'
Require-Pattern $authorizationMethod 'player\s*==\s*target[\s\S]*?return\s+true' 'Self must always remain manageable.'
Require-Pattern $authorizationMethod 'IsPlayerSectLeader\(player\)[\s\S]*?target\.belongForceID\s*==\s*player\.belongForceID' 'Disciple management must require current leadership and same-sect membership.'

Require-Pattern $scopeBegin '_mogaoActiveMode\s*!=\s*mode[\s\S]*?return\s+false[\s\S]*?_mogaoPlayerOverrideDepth\+\+' 'Only a matching active flow may enter the player override scope.'
Require-Pattern $worldPlayerPostfix '_mogaoPlayerOverrideDepth\s*<=\s*0[\s\S]*?_mogaoForgetTarget\s*==\s*null[\s\S]*?return' 'WorldData.Player must remain untouched outside a narrow Mogao scope.'
Require-Pattern $worldPlayerPostfix '_mogaoPlayerOverrideFrame\s*!=\s*Time\.frameCount[\s\S]*?ResetMogaoForgetState\(\)' 'A leaked player override must expire outside its originating frame.'
Require-Pattern $resetMethod '_mogaoPendingTargetMode\s*=\s*MogaoForgetMode\.None[\s\S]*?_mogaoPickerSelectedHero\s*=\s*null[\s\S]*?_mogaoBuildingController\s*=\s*null[\s\S]*?_mogaoPlayerOverrideDepth\s*=\s*0' 'Reset must clear picker, captured target, controller, and override state.'

Require-Pattern $typesSource 'mogaoDiscipleForgettingEnabled:\s*boolean;' 'Electron settings must carry the Mogao switch.'
Require-Pattern $visibleSettingsSource 'mogaoDiscipleForgettingEnabled:\s*true' 'Electron must enable the Mogao switch by default.'
Require-Pattern $configSource '\[Mogao\][\s\S]*?DiscipleForgettingEnabled\s*=\s*\$\{boolText\(settings\.mogaoDiscipleForgettingEnabled\)\}' 'Electron must write the Mogao switch.'
Require-Pattern $configSource 'getIniSectionBody\(text,\s*''Mogao''\)[\s\S]*?readBool\(\s*mogaoSection,\s*''DiscipleForgettingEnabled''' 'Electron must read the Mogao switch from its own section.'
Require-Pattern $configSource 'upsertIniSectionValue\(\s*nextMain,\s*''Mogao'',\s*''DiscipleForgettingEnabled''' 'Electron must persist edits to the Mogao switch.'
Require-Pattern $expTalentSource 'label="掌门可为本门弟子遗忘武学与天赋"[\s\S]*?onSettingChange\(''mogaoDiscipleForgettingEnabled'', value\)[\s\S]*?自己沿用原版耗时流程[\s\S]*?弟子直接生效且不耗时[\s\S]*?非掌门仍只能管理自己' 'Electron must expose and explain the Mogao switch.'

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) {
        Write-Error $failure
    }

    exit 1
}

Write-Host "Mogao disciple-forget semantic checks passed: $resolvedSourcePath"
