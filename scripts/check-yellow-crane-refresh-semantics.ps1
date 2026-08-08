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
    $match = [regex]::Match($source, "(?m)^    private static[^\r\n]*\b$escapedName\s*\(")
    if (-not $match.Success) {
        $failures.Add("Could not locate C# method: $Name")
        return ''
    }
    $nextRegex = [regex]::new('(?m)^    private static[^\r\n]*\b[A-Za-z_][A-Za-z0-9_]*\s*\(')
    $next = $nextRegex.Match($source, $match.Index + $match.Length)
    $end = if ($next.Success) { $next.Index } else { $source.Length }
    return $source.Substring($match.Index, $end - $match.Index)
}

function Require-Pattern {
    param([AllowEmptyString()][string]$Scope, [string]$Pattern, [string]$Message)
    if (-not [regex]::IsMatch($Scope, $Pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)) { $failures.Add($Message) }
}

function Reject-Pattern {
    param([AllowEmptyString()][string]$Scope, [string]$Pattern, [string]$Message)
    if ([regex]::IsMatch($Scope, $Pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)) { $failures.Add($Message) }
}

$finishPrefix = Get-CSharpMethodText 'FinishRecruitHeroPrefix'
$showPostfix = Get-CSharpMethodText 'RecruitUIControllerShowRecruitUIPostfix'
$hidePostfix = Get-CSharpMethodText 'RecruitUIControllerHideRecruitUIPostfix'
$updateMethod = Get-CSharpMethodText 'UpdateYellowCraneCandidateRefreshAssist'
$refreshMethod = Get-CSharpMethodText 'TryRefreshYellowCraneCandidates'
$candidateLookupMethod = Get-CSharpMethodText 'GetYellowCraneCandidateHeroes'
$deactivateMethod = Get-CSharpMethodText 'DeactivateYellowCraneCandidateIcons'
$resetMethod = Get-CSharpMethodText 'ResetYellowCraneCandidateRefreshState'
$clickMethod = Get-CSharpMethodText 'OverlayButtonOnPointerClickPrefix'
$gameUpdateMethod = Get-CSharpMethodText 'GameControllerUpdatePostfix'

Require-Pattern $source 'ConfigEntry<bool>\s+_yellowCraneCandidateRefreshEnabled\b' 'Yellow Crane candidate refresh must expose a persisted boolean switch.'
Require-Pattern $source 'Config\.Bind\s*\(\s*"YellowCraneTower"\s*,\s*"CandidateRefreshEnabled"\s*,\s*true\b' 'Yellow Crane candidate refresh must be enabled by default.'
Reject-Pattern $source '(?i)yellowCrane[^;\r\n]*(?:ConfigEntry<KeyCode>|Hotkey)|(?:Input\.GetKeyDown|Input\.GetKey)\([^\)]*yellowCrane' 'Yellow Crane candidate refresh must not expose or poll a hotkey.'

Require-Pattern $source 'PatchMethod\(\s*typeof\(PlotController\),\s*(?:"FinishRecruitHero"|nameof\(PlotController\.FinishRecruitHero\))[\s\S]*?nameof\(FinishRecruitHeroPrefix\)' 'The feature must arm only from the original FinishRecruitHero flow.'
Require-Pattern $source 'PatchMethod\(\s*typeof\(RecruitUIController\),\s*(?:"ShowRecruitUI"|nameof\(RecruitUIController\.ShowRecruitUI\))[\s\S]*?nameof\(RecruitUIControllerShowRecruitUIPostfix\)' 'Recruit UI show lifecycle must be observed.'
Require-Pattern $source 'PatchMethod\(\s*typeof\(RecruitUIController\),\s*(?:"HideRecruitUI"|nameof\(RecruitUIController\.HideRecruitUI\))[\s\S]*?nameof\(RecruitUIControllerHideRecruitUIPostfix\)' 'Recruit UI hide lifecycle must be observed.'
Require-Pattern $finishPrefix '_yellowCraneFinishRecruitFrame\s*=\s*Time\.frameCount[\s\S]*?_yellowCraneFinishRecruitType\s*=\s*recruitType' 'FinishRecruitHero must record the current frame and parsed recruit type as one context token.'
Require-Pattern $finishPrefix 'TryParseRecruitFinishContext\(\s*__0\s*,\s*out var recruitType\s*,\s*out var recruitLevel\s*\)' 'FinishRecruitHero must parse the original callback argument rather than infer the context globally.'
Require-Pattern $showPostfix '_yellowCraneFinishRecruitFrame\s*==\s*Time\.frameCount[\s\S]*?_yellowCraneFinishRecruitType\s*==\s*__0' 'ShowRecruitUI must accept only the same-frame, matching recruit context.'
Require-Pattern $showPostfix '_yellowCraneCandidateRefreshType\s*=\s*__0[\s\S]*?_yellowCraneCandidateRefreshHeroCount\s*=\s*Math\.Max\(\s*1\s*,\s*__1\s*\)[\s\S]*?_yellowCraneCandidateRefreshLevel\s*=\s*__2' 'ShowRecruitUI must cache the exact original arguments for later refreshes.'
Require-Pattern $showPostfix '_yellowCraneCandidateGenerationStartFrame\s*=\s*Time\.frameCount[\s\S]*?_yellowCraneCandidateRefreshBusy\s*=\s*true' 'Every candidate generation must record its start frame before entering the busy state.'
Require-Pattern $showPostfix '_yellowCraneCandidateRefreshBusy\s*=\s*true' 'Candidate generation must begin in a busy state.'
Require-Pattern $hidePostfix '_yellowCraneCandidateRefreshReopening[\s\S]*?return[\s\S]*?ResetYellowCraneCandidateRefreshState' 'A refresh-driven Hide must preserve the session, while a real close must reset it.'

Require-Pattern $clickMethod '__instance\s*==\s*_yellowCraneCandidateRefreshButton[\s\S]*?eventData\.button\s*!=\s*PointerEventData\.InputButton\.Left[\s\S]*?TryRefreshYellowCraneCandidates' 'Only the exact candidate-refresh button instance and a left click may dispatch refresh.'
Require-Pattern $gameUpdateMethod 'UpdateYellowCraneCandidateRefreshAssist\(\);' 'GameController.Update must maintain the candidate refresh UI lifecycle.'
Require-Pattern $updateMethod '_yellowCraneCandidateRefreshBusy[\s\S]*?Time\.frameCount\s*<=\s*_yellowCraneCandidateGenerationStartFrame\s*\|\|\s*candidateCount\s*!=\s*_yellowCraneCandidateRefreshHeroCount[\s\S]*?return[\s\S]*?_yellowCraneCandidateRefreshBusy\s*=\s*false' 'The button must remain busy for at least one frame and until the active candidate count exactly matches the expected count.'
Reject-Pattern $updateMethod 'candidateCount\s*(?:>=|>|<)\s*_yellowCraneCandidateRefreshHeroCount' 'Candidate readiness must not accept excess stale icons or use a one-sided candidate-count comparison.'
Require-Pattern $updateMethod '_yellowCraneCandidateRefreshEnabled\.Value[\s\S]*?activeInHierarchy' 'The candidate refresh button must be gated by both the setting and the visible recruit UI.'

Require-Pattern $refreshMethod '_yellowCraneCandidateRefreshBusy[\s\S]*?_yellowCraneCandidateRefreshBusy\s*=\s*true' 'The refresh action must reject reentry and mark the operation busy.'
Require-Pattern $refreshMethod 'DeactivateYellowCraneCandidateIcons\(\s*controller\s*\)[\s\S]*?worldData\.RemoveTempHero\(\s*hero\s*\)[\s\S]*?controller\.HideRecruitUI\(\)' 'Old candidate icons must be deactivated before delayed Unity destruction and before the replacement UI is opened.'
Require-Pattern $refreshMethod 'GetYellowCraneCandidateHeroes\(\s*controller\s*,\s*activeOnly:\s*false\s*\)[\s\S]*?hero\.isTempHero[\s\S]*?worldData\.RemoveTempHero\(\s*hero\s*\)' 'Discarded candidates must be resolved through the candidate helper and removed from WorldData.TempHeros through RemoveTempHero.'
Require-Pattern $candidateLookupMethod 'transform\.Find\(\s*"ToggleGroup"\s*\)[\s\S]*?GetComponentsInChildren<HeroIconController>\(includeInactive:\s*true\)[\s\S]*?icon\s*==\s*null[\s\S]*?icon\.gameObject\s*==\s*null[\s\S]*?icon\.heroData' 'Candidate cleanup must be sourced from null-checked hero icons in the visible recruit ToggleGroup.'
Require-Pattern $deactivateMethod 'transform\.Find\(\s*"ToggleGroup"\s*\)[\s\S]*?GetComponentsInChildren<HeroIconController>\(includeInactive:\s*true\)[\s\S]*?icon\?\.gameObject\s*!=\s*null[\s\S]*?icon\.gameObject\.SetActive\(false\)' 'Every old candidate icon must be hidden immediately so delayed Object.Destroy cannot satisfy the next generation count.'
Reject-Pattern $refreshMethod 'GameController\.instance\.RemoveHero\(|\.RemoveHero\(' 'Candidate refresh must not use the destructive GameController.RemoveHero path.'
Require-Pattern $refreshMethod 'var recruitType\s*=\s*_yellowCraneCandidateRefreshType[\s\S]*?var heroCount\s*=\s*_yellowCraneCandidateRefreshHeroCount[\s\S]*?var recruitLevel\s*=\s*_yellowCraneCandidateRefreshLevel[\s\S]*?_yellowCraneCandidateRefreshReopening\s*=\s*true[\s\S]*?HideRecruitUI\(\)[\s\S]*?ShowRecruitUI\(\s*recruitType\s*,\s*heroCount\s*,\s*recruitLevel\s*\)' 'Refresh must rebuild the UI with the exact cached type, candidate count, and level.'
Require-Pattern $refreshMethod 'finally[\s\S]*?_yellowCraneCandidateRefreshReopening\s*=\s*false' 'The refresh reopening guard must always be cleared.'
Require-Pattern $resetMethod '_yellowCraneCandidateGenerationStartFrame\s*=\s*-1' 'Closing or failing the recruit session must clear the generation-frame guard.'
Reject-Pattern $source 'ConfigEntry<KeyCode>\s+_yellowCrane' 'No Yellow Crane hotkey configuration may be added.'

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ -ErrorAction Continue }
    exit 1
}

Write-Host "Yellow Crane candidate refresh semantic checks passed: $resolvedSourcePath"
