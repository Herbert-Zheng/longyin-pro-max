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
    if (-not [regex]::IsMatch($Scope, $Pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)) {
        $failures.Add($Message)
    }
}

function Reject-Pattern {
    param([AllowEmptyString()][string]$Scope, [string]$Pattern, [string]$Message)
    if ([regex]::IsMatch($Scope, $Pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)) {
        $failures.Add($Message)
    }
}

$prefix = Get-CSharpMethodText 'BountyContributionRewardPrefix'
$postfix = Get-CSharpMethodText 'BountyContributionRewardPostfix'
$finalizer = Get-CSharpMethodText 'BountyContributionRewardFinalizer'
$restore = Get-CSharpMethodText 'RestoreBountyContributionReward'
$multiplier = Get-CSharpMethodText 'GetBountyContributionMultiplier'

Require-Pattern $source 'ConfigEntry<float>\s+_bountyContributionMultiplier\b' 'Commission contribution multiplier must use a persisted float setting.'
Require-Pattern $source 'Config\.Bind\s*\(\s*"BountyReward"\s*,\s*"ContributionMultiplier"\s*,\s*2f\b' 'Commission contribution multiplier must default to 2x in BountyReward.'
Require-Pattern $source 'PatchMethod\(\s*typeof\(GameController\),\s*nameof\(GameController\.FinishMission\),\s*new\[\]\s*\{\s*typeof\(MissionData\)\s*\}[\s\S]*?nameof\(BountyContributionRewardPrefix\)[\s\S]*?nameof\(BountyContributionRewardPostfix\)[\s\S]*?nameof\(BountyContributionRewardFinalizer\)' 'The multiplier must patch the single native FinishMission settlement boundary with rollback hooks.'

Require-Pattern $prefix 'targetMission\.missionSourceType\s*!=\s*MissionSourceType\.Bounty' 'Only bounty/commission missions may enter reward scaling.'
Require-Pattern $prefix 'targetMission\.missionBountyType\s*!=\s*BountyType\.ForceBounty[\s\S]*?targetMission\.missionBountyType\s*!=\s*BountyType\.GovernBounty' 'Only sect and government commission categories may scale contribution.'
Reject-Pattern $prefix 'BountyType\.(?:CommonBounty|NpcBounty)' 'Notice-board fame and NPC favor must not be treated as contribution.'
Require-Pattern $prefix 'originalReward\s*=\s*targetMission\.missionFameReward[\s\S]*?originalReward\s*<=\s*0f' 'The native bounty reward field must only scale for positive gains.'
Require-Pattern $prefix 'GetBountyContributionMultiplier\(\)[\s\S]*?originalReward\s*\*\s*\(double\)multiplier[\s\S]*?targetMission\.missionFameReward\s*=\s*appliedReward' 'The native reward field must receive the configured multiplier before settlement.'

Require-Pattern $postfix 'RestoreBountyContributionReward\(\s*__state\s*\)' 'Successful settlement must restore the MissionData reward field.'
Require-Pattern $finalizer 'RestoreBountyContributionReward\(\s*__state\s*\)[\s\S]*?return\s+__exception' 'Exceptional settlement must restore the MissionData reward field without swallowing the exception.'
Require-Pattern $restore 'state\.IsApplied[\s\S]*?state\.IsRestored[\s\S]*?state\.Mission\.missionFameReward\s*=\s*state\.OriginalReward[\s\S]*?state\.IsRestored\s*=\s*true' 'Reward restoration must be idempotent and restore the exact original value.'
Require-Pattern $multiplier 'float\.IsNaN\(configured\)[\s\S]*?float\.IsInfinity\(configured\)[\s\S]*?return\s+2f[\s\S]*?Mathf\.Clamp\(configured,\s*0f,\s*999f\)' 'Invalid multipliers must fall back to 2x and finite values must be clamped to 0-999x.'

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ -ErrorAction Continue }
    exit 1
}

Write-Host "Bounty contribution multiplier semantic checks passed: $resolvedSourcePath"
