param(
    [string]$SourcePath = (Join-Path $PSScriptRoot '..\mod-src\LongYinStaminaLock\LongYinStaminaLock.cs')
)

$ErrorActionPreference = 'Stop'

$resolvedSourcePath = (Resolve-Path -LiteralPath $SourcePath).Path
$source = Get-Content -Raw -LiteralPath $resolvedSourcePath
$failures = [System.Collections.Generic.List[string]]::new()

function Get-CSharpMethodText {
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $escapedName = [System.Text.RegularExpressions.Regex]::Escape($Name)
    $methodPattern = "(?m)^    private static[^\r\n]*\b$escapedName\s*\("
    $methodMatch = [System.Text.RegularExpressions.Regex]::Match($source, $methodPattern)
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

$regenerateMethod = Get-CSharpMethodText 'TryRegenerateAuctionPreviewDirect'
$refreshMethod = Get-CSharpMethodText 'TryRefreshAuctionPreview'
$reopenMethod = Get-CSharpMethodText 'ReopenAuctionPreview'
$findChooseItemsMethod = Get-CSharpMethodText 'TryGetAuctionPreviewChooseItemContainer'
$clearChooseItemsMethod = Get-CSharpMethodText 'ClearAuctionPreviewChooseItemsImmediately'

Require-ScopeText $regenerateMethod 'var regeneratedItems = new ItemListData();' 'Auction refresh must generate into a fresh item collection instead of appending to the current event list.'
Require-ScopeText $regenerateMethod 'eventData.eventItemList = regeneratedItems;' 'Auction refresh must replace the event item list with the freshly generated collection.'
Require-ScopeText $regenerateMethod 'controller.tempPlotShop = regeneratedItems;' 'Auction refresh must replace the preview backing list with the freshly generated collection.'
Require-ScopePattern `
    $refreshMethod `
    'TryGetAuctionPreviewChooseItemContainer\s*\([^\)]*\)[\s\S]*?TryRegenerateAuctionPreviewDirect\s*\(' `
    'Auction refresh must resolve the real ChooseController item container before mutating the auction data so an incompatible UI can fail safely.'
Require-ScopePattern `
    $refreshMethod `
    'if\s*\(\s*!TryGetAuctionPreviewChooseItemContainer\s*\(\s*out var chooseItemContainer\s*\)\s*\|\|\s*chooseItemContainer\s*==\s*null\s*\)\s*\{[\s\S]*?return false\s*;' `
    'Auction refresh must stop before data mutation when the runtime targetGrid container is unavailable.'
Require-ScopePattern `
    $reopenMethod `
    'nameof\(PlotController\.HidePlotItem\)[\s\S]*?\.Invoke\(controller,[\s\S]*?nameof\(PlotController\.ClearPlotItem\)[\s\S]*?\.Invoke\(controller,[\s\S]*?ClearAuctionPreviewChooseItemsImmediately\([^\)]*\)[\s\S]*?nameof\(PlotController\.ShowAuctionItem\)[\s\S]*?\.Invoke\(controller,' `
    'Every refresh must synchronously detach the visible ChooseController item rows after the original cleanup and before ShowAuctionItem; otherwise the new rows append to the old exhibit list.'
Require-ScopeText $findChooseItemsMethod 'ChooseController.Instance' 'Auction refresh must resolve the runtime ChooseController singleton that owns the visible exhibit list.'
Require-ScopePattern $findChooseItemsMethod 'var\s+targetGrid\s*=\s*chooseController\?\.targetGrid\s*;' 'Auction refresh must resolve ChooseController.targetGrid, the dynamic row parent used by CreateChooseItem and cleared by the original HideChoosePanel.'
Require-ScopePattern $findChooseItemsMethod 'chooseItemContainer\s*=\s*targetGrid\.transform\s*;' 'Auction refresh must pass the targetGrid Transform to the synchronous row cleanup.'
Require-ScopePattern $clearChooseItemsMethod 'for\s*\([^\)]*childCount\s*-\s*1[^\)]*>=\s*0[^\)]*--' 'Auction refresh must walk every existing ChooseController item row from the end before rebuilding the list.'
Require-ScopeText $clearChooseItemsMethod 'SetActive(false)' 'Old auction exhibit rows must be hidden synchronously before Unity delayed destruction.'
Require-ScopePattern $clearChooseItemsMethod 'SetParent\s*\(\s*null\s*,\s*false\s*\)' 'Old auction exhibit rows must be detached synchronously so ShowAuctionItem sees an empty targetGrid in the same frame.'
Require-ScopeText $clearChooseItemsMethod 'UnityEngine.Object.Destroy(' 'Detached auction exhibit rows must still be destroyed after they are removed from the visible targetGrid.'

$auctionUiMethods = $refreshMethod + $reopenMethod + $findChooseItemsMethod + $clearChooseItemsMethod

if ($auctionUiMethods.IndexOf('.itemList', [System.StringComparison]::Ordinal) -ge 0) {
    $failures.Add('Auction refresh must not delete ChooseController.itemList children; itemList contains fixed panel structure required by ShowChoosePanel.')
}

if ($auctionUiMethods.IndexOf('plotItemGrid', [System.StringComparison]::Ordinal) -ge 0) {
    $failures.Add('Auction refresh must not treat PlotController.plotItemGrid as the visible exhibit container; runtime evidence shows it remains empty.')
}

if ($source.IndexOf('[DEBUG-auction-hierarchy]', [System.StringComparison]::Ordinal) -ge 0) {
    $failures.Add('Auction refresh source must not retain temporary [DEBUG-auction-hierarchy] instrumentation.')
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host "Auction preview semantic checks passed: $resolvedSourcePath"
