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

$clickPrefix = Get-CSharpMethodText 'BountyFreshButtonClickedPrefix'
$freshPostfix = Get-CSharpMethodText 'BountyFreshPostfix'
$resolveTypeMethod = Get-CSharpMethodText 'TryResolveBountyType'
$enabledMethod = Get-CSharpMethodText 'IsBountyRefreshEnabled'

Require-Pattern $source 'ConfigEntry<bool>\s+_forceBountyRefreshEnabled\b' 'Sect/force bounty refresh must have its own switch.'
Require-Pattern $source 'ConfigEntry<bool>\s+_commonBountyRefreshEnabled\b' 'Notice-board/common bounty refresh must have its own switch.'
Require-Pattern $source 'ConfigEntry<bool>\s+_governBountyRefreshEnabled\b' 'Government bounty refresh must have its own switch.'
Require-Pattern $source 'Config\.Bind\s*\(\s*"BountyRefresh"\s*,\s*"ForceEnabled"\s*,\s*true\b' 'Force bounty refresh must default to enabled.'
Require-Pattern $source 'Config\.Bind\s*\(\s*"BountyRefresh"\s*,\s*"CommonEnabled"\s*,\s*true\b' 'Common bounty refresh must default to enabled.'
Require-Pattern $source 'Config\.Bind\s*\(\s*"BountyRefresh"\s*,\s*"GovernEnabled"\s*,\s*true\b' 'Government bounty refresh must default to enabled.'
Reject-Pattern $source '(?i)bounty[^;\r\n]*(?:ConfigEntry<KeyCode>|Hotkey)|(?:Input\.GetKeyDown|Input\.GetKey)\([^\)]*bounty' 'Bounty refresh must not expose or poll a hotkey.'

Require-Pattern $source 'PatchMethod\(\s*typeof\(BountyUIController\),\s*(?:"FreshBountyButtonClicked"|nameof\(BountyUIController\.FreshBountyButtonClicked\))[\s\S]*?nameof\(BountyFreshButtonClickedPrefix\)' 'The mod must reuse the original bounty refresh button click method.'
Require-Pattern $source 'PatchMethod\(\s*typeof\(BountyUIController\),\s*(?:"FreshBounty"|nameof\(BountyUIController\.FreshBounty\))[\s\S]*?nameof\(BountyFreshPostfix\)' 'The mod must observe every bounty UI rebuild to restore the original button interactability.'

Require-Pattern $resolveTypeMethod 'switch\s*\(\s*targetBuilding\.buildingID\s*\)[\s\S]*?case\s+0\s*:[\s\S]*?expectedType\s*=\s*BountyType\.ForceBounty[\s\S]*?case\s+15\s*:[\s\S]*?expectedType\s*=\s*BountyType\.GovernBounty[\s\S]*?case\s+18\s*:[\s\S]*?expectedType\s*=\s*BountyType\.CommonBounty[\s\S]*?default\s*:[\s\S]*?return\s+false[\s\S]*?var missions\s*=\s*targetBuilding\.missionDatas' 'Bounty type resolution must whitelist buildings 0/15/18 before inspecting mission types.'
Require-Pattern $resolveTypeMethod 'mission\.missionBountyType\s*!=\s*expectedType[\s\S]*?return\s+false[\s\S]*?bountyType\s*=\s*expectedType[\s\S]*?return\s+true' 'Every non-null mission must match the bounty type implied by the whitelisted building.'
Reject-Pattern $resolveTypeMethod 'case\s+54\s*:' 'Special building 54 must not be admitted to unlimited refresh even when its missions use ForceBounty.'
Reject-Pattern $resolveTypeMethod 'bountyType\s*=\s*mission\.missionBountyType' 'Mission type alone must never opt a non-whitelisted building into unlimited refresh.'
Reject-Pattern $resolveTypeMethod 'BountyType\.NpcBounty\s*(?:=>|:)[\s\S]{0,80}(?:true|return\s+true)' 'NPC bounty must never be opted into unlimited refresh.'
Require-Pattern $enabledMethod 'BountyType\.ForceBounty\s*=>\s*_forceBountyRefreshEnabled\.Value[\s\S]*?BountyType\.CommonBounty\s*=>\s*_commonBountyRefreshEnabled\.Value[\s\S]*?BountyType\.GovernBounty\s*=>\s*_governBountyRefreshEnabled\.Value[\s\S]*?_\s*=>\s*false' 'Only the three requested bounty categories may use their independent unlimited-refresh switches.'

Require-Pattern $clickPrefix '_bountyRefreshReentry[\s\S]*?return\s+true' 'The recursive original-call guard must let the inner vanilla click execute.'
Require-Pattern $clickPrefix 'TryResolveBountyType[\s\S]*?IsBountyRefreshEnabled\(\s*bountyType\s*\)[\s\S]*?return\s+true' 'Unknown, NPC, or disabled bounty categories must retain vanilla behavior.'
Require-Pattern $clickPrefix 'targetBuilding\s*=\s*__instance\.targetBuildingData[\s\S]*?buildingSnapshot\s*=\s*targetBuilding\.Clone\(\)\s+as\s+AreaBuildingData' 'The exact target building must be cloned before attempting unlimited refresh.'
Require-Pattern $clickPrefix 'var\s+\w*[Cc]ount\w*\s*=\s*worldData\.monthFreshBountyTime' 'The original monthly refresh counter must be snapshotted.'
Require-Pattern $clickPrefix '_bountyRefreshReentry\s*=\s*true[\s\S]*?monthFreshBountyTime\s*=\s*-1[\s\S]*?__instance\.FreshBountyButtonClicked\(\)[\s\S]*?return\s+false' 'Unlimited refresh must reenter the exact vanilla click with a temporary counter value and skip the outer original.'
Require-Pattern $clickPrefix 'catch\s*\(Exception ex\)[\s\S]*?targetBuilding\.missionDatas\s*=\s*buildingSnapshot\.missionDatas[\s\S]*?targetBuilding\.missionNumCount\s*=\s*buildingSnapshot\.missionNumCount[\s\S]*?__instance\.FreshBounty\(\)' 'A failed refresh must restore the cloned mission list/count and rebuild the visible UI.'
Require-Pattern $clickPrefix 'finally[\s\S]*?worldData\.monthFreshBountyTime\s*=\s*\w*[Cc]ount\w*[\s\S]*?_bountyRefreshReentry\s*=\s*false' 'The original monthly counter and recursive guard must always be restored.'

Require-Pattern $freshPostfix 'TryResolveBountyType[\s\S]*?IsBountyRefreshEnabled\(\s*bountyType\s*\)' 'FreshBounty postfix must honor the independent category switches through the shared category gate.'
Require-Pattern $freshPostfix 'bountyUIPanel\?\.transform\.Find\(\s*"FreshButton"\s*\)\?\.GetComponent<Button>\(\)[\s\S]*?interactable\s*=\s*true' 'The existing FreshButton must be forced interactable for enabled unlimited refresh categories.'
Reject-Pattern $source '(?i)(?:BountyRefreshButtonName|CreateBountyRefreshButton|EnsureBountyRefreshButton|TryCreate[^\r\n]*Bounty)' 'Bounty refresh must not create a second custom button.'
Reject-Pattern $source 'ConfigEntry<KeyCode>\s+_[A-Za-z0-9_]*Bounty' 'No bounty refresh hotkey configuration may be added.'

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ -ErrorAction Continue }
    exit 1
}

Write-Host "Bounty refresh semantic checks passed: $resolvedSourcePath"
