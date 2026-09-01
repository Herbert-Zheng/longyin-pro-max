param(
    [string]$SourcePath = (Join-Path $PSScriptRoot '..\mod-src\LongYinProMax\LongYinProMax.cs'),
    [string]$ElectronRoot = (Join-Path $PSScriptRoot '..\electron-app\src')
)

$ErrorActionPreference = 'Stop'
$source = Get-Content -Raw -LiteralPath (Resolve-Path -LiteralPath $SourcePath)
$types = Get-Content -Raw -LiteralPath (Join-Path $ElectronRoot 'shared\types.ts')
$defaults = Get-Content -Raw -LiteralPath (Join-Path $ElectronRoot 'shared\visible-settings.ts')
$config = Get-Content -Raw -LiteralPath (Join-Path $ElectronRoot 'shared\config.ts')
$page = Get-Content -Raw -LiteralPath (Join-Path $ElectronRoot 'renderer\settings\WorldExploreSettingsPage.tsx')
$failures = [System.Collections.Generic.List[string]]::new()

function Method([string]$name) {
    $escaped = [regex]::Escape($name)
    $match = [regex]::Match($source, "(?m)^    private static[^\r\n]*\b$escaped\s*\(")
    if (-not $match.Success) { $failures.Add("Could not locate C# method: $name"); return '' }
    $next = [regex]::Match($source.Substring($match.Index + $match.Length), '(?m)^    private static[^\r\n]*\b[A-Za-z_][A-Za-z0-9_]*\s*\(')
    $end = if ($next.Success) { $match.Index + $match.Length + $next.Index } else { $source.Length }
    return $source.Substring($match.Index, $end - $match.Index)
}

function Require([string]$scope, [string]$pattern, [string]$message) {
    if (-not [regex]::IsMatch($scope, $pattern, 'Singleline')) { $failures.Add($message) }
}

function Reject([string]$scope, [string]$pattern, [string]$message) {
    if ([regex]::IsMatch($scope, $pattern, 'Singleline')) { $failures.Add($message) }
}

$updateButton = Method 'TryUpdateBatchAreaUpgradeUi'
$ensureButton = Method 'EnsureBatchAreaUpgradeButton'
$click = Method 'TryBatchUpgradeCurrentArea'
$collect = Method 'CollectAreaUpgradeCandidates'
$nativeRoadCandidate = Method 'AddNativeRoadUpgradeCandidate'
$resolveRoad = Method 'ResolveAreaRoadTile'
$addCandidate = Method 'AddAreaUpgradeCandidate'
$sameTile = Method 'SameAreaTileIdentity'
$sameRoad = Method 'SameAreaRoadIdentity'
$canUpgradeRoad = Method 'CanUpgradeAreaRoad'
$nativeUpgrade = Method 'TryUpgradeAreaCandidateLikeHammer'
$nativeRoadChoice = Method 'TryInvokeNativeRoadUpgradeChoice'
$pendingRoad = Method 'TryRunPendingBatchRoadUpgrade'
$finishBatch = Method 'FinishBatchAreaUpgrade'
$tier = Method 'GetAreaBatchUpgradeTier'
$sort = Method 'CompareAreaUpgradeCandidates'

Require $source 'ConfigEntry<bool>\s+_batchAreaUpgradeEnabled' 'Batch area upgrade must have a persisted enable switch.'
Require $source 'Config\.Bind\("Construction",\s*"BatchUpgradeEnabled",\s*true' 'Batch area upgrade must default on in its own Construction section.'
Require $source 'BatchAreaUpgradeButtonName\s*=\s*"CodexBatchAreaUpgradeButton"' 'The in-game button must use a stable isolated name.'
Reject $source '_batchAreaForcedRoadTile|BatchAreaRoadSelectionPrefix' 'Batch road upgrades must leave the native random-road selector untouched.'
Require $ensureButton 'AreaBuildController[\s\S]*?buildModeButton[\s\S]*?TryCreateSafeStyledButton[\s\S]*?全部升级' 'The compact button must be attached to the active city/sect construction UI with the requested label.'
Require $updateButton 'hammerVisible\s*=\s*originalButton\.activeInHierarchy[\s\S]*?buildManagementVisible\s*=\s*hammerVisible\s*&&\s*buildController\.buildMode[\s\S]*?SetActive\(buildManagementVisible\)' 'The batch button must only be visible after the hammer has entered build-management mode.'
Require $ensureButton 'hammerRect[\s\S]*?buttonSize\s*=\s*new Vector2\(150f,\s*44f\)[\s\S]*?buttonPosition\s*=\s*hammerRect\.anchoredPosition\s*\+\s*new Vector2\([\s\S]*?hammerRect\.rect\.width[\s\S]*?buttonSize\.x[\s\S]*?\+\s*160f[\s\S]*?hammerRect\.rect\.height[\s\S]*?buttonSize\.y[\s\S]*?\)[\s\S]*?TryCreateSafeStyledButton[\s\S]*?buttonPosition' 'The compact button must be positioned to the right of the hammer beyond the adjacent native tab.'
Require $click 'AreaController\.Instance\?\.areaData[\s\S]*?CollectAreaUpgradeCandidates\(area,\s*candidates\)[\s\S]*?AddNativeRoadUpgradeCandidate\(area,\s*gameController,\s*candidates\)[\s\S]*?Sort\(CompareAreaUpgradeCandidates\)[\s\S]*?foreach[\s\S]*?TryUpgradeAreaCandidateLikeHammer' 'Batch execution must collect buildings and decoded roads, add the native road-selection fallback, sort, and visit each current-area candidate once.'
Require $collect 'area\.areaTiles[\s\S]*?tile\?\.building[\s\S]*?area\.roadTiles[\s\S]*?roadTileId[\s\S]*?ResolveAreaRoadTile\(area,\s*roadTileId\)[\s\S]*?IsRoad\s*=\s*true' 'Buildings must come from areaTiles while native road IDs from roadTiles are resolved into road candidates.'
Require $nativeRoadCandidate 'GetAreaRandomRoadTile\(area\)[\s\S]*?AreaTileType\.Road[\s\S]*?areaRoadData[\s\S]*?AddAreaUpgradeCandidate[\s\S]*?IsRoad\s*=\s*true' 'The native random-road selector must provide a deduplicated fallback candidate when roadTiles IDs cannot be decoded.'
Require $resolveRoad 'area\.areaTiles[\s\S]*?roadTileId[\s\S]*?area\.mapWidth[\s\S]*?area\.GetTile' 'Road ID resolution must support both the native areaTiles index and coordinate lookup representations.'
Require $addCandidate 'SameAreaTileIdentity[\s\S]*?SameAreaRoadIdentity' 'Candidate collection must deduplicate both duplicate tiles and the area-wide road network exposed by many road tile IDs.'
Require $sameTile 'ReferenceEquals[\s\S]*?\.Pointer[\s\S]*?areaID[\s\S]*?row[\s\S]*?column' 'Area tile identity must prefer the native pointer and safely fall back to stable coordinates.'
Require $sameRoad 'areaRoadData[\s\S]*?ReferenceEquals[\s\S]*?\.Pointer[\s\S]*?areaID' 'Road identity must collapse all visual tiles that share one area-wide AreaRoadData record.'
Reject $click 'currentTier|upgradedInTier|while\s*\(' 'One click must not repeatedly level the same high-priority target before later targets get their one attempt.'
Require $click 'foreach[\s\S]*?try[\s\S]*?TryUpgradeAreaCandidateLikeHammer[\s\S]*?catch' 'One failed building or road attempt must not abort the remaining batch candidates.'
Require $nativeUpgrade 'AreaBuildController[\s\S]*?PlayerUpgradeBuilding' 'Each batch attempt must enter through the same AreaBuildController player-upgrade method used by the hammer UI.'
Reject $nativeUpgrade '(?<!Player)UpgradeBuilding\s*\(' 'The batch helper must not bypass the hammer controller by calling AreaData.UpgradeBuilding directly.'
Reject $nativeUpgrade 'PlayerUpgradeBuilding\(null!\)' 'Road upgrades must not call PlayerUpgradeBuilding with a null building; the live game throws before completing the road transaction.'
Require $nativeUpgrade 'AreaTileType\.Road[\s\S]*?targetRoadTile\s*=\s*candidate\.Tile[\s\S]*?areaRoadData\s*=\s*targetRoadTile\.areaRoadData[\s\S]*?FindGrid\(targetRoadTile\)[\s\S]*?SetBuildTarget\([\s\S]*?QueuePendingNativeRoadUpgrade' 'Road attempts must use the exact native-selected candidate, establish the same selected-grid context as a manual hammer click, and queue the native road-upgrade choice for a later frame.'
Reject $nativeUpgrade 'SetBuildTarget\([\s\S]*?TryInvokeNativeRoadUpgradeChoice' 'The native road choice is created after SetBuildTarget returns, so it must not be invoked synchronously in the same batch stack.'
Require $nativeRoadChoice 'buildChoiceGrid[\s\S]*?GetComponentsInChildren<Button>[\s\S]*?GetComponentsInChildren<Text>[\s\S]*?升级[\s\S]*?onClick\.Invoke\(\)' 'Road upgrades must invoke the native button event so its original target and parameters match a manual hammer click.'
Reject $nativeRoadChoice 'BuildChoiceButtonClicked\(' 'Batch road upgrades must not guess the GameObject argument expected by the native button callback.'
Require $nativeRoadChoice '_batchAreaUpgradeButton[\s\S]*?continue[\s\S]*?string\.Equals\(normalized,\s*"升级",\s*StringComparison\.Ordinal\)' 'The native road-choice lookup must exclude the custom 全部升级 button and match only the exact native 升级 label.'
Reject $nativeRoadChoice 'normalized\.Contains\("升级"' 'The road-choice lookup must not treat 全部升级 as the native road 升级 action.'
Require $pendingRoad 'Time\.frameCount[\s\S]*?upgradeTimeLeft[\s\S]*?roadLv[\s\S]*?FinishBatchAreaUpgrade[\s\S]*?TryInvokeNativeRoadUpgradeChoice[\s\S]*?_pendingBatchRoadUpgradeReadyFrame' 'The queued road transaction must wait for a later frame, verify native state changed, invoke the native choice when still pending, and keep polling rather than accepting invocation alone.'
Require $pendingRoad 'upgradeTimeLeft\s*!=[\s\S]*?roadLv\s*!=[\s\S]*?TryInvokeNativeRoadUpgradeChoice' 'A queued road transaction must verify a real native state change before treating a previous choice invocation as complete.'
Require $source 'GameControllerUpdatePostfix[\s\S]*?TryRunPendingBatchRoadUpgrade\(\)' 'The game update loop must drive the queued native road transaction.'
Require $finishBatch '_batchAreaUpgradeBusy\s*=\s*false[\s\S]*?RefreshAreaBuildingChoiceInfo[\s\S]*?FreshAreaInfo\(true\)[\s\S]*?PushPlayerLog' 'Batch completion must restore the button and refresh/log only after any queued road transaction finishes.'
Require $nativeUpgrade 'CanUpgradeAreaRoad' 'Road attempts must perform a data-driven eligibility check before calling the native hammer transaction.'
Require $canUpgradeRoad 'upgradeTimeLeft[\s\S]*?roadLv\s*>=\s*10[\s\S]*?GetUpgradeTime\(\)[\s\S]*?GetUpgradeCostResource\(\)[\s\S]*?Count\s*>\s*0' 'Road eligibility must reject an in-progress or verified level-10 road and validate the native time/cost data before starting the hammer transaction.'
Require $tier 'AreaTileType\.MainBuilding[\s\S]*?forceCenter[\s\S]*?return\s+0[\s\S]*?noCancel[\s\S]*?return\s+1[\s\S]*?return\s+2' 'Priority must be main building, then non-demolishable special buildings, then ordinary buildings.'
Require $sort 'Tier\.CompareTo[\s\S]*?Row\.CompareTo[\s\S]*?Column\.CompareTo' 'Candidates in one tier must be ordered from top-left to bottom-right.'

Require $types 'batchAreaUpgradeEnabled:\s*boolean;' 'Electron VisibleSettings must carry the construction switch.'
Require $defaults 'batchAreaUpgradeEnabled:\s*true' 'Electron defaults must enable the construction switch.'
Require $config '\[Construction\][\s\S]*?BatchUpgradeEnabled\s*=\s*\$\{boolText\(settings\.batchAreaUpgradeEnabled\)\}' 'Electron must generate the Construction config section.'
Require $config 'getIniSectionBody\(text,\s*''Construction''\)[\s\S]*?readBool\([\s\S]*?''BatchUpgradeEnabled''' 'Electron must read the construction switch section-safely.'
Require $config 'upsertIniSectionValue\([\s\S]*?''Construction''[\s\S]*?''BatchUpgradeEnabled''[\s\S]*?normalized\.batchAreaUpgradeEnabled' 'Electron must persist the construction switch section-safely.'
Require $page 'label="一键升级全部建筑和道路"[\s\S]*?batchAreaUpgradeEnabled[\s\S]*?主楼[\s\S]*?特殊建筑[\s\S]*?左上到右下' 'Electron must expose and explain the complete priority contract.'

if ($failures.Count -gt 0) { $failures | ForEach-Object { Write-Error $_ -ErrorAction Continue }; exit 1 }
Write-Host "Batch area upgrade semantic checks passed."
