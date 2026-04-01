# LongYinLiZhiZhuan Modding Notes

Game version: `1.071F`
Date captured: `2026-03-17`
Status: working BepInEx IL2CPP gameplay mod path confirmed

## Quick Summary

This game can be modded successfully with `BepInEx 6 IL2CPP` plus `Harmony` patches.

The safest proven path is:

- Harmony-only gameplay patches
- no custom injected `MonoBehaviour`
- no `AddComponent<CustomType>()`
- external config/control tools are easier than in-game custom UI for this title

## Core Build Facts

The game is an `IL2CPP` Unity build, not Mono.

Important files:

- `GameAssembly.dll`
- `LongYinLiZhiZhuan_Data\il2cpp_data\Metadata\global-metadata.dat`
- `LongYinLiZhiZhuan.exe`

Observed runtime details from BepInEx:

- Unity: `2020.3.48f1c1`
- BepInEx: `6.0.0-be.755`
- Process: `64-bit`

## Loader Findings

### What worked

- Doorstop + BepInEx can load successfully.
- Plain IL2CPP plugins load successfully.
- Harmony gameplay-method patches work.

### What initially failed

BepInEx originally crashed during Unity log bridging. This was fixed by disabling Unity log listening in:

- `BepInEx\config\BepInEx.cfg`
- `_codex_disabled_loader\BepInEx\config\BepInEx.cfg`

Key setting:

- `UnityLogListening = false`

### What definitely does not work well

Custom injected `MonoBehaviour` / `AddComponent<CustomType>()` caused startup failure on this game.

Practical conclusion:

- avoid standalone injected overlay UI
- avoid update loops implemented through custom added components
- prefer Harmony patches on existing game methods

## Current Working Mod Layout

Main prototype folder:

- `mod-prototype\README.md`
- `mod-prototype\build-il2cpp-plugin.ps1`
- `mod-prototype\build-all-mods.ps1`

Current supported launcher and packaged plugins:

- `electron-app\`
- `LongYinProMax.exe`
- `BepInEx\plugins\LongYinBattleTurbo.dll`
- `BepInEx\plugins\LongYinHorseStaminaMultiplier.dll`
- `BepInEx\plugins\LongYinQuestSnapshot.dll`
- `BepInEx\plugins\LongYinSkillTalentGrant.dll`
- `BepInEx\plugins\LongYinSkipIntro.dll`
- `BepInEx\plugins\LongYinStaminaLock.dll`

Legacy retired probes and tracers are archived and not part of the active mod payload.

## Confirmed Working Gameplay Hooks

### 1. Exploration stamina lock

Confirmed drain method:

- `ExploreController.ChangeMoveStep(int num)`
- `ExploreController.ChangeMoveStep(int num, bool showText)`

Confirmed stamina owner for map exploration:

- `ExploreController.leftPower`

Working patch strategy:

- Harmony prefix
- if `num < 0`, replace with `0`

Result:

- exploration stamina lock works reliably

### 2. Read-book EXP multiplier

Confirmed read-book entry flow:

- `ReadBookController.StartReadBook(...)`
- `ReadBookController.SureStartReadBook()`
- `ReadBookController.RealStartReadBook()`
- `ReadBookController.ShowReadBookPanel()`
- `ReadBookController.GenerateReadBookPanel()`

Confirmed reward application path:

- repeated calls to `HeroData.AddSkillBookExp(float exp, KungfuSkillLvData skill, bool ...)`

Observed behavior:

- the read-book process itself does not spam writes while placing tiles
- the reward burst happens after confirmation / finish
- `player.power` did not change inside `AddSkillBookExp`
- this means EXP reward and study stamina drain are separate concerns

Working patch strategy:

- Harmony prefix on `HeroData.AddSkillBookExp`
- multiply incoming `exp` for the player hero

Result:

- book EXP multiplier is working in the current stable setup

### 3. Character creation point multiplier

Confirmed character-creation controller:

- `StartMenuController`

Confirmed remaining point pools:

- `StartMenuController.leftAttriPoint`
- `StartMenuController.leftFightSkillPoint`
- `StartMenuController.leftLivingSkillPoint`

Confirmed starting values on the tested preset:

- attributes: `60`
- martial skills: `90`
- living skills: `90`

Confirmed point-spend entry flow:

- `StartMenuController.PlusMinusButtonClicked(GameObject buttonClicked)`
- `StartMenuController.PlusMinus(string type, int id, bool plus)`

Observed behavior from trace:

- attribute `+` clicks reached `PlusMinus("Attri", 0, true)`
- each click reduced `leftAttriPoint` by exactly `1`
- the remaining point pools live on `StartMenuController`, not only in UI text
- `SetAttriPreset(0)` restored the tested preset values cleanly

Working patch strategy:

- Harmony postfix on `StartMenuController.SetAttriPreset(int presetID)`
- Harmony postfix on `StartMenuController.ResetPlayerAttri()`
- multiply the three remaining point pools after the game initializes / resets them

Result:

- character-creation point multiplier is working in the current stable setup
- `PointMultiplier = 2` gives double starting points
- `PointMultiplier = 3` gives triple starting points

### 4. Team-stat driven test features

Confirmed from interop metadata and live test work on `2026-03-24`:

- `HeroData.GetBaseAttriNum(BaseAttriType targetAttri)` is a valid stat-read entry point
- `HeroData.totalAttri` and `HeroData.baseAttri` are also readable and indexed by `BaseAttriType`
- `HeroData.ChangeMoney(int num, bool showInfo)` is the correct runtime money-grant path for the player

Important enum finding:

- `BaseAttriType.Inte = 2`
- `BaseAttriType.Knowledge = 17`
- for the requested `智慧` test, the correct mapped stat was `Inte`, not `Knowledge`

Practical stat-read recommendation:

- if the feature should use the hero's current effective attribute, prefer `hero.totalAttri[(int)BaseAttriType.Inte]`
- if a direct list read is not safe in the current context, `hero.GetBaseAttriNum(BaseAttriType.Inte)` is a workable fallback
- keep in mind that `GetBaseAttriNum(...)` appears base-stat oriented, while `totalAttri` is better for "current final stat" style features

Confirmed current-player team aggregation path:

- start with the player hero explicitly
- then append `GetPlayerTeamMembers(player)`
- the helper already de-duplicates heroes and checks actual current team membership
- this means "all team member certain stats sum, including player" should be implemented as `player + GetPlayerTeamMembers(player)`, not teammates alone

Confirmed money-grant test shape that worked in live play:

- test behavior: press `K`
- compute `X = team sum of 智慧`
- grant `X` money to the player
- show a visible player-facing confirmation message

Hotkey note for future sessions:

- `K` is currently reserved as a test hotkey reference for this team-stat / money-grant experiment
- do not casually reuse `K` for unrelated debug actions unless this test is intentionally retired or moved

Implementation caution:

- if the plugin already patches `HeroData.ChangeMoney(...)` for bonus effects such as lucky-money logic, guard the manual grant path against recursive side effects with a dedicated flag or by temporarily suppressing the bonus handler during the test grant

Result:

- the live test mod that granted team-`智慧` sum as money on `K` was confirmed fully working
- this establishes a proven path for future features based on single-character stats and team-stat sums

### 5. Custom talent system and bookwriter stat reading

Confirmed custom talent flow:

- custom talents are loaded from `BepInEx\config\codex.longyin.custom-talents.json`
- each entry is registered as a runtime `HeroTagDataBase` with marker `codex.custom-talent:<id>`
- the mod evaluates the player on a short interval from `GameController.Update`
- if a talent's conditions become true, the mod grants the tag with `HeroData.AddTempTag(...)` and falls back to `HeroData.AddTag(...)` if needed
- if the conditions stop being true, the mod removes the matching tag instances from the hero

Confirmed stat-read path used by both custom talents and bookwriter math:

- `TryReadHeroAttribute(HeroData hero, BaseAttriType attriType)` is the shared helper
- it reads `hero.totalAttri[(int)attriType]` first
- then it falls back to `hero.GetBaseAttriNum(attriType)`
- then it falls back to `hero.baseAttri[(int)attriType]`

Confirmed team-stat path used by custom talents:

- `TryReadTeamAttributeSum(player, attriType)` sums the player plus `GetPlayerTeamMembers(player)`
- this is the clean pattern when a condition should depend on the whole party instead of a single hero

Bookwriter implementation note:

- the manuscript-copy flow is a separate subsystem from the normal read-book EXP flow
- the correct bookwriter hooks are `BookWriterUIController.SureButtonClicked`, `BookWriterData.GetTotalTimeCost`, `BookWriterData.GetEachDayWorkPercent`, and `GameController.ManageBookWriter`
- if `BookWriterData.GetBookWriterHero()` ever returns null, fall back to `bookWriterHeroID` and resolve the hero through `GameController.Instance.worldData.GetHero(...)`
- the stat-based time formula being tested is:
  - `X = Inte * 0.5 + ((Agl + Wil) * 0.25)`
  - `Y = 100 - X`
  - clamp `Y` to a minimum of `1`
  - scale the time cost by `Y / 100`
  - round the final day cost to the nearest whole day, with a minimum of `1`
- the extra finished-book quantity can be granted cleanly from the completion manager instead of tracing UI display code:
  - when `GameController.ManageBookWriter(...)` advances a working task into completion, call `BookWriterData.GetWorkResult()`
  - keep the vanilla reward as the first copy
  - for validation, the current implementation grants a fixed `+1` extra cloned book
  - the correct destination for all writers is the force book storage, using `ForceData.BookStorageAddBook(clonedResult, false)`
  - this applies to any character / any book-writing event, not only the player inventory path

Practical mapping:

- `智慧` -> `BaseAttriType.Inte`
- `灵敏` -> `BaseAttriType.Agl`
- `意志` -> `BaseAttriType.Wil`

## Current User-Facing Control Path

The in-game custom menu experiment should be treated as failed for this game.

Current supported path:

- external control app edits stable mod config directly
- do not rely on the legacy in-game panel
- if old notes or old code mention the in-game panel, prefer the external tool instead

Use:

- `Open-Mod-Control.cmd`

The external tool currently controls:

- exploration stamina lock on/off
- read-book EXP multiplier integer value
- character-creation point multiplier integer value
- trace mode on/off
- freeze date on/off
- freeze date hotkey choice
- optional game launch

Stable config file:

- `BepInEx\config\codex.longyin.staminalock.cfg`

Current stable keys:

- `LockStamina = true/false`
- `ExpMultiplier = <integer>`
- `PointMultiplier = <integer>`
- `FreezeDate = true/false`
- `ToggleFreezeDateHotkey = <keycode>`

## Current Player Notification Path

Player-facing mod messages are now confirmed working, but not through the left-side area feed.

Confirmed working path:

- `GameController.ShowTextOnMouse(...)`
- this produces visible floating text near the cursor / map area
- this is good enough for gameplay notifications, warnings, reminders, and debug prompts

Important limitation:

- mod messages were accepted by `InfoController`, `HeroData.AddLog(...)`, and sometimes `AreaData.AddLog(...)`
- however, those calls did not reliably appear in the left-side feed during live testing
- do not assume the left-side log is the active player-visible channel for mod notices

Practical conclusion:

- use cursor/world popup text as the stable notification surface for now
- treat left-side feed delivery as a separate unresolved UI hook

## Character Detail / Fame Tier Findings

Confirmed live-game findings from the `K` hotkey test path:

- `HeroDetailController.ShowHeroDetail(...)`
- `HeroDetailController.SetHeroDetail(...)`
- `HeroDetailController.FreshNowHeroDetail(...)`
- `HeroDetailController.mainShowHero`
- `HeroDetailController.nowShowHero`

Practical conclusion:

- these are reliable hooks for "currently viewing character" on the character detail screen

Confirmed reputation path:

- `HeroData.fame`
- `HeroData.ChangeFame(...)`

Practical conclusion:

- the viewed character's displayed reputation is `fame`, not `favor`
- changing `favor` only changes relationship rating, which is the wrong stat for the reputation/tier experiments

Confirmed tier / rank path:

- `HeroData.heroForceLv`
- `HeroData.GetHeroForceLvDescribeSimplify()`
- `HeroData.CheckHeroFameForceLv()`
- `HeroData.GetFameForceLv()`
- `HeroData.ChangeHeroForceLv(...)`
- `HeroData.SetHeroForceLv(...)`

Practical conclusion:

- player-character tier can follow fame gain directly
- sect-affiliated NPC tier appears to remain managed by sect logic; fame gain alone did not force a visible tier upgrade in testing
- sect-less NPCs (for example `游侠 / 大侠 / 宗师` style 江湖人士) can be promoted by reading the fame-derived target with `GetFameForceLv()` and then applying `ChangeHeroForceLv(...)` or `SetHeroForceLv(...)`
- if a future mod wants reliable fame-tier promotion, branch sect NPCs and sect-less NPCs separately

## Dialog / Plot Handling Notes

These notes are from the confirmed chest-choice and NPC dialog work.

### Proven vanilla dialog close path

For a normal NPC leave / `[bye bye]` close, the traced sequence was:

- `PlotController.PlotTextShowFinished()`
- `PlotController.PlotChoiceShowFinished()`
- `PlotController.HideInteractUI()`
- `PlotController.HideInteractUIBase()`

Practical conclusion:

- if a custom plot-style dialog needs to close cleanly, prefer reusing the game's own plot close flow
- do not start with manual GameObject hiding or raw panel state mutation unless the normal plot close path fails

## Repo Memory Snapshot

This repository is the portable source-of-truth backup for the modded `LongYinLiZhiZhuan` setup.

Current working assumptions to preserve:

- GitHub repo: `Zhihong0321/longyin_plus`
- `dist/` is the install overlay that gets copied into a clean game root
- `run_this_first.ps1` and `run_this_first.cmd` are the supported install entry points
- the repo should keep mod source, packaging scripts, and install notes
- the repo should not store the base game itself or Steam-managed game assets
- do not create or upload work-report files for this project

### Treasure chest choice findings

Normal open-treasure tiles are not the same system as digging treasure.

Confirmed split:

- digging choice path:
  - `ExploreController.ManageTileEvent(event=6)`
  - `PlotController.ChangePlot(...)`
  - `PlotController.ChooseDigTreasure(...)`
  - `PlotController.DigTreasureChoosen()`
- normal treasure chest reward path:
  - `HeroData.GetItem(... treasureChestClickTime=3)`

Practical conclusion:

- do not reuse `ChooseDigTreasure(...)` for normal chest behavior
- chest mods should hook the chest reward path only
- digging `event=6` should be left alone unless the goal is specifically to mod digging

### Choice-row click behavior

Important behavior from live testing:

- clicking a choice row updates the game selection
- that click does not necessarily confirm the choice by itself
- the game's advance / auto-continue path uses the latest selected row correctly

Practical conclusion:

- when building choose-one dialogs on top of the game's plot UI, separate `selection` from `confirmation`
- if row click needs to immediately finish the dialog, it is safer to trigger the same confirm/advance path the game already uses after the selection has settled
- avoid assuming `nowChoice` is updated on the same frame as the click; delayed follow-up checks may be required

### Custom plot choice construction

Confirmed safe direction:

- `SinglePlotChoiceData()` parameterless constructor
- assign fields directly:
  - `choiceText`
  - `callFuc`
  - `callParam`
  - `describe`
  - `inited = true`
- `SinglePlotData` with:
  - `plotText`
  - `noAutoJump = true`
  - `clickCallFuc = string.Empty`
  - `choices = choiceDataList`

Avoid:

- relying on constructor overload assumptions without trace confirmation
- assuming row click alone means the dialog will close

### Trace workflow for dialogs

Best targeted method:

1. trace one exact dialog family only
2. capture both open and close calls
3. compare a known-good vanilla close flow against the custom dialog flow
4. only then wire the custom dialog to the confirmed close sequence

This was much more reliable than broad tracing or trying to infer the correct close path from field names alone.

## What Was Tried And Did Not Work Well

### Failed or poor-fit approaches

- custom `MonoBehaviour` injection via `AddComponent`
- standalone in-game overlay style UI
- Cheat Engine write tracing for stamina on this game, because it froze the game during writes

### Ambiguous / not worth relying on yet

- in-game custom menu injection on arbitrary screens
- heavy UI extension work without reusing existing game UI more carefully

## Unresolved Areas

### Study stamina lock for book learning

This is not solved yet.

Important finding:

- study stamina drain is not applied through `HeroData.AddSkillBookExp`
- it also did not appear in the earlier `HeroData.ChangePower(...)` trace

Meaning:

- the final EXP hook is known
- the read/study stamina drain still needs a deeper targeted trace

### Better UI control surface

If a future session wants an in-game settings UI again, do not start with standalone overlay ideas.

Better direction:

- piggyback on an existing game menu or panel
- reuse existing built-in UI objects only
- avoid custom injected components

### Left-side feed notification hook

This is still unresolved.

Current finding:

- the game accepts several log-style calls, but they do not reliably show up in the same left-side feed the player sees during normal gameplay
- the working fallback is `GameController.ShowTextOnMouse(...)`

Meaning:

- player notification support exists now
- exact replication of the native left-side feed still needs targeted tracing

## Reverse Engineering Tips For Future Sessions

### Best workflow that actually worked

1. Use Harmony-only trace builds.
2. Keep traces narrow and session-scoped.
3. Ask the player to do exactly one action, then quit.
4. Read `BepInEx\LogOutput.log`.
5. Promote confirmed paths into the stable plugin.

### Good candidate classes for future work

- `ExploreController`
- `ReadBookController`
- `StudySkillController`
- `StartMenuController`
- `AttriPresetData`
- `HeroData`
- `KungfuSkillLvData`

### Useful string discoveries from interop scan

Read-book related:

- `StartReadBook`
- `SureStartReadBook`
- `RealStartReadBook`
- `ReadBookChoosen`
- `ChooseReadBook`
- `ChooseReadBookMoney`
- `ShowReadBookPanel`
- `GenerateReadBookPanel`
- `FinishReadBook`
- `BookSelectFinished`

Study related:

- `SureStartStudySkill`
- `RealStartStudySkill`
- `FinishStudySkill`
- `StudyDayCost`
- `StudyMoneyCost`

Character-creation related:

- `ShowStartMenu`
- `SetAttriPreset`
- `ResetPlayerAttri`
- `PlusMinusButtonClicked`
- `PlusMinus`
- `RandomPlayerBaseAttri`
- `RandomPlayerBaseFightSkill`
- `RandomPlayerBaseLivingSkill`
- `leftAttriPoint`
- `leftFightSkillPoint`
- `leftLivingSkillPoint`

### Legacy tracing status

The old tracing and probe modules are retired.

- they are not part of the supported Electron workflow
- they are not part of the packaged `dist/` payload
- any historical tracer assets should stay under `archive/`, not in active mod folders
- useful stuck-dialog logging should include the controller field dump and the controller game object tree so hidden continue/next UI can be spotted
- forced fast-forward can wedge on treasure/dig choice branches such as `ChooseDigTreasure`; in that case, a branch-level guard is better than only turning skip off temporarily because `PlotController.Update` may reapply it on the next frame
- the same family of wedge also appears on lock-chest choice branches such as `OpenLockChest`; keep these treasure-choice call paths out of the forced skip reapply logic
- if a dialog has an active choice object (`nowChoice` or `newChoice`), do not force skip at all; this preserves the normal exit choice for city greetings and other choice-driven dialogs that can otherwise lose their "bye bye" option
- even better than “do not force skip” is to explicitly release skip when a choice UI appears, because a stale skip state can survive into the choice screen and suppress the exit choice even if the reapply logic is already blocked
- when a treasure-chest session is already active, the log can show `Skipped treasure chest choice because another chest choice session is already active.`; that is a separate lockup family from the text-only fast-forward wedge
- manual rescue key: `DialogFlow/EmergencyUnstuckHotkey` clears forced fast-forward, turns off auto/skip on the current `PlotController`, and tries to release the active treasure-chest session so a wedged dialog can recover
- keep the rescue key separate from the normal `P` fast-forward toggle; the rescue path is for emergencies, not as the default dialog control

## Build / Deploy Commands

Build all split plugins:

```powershell
powershell -ExecutionPolicy Bypass -File .\mod-prototype\build-all-mods.ps1
```

Build one plugin:

```powershell
powershell -ExecutionPolicy Bypass -File .\mod-prototype\build-il2cpp-plugin.ps1 `
  -Source .\mod-prototype\<PluginFolder>\<PluginSource>.cs `
  -Output .\mod-prototype\<PluginFolder>\artifacts\<PluginName>.dll `
  -StagedPluginOutput .\_codex_disabled_loader\BepInEx\plugins\<PluginName>.dll `
  -LivePluginOutput .\BepInEx\plugins\<PluginName>.dll
```

## Recommended Starting Point For A New Session

If starting fresh in a future session:

1. Read this file first.
2. Read the active Electron launcher source under `electron-app\`.
3. Use `LongYinProMax.exe` for user-facing settings and game launch.
4. Keep legacy tracer assets archived and out of active payloads.
5. Do not spend time retrying custom `MonoBehaviour` injection unless there is a strong reason.

## Bottom Line

For `LongYinLiZhiZhuan 1.071F`, the best proven modding path is:

- `BepInEx IL2CPP` loader
- Harmony gameplay hooks
- external config / helper tools
- no custom injected Unity behaviour types

This path already produced a working stable mod with:

- exploration stamina lock
- read-book EXP multiplier
- character-creation point multiplier
