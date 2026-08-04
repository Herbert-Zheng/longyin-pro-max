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
$updateMethod = Get-CSharpMethodText 'UpdateBreakthroughRerollAssist'
$actionMethod = Get-CSharpMethodText 'TryRerollBreakthroughChoices'
$clearMethod = Get-CSharpMethodText 'ClearBreakthroughChoicesImmediately'
$readyPostfix = Get-CSharpMethodText 'BreakthroughStartShowBreakChoicePostfix'
$choicePrefix = Get-CSharpMethodText 'BreakthroughChoiceOnClickPrefix'
$itemChoosePrefix = Get-CSharpMethodText 'BreakthroughItemChoosePrefix'
$resetMethod = Get-CSharpMethodText 'ResetBreakthroughRerollState'
$disableMethod = Get-CSharpMethodText 'DisableBreakthroughReroll'
$loadRecentPrefix = Get-CSharpMethodText 'LoadRecentGamePrefix'
$loadGamePrefix = Get-CSharpMethodText 'LoadGamePrefix'
$loadAllPostfix = Get-CSharpMethodText 'LoadAllGameDataPostfix'
$findTemplateMethod = Get-CSharpMethodText 'FindUiButtonTemplate'
$overlayRootMethod = Get-CSharpMethodText 'IsButtonInsideKnownOverlayRoot'
$ensureButtonMethod = Get-CSharpMethodText 'EnsureBreakthroughRerollButton'
$safeButtonMethod = Get-CSharpMethodText 'TryCreateSafeStyledButton'
$hooksReadyAssignmentMatch = [System.Text.RegularExpressions.Regex]::Match(
    $source,
    '_breakthroughRerollHooksReady\s*=\s*[^;]+;',
    [System.Text.RegularExpressions.RegexOptions]::Singleline)
$hooksReadyAssignment = if ($hooksReadyAssignmentMatch.Success) { $hooksReadyAssignmentMatch.Value } else { '' }

# Configuration is a single boolean bridge from Electron. This phase deliberately
# has no keyboard surface, and this regression contract locks the requested default.
Require-ScopePattern $source `
    'ConfigEntry<bool>\s+_breakthroughRerollEnabled\b' `
    'Breakthrough reroll must have a boolean _breakthroughRerollEnabled configuration field.'
Require-ScopePattern $source `
    'Config\.Bind\s*\(\s*"Breakthrough"\s*,\s*"RerollEnabled"\s*,\s*true\s*,' `
    '[Breakthrough] RerollEnabled must be bound with default true.'
Reject-ScopePattern $source `
    '(?i)(?:breakthrough|breakThrough)[A-Za-z0-9_]*(?:hotkey|requireAlt)|(?:hotkey|requireAlt)[A-Za-z0-9_]*(?:breakthrough|breakThrough)' `
    'Breakthrough reroll must not define or reference any hotkey or RequireAlt field.'
Reject-ScopePattern $source `
    'Config\.Bind\s*\(\s*"Breakthrough"\s*,\s*"[^"]*(?:Hotkey|RequireAlt)[^"]*"' `
    'The [Breakthrough] section must not bind a hotkey or RequireAlt setting.'
Reject-ScopePattern ($updateMethod + $actionMethod) `
    '\bInput\s*\.|GetKeyDown|IsConfiguredHotkeyPressed' `
    'Breakthrough reroll update/action code must not poll Unity input or a configured hotkey.'

# All required runtime hooks must be probed, and the combined result must control a
# degraded-mode availability gate rather than risking a partially patched feature.
Require-ScopePattern $source `
    'PatchMethod\s*\(\s*typeof\(BreakThroughController\)\s*,\s*nameof\(BreakThroughController\.StartShowBreakChoice\)\s*,\s*Type\.EmptyTypes\s*,\s*null\s*,\s*nameof\(BreakthroughStartShowBreakChoicePostfix\)\s*\)' `
    'StartShowBreakChoice must register BreakthroughStartShowBreakChoicePostfix as a postfix.'
Require-ScopePattern $source `
    'PatchMethod\s*\(\s*typeof\(BreakThroughChoiceController\)\s*,\s*nameof\(BreakThroughChoiceController\.OnClick\)\s*,\s*Type\.EmptyTypes\s*,\s*nameof\(BreakthroughChoiceOnClickPrefix\)\s*,\s*null\s*\)' `
    'BreakThroughChoiceController.OnClick must clear reroll state from a prefix.'
foreach ($methodName in @('BreakBookChoose', 'BreakFoodChoose', 'BreakMedChoose')) {
    $escapedMethodName = [System.Text.RegularExpressions.Regex]::Escape($methodName)
    Require-ScopePattern $source `
        "PatchMethod\s*\(\s*typeof\(BreakThroughController\)\s*,\s*nameof\(BreakThroughController\.$escapedMethodName\)\s*,\s*Type\.EmptyTypes\s*,\s*nameof\(BreakthroughItemChoosePrefix\)\s*,\s*null\s*\)" `
        "BreakThroughController.$methodName must clear reroll state from a prefix."
}
Require-ScopePattern $source `
    '_breakthroughRerollHooksReady\s*=\s*[^;]*(?:&&|&)\s*[^;]*;' `
    'Breakthrough reroll must combine its required patch results into _breakthroughRerollHooksReady.'
foreach ($requiredPatchResult in @(
    'breakthroughChoiceShowPatched',
    'breakthroughChoiceClickPatched',
    'breakthroughBookChoosePatched',
    'breakthroughFoodChoosePatched',
    'breakthroughMedChoosePatched',
    'breakthroughStartPatched',
    'breakthroughConfirmPatched',
    'breakthroughHidePatched',
    'overlayButtonPointerPatched',
    'gameControllerUpdatePatched',
    'loadRecentGamePatched',
    'loadGamePatched',
    'loadAllGameDataPatched'
)) {
    Require-ScopeText $hooksReadyAssignment $requiredPatchResult `
        "Breakthrough reroll availability must include required patch result: $requiredPatchResult"
}
Require-ScopePattern $disableMethod `
    '_breakthroughRerollHooksReady\s*=\s*false[\s\S]*?ResetBreakthroughRerollState\s*\(' `
    'Degraded-mode handling must mark hooks unavailable and reset/hide all breakthrough reroll state.'
Require-ScopePattern $source `
    'if\s*\(\s*!_breakthroughRerollHooksReady\s*\)[\s\S]*?DisableBreakthroughReroll\s*\(' `
    'Missing required hooks must enter safe degraded mode instead of leaving a partially active feature.'

# The postfix owns readiness; every path that consumes or invalidates the current
# choice session must synchronously clear it.
Require-ScopePattern $readyPostfix `
    '_breakthroughRerollReady\s*=\s*true[\s\S]*?_breakthroughRerollBusy\s*=\s*false' `
    'StartShowBreakChoice postfix must mark the completed candidate set ready and release busy.'
Require-ScopePattern $readyPostfix `
    'visibleChoiceCount\s*!=\s*totalChoiceCount[\s\S]*?DisableBreakthroughReroll\s*\(' `
    'StartShowBreakChoice postfix must fail closed when any generated candidate is not visible.'
Require-ScopePattern $readyPostfix `
    'visibleChoiceCount\s*!=\s*_breakthroughRerollExpectedChoiceCount[\s\S]*?totalChoiceCount\s*!=\s*_breakthroughRerollExpectedChoiceCount[\s\S]*?DisableBreakthroughReroll\s*\(' `
    'A rerolled candidate set must match the original visible and total candidate count before becoming ready.'
Require-ScopeText $choicePrefix 'ResetBreakthroughRerollState(' `
    'Choosing a breakthrough option must reset ready/busy/pending/button state before OnClick runs.'
Require-ScopeText $itemChoosePrefix 'ResetBreakthroughRerollState(' `
    'Entering book, food, or medicine selection must reset breakthrough reroll state.'
Require-ScopePattern $updateMethod `
    'breakThroughPanel[\s\S]*?(?:activeInHierarchy|activeSelf)[\s\S]*?ResetBreakthroughRerollState\s*\(' `
    'The update loop must reset state when the breakthrough panel closes or its controller becomes invalid.'
foreach ($loadMethod in @(
    @{ Scope = $loadRecentPrefix; Name = 'LoadRecentGamePrefix' },
    @{ Scope = $loadGamePrefix; Name = 'LoadGamePrefix' },
    @{ Scope = $loadAllPostfix; Name = 'LoadAllGameDataPostfix' }
)) {
    Require-ScopeText $loadMethod.Scope 'ResetBreakthroughRerollState(' `
        "$($loadMethod.Name) must reset breakthrough reroll state while loading a save."
}
Require-ScopePattern $resetMethod `
    '_breakthroughRerollReady\s*=\s*false[\s\S]*?_breakthroughRerollBusy\s*=\s*false[\s\S]*?_breakthroughRerollPendingFrame\s*=\s*-1[\s\S]*?Destroy\s*\(\s*_breakthroughRerollButtonRoot\s*\)[\s\S]*?_breakthroughRerollButtonRoot\s*=\s*null' `
    'ResetBreakthroughRerollState must clear ready, busy, pending frame, and the button root.'

# A non-empty constant name is the sole action route. Synthetic/null and non-left
# pointer events are rejected before dispatch, and the action retains its own gates.
Require-ScopePattern $source `
    'private const string BreakthroughRerollButtonName\s*=\s*"[^"]+"\s*;' `
    'Breakthrough reroll must use one non-empty constant button name.'
Require-ScopePattern $clickRouterMethod `
    'isBreakthroughReroll\s*=\s*string\.Equals\(\s*buttonName\s*,\s*BreakthroughRerollButtonName\s*,\s*StringComparison\.Ordinal\s*\)' `
    'OverlayButtonOnPointerClickPrefix must recognize breakthrough reroll by its exact button name.'
Require-ScopePattern $clickRouterMethod `
    'isBreakthroughReroll\s*=\s*string\.Equals\([^;]+&&\s*__instance\s*==\s*_breakthroughRerollButton\s*;' `
    'Breakthrough reroll routing must also require the exact saved Button instance.'
Require-ScopePattern $clickRouterMethod `
    'isBreakthroughReroll[\s\S]*?eventData\s*==\s*null[\s\S]*?eventData\.button\s*!=\s*PointerEventData\.InputButton\.Left[\s\S]*?return false\s*;' `
    'Breakthrough reroll must reject null, right, and middle pointer events.'
Require-ScopePattern $clickRouterMethod `
    'if\s*\(\s*isBreakthroughReroll\s*\)[\s\S]*?_breakthroughRerollEnabled\.Value[\s\S]*?TryRerollBreakthroughChoices\s*\(\s*\)' `
    'The exact left-click route must check enabled before dispatching breakthrough reroll.'
$actionReferenceCount = [System.Text.RegularExpressions.Regex]::Matches(
    $source,
    '\bTryRerollBreakthroughChoices\s*\(').Count
if ($actionReferenceCount -ne 2) {
    $failures.Add("TryRerollBreakthroughChoices must appear exactly twice (definition plus sole button-router call); found $actionReferenceCount references.")
}
Require-ScopePattern $updateMethod `
    '_breakthroughRerollEnabled\.Value[\s\S]*?_breakthroughRerollHooksReady[\s\S]*?_breakthroughRerollReady[\s\S]*?_breakthroughRerollBusy[\s\S]*?breakThroughPanel' `
    'Button visibility must be gated by enabled, hook availability, ready, not-busy, and visible breakthrough context.'
Require-ScopePattern $actionMethod `
    '!_breakthroughRerollEnabled\.Value[\s\S]*?!_breakthroughRerollHooksReady[\s\S]*?_breakthroughRerollBusy[\s\S]*?!_breakthroughRerollReady[\s\S]*?breakThroughPanel' `
    'The action must independently gate enabled, hook availability, busy, ready, and visible breakthrough context.'
Require-ScopePattern $actionMethod `
    '_breakthroughRerollBusy\s*=\s*true[\s\S]*?interactable\s*=\s*false' `
    'A valid click must enter busy and disable the reroll button immediately.'

# Unity destroys objects at end-of-frame. Old rows therefore have to disappear from
# layout synchronously, while the original generator is deferred to a later frame.
Require-ScopePattern $actionMethod `
    'ClearBreakthroughChoicesImmediately\s*\([\s\S]*?_breakthroughRerollPendingFrame\s*=\s*Time\.frameCount\s*\+\s*1' `
    'Reroll must hide/detach old choices first and schedule regeneration for the next frame.'
Require-ScopeText $clearMethod 'BreakThroughChoiceController' `
    'Immediate cleanup must target the old BreakThroughChoiceController objects.'
Require-ScopePattern $clearMethod `
    'SetActive\s*\(\s*false\s*\)[\s\S]*?SetParent\s*\(\s*null\s*,\s*false\s*\)[\s\S]*?UnityEngine\.Object\.Destroy\s*\(' `
    'Old breakthrough choices must be hidden, detached from layout, then destroyed in that order.'
Require-ScopePattern $updateMethod `
    '_breakthroughRerollPendingFrame\s*>=\s*0[\s\S]*?Time\.frameCount\s*<\s*_breakthroughRerollPendingFrame[\s\S]*?StartShowBreakChoice\s*\(\s*\)' `
    'The update loop must wait until the scheduled next frame before calling StartShowBreakChoice.'

$rerollImplementation = $actionMethod + $clearMethod + $updateMethod
foreach ($forbiddenCall in @(
    'StartBreakThrough',
    'RealStartBreakThrough',
    'BreakBookChoose',
    'BreakFoodChoose',
    'BreakMedChoose',
    'ChangeMoney',
    'ChangeDay',
    'ChangeMonth',
    'ChangeYear',
    'ChangeHour',
    'UseItem',
    'RemoveItem',
    'LoseItem',
    'CostItem',
    'ConsumeItem'
)) {
    Reject-ScopePattern $rerollImplementation "\b$forbiddenCall\s*\(" `
        "Breakthrough reroll implementation must not call side-effect/confirmation method $forbiddenCall."
}
$startShowCallCount = [System.Text.RegularExpressions.Regex]::Matches(
    $rerollImplementation,
    '\.StartShowBreakChoice\s*\(').Count
if ($startShowCallCount -ne 1) {
    $failures.Add("Breakthrough reroll must call only StartShowBreakChoice once from its deferred path; found $startShowCallCount calls.")
}

# The overlay must never clone itself, and exceptions must fail closed rather than
# leaving a clickable or half-ready control behind.
Require-ScopeText $findTemplateMethod 'BreakthroughRerollButtonName' `
    'FindUiButtonTemplate must exclude the breakthrough reroll button from template candidates.'
Require-ScopeText $overlayRootMethod '_breakthroughRerollButtonRoot' `
    'IsButtonInsideKnownOverlayRoot must recognize the breakthrough reroll overlay root.'
Require-ScopeText $ensureButtonMethod 'TryCreateSafeStyledButton(' `
    'Breakthrough reroll must create its UI through the safe visual-only button helper.'
Reject-ScopeText $ensureButtonMethod 'TryCreateButtonTemplateButton(' `
    'Breakthrough reroll must not clone a native button GameObject with inherited behavior scripts.'
Require-ScopePattern $safeButtonMethod `
    'new\s+GameObject\s*\(' `
    'The safe reroll button helper must construct a new GameObject rather than clone a native control.'
Reject-ScopePattern $safeButtonMethod `
    '(?:UnityEngine\.)?Object\.Instantiate\s*\(' `
    'The safe reroll button helper must not Instantiate any native template GameObject.'
Reject-ScopePattern $safeButtonMethod `
    '\bas\s+Image\b|\.(?:Try)?Cast<Image>\s*\(' `
    'The safe reroll button helper must avoid IL2CPP Graphic-to-Image runtime casts; copy only shared Graphic properties.'
Require-ScopePattern $clearMethod `
    'GetComponentsInChildren<BreakThroughChoiceController>\s*\(\s*(?:includeInactive\s*:\s*)?true\s*\)' `
    'Breakthrough cleanup must include inactive candidates so stale rows cannot survive a reroll.'
foreach ($exceptionBoundary in @(
    @{ Scope = $actionMethod; Name = 'reroll action' },
    @{ Scope = $updateMethod; Name = 'reroll update loop' }
)) {
    Require-ScopePattern $exceptionBoundary.Scope `
        'catch\s*\([^\)]*Exception[^\)]*\)[\s\S]*?DisableBreakthroughReroll\s*\(' `
        "Unexpected exceptions in the $($exceptionBoundary.Name) must safely disable and hide the breakthrough feature."
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ -ErrorAction Continue }
    exit 1
}

Write-Host "Breakthrough reroll semantic checks passed: $resolvedSourcePath"
