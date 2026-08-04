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
    $methodMatch = [System.Text.RegularExpressions.Regex]::Match(
        $source,
        "(?m)^    private static[^\r\n]*\b$escapedName\s*\(")
    if (-not $methodMatch.Success) {
        $failures.Add("Could not locate C# method: $Name")
        return ''
    }

    $nextMethodRegex = [System.Text.RegularExpressions.Regex]::new(
        '(?m)^    private static[^\r\n]*\b[A-Za-z_][A-Za-z0-9_]*\s*\(')
    $nextMethod = $nextMethodRegex.Match(
        $source,
        $methodMatch.Index + $methodMatch.Length)
    $endIndex = if ($nextMethod.Success) { $nextMethod.Index } else { $source.Length }
    return $source.Substring($methodMatch.Index, $endIndex - $methodMatch.Index)
}

function Get-AssignmentText {
    param([Parameter(Mandatory)][string]$FieldName)

    $escapedName = [System.Text.RegularExpressions.Regex]::Escape($FieldName)
    $match = [System.Text.RegularExpressions.Regex]::Match(
        $source,
        "$escapedName\s*=\s*[^;]+;",
        [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if (-not $match.Success) {
        $failures.Add("Could not locate C# assignment: $FieldName")
        return ''
    }
    return $match.Value
}

function Require-Text {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Scope,
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$FailureMessage
    )
    if ($Scope.IndexOf($Text, [System.StringComparison]::Ordinal) -lt 0) {
        $failures.Add($FailureMessage)
    }
}

function Reject-Text {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Scope,
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$FailureMessage
    )
    if ($Scope.IndexOf($Text, [System.StringComparison]::Ordinal) -ge 0) {
        $failures.Add($FailureMessage)
    }
}

function Require-Pattern {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Scope,
        [Parameter(Mandatory)][string]$Pattern,
        [Parameter(Mandatory)][string]$FailureMessage
    )
    if (-not [System.Text.RegularExpressions.Regex]::IsMatch(
        $Scope,
        $Pattern,
        [System.Text.RegularExpressions.RegexOptions]::Singleline)) {
        $failures.Add($FailureMessage)
    }
}

function Reject-Pattern {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Scope,
        [Parameter(Mandatory)][string]$Pattern,
        [Parameter(Mandatory)][string]$FailureMessage
    )
    if ([System.Text.RegularExpressions.Regex]::IsMatch(
        $Scope,
        $Pattern,
        [System.Text.RegularExpressions.RegexOptions]::Singleline)) {
        $failures.Add($FailureMessage)
    }
}

$clickRouter = Get-CSharpMethodText 'OverlayButtonOnPointerClickPrefix'
$updateMethod = Get-CSharpMethodText 'UpdateCraftRerollAssist'
$updateNormalCraft = Get-CSharpMethodText 'UpdateNormalCraftRerollAssist'
$craftAction = Get-CSharpMethodText 'TryRerollCraftResults'
$enhanceAction = Get-CSharpMethodText 'TryRerollSpeEnhanceChoices'
$captureSession = Get-CSharpMethodText 'CaptureCraftRerollSession'
$fingerprintMethod = Get-CSharpMethodText 'BuildCraftRerollFingerprint'
$resolveTargetHero = Get-CSharpMethodText 'ResolveCraftRerollTargetHero'
$buildResults = Get-CSharpMethodText 'TryBuildCraftRerollResults'
$clearCraftRows = Get-CSharpMethodText 'ClearCraftResultCandidateItemsImmediately'
$ownedCraftResultPanel = Get-CSharpMethodText 'IsOwnedCraftResultPanel'
$craftVisibility = Get-CSharpMethodText 'IsCraftRerollUiVisible'
$craftButtonHost = Get-CSharpMethodText 'ResolveCraftRerollButtonHost'
$ensureCraftButton = Get-CSharpMethodText 'EnsureCraftRerollButton'
$ensureEnhanceButton = Get-CSharpMethodText 'EnsureSpeEnhanceRerollButton'
$safeButtonHelper = Get-CSharpMethodText 'TryCreateSafeStyledButton'
$findTemplate = Get-CSharpMethodText 'FindUiButtonTemplate'
$knownRoot = Get-CSharpMethodText 'IsButtonInsideKnownOverlayRoot'
$resetCraft = Get-CSharpMethodText 'ResetCraftRerollState'
$resetEnhance = Get-CSharpMethodText 'ResetSpeEnhanceRerollState'
$disableCraft = Get-CSharpMethodText 'DisableCraftReroll'
$disableEnhance = Get-CSharpMethodText 'DisableSpeEnhanceReroll'
$craftResultsShownPostfix = Get-CSharpMethodText 'CraftResultsShownPostfix'
$craftOpenPostfix = Get-CSharpMethodText 'CraftUiOpenPostfix'
$craftHidePrefix = Get-CSharpMethodText 'CraftUiHidePrefix'
$craftConfirmPrefix = Get-CSharpMethodText 'CraftResultChoosenPrefix'
$enhanceOpenPostfix = Get-CSharpMethodText 'SpeEnhanceOpenPostfix'
$enhanceHidePrefix = Get-CSharpMethodText 'SpeEnhanceHidePrefix'
$enhanceConfirmPrefix = Get-CSharpMethodText 'SpeEnhanceConfirmPrefix'
$loadRecentPrefix = Get-CSharpMethodText 'LoadRecentGamePrefix'
$loadGamePrefix = Get-CSharpMethodText 'LoadGamePrefix'
$loadAllPostfix = Get-CSharpMethodText 'LoadAllGameDataPostfix'
$craftHooksReady = Get-AssignmentText '_craftRerollHooksReady'
$enhanceHooksReady = Get-AssignmentText '_speEnhanceRerollHooksReady'

# One Electron-facing switch, on by default, with no keyboard activation surface.
Require-Pattern $source 'ConfigEntry<bool>\s+_craftRerollEnabled\b' `
    'Craft reroll must have a boolean _craftRerollEnabled configuration field.'
Require-Pattern $source 'Config\.Bind\s*\(\s*"Craft"\s*,\s*"RerollEnabled"\s*,\s*true\s*,' `
    '[Craft] RerollEnabled must be bound with default true.'
Reject-Pattern $source '(?i)(?:craft|enhance)[A-Za-z0-9_]*(?:hotkey|requireAlt)|(?:hotkey|requireAlt)[A-Za-z0-9_]*(?:craft|enhance)' `
    'Craft and special-enhance reroll must not define or reference hotkey/RequireAlt fields.'
Reject-Pattern $source 'Config\.Bind\s*\(\s*"Craft"\s*,\s*"[^"]*(?:Hotkey|RequireAlt)[^"]*"' `
    'The [Craft] section must not bind a hotkey or RequireAlt setting.'
Reject-Pattern ($updateMethod + $craftAction + $enhanceAction) '\bInput\s*\.|GetKeyDown|IsConfiguredHotkeyPressed' `
    'Craft reroll update/action code must not poll Unity input or configured hotkeys.'

# Normal crafting and special enhancement own distinct controls and state.
foreach ($field in @(
    '_craftRerollButton', '_craftRerollButtonRoot', '_craftRerollReady', '_craftRerollBusy',
    '_speEnhanceRerollButton', '_speEnhanceRerollButtonRoot', '_speEnhanceRerollReady', '_speEnhanceRerollBusy'
)) {
    Require-Text $source $field "Craft and special-enhance reroll must define independent state field: $field"
}
Require-Pattern $source 'private const string CraftRerollButtonName\s*=\s*"[^"]+"\s*;' `
    'Normal crafting must use a non-empty constant reroll button name.'
Require-Pattern $source 'private const string SpeEnhanceRerollButtonName\s*=\s*"[^"]+"\s*;' `
    'Special enhancement must use a non-empty constant reroll button name.'
Require-Pattern $clickRouter 'isCraftReroll\s*=\s*string\.Equals\([^;]*CraftRerollButtonName[^;]*StringComparison\.Ordinal[^;]*\)\s*&&\s*__instance\s*==\s*_craftRerollButton' `
    'Normal crafting must route only the exact named and saved Button instance.'
Require-Pattern $clickRouter 'isSpeEnhanceReroll\s*=\s*string\.Equals\([^;]*SpeEnhanceRerollButtonName[^;]*StringComparison\.Ordinal[^;]*\)\s*&&\s*__instance\s*==\s*_speEnhanceRerollButton' `
    'Special enhancement must route only the exact named and saved Button instance.'
Require-Pattern $clickRouter '(?:isCraftReroll|isSpeEnhanceReroll)[\s\S]*?eventData\s*==\s*null[\s\S]*?eventData\.button\s*!=\s*PointerEventData\.InputButton\.Left[\s\S]*?return false\s*;' `
    'Craft reroll routes must reject null and every non-left pointer event.'
Require-Pattern $clickRouter 'if\s*\(\s*isCraftReroll\s*\)[\s\S]*?_craftRerollEnabled\.Value[\s\S]*?TryRerollCraftResults\s*\(\s*\)' `
    'The exact normal-craft left-click route must check enabled before dispatch.'
Require-Pattern $clickRouter 'if\s*\(\s*isSpeEnhanceReroll\s*\)[\s\S]*?_craftRerollEnabled\.Value[\s\S]*?TryRerollSpeEnhanceChoices\s*\(\s*\)' `
    'The exact special-enhance left-click route must check enabled before dispatch.'

# Buttons are visual-only objects, exclude both overlays as templates, and belong to distinct roots.
Require-Text $ensureCraftButton 'TryCreateSafeStyledButton(' `
    'Normal crafting must create its control through the safe visual-only button helper.'
Require-Text $ensureEnhanceButton 'TryCreateSafeStyledButton(' `
    'Special enhancement must create its control through the safe visual-only button helper.'
Reject-Text ($ensureCraftButton + $ensureEnhanceButton) 'TryCreateButtonTemplateButton(' `
    'Craft reroll controls must not clone native controls carrying inherited behavior scripts.'
Require-Pattern $safeButtonHelper 'new\s+GameObject\s*\(' `
    'The safe button helper must construct a clean GameObject.'
Reject-Pattern $safeButtonHelper '(?:UnityEngine\.)?Object\.Instantiate\s*\(' `
    'The safe button helper must not Instantiate a native template GameObject.'
Require-Text $findTemplate 'CraftRerollButtonName' `
    'FindUiButtonTemplate must exclude the normal craft reroll button.'
Require-Text $findTemplate 'SpeEnhanceRerollButtonName' `
    'FindUiButtonTemplate must exclude the special-enhance reroll button.'
Require-Text $knownRoot '_craftRerollButtonRoot' `
    'Known overlay root detection must include the normal craft reroll root.'
Require-Text $knownRoot '_speEnhanceRerollButtonRoot' `
    'Known overlay root detection must include the special-enhance reroll root.'

# Snapshot fidelity: every position (including null) is preserved and all rerolls use
# the session's initial seed/fingerprint rather than the most recent generated values.
Require-Pattern $captureSession 'for\s*\([^\)]*<\s*[^;]*(?:Count|Length)[^\)]*\)[\s\S]*?Add\s*\([^\)]*\)' `
    'Normal crafting must snapshot each result index, including null entries.'
Reject-Pattern $captureSession '\bWhere\s*\(|if\s*\([^\)]*!=\s*null[^\)]*\)[\s\S]*?Add\s*\(' `
    'Normal crafting snapshot must not filter null entries or collapse their indices.'
Require-Pattern $captureSession '_craftRerollInitialSeed\s*=\s*[^;]+;' `
    'Normal crafting must capture one initial generation seed for the session.'
Require-Pattern $buildResults '_craftRerollInitialSeed' `
    'Every normal-craft reroll must generate from the captured initial seed.'
Reject-Pattern $buildResults '_craftRerollInitialSeed\s*=' `
    'Normal-craft reroll generation must not replace the session initial seed.'
foreach ($identityPart in @(
    'craftType', 'material', 'resourceCostID', 'target', 'Weapon', 'Food', 'Building', 'lv', 'hero', 'useMoney', 'forceCraft'
)) {
    Require-Text $fingerprintMethod $identityPart `
        "Craft session fingerprint must include identity component: $identityPart"
}
Require-Pattern $fingerprintMethod '(?:GetType\s*\(\)|is\s+WeaponData|is\s+FoodData|is\s+BuildingData)' `
    'Craft fingerprint must distinguish the target item subtype.'
Require-Pattern $captureSession '\bResolveCraftRerollTargetHero\s*\(\s*\)' `
    'Normal crafting session capture must resolve the exact target hero through ResolveCraftRerollTargetHero.'
Require-Pattern $fingerprintMethod '\bResolveCraftRerollTargetHero\s*\(\s*\)' `
    'Craft fingerprint must resolve hero identity through the same ResolveCraftRerollTargetHero helper.'
Require-Pattern $resolveTargetHero 'HeroDetailController\.Instance[\s\S]*?\?\.nowShowHero' `
    'Craft reroll target hero must be read directly from HeroDetailController.Instance.nowShowHero.'
Reject-Pattern $resolveTargetHero '\bcatch\b' `
    'Craft reroll target hero helper must let access exceptions propagate to its fail-closed caller.'
Reject-Pattern $resolveTargetHero '\bTryGetPlayerHero\s*\(' `
    'Craft reroll target hero resolution must not fall back to the player hero.'

# Generate transactionally into a new IL2CPP list. Per-index generation failures fall
# back to the original slot; replacement occurs only after full validation.
Require-Pattern $buildResults 'new\s+Il2CppSystem\.Collections\.Generic\.List<ItemData>\s*\(' `
    'Normal crafting must build a fresh IL2CPP ItemData list atomically.'
Require-Pattern $captureSession 'BuildingLevel\s*=\s*controller\.targetBuilding\.lv\s*,' `
    'Normal crafting must capture the actual controller.targetBuilding.lv in every immutable seed.'
Require-Pattern $buildResults 'GenerateRandomItemValue\s*\(\s*seed\.Value\s*,\s*seed\.ItemType\s*,\s*seed\.BuildingLevel\s*,\s*subType\s*,\s*littleType\s*,\s*seed\.TargetHero\s*,\s*weaponType\s*\)' `
    'Normal crafting must call the seven-argument GenerateRandomItemValue with each immutable seed BuildingLevel.'
Require-Pattern $buildResults '(?:original|seed)\s*=\s*_craftRerollInitialSeed\s*\[\s*index\s*\][\s\S]*?catch\s*\([^\)]*Exception[^\)]*\)[\s\S]*?replacement\.Add\s*\(\s*(?:original|seed)\.OriginalItem\s*\)' `
    'A failed generated slot must fall back to the original item at the same index.'
Require-Pattern $craftAction '(?:Count|Length)[\s\S]*?(?:type|GetType|is\s+ItemData)[\s\S]*?(?:for\s*\(|SequenceEqual|Validate)[\s\S]*?craftResult[^=\r\n]*=\s*(?:newResults|rerolledResults|replacement)' `
    'Normal crafting must validate count, order/index, and types before replacing its result list.'
Require-Pattern $craftAction 'var\s+(?:old|original|previous)[A-Za-z0-9_]*\s*=\s*[^;]*craftResult[^;]*;[\s\S]*?catch\s*\([^\)]*Exception[^\)]*\)[\s\S]*?craftResult[^=\r\n]*=\s*(?:old|original|previous)' `
    'Normal crafting must roll back the previous result list if UI refresh fails.'
Require-Pattern $craftAction 'ClearCraftResultCandidateItemsImmediately\s*\([\s\S]*?ShowCraftResultChoosePanel\s*\(' `
    'Normal crafting must synchronously clear old CraftResult slot candidates before showing refreshed results.'
Require-Pattern $clearCraftRows 'SetActive\s*\(\s*false\s*\)[\s\S]*?SetParent\s*\(\s*null\s*,\s*false\s*\)[\s\S]*?UnityEngine\.Object\.Destroy\s*\(' `
    'Old dynamic craft candidates must be hidden, detached, then destroyed in that order.'

# Runtime probing establishes the craft panel's direct candidate hierarchy.
# They live under CraftUIPanel/CraftResult/{0..N-1}/ItemIcon/<dynamic candidate>;
# CraftResult/Material is a separate fixed subtree and is never part of cleanup.
Require-Pattern $ownedCraftResultPanel 'CraftUIController' `
    'IsOwnedCraftResultPanel must bind ownership to a concrete CraftUIController.'
Require-Pattern $ownedCraftResultPanel 'controller\s*==\s*CraftUIController\.Instance|controller\s*!=\s*CraftUIController\.Instance' `
    'IsOwnedCraftResultPanel must require the current CraftUIController instance.'
Require-Pattern $ownedCraftResultPanel 'creaftUIPanel[\s\S]*?(?:activeInHierarchy|activeSelf)' `
    'IsOwnedCraftResultPanel must require the active creaftUIPanel.'
Require-Pattern $ownedCraftResultPanel 'ownedSlots\s*=\s*null!\s*;[\s\S]*?if\s*\([\s\S]*?creaftUIPanel[\s\S]*?activeInHierarchy[\s\S]*?return\s+false\s*;[\s\S]*?ownedSlots\s*=\s*new\s+List<Transform>\s*\(\s*expectedCount\s*\)' `
    'IsOwnedCraftResultPanel must avoid allocating its slot list until the current craft panel passes the active-context fast guard.'
Require-Pattern $ownedCraftResultPanel '\.Find\s*\(\s*"CraftResult"\s*\)' `
    'IsOwnedCraftResultPanel must resolve the direct CraftResult root.'
Require-Pattern $ownedCraftResultPanel 'for\s*\([^\)]*(?:index|slot)[^\)]*<\s*(?:expectedCount|resultCount)[^\)]*\)' `
    'IsOwnedCraftResultPanel must validate every expected numeric slot from zero through N-1.'
Require-Pattern $ownedCraftResultPanel '\.Find\s*\(\s*(?:index|slot)\.ToString\s*\(' `
    'IsOwnedCraftResultPanel must resolve slots by their exact numeric names.'
Require-Pattern $ownedCraftResultPanel '\.Find\s*\(\s*"ItemIcon"\s*\)' `
    'IsOwnedCraftResultPanel must require each numeric slot fixed ItemIcon child.'
Require-Pattern $ownedCraftResultPanel '\.Find\s*\(\s*"Button"\s*\)' `
    'IsOwnedCraftResultPanel must require each numeric slot fixed Button child.'
Reject-Pattern $ownedCraftResultPanel 'GetComponentsInChildren[^\r\n]*(?:CraftResult|ItemIcon|Button)' `
    'CraftResult ownership must use direct-child paths, not recursive name matches.'
foreach ($ownershipBoundary in @(
    @{ Scope = $captureSession; Name = 'session capture' },
    @{ Scope = $updateNormalCraft; Name = 'normal-craft update' },
    @{ Scope = $craftVisibility; Name = 'craft visibility' },
    @{ Scope = $craftButtonHost; Name = 'button host resolution' },
    @{ Scope = $craftAction; Name = 'reroll action' },
    @{ Scope = $clearCraftRows; Name = 'row cleanup' }
)) {
    Require-Pattern $ownershipBoundary.Scope '\bIsOwnedCraftResultPanel\s*\(' `
        "CraftResult $($ownershipBoundary.Name) must require strict panel ownership."
}
Require-Pattern $captureSession 'rowCount\s*!=\s*resultCount[\s\S]*?return\s+false\s*;' `
    'Craft session capture must reject rowCount != resultCount instead of accepting a partial CraftResult panel.'
Require-Pattern $clearCraftRows 'if\s*\(\s*!IsOwnedCraftResultPanel\s*\([^\)]*(?:expectedCount|resultCount)[^\)]*\)[\s\S]*?return\s+0\s*;' `
    'Craft cleanup must return without mutation unless CraftResult ownership and exact slot count are proven.'
Require-Pattern $clearCraftRows 'foreach\s*\([^\)]*slot\s+in\s+ownedSlots\s*\)[\s\S]*?slot\.Find\s*\(\s*"ItemIcon"\s*\)[\s\S]*?for\s*\([^\)]*itemContainer\.childCount\s*-\s*1[\s\S]*?itemContainer\.GetChild\s*\(' `
    'Craft cleanup must walk only each validated numeric slot ItemIcon dynamic-child area.'
Reject-Pattern $clearCraftRows '"Material"|Find[^\r\n]*Material|GetChild[^\r\n]*Material' `
    'Craft cleanup must never access or clear the sibling CraftResult/Material subtree.'
Reject-Pattern $clearCraftRows '(?:(?:craftResultRoot|slotRoot|itemIcon|button)[A-Za-z0-9_]*\s*\.\s*(?:SetActive|SetParent)\s*\(|(?:Destroy|DestroyImmediate)\s*\([^\r\n]*(?:craftResultRoot|slotRoot|itemIcon|button))' `
    'Craft cleanup must preserve the fixed CraftResult root, numeric slots, ItemIcon roots, and Buttons.'
Reject-Pattern $craftAction 'ClearCraftResultCandidateItemsImmediately\s*\([^\)]*CountCraftResultChooseRows\s*\(' `
    'Craft rollback must not derive cleanup scope from an unvalidated global row count.'
Require-Pattern $craftAction 'catch\s*\([^\)]*Exception[^\)]*\)[\s\S]*?craftResult[^=\r\n]*=\s*(?:old|original|previous)[\s\S]*?IsOwnedCraftResultPanel\s*\([\s\S]*?_craftRerollExpectedResultCount[\s\S]*?ClearCraftResultCandidateItemsImmediately\s*\([\s\S]*?_craftRerollExpectedResultCount[\s\S]*?ShowCraftResultChoosePanel\s*\(' `
    'Craft rollback may clean/rebuild dynamic candidates only after revalidating CraftResult ownership and exact slot count.'

# Special enhancement deliberately delegates only to the three display-choice methods.
Require-Pattern $enhanceAction '\.ClearAllChoice\s*\(\s*\)[\s\S]*?\.GenerateChoice\s*\(\s*\)[\s\S]*?\.RefreshEnhanceButtonState\s*\(\s*\)' `
    'Special enhancement reroll must call ClearAllChoice, GenerateChoice, then RefreshEnhanceButtonState.'
Require-Pattern $enhanceAction 'GetComponentsInChildren[^\r\n]*\(\s*(?:includeInactive\s*:\s*)?false\s*\)[\s\S]*?(?:activeCount|visibleCount)[\s\S]*?(?:expected|original)[A-Za-z0-9_]*(?:Count|Choice)' `
    'Special enhancement must validate the active generated choice count.'
$allowedEnhanceCalls = @('ClearAllChoice', 'GenerateChoice', 'RefreshEnhanceButtonState')
$enhanceControllerCalls = [System.Text.RegularExpressions.Regex]::Matches(
    $enhanceAction,
    '\.(?<Name>[A-Za-z_][A-Za-z0-9_]*)\s*\(')
foreach ($call in $enhanceControllerCalls) {
    $name = $call.Groups['Name'].Value
    if ($name -match 'Choice|EnhanceButtonState' -and $allowedEnhanceCalls -notcontains $name) {
        $failures.Add("Special enhancement action calls disallowed choice/enhance method: $name")
    }
}

# Every lifecycle, confirmation, click, update, and load dependency participates in
# fail-closed hook readiness. Runtime exceptions disable and clear only the affected path.
foreach ($patchResult in @(
    'craftOpenPatched', 'craftHidePatched', 'craftResultsShownPatched', 'craftConfirmPatched',
    'craftGenerationStartPatched', 'craftClearAllMaterialPatched', 'craftClearMaterialPatched',
    'craftClearMaterialSubPatched', 'craftMaterialChosenPatched', 'craftMaterialSubChosenPatched',
    'craftFoodSubtypePatched', 'craftResourceCostPatched', 'craftSubtypePatched',
    'craftWeaponTypePatched', 'craftForceTogglePatched',
    'overlayButtonPointerPatched', 'gameControllerUpdatePatched',
    'loadRecentGamePatched', 'loadGamePatched', 'loadAllGameDataPatched'
)) {
    Require-Text $craftHooksReady $patchResult `
        "Normal crafting hook readiness must include: $patchResult"
}
foreach ($patchResult in @(
    'speEnhanceOpenPatched', 'speEnhanceHidePatched', 'speEnhanceConfirmPatched',
    'overlayButtonPointerPatched', 'gameControllerUpdatePatched',
    'loadRecentGamePatched', 'loadGamePatched', 'loadAllGameDataPatched'
)) {
    Require-Text $enhanceHooksReady $patchResult `
        "Special-enhance hook readiness must include: $patchResult"
}
Require-Pattern $disableCraft '_craftRerollHooksReady\s*=\s*false[\s\S]*?ResetCraftRerollState\s*\(' `
    'Normal crafting degraded mode must mark hooks unavailable and clear its state/UI.'
Require-Pattern $disableEnhance '_speEnhanceRerollHooksReady\s*=\s*false[\s\S]*?ResetSpeEnhanceRerollState\s*\(' `
    'Special-enhance degraded mode must mark hooks unavailable and clear its state/UI.'
foreach ($boundary in @(
    @{ Scope = $craftAction; Disable = 'DisableCraftReroll'; Name = 'normal-craft action' },
    @{ Scope = $enhanceAction; Disable = 'DisableSpeEnhanceReroll'; Name = 'special-enhance action' }
)) {
    Require-Pattern $boundary.Scope "catch\s*\([^\)]*Exception[^\)]*\)[\s\S]*?$($boundary.Disable)\s*\(" `
        "Unexpected exceptions in $($boundary.Name) must fail closed."
}
$updateCatchMatches = [System.Text.RegularExpressions.Regex]::Matches(
    $updateMethod,
    'catch\s*\([^\)]*Exception[^\)]*\)\s*\{(?<Body>[^}]*)\}',
    [System.Text.RegularExpressions.RegexOptions]::Singleline)
$hasCraftOnlyUpdateCatch = $false
$hasEnhanceOnlyUpdateCatch = $false
foreach ($catchMatch in $updateCatchMatches) {
    $catchBody = $catchMatch.Groups['Body'].Value
    $disablesCraft = $catchBody.IndexOf('DisableCraftReroll(', [System.StringComparison]::Ordinal) -ge 0
    $disablesEnhance = $catchBody.IndexOf('DisableSpeEnhanceReroll(', [System.StringComparison]::Ordinal) -ge 0
    if ($disablesCraft -and $disablesEnhance) {
        $failures.Add('One UpdateCraftRerollAssist catch must not disable both independent reroll paths.')
    }
    elseif ($disablesCraft) {
        $hasCraftOnlyUpdateCatch = $true
    }
    elseif ($disablesEnhance) {
        $hasEnhanceOnlyUpdateCatch = $true
    }
}
if (-not $hasCraftOnlyUpdateCatch) {
    $failures.Add('UpdateCraftRerollAssist must have a normal-craft-only catch/DisableCraftReroll boundary.')
}
if (-not $hasEnhanceOnlyUpdateCatch) {
    $failures.Add('UpdateCraftRerollAssist must have a special-enhance-only catch/DisableSpeEnhanceReroll boundary.')
}

Require-Text $craftResultsShownPostfix 'CaptureCraftRerollSession(' `
    'Only the genuine ShowCraftResultChoosePanel postfix may capture the immutable craft reroll session.'
Require-Pattern $craftResultsShownPostfix 'catch\s*\([^\)]*Exception[^\)]*\)[\s\S]*?DisableCraftReroll\s*\(' `
    'Craft result-show capture exceptions must fail closed through DisableCraftReroll.'
$captureReferenceCount = [System.Text.RegularExpressions.Regex]::Matches(
    $source,
    '\bCaptureCraftRerollSession\s*\(').Count
if ($captureReferenceCount -ne 2) {
    $failures.Add("CaptureCraftRerollSession must appear exactly twice (definition plus sole CraftResultsShownPostfix call); found $captureReferenceCount references.")
}
Require-Text $craftOpenPostfix 'ResetCraftRerollState(' `
    'Opening normal crafting must reset stale state and wait for the genuine results-shown hook.'
Reject-Text $craftOpenPostfix 'CaptureCraftRerollSession(' `
    'CraftUiOpenPostfix must not capture before the result panel is genuinely shown.'
Reject-Text $updateNormalCraft 'CaptureCraftRerollSession(' `
    'UpdateNormalCraftRerollAssist must not synthesize a session before the result-show hook.'
Require-Pattern $updateNormalCraft '_craftRerollInitialSeed\s*==\s*null[\s\S]*?SetOverlayObjectActive\s*\(\s*_craftRerollButtonRoot\s*,\s*false\s*\)[\s\S]*?return\s*;' `
    'Normal-craft Update must hide and return while no genuine result-show snapshot exists.'
Require-Text $craftHidePrefix 'ResetCraftRerollState(' `
    'Hiding normal crafting must clear its reroll session and button.'
Require-Text $craftConfirmPrefix 'ResetCraftRerollState(' `
    'Confirming a normal craft result must clear reroll state before the original method.'
Require-Text $enhanceOpenPostfix 'ResetSpeEnhanceRerollState(' `
    'Opening special enhancement must start with clean independent reroll state.'
Require-Text $enhanceHidePrefix 'ResetSpeEnhanceRerollState(' `
    'Hiding special enhancement must clear its reroll state and button.'
Require-Text $enhanceConfirmPrefix 'ResetSpeEnhanceRerollState(' `
    'Confirming special enhancement must clear reroll state before the original method.'
foreach ($loadBoundary in @(
    @{ Scope = $loadRecentPrefix; Name = 'LoadRecentGamePrefix' },
    @{ Scope = $loadGamePrefix; Name = 'LoadGamePrefix' },
    @{ Scope = $loadAllPostfix; Name = 'LoadAllGameDataPostfix' }
)) {
    Require-Text $loadBoundary.Scope 'ResetCraftRerollState(' `
        "$($loadBoundary.Name) must clear normal-craft reroll state."
    Require-Text $loadBoundary.Scope 'ResetSpeEnhanceRerollState(' `
        "$($loadBoundary.Name) must clear special-enhance reroll state."
}

# Reroll action bodies are preview-only: no confirmation, reward, resource, or time side effects.
$actionBodies = $craftAction + $buildResults + $clearCraftRows + $enhanceAction
foreach ($forbiddenCall in @(
    'CraftButtonClicked', 'CraftResultChoosen', 'FinishCraft', 'GetItem',
    'ChangeMoney', 'ChangeDay', 'ChangeMonth', 'ChangeYear', 'ChangeHour',
    'UseItem', 'RemoveItem', 'LoseItem', 'CostItem', 'ConsumeItem',
    'EnhanceButtonClicked', 'FinishSpeEnhance'
)) {
    Reject-Pattern $actionBodies "\b$forbiddenCall\s*\(" `
        "Craft reroll action bodies must not call side-effect method $forbiddenCall."
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ -ErrorAction Continue }
    exit 1
}

Write-Host "Craft and special-enhance reroll semantic checks passed: $resolvedSourcePath"
