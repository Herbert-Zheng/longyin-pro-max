using System;
using BepInEx;
using BepInEx.Configuration;
using BepInEx.Unity.IL2CPP;
using HarmonyLib;

namespace LongYinHorseStaminaMultiplier;

[BepInPlugin("codex.longyin.horsestamina", "LongYin Horse Stamina Multiplier", "1.0.1")]
public sealed class HorseStaminaMultiplierPlugin : BasePlugin
{
    private static ConfigEntry<float> _multiplier = null!;
    private Harmony _harmony = null!;

    public override void Load()
    {
        _multiplier = Config.Bind(
            "WorldMapHorse",
            "StaminaMultiplier",
            1f,
            "Scales horse stamina drain and recovery. Values above 1 make the horse last longer and refill more slowly.");
        _harmony = new Harmony("codex.longyin.horsestamina");
        _harmony.PatchAll(typeof(HorseStaminaMultiplierPlugin).Assembly);
        Log.LogInfo($"LongYin Horse Stamina Multiplier 1.0.1 loaded at x{Math.Max(0.01f, _multiplier.Value):0.###}.");
    }

    [HarmonyPrefix]
    [HarmonyPatch(typeof(HorseData), nameof(HorseData.ChangeNowPower), typeof(float))]
    private static void ChangeNowPowerPrefix(HorseData __instance, ref float delta)
    {
        if (__instance == null || !__instance.equiped)
        {
            return;
        }

        var multiplier = Math.Max(0.01f, _multiplier.Value);
        if (Math.Abs(multiplier - 1f) >= 0.001f)
        {
            delta /= multiplier;
        }
    }
}
