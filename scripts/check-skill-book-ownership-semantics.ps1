param(
    [string]$SourcePath = (Join-Path $PSScriptRoot '..\mod-src\LongYinProMax\LongYinProMax.cs'),
    [string]$ElectronRoot = (Join-Path $PSScriptRoot '..\electron-app\src')
)

$ErrorActionPreference = 'Stop'
$resolvedSourcePath = (Resolve-Path -LiteralPath $SourcePath).Path
$resolvedElectronRoot = (Resolve-Path -LiteralPath $ElectronRoot).Path
$source = Get-Content -Raw -LiteralPath $resolvedSourcePath
$typesSource = Get-Content -Raw -LiteralPath (Join-Path $resolvedElectronRoot 'shared\types.ts')
$visibleSettingsSource = Get-Content -Raw -LiteralPath (Join-Path $resolvedElectronRoot 'shared\visible-settings.ts')
$configSource = Get-Content -Raw -LiteralPath (Join-Path $resolvedElectronRoot 'shared\config.ts')
$expTalentSource = Get-Content -Raw -LiteralPath (Join-Path $resolvedElectronRoot 'renderer\settings\ExpTalentSettingsPage.tsx')
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

$updatePostfix = Get-CSharpMethodText 'SkillBookOwnershipUpdatePostfix'
$resolveVisibleSkillMethod = Get-CSharpMethodText 'ResolveVisibleSkillDetailId'
$resolveBookItemSkillMethod = Get-CSharpMethodText 'TryResolveSkillBookItemId'
$resolveListSkillMethod = Get-CSharpMethodText 'TryResolveSkillIconListId'
$resolveLabelSkillMethod = Get-CSharpMethodText 'TryResolveSkillIdFromLabels'
$titleMatchMethod = Get-CSharpMethodText 'VisibleSkillTitleMatches'
$visibleDescriptionMethod = Get-CSharpMethodText 'TryApplySkillBookOwnershipToVisibleDescription'
$nguiDescriptionMethod = Get-CSharpMethodText 'TryApplySkillBookOwnershipToNguiLabels'
$unityDescriptionMethod = Get-CSharpMethodText 'TryApplySkillBookOwnershipToUnityLabels'
$buildDescriptionMethod = Get-CSharpMethodText 'TryBuildSkillBookOwnershipDescription'
$removeDescriptionMethod = Get-CSharpMethodText 'RemoveSkillBookOwnershipDescription'
$practiceStatusMethod = Get-CSharpMethodText 'FindSkillPracticeStatusInsertionIndex'
$highestOwnedMethod = Get-CSharpMethodText 'FindHighestOwnedSkillBook'
$itemListMethod = Get-CSharpMethodText 'FindHighestSkillBookInItemList'
$showRoomMethod = Get-CSharpMethodText 'FindHighestSkillBookInShowRoom'
$qualityMethod = Get-CSharpMethodText 'GetSkillBookQualityName'

Require-Pattern $source 'ConfigEntry<bool>\s+_skillBookOwnershipIndicatorEnabled\b' 'Skill book ownership must expose a persisted enabled switch.'
Require-Pattern $source 'Config\.Bind\s*\(\s*"SkillDisplay"\s*,\s*"BookOwnershipIndicatorEnabled"\s*,\s*true\b' 'Skill book ownership must be enabled by default in the SkillDisplay section.'
Require-Pattern $source 'PatchMethod\(\s*typeof\(QuickDetail\),\s*"Update"\s*,\s*Type\.EmptyTypes\s*,\s*null\s*,\s*nameof\(SkillBookOwnershipUpdatePostfix\)\)' 'The feature must use the Unity QuickDetail.Update entry point instead of an IL2CPP-inlined private builder.'
Require-Pattern $updatePostfix 'skillDetailVisible\s*=\s*__instance\.skillDetail\s*!=\s*null\s*&&\s*__instance\.skillDetail\.activeInHierarchy[\s\S]*?bookDetailVisible\s*=\s*__instance\.bookDetail\s*!=\s*null\s*&&\s*__instance\.bookDetail\.activeInHierarchy[\s\S]*?descriptionVisible\s*=\s*__instance\.describeGrid\s*!=\s*null\s*&&\s*__instance\.describeGrid\.activeInHierarchy[\s\S]*?if\s*\(\s*!skillDetailVisible\s*&&\s*!bookDetailVisible\s*&&\s*!descriptionVisible\s*\)[\s\S]*?ResetSkillBookOwnershipAppliedLabel\(\)[\s\S]*?return[\s\S]*?ResolveVisibleSkillDetailId[\s\S]*?_skillBookOwnershipAppliedSkillId\s*==\s*skillId[\s\S]*?IndexOf\("功法书："[\s\S]*?TryApplySkillBookOwnershipToVisibleDescription' 'The update hook must accept learned-skill, backpack-book, and runtime describe-grid detail roots, reject when all are hidden, remain idempotent, and apply the resolved skill ID.'
Require-Pattern $resolveVisibleSkillMethod 'MouseController\.hoveredObject[\s\S]*?nowShowObject[\s\S]*?TryResolveSkillBookItemId\(hoveredObject\)[\s\S]*?TryResolveSkillBookItemId\(shownObject\)[\s\S]*?skillLvData\?\.skillID[\s\S]*?TryResolveSkillIconListId\(quickDetail, hoveredIcon\)[\s\S]*?TryResolveSkillIconListId\(quickDetail, shownIcon\)[\s\S]*?TryResolveSkillIdFromVisibleLabels' 'Skill resolution must prefer a hovered or shown book item, then direct skill data, the target-hero list slot, and finally visible-title matching.'
Require-Pattern $resolveBookItemSkillMethod 'TryFindItemIconController[\s\S]*?itemData\s*=\s*itemIcon\?\.itemData[\s\S]*?if\s*\(\s*itemData\s*==\s*null\s*\|\|\s*itemData\.type\s*!=\s*ItemType\.Book\s*\)[\s\S]*?return\s+-1[\s\S]*?return\s+itemData\.bookData\?\.skillID\s*\?\?\s*-1' 'Backpack and storage book tooltips must reject null or non-book items and resolve valid skill IDs from ItemIconController.itemData.bookData.'
Require-Pattern $resolveListSkillMethod 'GetTargetHero\(\)[\s\S]*?kungfuSkills[\s\S]*?listId\s*>=\s*0[\s\S]*?listId\s*<\s*skills\.Count[\s\S]*?skills\[listId\]\?\.skillID[\s\S]*?TryFindHeroSkill\(targetHero, listId\)' 'The list-slot fallback must resolve the target hero, bounds-check SkillIconController.skillListID, and retain the legacy skill-ID compatibility lookup.'
Require-Pattern $resolveListSkillMethod 'catch\s*\(Exception ex\)[\s\S]*?LogSkillBookOwnershipLookupFailure' 'Compatibility failures in target-hero/list-slot resolution must be logged through the one-shot skill-display warning.'
Require-Pattern $resolveLabelSkillMethod 'VisibleSkillTitleMatches\(label\.text, skillName\)' 'The final visible-label fallback must require a strict skill-title match for both label implementations.'
Require-Pattern $titleMatchMethod 'string\.Equals\([\s\S]*?StripVisibleTextFormatting\(labelText\)\.Trim\(\)[\s\S]*?StripVisibleTextFormatting\(skillName\)\.Trim\(\)[\s\S]*?StringComparison\.Ordinal' 'The title fallback must compare the full formatting-stripped title, not search for a skill-name substring in detail text.'
if ($resolveLabelSkillMethod -match 'IndexOf\s*\(\s*skillName') {
    $failures.Add('The title fallback must not use IndexOf(skillName), which can match unrelated skill names inside the full detail text.')
}
Require-Pattern $visibleDescriptionMethod 'TryApplySkillBookOwnershipToNguiLabels\(quickDetail\.skillDetail[\s\S]*?TryApplySkillBookOwnershipToNguiLabels\(quickDetail\.describeGrid[\s\S]*?TryApplySkillBookOwnershipToUnityLabels\(quickDetail\.skillDetail[\s\S]*?TryApplySkillBookOwnershipToUnityLabels\(quickDetail\.describeGrid[\s\S]*?quickDetail\.gameObject' 'The visible description updater must cover the original skill roots and both NGUI and Unity text implementations.'
Require-Pattern $nguiDescriptionMethod 'GetComponentsInChildren<UILabel>\(includeInactive:\s*true\)[\s\S]*?supportEncoding\s*=\s*true[\s\S]*?_skillBookOwnershipAppliedNguiLabel' 'NGUI skill labels must preserve encoded color text and remember the applied label.'
Require-Pattern $unityDescriptionMethod 'GetComponentsInChildren<Text>\(includeInactive:\s*true\)[\s\S]*?supportRichText\s*=\s*true[\s\S]*?_skillBookOwnershipAppliedUnityLabel' 'Unity skill labels must preserve rich color text and remember the applied label.'
Require-Pattern $buildDescriptionMethod '功法书：[\s\S]*?BuildSkillBookOwnershipLabel[\s\S]*?RemoveSkillBookOwnershipDescription[\s\S]*?FindSkillPracticeStatusInsertionIndex[\s\S]*?practiceStatusEnd\s*>=\s*0[\s\S]*?Shift查看详情[\s\S]*?装备效果' 'The status must replace an existing ownership fragment and prefer the learned/unlearned status before the Shift and equipment fallbacks.'
Require-Pattern $buildDescriptionMethod 'practiceStatusEnd\s*>=\s*0[\s\S]*?descriptionWithoutOwnership\.Insert\(\s*practiceStatusEnd\s*,\s*\$"\\n\{Marker\}\{ownershipText\}"\s*\)' 'The ownership status must render on its own line immediately below the learned/unlearned status.'
Require-Pattern $removeDescriptionMethod 'IndexOf\(marker[\s\S]*?currentText\[markerIndex\s*-\s*1\]\s*==\s*''　''[\s\S]*?IndexOf\("</color>"[\s\S]*?currentText\.Remove' 'Idempotent updates must remove the prior colored ownership fragment and its separator before choosing the current insertion point.'
Require-Pattern $practiceStatusMethod '已修习[\s\S]*?未修习[\s\S]*?已习得[\s\S]*?未习得[\s\S]*?statusText\.Length[\s\S]*?IndexOf\("\[-\]"[\s\S]*?IndexOf\("</"[\s\S]*?IndexOf\(''>''' 'The preferred insertion point must recognize all learned/unlearned wording variants, use the matched token length, and advance beyond adjacent NGUI or HTML closing tags.'

Require-Pattern $highestOwnedMethod 'FindHighestSkillBookInItemList\(player\??\.itemListData[\s\S]*?player\.selfStorage[\s\S]*?player\.GetForce\(false\)[\s\S]*?playerForce\.bookStorage[\s\S]*?FindHighestSkillBookInShowRoom\(playerForce\.showRoomItems' 'Ownership must merge the backpack, personal storage, current sect book storage, and every exhibition-room shelf.'
Require-Pattern $itemListMethod 'itemList\?\.allItem[\s\S]*?ItemType\.Book[\s\S]*?item\.bookData\?\.skillID\s*!=\s*skillId[\s\S]*?IsHigherQualitySkillBook' 'Flat item-list lookup must filter by BookData.skillID and retain the highest-quality matching copy.'
Require-Pattern $showRoomMethod 'TryGetCollectionCount\(showRoomItems\)[\s\S]*?shelfIndex[\s\S]*?TryGetIndexedValue\(showRoomItems, shelfIndex\)[\s\S]*?TryGetCollectionCount\(shelf\)[\s\S]*?itemIndex[\s\S]*?TryGetIndexedValue\(shelf, itemIndex\)[\s\S]*?IsHigherQualitySkillBook' 'Exhibition-room lookup must visit every IL2CPP shelf and compare every matching book.'
Require-Pattern $qualityMethod 'GetBookRareLvName\(\)[\s\S]*?rareLv[\s\S]*?品' 'Owned-book display must use the game quality name with a deterministic rarity fallback.'
Require-Pattern $source '<color=#8FD17A>已拥有（最高：\{qualityName\}）</color>' 'Owned skill books must be green and state the highest owned quality.'
Require-Pattern $source '<color=#F08A6A>未拥有</color>' 'Missing skill books must be shown in red.'

Require-Pattern $typesSource 'skillBookOwnershipIndicatorEnabled:\s*boolean;' 'The ownership switch must be a required VisibleSettings field so every process carries it explicitly.'
Require-Pattern $visibleSettingsSource 'skillBookOwnershipIndicatorEnabled:\s*true' 'The shared visible-settings defaults must enable the ownership indicator.'
Require-Pattern $configSource '\[SkillDisplay\][\s\S]*?BookOwnershipIndicatorEnabled\s*=\s*\$\{boolText\(settings\.skillBookOwnershipIndicatorEnabled\)\}' 'Electron must write the ownership switch into the SkillDisplay config section.'
Require-Pattern $configSource 'getIniSectionBody\(text,\s*''SkillDisplay''\)[\s\S]*?readBool\(\s*skillDisplaySection,\s*''BookOwnershipIndicatorEnabled''' 'Electron must read the ownership switch from the SkillDisplay config section.'
Require-Pattern $configSource 'upsertIniSectionValue\(\s*nextMain,\s*''SkillDisplay'',\s*''BookOwnershipIndicatorEnabled'',\s*boolText\(normalized\.skillBookOwnershipIndicatorEnabled\)' 'Electron must persist edits to the ownership switch.'
Require-Pattern $expTalentSource 'label="显示功法书拥有状态"[\s\S]*?onSettingChange\(''skillBookOwnershipIndicatorEnabled'', value\)[\s\S]*?展览室[\s\S]*?最高品质' 'Electron must explain that ownership includes the exhibition room and reports the highest quality.'

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ -ErrorAction Continue }
    exit 1
}

Write-Host "Skill book ownership semantic checks passed: $resolvedSourcePath"
