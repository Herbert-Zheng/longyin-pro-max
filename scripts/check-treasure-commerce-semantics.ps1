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
        [AllowEmptyString()]
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
        [AllowEmptyString()]
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
        [AllowEmptyString()]
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

function Reject-ScopePattern {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Scope,

        [Parameter(Mandatory)]
        [string]$Pattern,

        [Parameter(Mandatory)]
        [string]$FailureMessage
    )

    if ([System.Text.RegularExpressions.Regex]::IsMatch(
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
$shopContextMethod = Get-CSharpMethodText 'TryGetTreasureTradeShopContext'
$queueCartMethod = Get-CSharpMethodText 'QueueTreasureTradeCartItems'
$updateOverlayMethod = Get-CSharpMethodText 'UpdateTreasureTradeOverlay'
$cartSummaryMethod = Get-CSharpMethodText 'BuildTreasureTradeCartSummary'
$cartSummaryTextMethod = Get-CSharpMethodText 'BuildTreasureTradeCartSummaryText'
$setTradeInfoLabelTextMethod = Get-CSharpMethodText 'SetTradeInfoLabelText'
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
Require-ScopePattern $sellEstimatorMethod 'return\s+Math\.Max\(\s*Math\.Max\(0,\s*currentSellPrice\),\s*Math\.Max\(0,\s*appraisedValue\)\s*\)\s*;' 'The parenthesized appraisal value is already the player-knowledge trade estimate and must be used directly without a second sell-ratio discount.'
Reject-ScopeText $sellEstimatorMethod 'item.value' 'The sell estimator must not derive another discount ratio from the raw treasure value.'
Reject-ScopeText $sellEstimatorMethod 'sellRatio' 'The sell estimator must not discount the verified parenthesized appraisal value a second time.'
Require-ScopePattern $appraisedValueMethod 'appraisedValue\s*=\s*Math\.Max\(0,\s*item\.GetTreasureRealValue\(\)\);\s*return true;' 'The shared appraisal helper must succeed only after reading the verified game API.'
Require-ScopePattern $appraisedValueMethod 'catch\s*\(Exception ex\).*?return false;' 'The shared appraisal helper must skip the item when the verified game API fails.'
Reject-ScopeText $appraisedValueMethod 'item.value' 'The shared appraisal helper must not silently substitute the raw item value when the parenthesized appraisal API fails.'
Reject-ScopeText $tradeAnalyzerMethod '.Clone(' 'The per-frame shop analyzer must not clone shop items.'
Reject-ScopeText $tradeAnalyzerMethod '.FullIdentify(' 'The per-frame shop analyzer must not fully identify shop items.'
Reject-ScopeText $sellEstimatorMethod '.Clone(' 'The sell-price estimator must not clone shop items.'
Reject-ScopeText $sellEstimatorMethod '.FullIdentify(' 'The sell-price estimator must not fully identify shop items.'
Reject-SourceText 'TryCloneAndIdentifyItem' 'The shop helper must not clone and fully identify shop items during its per-frame overlay refresh.'
Reject-SourceText '.FullIdentify(' 'Commerce must not reintroduce full-identification probing under a renamed helper.'
Require-ScopePattern $autoTradeMethod 'opportunity\.NetProfit\s*>\s*0' 'Automatic treasure shopping must preserve the reference behavior of using positive estimated profit.'
Reject-ScopePattern $autoTradeMethod 'if\s*\(\s*opportunities\.Count\s*<=\s*0\s*\)\s*\{[^}]*_treasureTradeAutoProcessed\s*=\s*true' 'A zero-opportunity snapshot must remain retryable instead of permanently locking treasure auto-shopping for the current shop session.'
Require-ScopePattern $autoTradeMethod 'shopTargetCount\s*>\s*0\s*&&\s*shopIconCount\s*<\s*shopTargetCount[\s\S]*?_treasureTradeAutoRetryAtRealtime\s*=' 'Automatic treasure shopping must wait and retry until every shop item has a rendered icon instead of processing a partial first frame.'
Require-ScopePattern $autoTradeMethod '_treasureTradeAutoProcessed\s*=\s*QueueTreasureTradeCartItems\s*\(' 'A shop session may be marked processed only from the verified queue result.'
Require-ScopePattern $shopContextMethod 'identifyCost\s*=\s*[^;\r\n]*GetBuildingIdentifyMoney\s*\(' 'Treasure appraisal cost must come from the current building GetBuildingIdentifyMoney API.'
Require-ScopePattern $queueCartMethod 'CountItemListItems\s*\(\s*tradeUi\.rightOutList\?\.targetItemList\s*\)[\s\S]*?TradeIconClicked\s*\([^;]+\);[\s\S]*?CountItemListItems\s*\(\s*tradeUi\.rightOutList\?\.targetItemList\s*\)' 'Each treasure cart click must be verified against the actual rightOutList item count before it is reported as added.'
Require-ScopePattern $queueCartMethod 'matchingCountAfter\s*>\s*matchingCountBefore[\s\S]*?verifiedCount\+\+' 'A click counts as successful only when the intended item increases inside rightOutList.'
Require-ScopePattern $queueCartMethod 'PushPlayerLog\s*\([^;]*\{verifiedCount\}' 'The player-facing auto-cart result must report verified additions rather than attempted clicks.'
Require-ScopeText $cartSummaryMethod 'CountItemListItems(tradeUi.rightOutList?.targetItemList)' 'The treasure assistant cart summary must take its authoritative total count from the actual rightOutList cart.'
Require-ScopeText $cartSummaryMethod 'EnumerateTradeIconsMatchingTargetList(tradeUi.rightOutList)' 'The treasure assistant must aggregate only icons that still correspond to actual rightOutList cart entries.'
Require-ScopePattern $cartSummaryMethod 'BuyTotal\s*\+=' 'The cart summary must add every treasure buy price into a total.'
Require-ScopePattern $cartSummaryMethod 'IdentifyCostTotal\s*\+=' 'The cart summary must add appraisal costs for unidentified treasures.'
Require-ScopePattern $cartSummaryMethod 'EstimatedSellTotal\s*\+=' 'The cart summary must add estimated post-appraisal sell proceeds.'
Require-ScopePattern $updateOverlayMethod 'BuildTreasureTradeCartSummary\s*\([\s\S]*?BuildTreasureTradeCartSummaryText\s*\(' 'The visible treasure assistant must be driven by the live cart aggregate rather than a selected shop item.'
Require-ScopeText $updateOverlayMethod 'verticalOffset: -13f' 'The treasure money icon must align with the second summary line that contains the buy amount.'
Reject-ScopeText $updateOverlayMethod 'TryResolveTreasureTradeOpportunity' 'The visible treasure assistant must no longer fall back to a selected or first shop item.'
Require-ScopePattern $setTradeInfoLabelTextMethod 'if\s*\(\s*!string\.Equals\(label\.text,\s*text,[^)]*\)\s*\)[\s\S]*?label\.text\s*=\s*text;[\s\S]*?AlignTradeInfoIcon\(' 'Money icon alignment must still run when the visible summary text has not changed.'
foreach ($label in @('购物车', '珍宝', '未鉴定', '买入', '鉴定', '预计卖出', '预计利润')) {
    Require-ScopeText $cartSummaryTextMethod $label "The live cart summary text is missing its '$label' aggregate label."
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ -ErrorAction Continue }
    exit 1
}

Write-Host "Treasure commerce semantic checks passed: $resolvedSourcePath"
