param(
    [string]$SourcePath = (Join-Path $PSScriptRoot '..\mod-src\LongYinStaminaLock\LongYinStaminaLock.cs')
)

$ErrorActionPreference = 'Stop'

$resolvedSourcePath = (Resolve-Path -LiteralPath $SourcePath).Path
$source = Get-Content -Raw -LiteralPath $resolvedSourcePath
$failures = [System.Collections.Generic.List[string]]::new()

function Require-SourceText {
    param(
        [Parameter(Mandatory)]
        [string]$Text,

        [Parameter(Mandatory)]
        [string]$FailureMessage
    )

    if ($source.IndexOf($Text, [System.StringComparison]::Ordinal) -lt 0) {
        $failures.Add($FailureMessage)
    }
}

function Reject-SourceText {
    param(
        [Parameter(Mandatory)]
        [string]$Text,

        [Parameter(Mandatory)]
        [string]$FailureMessage
    )

    if ($source.IndexOf($Text, [System.StringComparison]::Ordinal) -ge 0) {
        $failures.Add($FailureMessage)
    }
}

function Get-CSharpMethodText {
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $escapedName = [System.Text.RegularExpressions.Regex]::Escape($Name)
    $methodPattern = "(?m)^    private static[^\r\n]*\b$escapedName\s*\("
    $methodRegex = [System.Text.RegularExpressions.Regex]::new($methodPattern)
    $methodMatch = $methodRegex.Match($source)
    if (-not $methodMatch.Success) {
        $failures.Add("Could not locate C# method: $Name")
        return ''
    }

    $nextMethodRegex = [System.Text.RegularExpressions.Regex]::new(
        '(?m)^    private static[^\r\n]*\b[A-Za-z_][A-Za-z0-9_]*\s*\(')
    $nextMethodMatch = $nextMethodRegex.Match($source, $methodMatch.Index + $methodMatch.Length)
    $endIndex = if ($nextMethodMatch.Success) { $nextMethodMatch.Index } else { $source.Length }
    return $source.Substring($methodMatch.Index, $endIndex - $methodMatch.Index)
}

function Require-ScopeText {
    param(
        [Parameter(Mandatory)]
        [string]$Scope,

        [Parameter(Mandatory)]
        [string]$Text,

        [Parameter(Mandatory)]
        [string]$FailureMessage
    )

    if ($Scope.IndexOf($Text, [System.StringComparison]::Ordinal) -lt 0) {
        $failures.Add($FailureMessage)
    }
}

function Reject-ScopeText {
    param(
        [Parameter(Mandatory)]
        [string]$Scope,

        [Parameter(Mandatory)]
        [string]$Text,

        [Parameter(Mandatory)]
        [string]$FailureMessage
    )

    if ($Scope.IndexOf($Text, [System.StringComparison]::Ordinal) -ge 0) {
        $failures.Add($FailureMessage)
    }
}

function Require-ScopePattern {
    param(
        [Parameter(Mandatory)]
        [string]$Scope,

        [Parameter(Mandatory)]
        [string]$Pattern,

        [Parameter(Mandatory)]
        [string]$FailureMessage
    )

    if (-not [System.Text.RegularExpressions.Regex]::IsMatch(
        $Scope,
        $Pattern,
        [System.Text.RegularExpressions.RegexOptions]::Singleline)) {
        $failures.Add($FailureMessage)
    }
}

$selectorMethod = Get-CSharpMethodText 'TrySelectHighestValueIdentifyTreasure'
$tradeAnalyzerMethod = Get-CSharpMethodText 'TryAnalyzeTreasureTradeIcon'
$sellEstimatorMethod = Get-CSharpMethodText 'EstimateTreasureSellPriceFromAppraisedValue'
$appraisedValueMethod = Get-CSharpMethodText 'TryGetTreasureAppraisedValue'
$autoTradeMethod = Get-CSharpMethodText 'TryRunTreasureAutoTrade'
$overlayTextMethod = Get-CSharpMethodText 'BuildTreasureTradeOverlayText'
$clickRouterMethod = Get-CSharpMethodText 'OverlayButtonOnPointerClickPrefix'
$updateShopOwnershipMethod = Get-CSharpMethodText 'UpdateShopOwnershipUiState'
$ensureShopOwnershipMethod = Get-CSharpMethodText 'EnsureShopOwnershipOverlay'
$buyShopMethod = Get-CSharpMethodText 'TryBuyCurrentShop'
$externalOverlayStateMethod = Get-CSharpMethodText 'WriteExternalOverlayState'

Require-ScopePattern $source 'Config\.Bind\s*\(\s*"Commerce"\s*,\s*"ShopOwnershipEnabled"\s*,\s*true\b' 'Shop ownership must have an enabled-by-default Commerce feature switch.'
Require-ScopePattern $clickRouterMethod 'isShopOwnershipBuy[\s\S]*?_shopOwnershipEnabled\.Value[\s\S]*?OnShopOwnershipBuyButtonClicked' 'The shared overlay click router must gate shop buyout dispatch behind ShopOwnershipEnabled.'
Require-ScopePattern $updateShopOwnershipMethod '!_shopOwnershipEnabled\.Value[\s\S]*?HideShopOwnershipOverlay\(\)' 'Disabling shop ownership must actively hide any existing ownership overlay and buyout button.'
Require-ScopeText $ensureShopOwnershipMethod '!_shopOwnershipEnabled.Value' 'Disabled shop ownership must not create its overlay or buyout button.'
Require-ScopePattern $buyShopMethod '!_shopOwnershipEnabled\.Value[\s\S]*?return false;' 'The shop buyout action must have a final ShopOwnershipEnabled gate.'
Require-ScopePattern $externalOverlayStateMethod 'inShop\s*=\s*_shopOwnershipEnabled\.Value\s*&&\s*TryResolveCurrentShopOwnershipContext' 'External overlay state must report no active shop when shop ownership is disabled.'
Require-ScopePattern $externalOverlayStateMethod 'canBuy\s*=\s*inShop\s*&&' 'External overlay buyout availability must remain derived from the gated inShop state.'
Require-ScopePattern $clickRouterMethod 'isIdentifyAssist[\s\S]*?_treasureIdentifyBestValueAssistEnabled\.Value[\s\S]*?TrySelectHighestValueIdentifyTreasure' 'The shared overlay click router must gate treasure identify assist dispatch behind BestValueAssistEnabled.'
Require-ScopeText $selectorMethod '!_treasureIdentifyBestValueAssistEnabled.Value' 'The treasure identify selection action must have a final BestValueAssistEnabled gate.'

Reject-SourceText '自动选中真品' 'The appraisal control still claims to select a genuine item instead of the highest displayed value.'
Require-SourceText '自动选择最高价' 'The appraisal control must say that it selects the highest-priced item.'
Require-SourceText 'TryGetTreasureAppraisedValue' 'Appraisal and commerce must share an explicitly named player-appraised value helper.'
Require-SourceText '括号估价' 'The treasure trade overlay must expose the same parenthesized appraisal value used by the appraisal mini-game.'
Reject-SourceText 'EstimateTreasureSellPriceFromRealValue' 'The old real-value wording must not remain in the trade estimate implementation.'
Require-ScopeText $selectorMethod 'TryGetTreasureAppraisedValue(icon.itemData, out var appraisedValue)' 'The appraisal selector must read every candidate through the shared parenthesized appraisal helper.'
Require-ScopePattern $selectorMethod 'appraisedValue\s*>\s*bestValue' 'The appraisal selector must rank active candidates by the shared parenthesized appraisal value.'
Require-ScopeText $tradeAnalyzerMethod 'TryGetTreasureAppraisedValue(item, out var appraisedValue)' 'The shop helper must read the same parenthesized appraisal value.'
Require-ScopeText $tradeAnalyzerMethod 'EstimateTreasureSellPriceFromAppraisedValue(' 'The shop helper must derive its estimated post-appraisal sell price from the parenthesized appraisal value.'
Require-ScopePattern $appraisedValueMethod 'appraisedValue\s*=\s*Math\.Max\(0,\s*item\.GetTreasureRealValue\(\)\);\s*return true;' 'The shared appraisal helper must succeed only after reading the verified game API.'
Require-ScopePattern $appraisedValueMethod 'catch\s*\(Exception ex\).*?return false;' 'The shared appraisal helper must skip the item when the verified game API fails.'
Reject-ScopeText $appraisedValueMethod 'item.value' 'The shared appraisal helper must not silently substitute the raw item value when the parenthesized appraisal API fails.'
Reject-ScopeText $tradeAnalyzerMethod '.Clone(' 'The per-frame shop analyzer must not clone shop items.'
Reject-ScopeText $tradeAnalyzerMethod '.FullIdentify(' 'The per-frame shop analyzer must not fully identify shop items.'
Reject-ScopeText $sellEstimatorMethod '.Clone(' 'The sell-price estimator must not clone shop items.'
Reject-ScopeText $sellEstimatorMethod '.FullIdentify(' 'The sell-price estimator must not fully identify shop items.'
Reject-SourceText 'TryCloneAndIdentifyItem' 'The shop helper must not clone and fully identify shop items during its per-frame overlay refresh.'
Reject-SourceText '.FullIdentify(' 'Commerce must not reintroduce full-identification probing under a renamed helper.'
Require-ScopeText $overlayTextMethod '预计鉴后卖价' 'The derived post-appraisal sell price must be visibly labeled as an estimate.'
Require-ScopePattern $autoTradeMethod 'opportunity\.NetProfit\s*>\s*0' 'Automatic treasure shopping must preserve the reference behavior of using positive estimated profit.'

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host "Treasure commerce semantic checks passed: $resolvedSourcePath"
