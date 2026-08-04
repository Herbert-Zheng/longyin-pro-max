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
    'if\s*\(\s*\(\s*isAuctionRefresh\s*\|\|\s*isIdentifyAssist\s*\)\s*&&\s*\(\s*eventData\s*==\s*null\s*\|\|\s*eventData\.button\s*!=\s*PointerEventData\.InputButton\.Left\s*\)\s*\)\s*\{?\s*return false\s*;' `
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
