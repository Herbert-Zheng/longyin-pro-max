[CmdletBinding()]
param(
    [string]$RepoRoot = '',
    [string]$InteropAssembly,
    [string[]]$PluginSource,
    [string]$RuntimeLog = '',
    [switch]$SkipRuntimeLog
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}

if (-not $InteropAssembly) {
    $InteropAssembly = Join-Path $RepoRoot 'dist\BepInEx\interop\Assembly-CSharp.dll'
}

if (-not $PluginSource) {
    $PluginSource = @(
        (Join-Path $RepoRoot 'mod-src\LongYinStaminaLock\LongYinStaminaLock.cs'),
        (Join-Path $RepoRoot 'mod-src\LongYinBattleTurbo\LongYinBattleTurbo.cs'),
        (Join-Path $RepoRoot 'mod-src\LongYinHorseStaminaMultiplier\LongYinHorseStaminaMultiplier.cs'),
        (Join-Path $RepoRoot 'mod-src\LongYinSkipIntro\LongYinSkipIntro.cs')
    )
}

if (-not $RuntimeLog) {
    $RuntimeLog = 'C:\Program Files (x86)\Steam\steamapps\common\LongYinLiZhiZhuan\BepInEx\LogOutput.log'
}

$failures = [System.Collections.Generic.List[string]]::new()

foreach ($requiredPath in @($InteropAssembly) + @($PluginSource)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Required compatibility input is missing: $requiredPath"
    }
}

$inspectScript = Join-Path $RepoRoot 'scripts\inspect-interop-type.ps1'
$inspection = & $inspectScript `
    -AssemblyPath $InteropAssembly `
    -TypeName 'GameDataController' `
    -MemberPattern @('heroTagDataBase') `
    -SkipRestore 2>&1 | Out-String

$interopHasHeroTagDatabase =
    $inspection -match '(?im)^(FIELDS|PROPERTIES|METHODS)\s+.*heroTagDataBase'
$staminaSource = $PluginSource | Where-Object { [System.IO.Path]::GetFileName($_) -eq 'LongYinStaminaLock.cs' } | Select-Object -First 1
if (-not $staminaSource) {
    throw 'LongYinStaminaLock.cs is required for the static compatibility check.'
}
$sourceText = Get-Content -LiteralPath $staminaSource -Raw
$sourceHasStaticHeroTagReference =
    $sourceText -match '(?m)(?:\.|\?\.)heroTagDataBase\b'
$sourceUsesPrivateIdentifyAnswer =
    $sourceText -match '(?m)(?:\.|\?\.)correctTreasure\b|Safe(?:Property|Field)\([^\r\n]*["'']correctTreasure["'']'
$sourceRegistersManagedUnityClickListener =
    $sourceText -match '(?m)\.onClick\.AddListener\s*\('

if ($sourceHasStaticHeroTagReference) {
    $failures.Add(
        'The plugin still contains a static GameDataController.heroTagDataBase reference; this optional native accessor has already failed with MissingMethodException and must be capability-detected dynamically.'
    )
}

if ($sourceUsesPrivateIdentifyAnswer) {
    $failures.Add(
        'The treasure-identify assist still reads IdentifyMatchController.correctTreasure. The current implementation must select by ItemData.GetTreasureRealValue instead of the private answer list.'
    )
}

if ($sourceRegistersManagedUnityClickListener) {
    $failures.Add(
        'The plugin registers a managed Unity onClick listener. This game build crashes in DelegateSupport.ConvertDelegate; route custom button clicks through the patched Button.OnPointerClick method instead.'
    )
}

$requiredInteropMembers = [ordered]@{
    PlotController = @(
        'ShowAuctionItem',
        'HidePlotItem',
        'FreshAuctionItem',
        'GenerateAuctionItem',
        'Update',
        'plotPanel',
        'plotItemGrid',
        'tempPlotShop',
        'nowEvent'
    )
    EventData = @('eventItemList', 'difficulty', 'randomSeed')
    IdentifyMatchController = @(
        'ShowIdentifyMatchUI',
        'HideIdentifyMatchUI',
        'SetNowChooseTreasure',
        'identifyMatchUIPanel',
        'sureButton'
    )
    ItemData = @('GetTreasureRealValue')
}

foreach ($typeName in $requiredInteropMembers.Keys) {
    $typeInspection = & $inspectScript `
        -AssemblyPath $InteropAssembly `
        -TypeName $typeName `
        -MemberPattern $requiredInteropMembers[$typeName] `
        -SkipRestore 2>&1 | Out-String
    $declaredMemberLines = @($typeInspection -split "`r?`n" | Where-Object {
        $_ -match '^\s{2}(?:public|private|protected|internal)\s+'
    })
    foreach ($memberName in $requiredInteropMembers[$typeName]) {
        $escapedMemberName = [regex]::Escape($memberName)
        $memberPattern = "(?<![A-Za-z0-9_])$escapedMemberName(?![A-Za-z0-9_])"
        if (-not ($declaredMemberLines | Where-Object { $_ -match $memberPattern } | Select-Object -First 1)) {
            $failures.Add("Required interop capability is missing: $typeName.$memberName")
        }
    }
}

if (-not $SkipRuntimeLog) {
    if (-not (Test-Path -LiteralPath $RuntimeLog -PathType Leaf)) {
        $failures.Add("Runtime log is missing: $RuntimeLog")
    }
    else {
        $logText = Get-Content -LiteralPath $RuntimeLog -Raw
        $runtimePatterns = @(
            'MissingMethodException',
            'MissingFieldException',
            'TypeLoadException',
            'HarmonyException',
            'Could not patch',
            'Unhandled exception'
        )

        foreach ($pattern in $runtimePatterns) {
            if ($logText -match $pattern) {
                $failures.Add("Runtime compatibility failure matched: $pattern")
            }
        }

        $degradedLines = @($logText -split "`r?`n" | Where-Object {
            $_ -match '\[Compatibility\].*(?::\s*|;\s*| is )(?:SKIPPED|PARTIAL|DEGRADED)\b'
        })
        foreach ($line in $degradedLines) {
            $failures.Add("Unexpected compatibility degradation: $($line.Trim())")
        }

        $requiredMarkers = @(
            'LongYin Stamina Lock loaded',
            'LongYin Battle Turbo 1.1.2 loaded',
            'LongYin Horse Stamina Multiplier 1.0.1 loaded',
            'LongYin Skip Intro 1.0.1 loaded',
            '[Compatibility] Summary:',
            '[Compatibility] Auction preview refresh: ENABLED',
            '[Compatibility] Treasure identify assist: ENABLED',
            '[Compatibility] Hero tag database: ENABLED'
        )
        foreach ($marker in $requiredMarkers) {
            if (-not $logText.Contains($marker)) {
                $failures.Add("Runtime compatibility marker is missing: $marker")
            }
        }

        $logItem = Get-Item -LiteralPath $RuntimeLog
        $livePluginRoot = Join-Path (Split-Path -Parent $RuntimeLog) 'plugins'
        if (Test-Path -LiteralPath $livePluginRoot -PathType Container) {
            $maintainedNames = @($PluginSource | ForEach-Object { "$([System.IO.Path]::GetFileNameWithoutExtension($_)).dll" })
            $newestPluginWrite = Get-ChildItem -LiteralPath $livePluginRoot -File |
                Where-Object { $maintainedNames -contains $_.Name } |
                Sort-Object LastWriteTimeUtc -Descending |
                Select-Object -First 1
            if ($newestPluginWrite -and $logItem.LastWriteTimeUtc -lt $newestPluginWrite.LastWriteTimeUtc) {
                $failures.Add("Runtime log predates the maintained live plugins: $($logItem.LastWriteTimeUtc.ToString('o')) < $($newestPluginWrite.LastWriteTimeUtc.ToString('o'))")
            }
        }
    }
}

Write-Host "Interop: $InteropAssembly"
Write-Host "Plugin sources: $($PluginSource -join ', ')"
Write-Host "Interop exposes heroTagDataBase: $interopHasHeroTagDatabase"
Write-Host "Plugin has static heroTagDataBase reference: $sourceHasStaticHeroTagReference"
Write-Host "Plugin reads private identify answer list: $sourceUsesPrivateIdentifyAnswer"
Write-Host "Plugin registers managed Unity onClick listeners: $sourceRegistersManagedUnityClickListener"

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) {
        Write-Host "ERROR: $failure" -ForegroundColor Red
    }

    exit 1
}

Write-Host 'Runtime compatibility check passed.' -ForegroundColor Green
