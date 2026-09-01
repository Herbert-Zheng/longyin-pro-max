param(
    [string]$SourcePath = (Join-Path $PSScriptRoot '..\mod-src\LongYinProMax\LongYinProMax.cs'),
    [string]$ElectronRoot = (Join-Path $PSScriptRoot '..\electron-app\src')
)

$ErrorActionPreference = 'Stop'
$source = Get-Content -Raw -LiteralPath (Resolve-Path -LiteralPath $SourcePath)
$types = Get-Content -Raw -LiteralPath (Join-Path $ElectronRoot 'shared\types.ts')
$defaults = Get-Content -Raw -LiteralPath (Join-Path $ElectronRoot 'shared\visible-settings.ts')
$config = Get-Content -Raw -LiteralPath (Join-Path $ElectronRoot 'shared\config.ts')
$page = Get-Content -Raw -LiteralPath (Join-Path $ElectronRoot 'renderer\settings\ExpTalentSettingsPage.tsx')
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

$ui = Method 'TryUpdateContinuousBookCombineUi'
$title = Method 'FindBookWriterTitleText'
$toggle = Method 'ToggleContinuousBookCombine'
$surePrefix = Method 'BookWriterSureButtonPrefix'
$surePostfix = Method 'BookWriterSureButtonPostfix'
$capture = Method 'CaptureContinuousBookCombinePlan'
$complete = Method 'QueueContinuousBookCombineAfterCompletion'
$run = Method 'TryRunPendingContinuousBookCombines'
$restore = Method 'TryRestoreContinuousBookCombineWriter'
$pair = Method 'TrySelectNextContinuousBookCombinePair'
$collectCandidates = Method 'CollectContinuousBookCombineCandidates'
$sameItem = Method 'SameContinuousBookCombineItem'
$inputAvailable = Method 'IsContinuousBookCombineInputAvailable'
$stop = Method 'StopContinuousBookCombinePlan'
$reset = Method 'ResetContinuousBookCombineWriter'
$bonusCopies = Method 'TryGrantBookWriterBonusCopies'

Require $source 'ConfigEntry<bool>\s+_continuousBookCombineEnabled' 'Continuous combine must have a persisted checkbox state.'
Require $source 'Config\.Bind\("BookWriter",\s*"ContinuousCombineEnabled",\s*false' 'Continuous combine must be opt-in by default.'
Require $source 'ContinuousBookCombineButtonName\s*=\s*"CodexContinuousBookCombineButton"' 'The in-game checkbox must have a stable isolated name.'
Require $ui 'bookWriterUI\.activeInHierarchy[\s\S]*?BookWriterType\.Combine[\s\S]*?TryCreateSafeStyledButton[\s\S]*?持续合成' 'The checkbox must only appear for the active combine-book editor.'
Require $title 'GetComponentsInChildren<Text>\(true\)[\s\S]*?char\.IsWhiteSpace[\s\S]*?编纂秘籍' 'The continuous-combine control must locate the visible 编纂秘籍 title robustly even when its characters are vertically separated.'
Require $ui 'FindBookWriterTitleText[\s\S]*?titleRect[\s\S]*?CalculateRelativeRectTransformBounds\(hostRect,\s*titleRect\)[\s\S]*?preferredHeight[\s\S]*?bounds\.min\.y\s*-\s*renderedTitleHeight\s*-\s*8f[\s\S]*?TryCreateSafeStyledButton\([\s\S]*?hostRect[\s\S]*?new Vector2\(0\.5f,\s*0\.5f\)[\s\S]*?new Vector2\(150f,\s*36f\)' 'The continuous-combine option must account for the vertically overflowing title text and render compactly below the full 编纂秘籍 title.'
Reject $ui 'new Vector2\(250f,\s*-132f\)|new Vector2\(220f,\s*48f\)' 'The continuous-combine option must not keep the old oversized center-panel placement.'
Require $toggle '_continuousBookCombineEnabled\.Value\s*=\s*!_continuousBookCombineEnabled\.Value[\s\S]*?CaptureContinuousBookCombinePlan[\s\S]*?RemoveContinuousBookCombinePlan' 'Toggling must persist the state and arm or cancel the active combine slot.'
Require $source 'class BookWriterSureButtonState[\s\S]*?BookWriterData\?\s+Writer[\s\S]*?ContinuousBookCombinePlan\?\s+Plan[\s\S]*?bool\s+WasWorking' 'The native start/cancel button hook must preserve the active slot and continuous plan state from before the original click.'
Require $surePrefix 'out\s+BookWriterSureButtonState\s+__state[\s\S]*?Plan\s*=\s*FindContinuousBookCombinePlan\(activeWriter\)[\s\S]*?WasWorking\s*=\s*activeWriter\?\.workStarted\s*\?\?\s*false[\s\S]*?!__state\.WasWorking[\s\S]*?CaptureContinuousBookCombinePlan' 'The hook must distinguish a native cancel click from a start click and must not re-arm a plan while cancellation is in progress.'
Require $surePostfix '__state\.WasWorking[\s\S]*?__state\.Plan\s*!=\s*null[\s\S]*?!__state\.Writer\.workStarted[\s\S]*?StopContinuousBookCombinePlan\([\s\S]*?player cancelled native task' 'After the original cancel succeeds, the tracked continuous slot must use the unified stop-and-reset path.'
Require $capture 'BookWriterType\.Combine[\s\S]*?GetMoneyCost\(\)[\s\S]*?BaselineMoneyCost[\s\S]*?TargetSkillId' 'The initial manually-approved combine must capture its skill and normal money cost.'
Require $complete 'WasWorking[\s\S]*?WorkPercentBefore\s*>=\s*0\.999f[\s\S]*?workCompleted\s*=\s*!writerData\.workStarted\s*\|\|\s*writerData\.workPercent\s*>=\s*0\.999f[\s\S]*?Pending\s*=\s*true' 'Only a real task transition from working to completed may queue another combine cycle.'
Require $restore 'TargetForce\.bookWriterList[\s\S]*?WriterIndex[\s\S]*?GetOwnHero\(plan\.WriterHeroId\)[\s\S]*?bookWriterHeroID\s*=\s*plan\.WriterHeroId[\s\S]*?bookWriterType\s*=\s*BookWriterType\.Combine[\s\S]*?targetSkillData\s*=\s*null[\s\S]*?plan\.Writer\s*=' 'After vanilla resets a completed slot, continuous combining must reacquire that slot and restore the same disciple and combine mode without requiring the disciple to have learned the target book skill.'
Reject $restore 'FindSkill\(' 'Combine-book restoration must not require the selected disciple to have learned the target skill; vanilla combine mode keeps targetSkillData empty.'
Require $pair 'CollectContinuousBookCombineCandidates\(plan\.TargetForce\.bookStorage[\s\S]*?plan\.TargetForce\.forceStorage[\s\S]*?writerHero\?\.itemListData[\s\S]*?writerHero\?\.selfStorage[\s\S]*?player\?\.itemListData[\s\S]*?player\?\.selfStorage[\s\S]*?BookSelectFinished\(\)[\s\S]*?CanStartWork\(\)[\s\S]*?GetMoneyCost\(\)' 'Repeat selection must inspect the same native item sources exposed by the original picker, then validate every candidate pair through vanilla rules.'
Require $collectCandidates 'source\.allItem[\s\S]*?source\.itemTypeList[\s\S]*?AddContinuousBookCombineCandidate' 'Candidate discovery must inspect both the aggregate list and the native per-type lists because book storage can keep selectable books only in itemTypeList after a day transition.'
Require $sameItem 'ReferenceEquals[\s\S]*?\.Pointer[\s\S]*?IntPtr\.Zero' 'Continuous combine item identity must compare the native IL2CPP pointer instead of relying on managed wrapper identity alone.'
Require $source 'AddContinuousBookCombineCandidate[\s\S]*?candidates\.Any\(existing\s*=>\s*SameContinuousBookCombineItem\(existing,\s*item\)\)' 'Candidate discovery must deduplicate the same native book across allItem and itemTypeList.'
Require $pair 'SameContinuousBookCombineItem\(candidates\[leftIndex\],\s*candidates\[rightIndex\]\)[\s\S]*?continue' 'A combine pair must never select the same native book twice.'
Require $inputAvailable 'bookStorage[\s\S]*?forceStorage[\s\S]*?itemListData[\s\S]*?selfStorage' 'Post-transaction verification must inspect every selectable native source for retained input books.'
Require $run 'TryRestoreContinuousBookCombineWriter\(plan\)[\s\S]*?TrySelectNextContinuousBookCombinePair\(plan,\s*out var nextMoneyCost\)[\s\S]*?nextMoneyCost\s*>\s*plan\.BaselineMoneyCost[\s\S]*?StopContinuousBookCombinePlan' 'Repeating must use a unified terminal stop path after native prerequisite checks.'
Require $run 'selectedTargetBook[\s\S]*?selectedCombineBook[\s\S]*?RefreshUI\(\)[\s\S]*?SureButtonClicked\(sureButtonObject\)[\s\S]*?IsContinuousBookCombineInputAvailable[\s\S]*?StopContinuousBookCombinePlan' 'Repeating must capture both inputs, invoke the real native transaction, verify the inputs are no longer selectable, and stop on an inconsistent transaction.'
Require $run 'HaveMoney\(\)[\s\S]*?CanStartWork\(\)' 'Repeating must also stop safely when native money or work requirements fail.'
Require $stop 'plan\.Pending\s*=\s*false[\s\S]*?ResetContinuousBookCombineWriter\(plan\)[\s\S]*?RemoveContinuousBookCombinePlan[\s\S]*?RefreshUI\(\)[\s\S]*?PushPlayerLog' 'Every terminal condition must clear pending state, reset the slot, remove the plan, refresh the UI, and notify the player.'
Require $reset 'Reset\(\)[\s\S]*?bookWriterHeroID\s*=\s*-1[\s\S]*?targetBookData\s*=\s*null[\s\S]*?combineBookData\s*=\s*null[\s\S]*?targetSkillData\s*=\s*null[\s\S]*?workPercent\s*=\s*0f[\s\S]*?workStarted\s*=\s*false' 'A stopped continuous combine must leave a completely idle native writer slot even if the original Reset is incomplete.'
Reject $reset 'bookWriterHeroID\s*=\s*plan\.WriterHeroId|bookWriterType\s*=\s*BookWriterType\.Combine' 'Terminal reset must not restore the old disciple or force the combine editor back into an active-looking state.'
Require $source '同类秘籍不足，持续合成已停止并重置' 'Insufficient books must produce an explicit player-visible stop-and-reset message.'
Require $source '☑ 持续合成|☐ 持续合成' 'The in-game option must render as a visible checked/unchecked control.'
Require $source 'class BookWriterCompletionState[\s\S]*?BookWriterType\s+WriterType' 'Book-writer completion state must preserve the original task type after vanilla resets the slot.'
Require $source 'WriterType\s*=\s*targetBookWriter\?\.bookWriterType\s*\?\?' 'The completion prefix must capture the task type before vanilla completion mutates the writer.'
Require $bonusCopies 'state\.WriterType\s*==\s*BookWriterType\.Combine[\s\S]*?return' 'Extra bookwriter copies must not replenish combine inputs, otherwise continuous combining can never exhaust its source books.'

Require $types 'continuousBookCombineEnabled:\s*boolean;' 'Electron VisibleSettings must carry the continuous-combine state.'
Require $defaults 'continuousBookCombineEnabled:\s*false' 'Electron defaults must keep continuous combining opt-in.'
Require $config '\[BookWriter\][\s\S]*?ContinuousCombineEnabled\s*=\s*\$\{boolText\(settings\.continuousBookCombineEnabled\)\}' 'Electron must generate the BookWriter checkbox state.'
Require $config 'getIniSectionBody\(text,\s*''BookWriter''\)[\s\S]*?readBool\([\s\S]*?''ContinuousCombineEnabled''' 'Electron must read the BookWriter checkbox section-safely.'
Require $config 'upsertIniSectionValue\([\s\S]*?''BookWriter''[\s\S]*?''ContinuousCombineEnabled''[\s\S]*?normalized\.continuousBookCombineEnabled' 'Electron must persist the BookWriter checkbox section-safely.'
Require $page 'label="持续合成秘籍"[\s\S]*?continuousBookCombineEnabled[\s\S]*?初次确认[\s\S]*?费用更高' 'Electron must expose the option and explain its baseline-cost stop rule.'

if ($failures.Count -gt 0) { $failures | ForEach-Object { Write-Error $_ -ErrorAction Continue }; exit 1 }
Write-Host "Continuous book combine semantic checks passed."
