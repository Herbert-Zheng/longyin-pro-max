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
    $nextMethodMatch = $nextMethodRegex.Match(
        $source,
        $methodMatch.Index + $methodMatch.Length)
    $endIndex = if ($nextMethodMatch.Success) { $nextMethodMatch.Index } else { $source.Length }
    return $source.Substring($methodMatch.Index, $endIndex - $methodMatch.Index)
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

$changeFavorPrefix = Get-CSharpMethodText 'ChangeFavorPrefix'
$changeFavorPostfix = Get-CSharpMethodText 'ChangeFavorPostfix'
$queueMethod = Get-CSharpMethodText 'QueueDeferredRelationshipBonusLog'
$flushMethod = Get-CSharpMethodText 'FlushDeferredRelationshipBonusLogs'
$resetMethod = Get-CSharpMethodText 'ResetDeferredRelationshipBonusLogs'
$updatePostfix = Get-CSharpMethodText 'GameControllerUpdatePostfix'
$loadGamePrefix = Get-CSharpMethodText 'LoadGamePrefix'
$showMainMenuPostfix = Get-CSharpMethodText 'ShowMainMenuPostfix'

Require-Pattern $changeFavorPrefix 'var\s+originalGain\s*=\s*num\s*;[\s\S]*?num\s*\*=\s*2f\s*;' 'Relationship bonus must still double the original positive favor gain.'
Require-Pattern $source 'changeFavorPatched\s*=\s*PatchMethod\([^;]+nameof\(ChangeFavorPrefix\),\s*nameof\(ChangeFavorPostfix\)\)' 'Relationship bonus must patch both the value-scaling prefix and the post-success notification postfix.'
Require-Pattern $source '_relationshipBonusHooksReady\s*=\s*changeFavorPatched\s*&&\s*gameControllerUpdatePatched\s*;' 'Relationship bonus must be disabled unless both ChangeFavor and the deferred update hook are available.'
Require-Pattern $changeFavorPrefix '!_relationshipBonusHooksReady' 'ChangeFavorPrefix must not mutate favor when the deferred notification path is unavailable.'
Require-Pattern $changeFavorPrefix '__state\s*=\s*new\s+RelationshipBonusState[\s\S]*?IsApplied\s*=\s*true' 'ChangeFavorPrefix must return explicit state for a successfully selected bonus.'
Reject-Pattern $changeFavorPrefix 'QueueDeferredRelationshipBonusLog|PushPlayerLog|InfoController|ShowTextOnMouse|AreaData' 'ChangeFavorPrefix must not synchronously queue or refresh game UI and player logs.'
Require-Pattern $changeFavorPostfix '__state\s*==\s*null\s*\|\|\s*!__state\.IsApplied[\s\S]*?QueueDeferredRelationshipBonusLog\(__state\.Message\)' 'The relationship postfix must tolerate another mod skipping ChangeFavor, and may queue only after this prefix selected a bonus.'
Require-Pattern $queueMethod 'Time\.frameCount\s*\+\s*1' 'Deferred relationship notifications must wait for at least the next Unity frame.'
Require-Pattern $queueMethod 'DeferredRelationshipBonusLogs\.Count\s*>=\s*MaxDeferredRelationshipBonusLogs[\s\S]*?DeferredRelationshipBonusLogs\.Dequeue\(\)' 'The deferred relationship notification queue must be bounded.'
Require-Pattern $flushMethod 'DeferredRelationshipBonusLogs\.Dequeue\(\)[\s\S]*?PushPlayerLog\(entry\.Message\)' 'The deferred queue must clear its state before publishing the relationship notification.'
Reject-Pattern $flushMethod '\bwhile\s*\(' 'The deferred relationship notification queue must publish at most one message per frame.'
Require-Pattern $updatePostfix 'try\s*\{[\s\S]*?ApplyViewedHeroCharacterDataTest\(\);[\s\S]*?\}\s*finally\s*\{\s*FlushDeferredRelationshipBonusLogs\(\);\s*\}' 'The main game update postfix must flush deferred relationship notifications from a finally block after its normal update work.'
Require-Pattern $loadGamePrefix 'ResetDeferredRelationshipBonusLogs\(' 'Loading a save must discard notifications from the previous game session.'
Require-Pattern $showMainMenuPostfix 'ResetDeferredRelationshipBonusLogs\(' 'Returning to the title screen must discard pending relationship notifications.'
Require-Pattern $resetMethod 'DeferredRelationshipBonusLogs\.Clear\(\)' 'The relationship notification reset must clear the queue.'

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ -ErrorAction Continue }
    exit 1
}

Write-Host "Relationship bonus safety checks passed: $resolvedSourcePath"
