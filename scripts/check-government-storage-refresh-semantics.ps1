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

$activeMethod = Get-CSharpMethodText 'TryGetActiveGovernmentStorageTradeUi'
$updateMethod = Get-CSharpMethodText 'UpdateGovernmentStorageRefreshAssist'
$refreshMethod = Get-CSharpMethodText 'TryRefreshGovernmentStorage'
$ensureButtonMethod = Get-CSharpMethodText 'EnsureGovernmentStorageRefreshButton'
$resolveButtonLayoutMethod = Get-CSharpMethodText 'TryResolveGovernmentStorageRefreshButtonLayout'
$clickMethod = Get-CSharpMethodText 'OverlayButtonOnPointerClickPrefix'
$gameUpdateMethod = Get-CSharpMethodText 'GameControllerUpdatePostfix'

Require-Pattern $source 'ConfigEntry<bool>\s+_governmentStorageRefreshEnabled\b' 'Government storage refresh must expose an enabled switch.'
Require-Pattern $source 'ConfigEntry<KeyCode>\s+_governmentStorageRefreshHotkey\b' 'Government storage refresh must expose a configurable KeyCode.'
Require-Pattern $source 'bool\s+_governmentStorageRefreshHooksReady\b' 'Government storage refresh must keep runtime compatibility state separate from the persisted user setting.'
Require-Pattern $source 'Config\.Bind\s*\(\s*"GovernmentStorage"\s*,\s*"RefreshEnabled"\s*,\s*true\b' 'Government storage refresh must be enabled by default.'
Require-Pattern $source 'Config\.Bind\s*\(\s*"GovernmentStorage"\s*,\s*"RefreshHotkey"\s*,\s*KeyCode\.R\b' 'Government storage refresh must default to R.'

Require-Pattern $activeMethod 'tradeUI\s*==\s*null[\s\S]*?!candidate\.tradeUI\.activeInHierarchy[\s\S]*?candidate\.tradeUIType\s*!=\s*TradeUIType\.GovernStorage' 'The active-page resolver must require a visible GovernStorage TradeUI.'
Require-Pattern $activeMethod 'catch\s*\(Exception ex\)[\s\S]*?!_governmentStorageActiveLookupFailureLogged[\s\S]*?DescribeCompatibilityException\(ex\)' 'Government storage page-detection exceptions must be logged once instead of being swallowed or emitted every frame.'
Require-Pattern $updateMethod '!_governmentStorageRefreshHooksReady[\s\S]*?!_governmentStorageRefreshEnabled\.Value[\s\S]*?!TryGetActiveGovernmentStorageTradeUi\(out var tradeUi\)[\s\S]*?Input\.GetKeyDown\(_governmentStorageRefreshHotkey\.Value\)[\s\S]*?TryRefreshGovernmentStorage\("hotkey"\)' 'The configurable hotkey must dispatch only while compatible, enabled, and on the government storage page.'
Require-Pattern $clickMethod 'isGovernmentStorageRefresh[\s\S]*?_governmentStorageRefreshEnabled\.Value[\s\S]*?TryRefreshGovernmentStorage\("button"\)' 'The government storage button must be gated by the feature switch and dispatch the same refresh action.'
Require-Pattern $gameUpdateMethod 'UpdateGovernmentStorageRefreshAssist\(\);' 'GameController.Update must poll the government storage assist.'

Require-Pattern $ensureButtonMethod 'TryResolveGovernmentStorageRefreshButtonLayout\(\s*tradeUi,\s*out var expectedParent,\s*out var buttonAnchor,\s*out var buttonAnchoredPosition\s*\)' 'Government storage refresh must resolve its layout from the visible storage list instead of the player contribution label.'
Require-Pattern $ensureButtonMethod 'buttonAnchor,\s*buttonAnchor,\s*new Vector2\(0\.5f, 0\.5f\),\s*buttonAnchoredPosition' 'Government storage refresh must use a centered pivot at the resolved bottom-center position.'
Reject-Pattern $ensureButtonMethod 'leftResourceLabel' 'Government storage refresh must not anchor to the player contribution label because that overlaps the player item grid.'
Reject-Pattern $ensureButtonMethod 'new Vector2\(18f, 58f\)' 'The legacy left-side button offset must not return.'
Require-Pattern $resolveButtonLayoutMethod 'tradeUi\.rightList[\s\S]*?TryGetAuctionPreviewScreenRect\(storageListRect, camera, out var storageBounds\)[\s\S]*?storageBounds\.center\.x[\s\S]*?storageBounds\.yMin\s*-\s*32f' 'Government storage refresh must sit centered 32 pixels below the government item list.'
Require-Pattern $resolveButtonLayoutMethod 'ScreenPointToLocalPointInRectangle\(\s*parentRect,\s*targetScreenPoint,\s*camera,\s*out var targetLocalPoint\s*\)' 'Government storage refresh must convert the list bottom-center screen point into its parent layout space.'

Require-Pattern $refreshMethod '_governmentStorageRefreshBusy[\s\S]*?!_governmentStorageRefreshHooksReady[\s\S]*?!_governmentStorageRefreshEnabled\.Value[\s\S]*?!TryGetActiveGovernmentStorageTradeUi\(out var tradeUi\)' 'The refresh action must retain busy, compatibility, enabled, and active-page gates internally.'
Require-Pattern $refreshMethod 'try\s*\{[\s\S]*?var storageBefore\s*=\s*worldData\.governStorage[\s\S]*?storageSnapshot\s*=\s*storageBefore\?\.Clone\(\)\s+as\s+ItemListData[\s\S]*?itemsBefore\s*=\s*DescribeGovernmentStorageItems\(storageBefore\)' 'Reading, cloning, and describing the current storage must all be protected by the refresh try/finally.'
Require-Pattern $refreshMethod 'gameController\.RefreshGovernStorage\(\)[\s\S]*?tradeUi\.HideTradeUI\(\)[\s\S]*?plotController\.ShowGovernStorage\(\)' 'A successful refresh must invoke the original generator and rebuild TradeUI to avoid accumulated list entries.'
Require-Pattern $refreshMethod 'catch\s*\(Exception ex\)[\s\S]*?worldData\.governStorage\s*=\s*storageSnapshot[\s\S]*?tradeUi\.HideTradeUI\(\)[\s\S]*?plotController\.ShowGovernStorage\(\)' 'A failed refresh must restore the snapshot and reopen the government storage UI.'
Require-Pattern $refreshMethod 'finally[\s\S]*?_governmentStorageRefreshBusy\s*=\s*false' 'The refresh busy flag must always be cleared.'

# The mod must not charge government contribution. Calling the vanilla storage generator
# is allowed; explicit contribution/currency mutation in this action is not.
Reject-Pattern $refreshMethod '(?i)(govern(?:ment)?(?:Contribution|Merit|Score)|contribution|功绩)\s*(?:\+\+|--|[+\-*/]?=)' 'The mod refresh action must not mutate government contribution.'
Reject-Pattern $refreshMethod '(?i)(Spend|Consume|Deduct|Remove).{0,24}(Govern|Contribution|Merit|功绩)' 'The mod refresh action must not call a contribution-spending helper.'
Require-Pattern $refreshMethod 'no contribution was spent by the mod' 'The success log must explicitly document the no-contribution contract.'
Reject-Pattern $source 'if\s*\(!_governmentStorageRefreshHooksReady\)[\s\S]{0,160}_governmentStorageRefreshEnabled\.Value\s*=\s*false' 'A compatibility failure must not overwrite and persist the user-facing enabled setting.'

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ -ErrorAction Continue }
    exit 1
}

Write-Host "Government storage refresh semantic checks passed: $resolvedSourcePath"
