param(
    [string]$SourcePath = (Join-Path $PSScriptRoot '..\mod-src\LongYinProMax\LongYinProMax.cs'),
    [string]$ElectronRoot = (Join-Path $PSScriptRoot '..\electron-app')
)

$ErrorActionPreference = 'Stop'
$resolvedSourcePath = (Resolve-Path -LiteralPath $SourcePath).Path
$resolvedElectronRoot = (Resolve-Path -LiteralPath $ElectronRoot).Path
$source = Get-Content -Raw -LiteralPath $resolvedSourcePath
$visibleSettings = Get-Content -Raw -LiteralPath (Join-Path $resolvedElectronRoot 'src\shared\visible-settings.ts')
$configSource = Get-Content -Raw -LiteralPath (Join-Path $resolvedElectronRoot 'src\shared\config.ts')
$rendererSource = Get-Content -Raw -LiteralPath (Join-Path $resolvedElectronRoot 'src\renderer\settings\TradeCraftSettingsPage.tsx')
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
    if (-not [regex]::IsMatch($Scope, $Pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)) {
        $failures.Add($Message)
    }
}

$capacityPostfix = Get-CSharpMethodText 'TreasurePavilionCapacityGetMaxValuePostfix'
$multiplier = Get-CSharpMethodText 'GetTreasurePavilionCapacityMultiplier'

function Reject-Pattern {
    param([AllowEmptyString()][string]$Scope, [string]$Pattern, [string]$Message)
    if ([regex]::IsMatch($Scope, $Pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)) {
        $failures.Add($Message)
    }
}

Require-Pattern $source 'ConfigEntry<float>\s+_treasurePavilionCapacityMultiplier\b' 'Treasure pavilion capacity must use a persisted float multiplier.'
Require-Pattern $source 'Config\.Bind\s*\(\s*"TreasurePavilion"\s*,\s*"CapacityMultiplier"\s*,\s*10f\b' 'Treasure pavilion capacity must default to 10x.'
Require-Pattern $source 'typeof\(GameDataController\)[\s\S]*?nameof\(GameDataController\.GetExternalStorageMaxValue\)[\s\S]*?nameof\(TreasurePavilionCapacityGetMaxValuePostfix\)' 'The feature must patch the native external-storage item-value capacity calculation.'
Require-Pattern $source '_treasurePavilionCapacityHooksReady\s*=\s*treasurePavilionCapacityPatched' 'Compatibility readiness must depend only on the native capacity hook.'

Require-Pattern $capacityPostfix '_treasurePavilionCapacityHooksReady' 'Capacity scaling must be compatibility-gated.'
Require-Pattern $capacityPostfix 'vanillaCapacity\s*=\s*Math\.Max\(0,\s*__result\)' 'The postfix must preserve the non-negative vanilla value as its multiplication baseline.'
Require-Pattern $capacityPostfix 'vanillaCapacity\s*\*\s*\(double\)multiplier' 'The postfix must multiply the live vanilla item-value capacity.'
Require-Pattern $capacityPostfix 'Math\.Round\([\s\S]*?MidpointRounding\.AwayFromZero\)' 'Fractional results must use deterministic integer rounding.'
Require-Pattern $capacityPostfix 'Math\.Min\(int\.MaxValue[\s\S]*?Math\.Max\(0d,\s*scaledCapacity\)' 'Scaled capacity must remain within the native non-negative Int32 range.'
Require-Pattern $capacityPostfix '__result\s*=\s*appliedCapacity' 'The postfix must replace only the returned capacity value.'
Require-Pattern $capacityPostfix 'computed return value only[\s\S]*?save data unchanged' 'Runtime diagnostics must state that no save data is mutated.'
Reject-Pattern $source 'TreasurePavilionCapacityShowTradeUiPrefix|TreasurePavilionCapacityShowTradeUiFinalizer|TreasurePavilionCapacityHideTradeUiPrefix|TreasurePavilionCapacitySavePrefix|RestoreTreasurePavilionCapacity|_activeTreasurePavilionStorage' 'Legacy personal-storage mutation and rollback hooks must be removed.'
Reject-Pattern $capacityPostfix 'selfStorage|maxWeight|\.weight\b' 'Treasure pavilion capacity must not mutate personal-storage weight fields.'
Require-Pattern $multiplier 'float\.IsNaN\(configured\)[\s\S]*?float\.IsInfinity\(configured\)[\s\S]*?return\s+10f[\s\S]*?Mathf\.Clamp\(configured,\s*0\.1f,\s*999f\)' 'Invalid multipliers must fall back to 10x and valid values must be clamped to 0.1-999x.'

Require-Pattern $visibleSettings 'treasurePavilionCapacityMultiplier:\s*10\b' 'Electron defaults must expose a 10x treasure pavilion capacity.'
Require-Pattern $visibleSettings 'treasurePavilionCapacityMultiplier:\s*clamp\(input\.treasurePavilionCapacityMultiplier,\s*0\.1,\s*999\)' 'Electron sanitization must match the plugin multiplier range.'
Require-Pattern $configSource '\[TreasurePavilion\][\s\S]*?CapacityMultiplier\s*=\s*\$\{formatFloat\(settings\.treasurePavilionCapacityMultiplier\)\}' 'Electron config templates must write TreasurePavilion.CapacityMultiplier.'
Require-Pattern $configSource "getIniSectionBody\(text, 'TreasurePavilion'\)[\s\S]*?readFloat\([\s\S]*?'CapacityMultiplier'[\s\S]*?DEFAULT_VISIBLE_SETTINGS\.treasurePavilionCapacityMultiplier" 'Electron config reads must be section-scoped with the shared default.'
Require-Pattern $configSource "upsertIniSectionValue\([\s\S]*?'TreasurePavilion'[\s\S]*?'CapacityMultiplier'[\s\S]*?normalized\.treasurePavilionCapacityMultiplier" 'Electron saves must update only TreasurePavilion.CapacityMultiplier.'
Require-Pattern $rendererSource 'label="藏宝阁容量倍率"[\s\S]*?settings\.treasurePavilionCapacityMultiplier[\s\S]*?onSettingChange\(''treasurePavilionCapacityMultiplier'',\s*value\)' 'Electron must show a dedicated treasure pavilion capacity control.'
Require-Pattern $rendererSource '物品总价值上限[\s\S]*?1 倍为原版，默认 10 倍[\s\S]*?原版上限由成就数计算[\s\S]*?不改动藏宝阁物品、重量或存档中的原始数据' 'Electron must explain the actual value-capacity semantics and non-persistent multiplier.'

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ -ErrorAction Continue }
    exit 1
}

Write-Host "Treasure pavilion capacity semantic checks passed: $resolvedSourcePath"
