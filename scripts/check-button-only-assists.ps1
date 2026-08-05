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

$clickRouterMethod = Get-CSharpMethodText 'OverlayButtonOnPointerClickPrefix'
$updateAuctionMethod = Get-CSharpMethodText 'UpdateAuctionPreviewRefreshAssist'
$updateIdentifyMethod = Get-CSharpMethodText 'UpdateTreasureIdentifyBestValueAssist'
$ensureAuctionButtonMethod = Get-CSharpMethodText 'EnsureAuctionPreviewRefreshButton'
$resolveAuctionHostMethod = Get-CSharpMethodText 'TryResolveAuctionPreviewExhibitHost'
$resolveAuctionBoundsMethod = Get-CSharpMethodText 'TryResolveAuctionPreviewVisualBounds'
$getAuctionScreenRectMethod = Get-CSharpMethodText 'TryGetAuctionPreviewScreenRect'
$ensureIdentifyButtonMethod = Get-CSharpMethodText 'EnsureIdentifyBestTreasureButton'
$auctionActionMethod = Get-CSharpMethodText 'TryRefreshAuctionPreview'
$identifyActionMethod = Get-CSharpMethodText 'TrySelectHighestValueIdentifyTreasure'

# These are the four legacy shortcut settings owned by the auction/appraisal assists.
# Other game features may continue to use their own shortcuts.
$legacyShortcutSettings = @(
    @{ Identifier = '_auctionPreviewRefreshHotkey'; Section = 'Auction'; Key = 'PreviewRefreshHotkey' },
    @{ Identifier = '_auctionPreviewRefreshRequireAlt'; Section = 'Auction'; Key = 'PreviewRefreshRequireAlt' },
    @{ Identifier = '_treasureIdentifyBestValueHotkey'; Section = 'TreasureIdentify'; Key = 'BestValueHotkey' },
    @{ Identifier = '_treasureIdentifyBestValueRequireAlt'; Section = 'TreasureIdentify'; Key = 'BestValueRequireAlt' }
)

foreach ($setting in $legacyShortcutSettings) {
    Reject-ScopePattern $source "ConfigEntry<[^>]+>\s+$([System.Text.RegularExpressions.Regex]::Escape($setting.Identifier))\b" `
        "The legacy shortcut field $($setting.Identifier) must be removed; this assist is button-only."
    Reject-ScopePattern $source "Config\.Bind\s*\(\s*`"$([System.Text.RegularExpressions.Regex]::Escape($setting.Section))`"\s*,\s*`"$([System.Text.RegularExpressions.Regex]::Escape($setting.Key))`"" `
        "The legacy [$($setting.Section)] $($setting.Key) Config.Bind must be removed; Electron exposes only the enabled toggle."
}

foreach ($updateMethod in @(
    @{ Scope = $updateAuctionMethod; Name = 'auction preview refresh' },
    @{ Scope = $updateIdentifyMethod; Name = 'treasure appraisal selection' }
)) {
    Reject-ScopeText $updateMethod.Scope 'IsConfiguredHotkeyPressed' `
        "The $($updateMethod.Name) update loop must not poll IsConfiguredHotkeyPressed."
    Reject-ScopePattern $updateMethod.Scope '\bInput\s*\.' `
        "The $($updateMethod.Name) update loop must not poll Unity Input; only its visible UI button may trigger the action."
    Reject-ScopePattern $updateMethod.Scope '["'']hotkey["'']' `
        "The $($updateMethod.Name) update loop must not retain a hotkey dispatch path."
}

Require-ScopeText $ensureAuctionButtonMethod '免费刷新展品' `
    'The auction assist button must retain the plain action label 免费刷新展品.'
Require-ScopePattern $ensureAuctionButtonMethod `
    '_auctionPreviewRefreshButtonHost\.gameObject\.activeInHierarchy[\s\S]*?_auctionPreviewRefreshButtonRoot\.transform\.parent\s*==\s*_auctionPreviewRefreshButtonHost\.transform[\s\S]*?return\s*;[\s\S]*?TryResolveAuctionPreviewExhibitHost\s*\(\s*controller\s*,\s*out var exhibitHost\s*\)' `
    'A valid cached auction button and host must return before the expensive live-host resolver runs.'
Require-ScopePattern $ensureAuctionButtonMethod `
    'TryResolveAuctionPreviewExhibitHost\s*\(\s*controller\s*,\s*out var exhibitHost\s*\)' `
    'The auction refresh button must resolve the live exhibit host instead of using a fixed plot-panel position.'
Require-ScopePattern $ensureAuctionButtonMethod `
    'TryResolveAuctionPreviewVisualBounds\s*\([\s\S]*?out var visualBounds[\s\S]*?out var buttonAnchoredPosition[\s\S]*?SetOverlayObjectActive\(_auctionPreviewRefreshButtonRoot, false\)[\s\S]*?return\s*;' `
    'The auction refresh button must hide safely when reliable visible exhibit bounds cannot be resolved.'
Require-ScopePattern $ensureAuctionButtonMethod `
    '_auctionPreviewRefreshButtonRoot\.transform\.parent\s*!=\s*exhibitHost\.transform[\s\S]*?Destroy\(_auctionPreviewRefreshButtonRoot\)' `
    'A cached auction refresh button must be rebuilt when its parent no longer matches the live exhibit host.'
Require-ScopePattern $ensureAuctionButtonMethod `
    'var\s+buttonParent\s*=\s*exhibitHost\.transform\s*;' `
    'The auction refresh button must be parented to the resolved exhibit host.'
Reject-ScopeText $ensureAuctionButtonMethod 'rootCanvas' `
    'The auction refresh button must not be parented to the root canvas, which renders it above transient item descriptions.'
Reject-ScopeText $ensureAuctionButtonMethod 'plotItemGrid' `
    'The auction refresh button must not depend on PlotController.plotItemGrid, which is empty at runtime.'
Reject-ScopePattern $ensureAuctionButtonMethod `
    'new\s+Vector2\s*\(\s*0\.5f\s*,\s*0\.31f\s*\)' `
    'The auction refresh button must not use the obsolete fixed 31% plot-panel anchor.'
Require-ScopePattern $ensureAuctionButtonMethod `
    'new\s+Vector2\s*\(\s*0\.5f\s*,\s*0f\s*\)[\s\S]*?buttonAnchoredPosition' `
    'The auction refresh button must use the visual-bounds-derived position with a bottom-center host anchor.'
Require-ScopePattern $resolveAuctionHostMethod `
    'var\s+marker\s*=\s*_auctionPreviewVisibilityMarker[\s\S]*?for\s*\(\s*var candidate\s*=\s*marker\.transform[\s\S]*?candidate\s*=\s*candidate\.parent\s*\)' `
    'Exhibit host resolution must ascend from the confirmed active auction marker to select the smallest qualifying ancestor.'
Require-ScopePattern $resolveAuctionHostMethod `
    'candidate\s*==\s*plotPanel\.transform\s*\|\|\s*candidate\s*==\s*rootCanvas\?\.transform' `
    'Exhibit host resolution must reject both plotPanel and the root canvas.'
Require-ScopePattern $resolveAuctionHostMethod `
    'openAllCount\s*<\s*2\s*\|\|\s*closeAllCount\s*<\s*2[\s\S]*?GetComponentsInChildren<ItemIconController>[\s\S]*?activeInHierarchy' `
    'Exhibit host resolution must require two active 全开 markers, two active 全关 markers, and an active item icon.'
Require-ScopePattern $resolveAuctionBoundsMethod `
    'GetComponentsInChildren<ItemIconController>[\s\S]*?WorldToScreenPoint[\s\S]*?visualSearchRoot\s*=\s*exhibitHost\.parent\?\.GetComponent<RectTransform>\(\)\s*\?\?\s*exhibitHost[\s\S]*?visualSearchRoot\.GetComponentsInChildren<RectTransform>[\s\S]*?GetComponent<Graphic>[\s\S]*?GetComponent<Text>[\s\S]*?GetComponent<Button>' `
    'Visual bounds resolution must search the parent visual panel around the structural icon host and exclude text/button/non-graphic rectangles.'
Require-ScopePattern $resolveAuctionBoundsMethod `
    'isTrustedChoosePanel\s*=\s*candidate\s*==\s*visualSearchRoot[\s\S]*?candidate\.name\s*,\s*"ChoosePanel"[\s\S]*?graphic\s*=\s*candidate\.GetComponent<Graphic>\(\)[\s\S]*?\(!isTrustedChoosePanel\s*&&\s*graphic\s*==\s*null\)' `
    'Only the structurally verified direct ChoosePanel parent may supply bounds without a Graphic component.'
Require-ScopePattern $resolveAuctionBoundsMethod `
    'candidateBounds\.width\s*<\s*210f\s*\|\|\s*candidateBounds\.height\s*<\s*100f[\s\S]*?containsAllIcons[\s\S]*?area\s*>=\s*bestArea' `
    'Visual bounds resolution must reject small rectangles, contain every active item icon, and choose the smallest qualifying frame.'
Require-ScopePattern $resolveAuctionBoundsMethod `
    'visualBounds\.yMin\s*\+\s*42f[\s\S]*?ScreenPointToLocalPointInRectangle[\s\S]*?buttonAnchoredPosition\s*=\s*targetLocalPoint' `
    'The button target must be 42 screen pixels inside the visual frame bottom and converted into host-local anchored coordinates.'
Require-ScopePattern $getAuctionScreenRectMethod `
    'rectTransform\.rect[\s\S]*?TransformPoint\s*\([\s\S]*?WorldToScreenPoint[\s\S]*?new\s+Rect\s*\(' `
    'Candidate visual rectangles must transform their corners individually before comparing screen-space bounds.'
Reject-ScopeText $getAuctionScreenRectMethod 'GetWorldCorners' `
    'IL2CPP does not reliably populate a managed Vector3 array passed to RectTransform.GetWorldCorners.'
Require-ScopeText $ensureIdentifyButtonMethod '自动选择最高估价' `
    'The appraisal assist button must use the plain action label 自动选择最高估价.'
foreach ($buttonMethod in @(
    @{ Scope = $ensureAuctionButtonMethod; Name = 'auction refresh' },
    @{ Scope = $ensureIdentifyButtonMethod; Name = 'appraisal selection' }
)) {
    Reject-ScopeText $buttonMethod.Scope 'FormatConfiguredHotkey' `
        "The $($buttonMethod.Name) button label must not append a configured shortcut."
    Reject-ScopePattern $buttonMethod.Scope 'Alt\s*\+' `
        "The $($buttonMethod.Name) button label must not display an Alt shortcut hint."
    Reject-ScopePattern $buttonMethod.Scope '(?i)hotkey|快捷键' `
        "The $($buttonMethod.Name) button construction must not contain shortcut wording."
}

Require-ScopePattern $clickRouterMethod `
    'isAuctionRefresh\s*=\s*string\.Equals\(\s*buttonName\s*,\s*AuctionPreviewRefreshButtonName\s*,\s*StringComparison\.Ordinal\s*\)' `
    'The shared click router must recognize the auction action by its exact overlay button name.'
Require-ScopePattern $clickRouterMethod `
    'isIdentifyAssist\s*=\s*string\.Equals\(\s*buttonName\s*,\s*IdentifyBestTreasureButtonName\s*,\s*StringComparison\.Ordinal\s*\)' `
    'The shared click router must recognize the appraisal action by its exact overlay button name.'

# Null PointerEventData used to be accepted as a left click. Require a guard scoped to
# these two assists so unrelated overlay-button behavior is deliberately left untouched.
Require-ScopePattern $clickRouterMethod `
    'if\s*\(\s*\(\s*isAuctionRefresh\s*\|\|\s*isIdentifyAssist(?:\s*\|\|\s*[A-Za-z_][A-Za-z0-9_]*)*\s*\)\s*&&\s*\(\s*eventData\s*==\s*null\s*\|\|\s*eventData\.button\s*!=\s*PointerEventData\.InputButton\.Left\s*\)\s*\)\s*\{?\s*return false\s*;' `
    'Auction and appraisal buttons must reject null PointerEventData, right clicks, and middle clicks before dispatch.'
Reject-ScopePattern $clickRouterMethod `
    'eventData\s*==\s*null\s*\|\|\s*eventData\.button\s*==\s*PointerEventData\.InputButton\.Left' `
    'Null PointerEventData must no longer be treated as a successful left click.'

Require-ScopePattern $clickRouterMethod `
    'if\s*\(\s*isAuctionRefresh\s*\)[\s\S]*?_auctionPreviewRefreshEnabled\.Value[\s\S]*?TryRefreshAuctionPreview\s*\(\s*"button"\s*\)' `
    'The auction button route must check PreviewRefreshEnabled before dispatching its exact button action.'
Require-ScopePattern $clickRouterMethod `
    'if\s*\(\s*isIdentifyAssist\s*\)[\s\S]*?_treasureIdentifyBestValueAssistEnabled\.Value[\s\S]*?TrySelectHighestValueIdentifyTreasure\s*\([^;]*"button"\s*\)' `
    'The appraisal button route must check BestValueAssistEnabled before dispatching its exact button action.'

Require-ScopePattern $auctionActionMethod `
    '_auctionPreviewRefreshBusy\s*\|\|[\s\S]*?!_auctionPreviewRefreshEnabled\.Value[\s\S]*?requireVisible\s*&&\s*!IsAuctionPreviewVisible\(\)' `
    'The auction action must retain busy, enabled, and visible-context gates internally.'
Require-ScopePattern $identifyActionMethod `
    '!_treasureIdentifyBestValueAssistEnabled\.Value[\s\S]*?controller\?\.identifyMatchUIPanel\s*==\s*null[\s\S]*?!IsIdentifyMatchVisible\(\)' `
    'The appraisal action must retain enabled and visible appraisal-context gates internally.'

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ -ErrorAction Continue }
    exit 1
}

Write-Host "Button-only auction/appraisal semantic checks passed: $resolvedSourcePath"
