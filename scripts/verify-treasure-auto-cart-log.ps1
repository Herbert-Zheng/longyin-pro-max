[CmdletBinding()]
param(
    [string]$LogPath = '',

    [ValidateRange(1, [int]::MaxValue)]
    [int]$StartLine = 1,

    [string]$TriggerMarker,

    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'

function New-VerificationResult {
    param(
        [Parameter(Mandatory)]
        [string]$Status,

        [Parameter(Mandatory)]
        [int]$ExitCode,

        [Parameter(Mandatory)]
        [string]$Evidence,

        [Parameter(Mandatory)]
        [string]$Detail
    )

    [pscustomobject]@{
        Status = $Status
        ExitCode = $ExitCode
        Evidence = $Evidence
        Detail = $Detail
    }
}

function Test-TreasureAutoCartLog {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$Lines,

        [string]$KnownTriggerMarker
    )

    $scopeStart = 0
    if (-not [string]::IsNullOrWhiteSpace($KnownTriggerMarker)) {
        $markerIndex = -1
        for ($index = 0; $index -lt $Lines.Count; $index++) {
            if ($Lines[$index].IndexOf($KnownTriggerMarker, [StringComparison]::Ordinal) -ge 0) {
                $markerIndex = $index
            }
        }

        if ($markerIndex -lt 0) {
            return New-VerificationResult `
                -Status 'NOT_TRIGGERED' `
                -ExitCode 10 `
                -Evidence "Trigger marker was not found: $KnownTriggerMarker" `
                -Detail 'The requested trigger window is absent from the log.'
        }

        $scopeStart = $markerIndex + 1
    }

    $scopedLines = @()
    if ($scopeStart -lt $Lines.Count) {
        $scopedLines = @($Lines[$scopeStart..($Lines.Count - 1)])
    }

    $attemptPattern = '\[TreasureAutoCart\]\s+(?:attempt|triggered)\b'
    $candidatePattern = '\[TreasureAutoCart\]\s+candidates(?:\s+count)?=(\d+)\b'
    $notReflectedPattern = 'Treasure trade cart add was not reflected by rightOutList:'
    $queueFailedPattern = 'Treasure cart auto-queue failed:'
    $verifiedPattern = 'Treasure trade cart add verified:'
    $finishedPattern = 'Treasure cart auto-queue finished:\s*verified=(\d+),\s*failed=(\d+),\s*cartCount=(\d+)'

    $lastAttempt = -1
    for ($index = 0; $index -lt $scopedLines.Count; $index++) {
        if ($scopedLines[$index] -match $attemptPattern) {
            $lastAttempt = $index
        }
    }

    $attemptLines = $scopedLines
    if ($lastAttempt -ge 0) {
        $attemptLines = @($scopedLines[$lastAttempt..($scopedLines.Count - 1)])
    }

    $candidateCount = $null
    $candidateEvidence = $null
    $verifiedCount = 0
    $finishedVerified = $null
    $finishedFailed = $null
    $finishedCartCount = $null
    $notReflectedEvidence = $null
    $queueFailedEvidence = $null
    $successEvidence = $null

    foreach ($line in $attemptLines) {
        if ($line -match $candidatePattern) {
            $candidateCount = [int]$Matches[1]
            $candidateEvidence = $line
        }
        if ($line -match $notReflectedPattern) {
            $notReflectedEvidence = $line
        }
        if ($line -match $queueFailedPattern) {
            $queueFailedEvidence = $line
        }
        if ($line -match $verifiedPattern) {
            $verifiedCount++
            $successEvidence = $line
        }
        if ($line -match $finishedPattern) {
            $finishedVerified = [int]$Matches[1]
            $finishedFailed = [int]$Matches[2]
            $finishedCartCount = [int]$Matches[3]
            $successEvidence = $line
        }
    }

    if ($null -ne $finishedVerified -and $finishedFailed -gt 0) {
        return New-VerificationResult `
            -Status 'QUEUE_FAILED' `
            -ExitCode 14 `
            -Evidence $successEvidence `
            -Detail "The terminal result recorded $finishedFailed failed addition(s); verified=$finishedVerified and cartCount=$finishedCartCount."
    }

    if ($null -ne $queueFailedEvidence) {
        return New-VerificationResult `
            -Status 'QUEUE_FAILED' `
            -ExitCode 14 `
            -Evidence $queueFailedEvidence `
            -Detail 'The treasure auto-cart queue raised an exception.'
    }

    if ($null -ne $notReflectedEvidence) {
        return New-VerificationResult `
            -Status 'CART_ADD_NOT_REFLECTED' `
            -ExitCode 12 `
            -Evidence $notReflectedEvidence `
            -Detail 'A profitable candidate was clicked, but neither the cart count nor matching-item count increased. This matches the reported user symptom.'
    }

    if ($null -ne $finishedVerified) {
        if ($finishedVerified -gt 0 -and $finishedFailed -eq 0 -and $finishedCartCount -gt 0) {
            return New-VerificationResult `
                -Status 'SUCCESS' `
                -ExitCode 0 `
                -Evidence $successEvidence `
                -Detail "The cart contains $finishedCartCount item(s); this attempt verified $finishedVerified addition(s) and recorded no failures."
        }

        return New-VerificationResult `
            -Status 'INDETERMINATE' `
            -ExitCode 13 `
            -Evidence $successEvidence `
            -Detail "The terminal result is not a clean success: verified=$finishedVerified, failed=$finishedFailed, cartCount=$finishedCartCount."
    }

    if ($verifiedCount -gt 0) {
        return New-VerificationResult `
            -Status 'SUCCESS' `
            -ExitCode 0 `
            -Evidence $successEvidence `
            -Detail "At least $verifiedCount cart addition(s) were reflected by rightOutList."
    }

    if ($null -ne $candidateCount -and $candidateCount -eq 0) {
        return New-VerificationResult `
            -Status 'ZERO_CANDIDATES' `
            -ExitCode 11 `
            -Evidence $candidateEvidence `
            -Detail 'The auto-cart ran, but its profitability filter produced no candidates.'
    }

    $hasAttempt = $lastAttempt -ge 0
    $hasLegacyResult = $attemptLines | Where-Object { $_ -match $finishedPattern -or $_ -match $verifiedPattern -or $_ -match $notReflectedPattern -or $_ -match $queueFailedPattern } | Select-Object -First 1
    if (-not $hasAttempt -and $null -eq $hasLegacyResult) {
        return New-VerificationResult `
            -Status 'NOT_TRIGGERED' `
            -ExitCode 10 `
            -Evidence 'No treasure auto-cart attempt or result line was found in the selected log window.' `
            -Detail 'With current production logging, this can also mean the method ran but found zero candidates. Add the instrumentation contract printed below to disambiguate.'
    }

    return New-VerificationResult `
        -Status 'INDETERMINATE' `
        -ExitCode 13 `
        -Evidence 'An auto-cart attempt was logged without a candidate count or terminal cart result.' `
        -Detail 'The attempt did not produce enough evidence to prove success or the reported symptom.'
}

function Invoke-SelfTest {
    $cases = @(
        @{ Name = 'reports not-triggered when the trigger has no attempt'; Expected = 'NOT_TRIGGERED'; Lines = @('KNOWN TRIGGER', 'unrelated') },
        @{ Name = 'reports zero candidates'; Expected = 'ZERO_CANDIDATES'; Lines = @('KNOWN TRIGGER', '[TreasureAutoCart] attempt shopItems=3 renderedIcons=3', '[TreasureAutoCart] candidates=0') },
        @{ Name = 'reports cart-add-not-reflected'; Expected = 'CART_ADD_NOT_REFLECTED'; Lines = @('KNOWN TRIGGER', '[TreasureAutoCart] attempt shopItems=3 renderedIcons=3', '[TreasureAutoCart] candidates=1', 'Treasure trade cart add was not reflected by rightOutList: item=x, cart=0->0, matching=0->0.') },
        @{ Name = 'reports success from current production completion log'; Expected = 'SUCCESS'; Lines = @('KNOWN TRIGGER', 'Treasure trade cart add verified: item=x, buy=1, sellIdentified=2, net=1, cart=0->1.', 'Treasure cart auto-queue finished: verified=1, failed=0, cartCount=1.') },
        @{ Name = 'uses only the latest attempt'; Expected = 'ZERO_CANDIDATES'; Lines = @('KNOWN TRIGGER', '[TreasureAutoCart] attempt shopItems=1 renderedIcons=1', 'Treasure trade cart add verified: item=x, buy=1, sellIdentified=2, net=1, cart=0->1.', '[TreasureAutoCart] attempt shopItems=2 renderedIcons=2', '[TreasureAutoCart] candidates=0') },
        @{ Name = 'rejects a partially failed terminal result'; Expected = 'QUEUE_FAILED'; Lines = @('KNOWN TRIGGER', 'Treasure trade cart add verified: item=x, buy=1, sellIdentified=2, net=1, cart=0->1.', 'Treasure cart auto-queue finished: verified=1, failed=1, cartCount=1.') },
        @{ Name = 'rejects a terminal result with an empty cart'; Expected = 'INDETERMINATE'; Lines = @('KNOWN TRIGGER', 'Treasure trade cart add verified: item=x, buy=1, sellIdentified=2, net=1, cart=0->1.', 'Treasure cart auto-queue finished: verified=1, failed=0, cartCount=0.') },
        @{ Name = 'not-reflected evidence overrides a legacy verified line'; Expected = 'CART_ADD_NOT_REFLECTED'; Lines = @('KNOWN TRIGGER', 'Treasure trade cart add verified: item=x, buy=1, sellIdentified=2, net=1, cart=0->1.', 'Treasure trade cart add was not reflected by rightOutList: item=y, cart=1->1, matching=0->0.') },
        @{ Name = 'reports a queue exception'; Expected = 'QUEUE_FAILED'; Lines = @('KNOWN TRIGGER', 'Treasure cart auto-queue failed: boom') }
    )

    $failed = 0
    foreach ($case in $cases) {
        $actual = Test-TreasureAutoCartLog -Lines $case.Lines -KnownTriggerMarker 'KNOWN TRIGGER'
        if ($actual.Status -ne $case.Expected) {
            Write-Error "FAIL: $($case.Name): expected $($case.Expected), got $($actual.Status)" -ErrorAction Continue
            $failed++
        }
        else {
            Write-Host "PASS: $($case.Name)"
        }
    }

    if ($failed -gt 0) {
        exit 1
    }

    Write-Host "Treasure auto-cart verifier self-test passed: $($cases.Count) tests, 0 failed."
    exit 0
}

if ($SelfTest) {
    Invoke-SelfTest
}

if ([string]::IsNullOrWhiteSpace($LogPath)) {
    $candidateLogPaths = @(
        'C:\Program Files (x86)\Steam\steamapps\common\LongYinLiZhiZhuan\BepInEx\LogOutput.log',
        'G:\Steam\steamapps\common\LongYinLiZhiZhuan\BepInEx\LogOutput.log'
    )
    $LogPath = $candidateLogPaths |
        Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
        Select-Object -First 1
}

if (-not (Test-Path -LiteralPath $LogPath -PathType Leaf)) {
    Write-Error "BepInEx log not found: $LogPath"
    exit 2
}

$resolvedLogPath = (Resolve-Path -LiteralPath $LogPath).Path
$allLines = @(Get-Content -LiteralPath $resolvedLogPath)
$selectedLines = @()
if ($StartLine -le $allLines.Count) {
    $selectedLines = @($allLines[($StartLine - 1)..($allLines.Count - 1)])
}

$result = Test-TreasureAutoCartLog -Lines $selectedLines -KnownTriggerMarker $TriggerMarker

Write-Host "Treasure auto-cart verification: $($result.Status)"
Write-Host "Log: $resolvedLogPath"
Write-Host "Window: line $StartLine through $($allLines.Count)"
Write-Host "Evidence: $($result.Evidence)"
Write-Host "Detail: $($result.Detail)"

if ($result.Status -ne 'SUCCESS') {
    Write-Host ''
    Write-Host 'Minimal instrumentation contract (one attempt line and one candidate line per evaluation):'
    Write-Host '  [TreasureAutoCart] attempt shopItems=<n> renderedIcons=<n> enabled=<true|false>'
    Write-Host '  [TreasureAutoCart] candidates=<n>'
    Write-Host 'Existing "add verified", "add was not reflected", and "auto-queue finished" logs are sufficient terminal events.'
}

exit $result.ExitCode
