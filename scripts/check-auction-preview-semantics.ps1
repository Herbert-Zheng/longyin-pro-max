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
$reopenMethod = Get-CSharpMethodText 'ReopenAuctionPreview'
$clearGridMethod = Get-CSharpMethodText 'ClearAuctionPreviewItemGridImmediately'

Require-ScopeText $regenerateMethod 'var regeneratedItems = new ItemListData();' 'Auction refresh must generate into a fresh item collection instead of appending to the current event list.'
Require-ScopeText $regenerateMethod 'eventData.eventItemList = regeneratedItems;' 'Auction refresh must replace the event item list with the freshly generated collection.'
Require-ScopeText $regenerateMethod 'controller.tempPlotShop = regeneratedItems;' 'Auction refresh must replace the preview backing list with the freshly generated collection.'
Require-ScopePattern `
    $reopenMethod `
    'nameof\(PlotController\.HidePlotItem\)[\s\S]*?\.Invoke\(controller,[\s\S]*?nameof\(PlotController\.ClearPlotItem\)[\s\S]*?\.Invoke\(controller,[\s\S]*?ClearAuctionPreviewItemGridImmediately\(controller\)[\s\S]*?nameof\(PlotController\.ShowAuctionItem\)[\s\S]*?\.Invoke\(controller,' `
    'Every refresh must synchronously detach the visible plotItemGrid rows after the original cleanup and before ShowAuctionItem; delayed Destroy calls otherwise let the new rows append for the current frame.'
Require-ScopeText $clearGridMethod 'controller.plotItemGrid' 'Auction refresh must clear the runtime-confirmed PlotController.plotItemGrid exhibit container.'
Require-ScopePattern $clearGridMethod 'for\s*\([^\)]*childCount\s*-\s*1[^\)]*>=\s*0[^\)]*--' 'Auction refresh must walk every existing plotItemGrid row from the end before rebuilding the list.'
Require-ScopeText $clearGridMethod 'SetActive(false)' 'Old auction exhibit rows must be hidden synchronously before Unity delayed destruction.'
Require-ScopePattern $clearGridMethod 'SetParent\s*\(\s*null\s*,\s*false\s*\)' 'Old auction exhibit rows must be detached synchronously so ShowAuctionItem sees an empty grid in the same frame.'
Require-ScopeText $clearGridMethod 'UnityEngine.Object.Destroy(' 'Detached auction exhibit rows must still be destroyed after they are removed from the visible grid.'

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host "Auction preview semantic checks passed: $resolvedSourcePath"
