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

$openMethod = Get-CSharpMethodText 'ToggleMaterialAffixFilterPopup'
$closeMethod = Get-CSharpMethodText 'CloseMaterialAffixFilterPopup'
$addMethod = Get-CSharpMethodText 'TryAddMaterialAffixFilterDraftRule'
$applyMethod = Get-CSharpMethodText 'ApplyMaterialAffixFilterDraft'
$combineMethod = Get-CSharpMethodText 'SetMaterialAffixFilterDraftCombineMode'
$kindMethod = Get-CSharpMethodText 'ToggleMaterialAffixFilterComposerKind'
$sweepPredicate = Get-CSharpMethodText 'IsMaterialMatchingSweepFilters'
$affixPredicate = Get-CSharpMethodText 'IsMaterialMatchingAffixFilter'
$cartMethod = Get-CSharpMethodText 'TryAddFilteredMaterialsToTradeCart'

Require-Pattern $source 'private const int MaterialAffixFilterMaxRuleCount\s*=\s*4\s*;' 'Material affix filtering must allow at most four rules.'
Require-Pattern $addMethod '_materialAffixFilterDraftRules\.Count\s*>=\s*MaterialAffixFilterMaxRuleCount[\s\S]*?return false' 'Adding a fifth affix rule must be rejected.'
Require-Pattern $source 'for\s*\(var index\s*=\s*0\s*;\s*index\s*<\s*MaterialAffixFilterMaxRuleCount\s*;\s*index\+\+\)' 'The popup must allocate exactly the configured maximum rule rows.'

Require-Pattern $openMethod '_materialAffixFilterDraftRules\.Clear\(\)[\s\S]*?_materialAffixFilterAppliedRules\.Select\(CloneMaterialAffixFilterRule\)[\s\S]*?_materialAffixFilterDraftEnabled\s*=\s*_materialAffixFilterEnabled\.Value[\s\S]*?_materialAffixFilterDraftCombineMode\s*=\s*_materialAffixFilterCombineMode\.Value' 'Opening the popup must create an isolated draft from all applied settings.'
Require-Pattern $applyMethod '_materialAffixFilterAppliedRules\.Clear\(\)[\s\S]*?_materialAffixFilterDraftRules\.Select\(CloneMaterialAffixFilterRule\)[\s\S]*?_materialAffixFilterEnabled\.Value\s*=\s*_materialAffixFilterDraftEnabled[\s\S]*?_materialAffixFilterCombineMode\.Value\s*=\s*_materialAffixFilterDraftCombineMode[\s\S]*?PersistMaterialAffixFilterRules\(\)' 'Apply must atomically promote and persist the draft rules, enabled state, and AND/OR mode.'
Require-Pattern $closeMethod 'if\s*\(discardDraft\)[\s\S]*?_materialAffixFilterDraftRules\.Clear\(\)' 'Cancel/close must discard draft rules.'
Reject-Pattern $closeMethod '_materialAffixFilterAppliedRules\.(?:Clear|Add|Remove)' 'Cancel/close must not mutate applied rules.'
Require-Pattern $source 'isMaterialAffixClose\s*\|\|\s*isMaterialAffixCancel[\s\S]*?CloseMaterialAffixFilterPopup\(discardDraft:\s*true\)' 'Both close and cancel buttons must discard the draft.'

Require-Pattern $combineMethod '_materialAffixFilterDraftCombineMode\s*=\s*mode' 'The popup must edit AND/OR mode in draft state only.'
Require-Pattern $kindMethod 'MaterialAffixMatchKind\.Contains[\s\S]*?MaterialAffixMatchKind\.Exact[\s\S]*?MaterialAffixMatchKind\.Contains' 'The rule composer must toggle between contains and exact matching.'
Require-Pattern $affixPredicate 'rule\.Kind\s*==\s*MaterialAffixMatchKind\.Exact[\s\S]*?string\.Equals\(line,\s*rule\.Text,\s*StringComparison\.OrdinalIgnoreCase\)[\s\S]*?line\.IndexOf\(rule\.Text,\s*StringComparison\.OrdinalIgnoreCase\)\s*>=\s*0' 'Exact rules must compare full lines, while contains rules must use case-insensitive substring matching.'
Require-Pattern $affixPredicate 'MaterialAffixCombineMode\.All[\s\S]*?_materialAffixFilterAppliedRules\.All\(MatchesRule\)[\s\S]*?_materialAffixFilterAppliedRules\.Any\(MatchesRule\)' 'ALL mode must require every rule and ANY mode must require at least one rule.'
Require-Pattern $affixPredicate '!_materialAffixFilterEnabled\.Value\s*\|\|\s*_materialAffixFilterAppliedRules\.Count\s*==\s*0[\s\S]*?return true' 'Disabled filtering or an empty applied rule set must preserve all threshold-matching materials.'

Require-Pattern $sweepPredicate 'item\.rareLv\s*>=\s*ClampMaterialFilterLevel\(minRareLv\)[\s\S]*?item\.itemLv\s*>=\s*ClampMaterialFilterLevel\(minItemLv\)[\s\S]*?IsMaterialMatchingAffixFilter\(item\)' 'Rarity, item-level, and affix predicates must all be combined with AND.'
Require-Pattern $cartMethod 'IsMaterialMatchingSweepFilters\(item,\s*minRareLv,\s*minItemLv\)[\s\S]*?tradeUi\.TradeIconClicked\(icon\.gameObject\)' 'Only materials satisfying the combined predicate may be added through the vanilla cart path.'
foreach ($forbidden in @('TradeButtonClicked', 'SureButtonClicked', 'ConfirmTrade', 'FinishTrade', 'ExecuteTrade')) {
    Reject-Pattern $cartMethod ([regex]::Escape($forbidden)) "Affix-filtered sweep must not automatically confirm a transaction: $forbidden"
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ -ErrorAction Continue }
    exit 1
}

Write-Host "Material affix filter semantic checks passed: $resolvedSourcePath"
