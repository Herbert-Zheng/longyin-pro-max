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

$clickRouterMethod = Get-CSharpMethodText 'OverlayButtonOnPointerClickPrefix'
$autoBuyClickMethod = Get-CSharpMethodText 'OnMaterialAutoBuyButtonClicked'
$filterMaterialsMethod = Get-CSharpMethodText 'TryAddFilteredMaterialsToTradeCart'
$matchingThresholdsMethod = Get-CSharpMethodText 'IsMaterialMatchingThresholds'
$activeShopMethod = Get-CSharpMethodText 'TryGetActiveShopTradeUi'
$ensureControlsMethod = Get-CSharpMethodText 'EnsureMaterialAutoBuyControls'
$createFilterOptionMethod = Get-CSharpMethodText 'TryCreateMaterialFilterOptionButton'
$destroyControlsMethod = Get-CSharpMethodText 'DestroyMaterialAutoBuyControls'
$setOptionsVisibleMethod = Get-CSharpMethodText 'SetMaterialFilterOptionsVisible'
$setFilterLevelMethod = Get-CSharpMethodText 'SetMaterialFilterLevel'
$hideTradeUiMethod = Get-CSharpMethodText 'HideTradeUiPostfix'
$tradeUiShownMethod = Get-CSharpMethodText 'HandleTreasureTradeUiShown'
$findButtonTemplateMethod = Get-CSharpMethodText 'FindUiButtonTemplate'
$insideOverlayRootMethod = Get-CSharpMethodText 'IsButtonInsideKnownOverlayRoot'
$filterOptionNameMethod = Get-CSharpMethodText 'IsMaterialFilterOptionButtonName'
$filterOptionParserMethod = Get-CSharpMethodText 'TryParseMaterialFilterOptionButton'

foreach ($controlName in @(
    'MaterialAutoBuyButtonName',
    'MaterialFilterDropdownButtonName',
    'MaterialFilterDropdownPanelName',
    'MaterialRareOptionButtonPrefix',
    'MaterialItemLevelOptionButtonPrefix'
)) {
    Require-SourceText $controlName "Missing material auto-buy UI control name: $controlName"
}

Require-ScopeText $clickRouterMethod 'MaterialAutoBuyButtonName' 'The shared overlay click router must recognize the material auto-buy button.'
Require-ScopeText $clickRouterMethod 'MaterialFilterDropdownButtonName' 'The shared overlay click router must recognize the material filter dropdown button.'
Require-ScopeText $clickRouterMethod 'TryParseMaterialFilterOptionButton' 'The shared overlay click router must parse both kinds of material filter option.'
Require-ScopeText $clickRouterMethod 'OnMaterialAutoBuyButtonClicked' 'The shared overlay click router must dispatch the material auto-buy action.'
Reject-ScopeText $clickRouterMethod 'onClick.AddListener' 'Material overlay buttons must use the pointer-click patch route instead of Unity onClick listeners.'

Reject-ScopeText $autoBuyClickMethod 'onClick.AddListener' 'The material auto-buy click handler must not register Unity onClick listeners.'
Require-ScopeText $autoBuyClickMethod 'TryGetActiveShopTradeUi' 'The material auto-buy click handler must resolve an active shop before filling its cart.'
Require-ScopeText $autoBuyClickMethod 'TryAddFilteredMaterialsToTradeCart' 'The material auto-buy click handler must delegate to the filtered cart operation.'

Require-ScopeText $activeShopMethod 'tradeUIType != TradeUIType.Shop' 'Material auto-buy must reject a non-shop trade UI.'
Require-ScopePattern $activeShopMethod 'tradeUI\s*!=\s*null\s*&&\s*tradeUi\.tradeUI\.activeInHierarchy' 'Material auto-buy must operate only while the shop trade UI is active.'
Require-ScopeText $filterMaterialsMethod 'tradeUi.rightList' 'Material auto-buy must enumerate only the active shop right-side list.'
Reject-ScopeText $filterMaterialsMethod 'tradeUi.leftList' 'Material auto-buy must not scan the player inventory.'
Require-ScopePattern $filterMaterialsMethod 'item(?:Data)?\.type\s*!=\s*ItemType\.Material|item(?:Data)?\.type\s*==\s*ItemType\.Material' 'Material auto-buy must filter strictly to ItemType.Material.'
Require-ScopeText $filterMaterialsMethod 'IsMaterialMatchingThresholds(item, minRareLv, minItemLv)' 'Material auto-buy must apply both selected thresholds to every material.'
Require-ScopePattern $matchingThresholdsMethod 'item\.type\s*==\s*ItemType\.Material' 'The threshold helper must preserve the material-only restriction.'
Require-ScopePattern $matchingThresholdsMethod 'item\.rareLv\s*>=\s*ClampMaterialFilterLevel\(minRareLv\)' 'Material auto-buy must enforce the selected minimum rarity.'
Require-ScopePattern $matchingThresholdsMethod 'item\.itemLv\s*>=\s*ClampMaterialFilterLevel\(minItemLv\)' 'Material auto-buy must enforce the selected minimum item level.'
Require-ScopeText $filterMaterialsMethod 'TradeIconClicked' 'Material auto-buy must add matching shop icons through the vanilla trade-cart click path.'
foreach ($forbiddenTransactionCall in @(
    'TradeButtonClicked',
    'SureButtonClicked',
    'ConfirmTrade',
    'FinishTrade',
    'ExecuteTrade'
)) {
    Reject-ScopeText $filterMaterialsMethod $forbiddenTransactionCall "Material auto-buy must only fill the cart; forbidden transaction call found: $forbiddenTransactionCall"
}

Require-ScopePattern $ensureControlsMethod 'for\s*\(var level\s*=\s*0\s*;\s*level\s*<=\s*5\s*;\s*level\+\+\)' 'The dropdown must create threshold options 0 through 5.'
Require-ScopePattern $ensureControlsMethod 'TryCreateMaterialFilterOptionButton\([\s\S]*?isRareLevel:\s*true[\s\S]*?TryCreateMaterialFilterOptionButton\([\s\S]*?isRareLevel:\s*false' 'The dropdown must create separate rarity and item-level option columns.'
Require-ScopeText $ensureControlsMethod 'MaterialFilterDropdownPanelName' 'The dropdown must create one panel root for both threshold columns.'
Require-ScopeText $ensureControlsMethod '_materialAutoBuyButtonRoot.transform.parent == expectedParent' 'Cached material controls must be rejected when the trade UI rebuilds under a different parent.'
Require-ScopeText $createFilterOptionMethod '_materialFilterDropdownPanelRoot.transform' 'Every threshold option must be parented under the shared dropdown panel.'
Require-ScopeText $setOptionsVisibleMethod 'SetOverlayObjectActive(_materialFilterDropdownPanelRoot, visible)' 'Dropdown visibility must be controlled through the shared panel root.'
Reject-ScopeText $setOptionsVisibleMethod '_materialFilterOptionRoots' 'Dropdown visibility must not reorder or toggle all twelve option roots every frame.'
Reject-ScopeText $setOptionsVisibleMethod 'SetAsLastSibling' 'Dropdown visibility must not reorder option nodes every frame.'
Require-ScopeText $destroyControlsMethod 'if (destroyFailed)' 'Failed UI destruction must be detected before references are cleared.'
Require-ScopeText $destroyControlsMethod 'retaining references to prevent duplicate controls' 'Failed UI destruction must be logged and retain references to prevent duplicate controls.'
Require-ScopePattern $destroyControlsMethod 'catch\s*\([^)]*\)\s*\{[\s\S]*?LogWarning' 'UI-destruction exceptions must be logged instead of silently swallowed.'
if ([System.Text.RegularExpressions.Regex]::IsMatch(
    $destroyControlsMethod,
    'catch(?:\s*\([^)]*\))?\s*\{\s*\}',
    [System.Text.RegularExpressions.RegexOptions]::Singleline)) {
    $failures.Add('UI destruction must not contain an empty catch block.')
}
Require-ScopeText $setFilterLevelMethod '_materialPurchaseMinRareLv.Value = clampedLevel' 'Selecting a rarity option must update the rarity threshold.'
Require-ScopeText $setFilterLevelMethod '_materialPurchaseMinItemLv.Value = clampedLevel' 'Selecting an item-level option must update the item-level threshold.'
Require-ScopeText $setFilterLevelMethod 'ClampMaterialFilterLevel(level)' 'Dropdown threshold writes must be clamped to 0 through 5.'

Require-ScopePattern $hideTradeUiMethod 'material|Material' 'Closing the trade UI must also reset or hide the material filter menu.'
Require-ScopePattern $tradeUiShownMethod 'targetType\s*!=\s*TradeUIType\.Shop[\s\S]*material|material[\s\S]*targetType\s*!=\s*TradeUIType\.Shop' 'Opening a non-shop trade UI must hide the material controls/menu.'

Require-ScopeText $findButtonTemplateMethod 'MaterialAutoBuyButtonName' 'Button-template discovery must exclude the material auto-buy control.'
Require-ScopeText $findButtonTemplateMethod 'MaterialFilterDropdownButtonName' 'Button-template discovery must exclude the material filter dropdown control.'
Require-ScopeText $findButtonTemplateMethod 'MaterialFilterDropdownPanelName' 'Button-template discovery must exclude the material filter panel root.'
Require-ScopeText $findButtonTemplateMethod 'IsMaterialFilterOptionButtonName' 'Button-template discovery must exclude both kinds of material filter option control.'
Require-ScopeText $findButtonTemplateMethod 'IsButtonInsideKnownOverlayRoot' 'Button-template discovery must reject descendants of custom overlay roots.'
Require-ScopeText $insideOverlayRootMethod '_materialAutoBuyButtonRoot' 'Overlay-descendant detection must include the material auto-buy root.'
Require-ScopeText $insideOverlayRootMethod '_materialFilterDropdownButtonRoot' 'Overlay-descendant detection must include the material dropdown button root.'
Require-ScopeText $insideOverlayRootMethod '_materialFilterDropdownPanelRoot' 'Overlay-descendant detection must include the material dropdown panel root.'
Require-ScopeText $filterOptionNameMethod 'MaterialRareOptionButtonPrefix' 'Material filter option-name matching must recognize rarity options.'
Require-ScopeText $filterOptionNameMethod 'MaterialItemLevelOptionButtonPrefix' 'Material filter option-name matching must recognize item-level options.'
Require-ScopeText $filterOptionParserMethod 'MaterialRareOptionButtonPrefix' 'Material filter option parsing must recognize rarity options.'
Require-ScopeText $filterOptionParserMethod 'MaterialItemLevelOptionButtonPrefix' 'Material filter option parsing must recognize item-level options.'

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host "Material auto-buy semantic checks passed: $resolvedSourcePath"
