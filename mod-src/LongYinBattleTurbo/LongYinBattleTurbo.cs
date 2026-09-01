using System;
using System.Linq;
using System.Reflection;
using BepInEx;
using BepInEx.Configuration;
using BepInEx.Logging;
using BepInEx.Unity.IL2CPP;
using HarmonyLib;
using UnityEngine;

[BepInPlugin("codex.longyin.battleturbo", "LongYin Battle Turbo", "1.1.2")]
public sealed class LongYinBattleTurboPlugin : BasePlugin
{
    private static ManualLogSource LoggerInstance = null!;
    private static ConfigEntry<bool> _enabled = null!;
    private static ConfigEntry<KeyCode> _toggleHotkey = null!;
    private static ConfigEntry<float> _attackDelayMultiplier = null!;
    private static ConfigEntry<float> _entryDelayMultiplier = null!;
    private static ConfigEntry<float> _maxUnitMoveOneGridTime = null!;
    private static ConfigEntry<float> _forcedAiWaitTime = null!;
    private static ConfigEntry<bool> _disableCameraFocusTweens = null!;
    private static ConfigEntry<bool> _disableFocusAnimations = null!;
    private static ConfigEntry<bool> _disableHighlightAnimations = null!;
    private static ConfigEntry<bool> _disableHitAnimations = null!;
    private static ConfigEntry<bool> _disableSkillSpecialEffects = null!;
    private static ConfigEntry<bool> _disableBattleVoices = null!;
    private static ConfigEntry<bool> _traceMode = null!;
    private static bool _runtimeEnabled;
    private Harmony _harmony = null!;

    public override void Load()
    {
        LoggerInstance = Log;
        _enabled = Config.Bind("General", "Enabled", true, "Enables battle-only turbo simulation tweaks.");
        _toggleHotkey = Config.Bind("General", "ToggleHotkey", KeyCode.F8, "Hotkey that toggles battle turbo on or off while in game.");
        _attackDelayMultiplier = Config.Bind("Timing", "AttackDelayMultiplier", 0.1f, "Scales attack wait windows. Lower values make AUTO battles resolve faster.");
        _entryDelayMultiplier = Config.Bind("Timing", "EntryDelayMultiplier", 0.05f, "Scales battle-entry and move-to-grid delay windows.");
        _maxUnitMoveOneGridTime = Config.Bind("Timing", "MaxUnitMoveOneGridTime", 0.03f, "Reserved compatibility value; direct unit move overriding stays disabled.");
        _forcedAiWaitTime = Config.Bind("Timing", "ForcedAiWaitTime", 0f, "Reserved compatibility value; direct AI wait overriding stays disabled.");
        _disableCameraFocusTweens = Config.Bind("Visuals", "DisableCameraFocusTweens", true, "Skips camera focus tweening during battle actions.");
        _disableFocusAnimations = Config.Bind("Visuals", "DisableFocusAnimations", true, "Skips target focus animations on battle units.");
        _disableHighlightAnimations = Config.Bind("Visuals", "DisableHighlightAnimations", true, "Skips unit highlight animations in battle.");
        _disableHitAnimations = Config.Bind("Visuals", "DisableHitAnimations", false, "Skips hit reaction animations.");
        _disableSkillSpecialEffects = Config.Bind("Visuals", "DisableSkillSpecialEffects", true, "Skips spawning battle special effects.");
        _disableBattleVoices = Config.Bind("Audio", "DisableBattleVoices", true, "Skips battle voice and action audio calls from units.");
        _traceMode = Config.Bind("Debug", "TraceMode", false, "Logs battle turbo adjustments when they are applied.");
        _runtimeEnabled = _enabled.Value;
        _harmony = new Harmony("codex.longyin.battleturbo");

        PatchExact(typeof(BattleController), "Update", Type.EmptyTypes, null, nameof(BattleControllerUpdatePostfix));
        PatchHeroEntryCoroutine();
        PatchExact(typeof(BattleController), "HeroEnterGridDelay", new[] { typeof(BattleUnit), typeof(GridUnitData), typeof(float) }, nameof(HeroEnterGridDelayPrefix), null);
        PatchExact(typeof(BattleController), "GetBattleUnitAttackHitDelay", new[] { typeof(GridUnitData) }, null, nameof(GetBattleUnitAttackHitDelayPostfix));
        PatchExact(typeof(BattleController), "BattleUnitAttackHit", new[] { typeof(GridUnitData), typeof(float) }, nameof(BattleUnitAttackHitPrefix), null);
        PatchExact(typeof(BattleController), "BattleUnitAttackEnd", new[] { typeof(float) }, nameof(BattleUnitAttackEndPrefix), null);
        PatchExact(typeof(BattleController), "TweenFocusTarget", new[] { typeof(Vector3), typeof(float) }, nameof(TweenFocusTargetPrefix), null);
        PatchExact(typeof(BattleController), "CreateSpeEffect", new[] { typeof(SkillSpeEffectTargetType), typeof(GameObject), typeof(string) }, nameof(CreateSpeEffectPrefix), null);
        PatchExact(typeof(BattleController), "CreateSpeEffect", new[] { typeof(SkillSpeEffectTargetType), typeof(GameObject), typeof(string), typeof(float) }, nameof(CreateSpeEffectPrefix), null);
        PatchExact(typeof(BattleController), "CreateSpeEffect", new[] { typeof(SkillSpeEffectTargetType), typeof(GameObject), typeof(string), typeof(float), typeof(Vector3) }, nameof(CreateSpeEffectPrefix), null);
        PatchExact(typeof(BattleUnit), "SetHighLightAnim", new[] { typeof(bool) }, nameof(SetHighLightAnimPrefix), null);
        PatchExact(typeof(BattleUnit), "ShowFocusAnim", Type.EmptyTypes, nameof(ShowFocusAnimPrefix), null);
        PatchExact(typeof(BattleUnit), "PlayHitAnim", Type.EmptyTypes, nameof(PlayHitAnimPrefix), null);
        PatchFirstByName(typeof(BattleUnit), "PlayHeroSound", nameof(PlayHeroSoundPrefix), null);

        Log.LogInfo($"LongYin Battle Turbo 1.1.2 loaded. Enabled={_runtimeEnabled}; Hotkey={_toggleHotkey.Value}; AttackDelay=x{FormatFloat(_attackDelayMultiplier.Value)}; EntryDelay=x{FormatFloat(_entryDelayMultiplier.Value)}.");
        Log.LogInfo($"Compatibility: unitMove={FormatFloat(_maxUnitMoveOneGridTime.Value)} and aiWait={FormatFloat(_forcedAiWaitTime.Value)} remain intentionally disabled for stability.");
    }

    private void PatchHeroEntryCoroutine()
    {
        var currentParameters = new[]
        {
            typeof(HeroData), typeof(BattleTeam), typeof(GridUnitData), typeof(int), typeof(float), typeof(float)
        };
        if (TryPatchExact(typeof(BattleController), "HeroEnterBattleFieldCoroutine", currentParameters, nameof(HeroEnterBattleFieldCoroutine6Prefix), null))
        {
            Log.LogInfo("Compatibility: using six-parameter HeroEnterBattleFieldCoroutine.");
            return;
        }

        var legacyParameters = new[]
        {
            typeof(HeroData), typeof(BattleTeam), typeof(GridUnitData), typeof(int), typeof(float)
        };
        if (TryPatchExact(typeof(BattleController), "HeroEnterBattleFieldCoroutine", legacyParameters, nameof(HeroEnterBattleFieldCoroutine5Prefix), null))
        {
            Log.LogInfo("Compatibility: using legacy five-parameter HeroEnterBattleFieldCoroutine.");
            return;
        }

        Log.LogInfo("Compatibility: HeroEnterBattleFieldCoroutine unavailable; entry-delay scaling remains active through HeroEnterGridDelay.");
    }

    private void PatchExact(Type type, string name, Type[] parameterTypes, string? prefix, string? postfix)
    {
        if (!TryPatchExact(type, name, parameterTypes, prefix, postfix))
        {
            Log.LogInfo($"Compatibility: optional patch unavailable: {type.Name}.{name}({parameterTypes.Length} params).");
        }
    }

    private bool TryPatchExact(Type type, string name, Type[] parameterTypes, string? prefix, string? postfix)
    {
        var target = FindExactMethod(type, name, parameterTypes);
        if (target == null)
        {
            return false;
        }

        ApplyPatch(target, prefix, postfix);
        Log.LogInfo($"Patched {type.Name}.{target.Name}({target.GetParameters().Length} params).");
        return true;
    }

    private void PatchFirstByName(Type type, string name, string? prefix, string? postfix)
    {
        var target = type.GetMethods(BindingFlags.Instance | BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic)
            .FirstOrDefault(method => string.Equals(method.Name, name, StringComparison.Ordinal));
        if (target == null)
        {
            Log.LogInfo($"Compatibility: optional patch unavailable: {type.Name}.{name}.");
            return;
        }

        ApplyPatch(target, prefix, postfix);
        Log.LogInfo($"Patched {type.Name}.{target.Name}({target.GetParameters().Length} params).");
    }

    private static MethodInfo? FindExactMethod(Type type, string name, Type[] parameterTypes)
    {
        return type.GetMethods(BindingFlags.Instance | BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic)
            .FirstOrDefault(method =>
                string.Equals(method.Name, name, StringComparison.Ordinal) &&
                method.GetParameters().Select(parameter => parameter.ParameterType).SequenceEqual(parameterTypes));
    }

    private void ApplyPatch(MethodInfo target, string? prefix, string? postfix)
    {
        var prefixMethod = prefix == null ? null : AccessTools.Method(typeof(LongYinBattleTurboPlugin), prefix);
        var postfixMethod = postfix == null ? null : AccessTools.Method(typeof(LongYinBattleTurboPlugin), postfix);
        _harmony.Patch(
            target,
            prefixMethod == null ? null : new HarmonyMethod(prefixMethod),
            postfixMethod == null ? null : new HarmonyMethod(postfixMethod));
    }

    private static void BattleControllerUpdatePostfix() => TryHandleToggleHotkey();

    private static void HeroEnterBattleFieldCoroutine6Prefix(ref float __5)
    {
        if (IsEnabled()) __5 = ScaleDelay(__5, _entryDelayMultiplier.Value);
    }

    private static void HeroEnterBattleFieldCoroutine5Prefix(ref float __4)
    {
        if (IsEnabled()) __4 = ScaleDelay(__4, _entryDelayMultiplier.Value);
    }

    private static void HeroEnterGridDelayPrefix(ref float delayTime)
    {
        if (IsEnabled()) delayTime = ScaleDelay(delayTime, _entryDelayMultiplier.Value);
    }

    private static void GetBattleUnitAttackHitDelayPostfix(ref float __result)
    {
        if (IsEnabled()) __result = ScaleDelay(__result, _attackDelayMultiplier.Value);
    }

    private static void BattleUnitAttackHitPrefix(ref float startDelay)
    {
        if (IsEnabled()) startDelay = ScaleDelay(startDelay, _attackDelayMultiplier.Value);
    }

    private static void BattleUnitAttackEndPrefix(ref float delayTime)
    {
        if (IsEnabled()) delayTime = ScaleDelay(delayTime, _attackDelayMultiplier.Value);
    }

    private static bool TweenFocusTargetPrefix() => !IsEnabled() || !_disableCameraFocusTweens.Value;
    private static bool CreateSpeEffectPrefix() => !IsEnabled() || !_disableSkillSpecialEffects.Value;
    private static bool SetHighLightAnimPrefix() => !IsEnabled() || !_disableHighlightAnimations.Value;
    private static bool ShowFocusAnimPrefix() => !IsEnabled() || !_disableFocusAnimations.Value;
    private static bool PlayHitAnimPrefix() => !IsEnabled() || !_disableHitAnimations.Value;
    private static bool PlayHeroSoundPrefix() => !IsEnabled() || !_disableBattleVoices.Value;

    private static void TryHandleToggleHotkey()
    {
        if (_toggleHotkey.Value == KeyCode.None || !Input.GetKeyDown(_toggleHotkey.Value))
        {
            return;
        }

        _runtimeEnabled = !_runtimeEnabled;
        LoggerInstance.LogInfo($"Battle turbo {(_runtimeEnabled ? "enabled" : "disabled")} from hotkey {_toggleHotkey.Value}.");
        PushPlayerLog($"Mod: Battle Turbo {(_runtimeEnabled ? "ON" : "OFF")}");
        if (_traceMode.Value)
        {
            LoggerInstance.LogInfo($"Battle turbo hotkey toggled {(_runtimeEnabled ? "ON" : "OFF")}.");
        }
    }

    private static bool IsEnabled() => _runtimeEnabled;

    private static float ScaleDelay(float original, float multiplier)
    {
        return original <= 0f ? original : original * Mathf.Max(0f, multiplier);
    }

    private static string FormatFloat(float value) => Mathf.Max(0f, value).ToString("0.###");

    private static void PushPlayerLog(string text)
    {
        try
        {
            var info = InfoController.Instance;
            if (info != null)
            {
                info.AddInfo(InfoType.WorldInfo, text);
                info.AddInfo(InfoType.PersonalInfo, text);
                info.BuildInfoList();
            }
        }
        catch (Exception ex)
        {
            LoggerInstance.LogWarning($"Battle turbo InfoController notification failed: {ex.Message}");
        }

        try
        {
            GameController.Instance?.ShowTextOnMouse(text, 28, Color.yellow);
        }
        catch (Exception ex)
        {
            LoggerInstance.LogWarning($"Battle turbo cursor notification failed: {ex.Message}");
        }
    }
}
