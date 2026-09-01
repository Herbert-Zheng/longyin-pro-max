# About Modding Game Data

## Purpose

This note captures a read-only investigation into whether `龙胤立志传 Pro Max` can support future features that modify game data, especially the kinds of data described in forum posts about editing `HeroTagData`, `KungFuData`, and `PlotData`.

This was not an implementation pass. The goal was only to determine feasibility, identify likely integration points, and leave a practical starting point for future work.

## Short Conclusion

Yes, the mod can very likely support game-data editing features without depending on manual `resources.assets` dump/import every time.

The game exposes runtime-accessible in-memory databases and hero APIs that strongly suggest we can:

- modify existing talent/tag definitions in memory
- append new talent/tag definitions at startup
- modify kungfu / skill definitions in memory
- modify or inject plot data in memory
- grant newly defined tags to heroes at runtime

This would still be version-sensitive, but it should be much more maintainable than repeatedly editing `resources.assets` by hand after every game update.

## What Prompted This Investigation

A forum workflow described editing dumped CSV-like data from `resources.assets`, for example:

- `HeroTagData` for talents
- `KungFuData` for martial skills
- `PlotData` for plot text

The forum method was:

1. export dump from `resources.assets`
2. edit the Chinese-configured row text manually
3. import dump back into the asset
4. save the asset
5. add the talent ID into the save data

That proves the source data exists in asset tables. The key question for the mod was whether we can reach the same data through runtime code instead of patching assets directly.

## High-Confidence Findings

### 1. The game exposes runtime databases through `GameDataController`

From the IL2CPP interop metadata in [Assembly-CSharp.dll](G:\Steam\steamapps\common\LongYinLiZhiZhuan\BepInEx\interop\Assembly-CSharp.dll), `GameDataController` owns in-memory database lists including:

- `heroTagDataBase`
- `kungfuSkillDataBase`
- `PlotDataBase`
- `HeroNatureTalkTextDataBase`
- `HeroSpeTalkTextDataBase`
- `resourcePointDataBase`

Relevant methods exposed on `GameDataController` include:

- `LoadAllGameData()`
- `LoadSkillData(LTCSVLoader, int, bool)`
- `GetSkillDataBase(int)`
- `GetTagDataBase(int)`
- `GetTagID(string)`
- `WriteGameDataCsv()`

This is the biggest evidence that game data is loaded into mutable runtime structures we can potentially patch after startup.

### 2. `LTCSVLoader` exists and looks like the game's table parser

The interop metadata also exposes `LTCSVLoader` with methods such as:

- `ReadFile(string)`
- `ReadMultiLine(string)`
- `GetRow()`
- `GetCol()`
- `GetValueAt(int, int)`
- `GetFirstIndexAtCol(...)`
- `GetFirstIndexAtRow(...)`

That strongly suggests the asset-backed data is being parsed from CSV-like text into runtime objects.

This aligns with the forum screenshot and dump-edit workflow.

### 3. Talent/tag definitions are split into definition data and runtime hero data

There are two important tag-related types:

- `HeroTagDataBase`
  This looks like the definition/template row for a tag.
- `HeroTagData`
  This looks like the runtime instance applied to a hero.

`HeroTagDataBase` exposes fields and properties like:

- `name`
- `value`
- `effectTarget`
- `sameMeaning`
- `oppositeMeaning`
- `canRandom`
- `requirement`
- `replaceTag`
- `category`
- `buffData`
- `showRightLine`
- `order`

This maps very closely to the forum idea of adding a new talent row with human-readable fields.

### 4. Heroes already support runtime tag management

`HeroData` exposes:

- `heroTagData`
- `heroTagPoint`
- `GetTotalTagPoint()`
- `HaveTag(int)`
- `FindTag(int)`
- `AddTag(int id, float time, string source, bool showInfo, bool needFreshHeroDetail)`
- `AddTempTag(HeroTagDataBase tempTag, int time, bool showInfo)`
- `RemoveTag(...)`
- `UnderstandTag(...)`
- `ChangeTagPoint(...)`

This is critical. It means the game already has native code paths for applying tag data to a hero at runtime.

So a future feature would not need to invent a new system for hero talents. It would be extending existing game behavior.

### 5. Kungfu data is also runtime-accessible

The forum name `KungFuData` appears to correspond to `KungfuSkillData` in code.

`KungfuSkillData` exposes fields such as:

- `skillID`
- `name`
- `describe`
- `type`
- `rareLv`
- `manaCost`
- `baseDamage`
- `expRatio`
- `addDamageRatio`
- `skillNeeds`
- `upgradeAddData`
- `equipAddData`
- `useAddData`
- `attackRangeData`
- `damageRangeData`
- `battleMaxUseTime`
- `hide`

`GameDataController.GetSkillDataBase(int)` returns `KungfuSkillData`.

This makes skill-data patching a realistic future path.

### 6. Plot data is also runtime-accessible and already proven in our mod code

The game exposes:

- `PlotData`
- `SinglePlotData`
- `SinglePlotChoiceData`
- `PlotController`

Our current mod already patches plot-related functions in `mod-src/LongYinProMax/LongYinProMax.cs`:

- line 242 patches `PlotController.ChangePlotDataBase`
- line 247 patches `PlotController.ShowPlot`
- line 248 patches `PlotController.ShowSinglePlot`

The mod also already constructs custom plot objects:

- `mod-src/LongYinProMax/LongYinProMax.cs`

And the existing notes confirm direct construction is viable:

- [MODDING-NOTES-1.071F.md:304](MODDING-NOTES-1.071F.md#L304)
- [MODDING-NOTES-1.071F.md:305](MODDING-NOTES-1.071F.md#L305)
- [MODDING-NOTES-1.071F.md:311](MODDING-NOTES-1.071F.md#L311)

So plot editing is not just theoretical. We already know the mod can interact with this system.

## Practical Interpretation Of The Forum Method

The forum workflow appears to be editing the source text table that the game later parses into runtime objects.

In mod terms, that likely means:

- the asset dump contains the source rows
- the game loads those rows through `LTCSVLoader`
- `GameDataController.LoadAllGameData()` transforms them into objects such as `HeroTagDataBase`, `KungfuSkillData`, and `PlotData`

If this reading is correct, then a mod does not need to patch the asset file itself. It can instead:

1. wait for game data load to complete
2. inspect the loaded database lists
3. mutate or append entries in memory
4. use the game's native APIs to apply those entries to heroes or plot flow

## Feasible Future Approaches

### Option A: Patch runtime databases after `LoadAllGameData()`

This is the most promising approach.

Potential flow:

1. hook `GameDataController.LoadAllGameData()`
2. read `GameDataController.Instance`
3. patch `heroTagDataBase`, `kungfuSkillDataBase`, `PlotDataBase`, etc.
4. optionally grant tags to the player hero through `HeroData.AddTag(...)`

Pros:

- no manual asset editing
- can keep mod logic in code
- easier to version-control
- easier to reapply after updates than raw asset surgery

Risks:

- row/object invariants must be respected
- future game patches may rename or change fields

### Option B: Load our own external override file and merge into runtime data

Instead of hardcoding rows in C#, a future feature could read mod-owned data such as:

- JSON
- CSV
- TOML

Then convert that file into runtime objects and merge it into the game's loaded databases.

Pros:

- user-editable
- easier to expand later
- supports custom packs or presets

Risks:

- requires a reliable serializer / mapper to game object shapes
- more work up front

### Option C: Hook lower-level text loading through `LTCSVLoader`

This seems possible, but it is likely more brittle than patching the already-loaded database objects.

Good as a fallback, not as a first choice.

### Option D: Runtime grant / mutate only, without defining new rows

For some features, we may not need new database rows at all.

Example:

- use existing tag IDs
- apply them conditionally with `HeroData.AddTag(...)`
- alter hero tag points or skill progress at runtime

This is lower-risk if the feature only needs to remix existing game content.

## Important Caveats

### 1. New IDs still matter

If we add new tag or skill definitions, IDs must still avoid collisions with vanilla rows and any future modded rows.

The forum advice about avoiding duplicate IDs is still valid.

### 2. Some tables are clean object lists, others are more raw

`HeroTagDataBase`, `KungfuSkillData`, and `PlotData` look clean and usable.

`HeroNatureTalkTextDataBase` appears to be a nested string list rather than a rich typed row object, so it may be less convenient to patch.

### 3. Runtime patching is safer than asset editing, but not magic

This approach is still version-sensitive because field names, list structure, and load timing can change with game updates.

Still, it should be much easier to maintain than repeatedly redoing `resources.assets` import/export.

### 4. Plot callback strings must be valid

When editing or injecting plot choices, callback strings like `callFuc` and `callParam` must match real game behavior.

We already have evidence that these are usable, but they still need careful validation.

## Suggested Future Starting Plan

When we actually decide to build this feature, the safest first milestone would be:

1. hook `GameDataController.LoadAllGameData()`
2. log database counts for:
   - `heroTagDataBase`
   - `kungfuSkillDataBase`
   - `PlotDataBase`
3. patch one existing row in memory as a proof of concept
4. verify the changed value appears in game
5. append one new `HeroTagDataBase` entry
6. grant it to the player with `HeroData.AddTag(...)`

That would prove the full chain:

- load
- mutate database
- apply to hero
- observe in UI/gameplay

After that, we could decide whether to keep the feature:

- code-driven only
- config-file-driven
- mixed mode

## Recommendation

If and when this feature starts, prefer this implementation order:

1. patch runtime databases after `LoadAllGameData()`
2. start with `HeroTagDataBase` and `HeroData.AddTag(...)`
3. then expand to `KungfuSkillData`
4. treat plot injection as a separate track because plot behavior has extra callback risk

This gives the best balance of power, maintainability, and lowest reverse-engineering risk.

## Final Summary

The investigation supports the following conclusion:

- manual `resources.assets` editing is not the only route
- the game already exposes runtime database objects for tags, skills, and plots
- heroes already expose native methods for tag application and management
- our current mod already proves runtime plot injection and Harmony patching are viable

So this future feature looks realistic and strategically worth keeping on the roadmap.
