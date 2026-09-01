using System;
using System.Linq;
using System.Reflection;
using BepInEx;
using BepInEx.Configuration;
using BepInEx.Logging;
using BepInEx.Unity.IL2CPP;
using HarmonyLib;
using UnityEngine.Video;

[BepInPlugin("codex.longyin.skipintro", "LongYin Skip Intro", "1.0.1")]
public sealed class LongYinSkipIntroPlugin : BasePlugin
{
    private static ManualLogSource LoggerInstance = null!;
    private static ConfigEntry<bool> _enabled = null!;
    private static bool _startupIntroSkipped;
    private Harmony _harmony = null!;

    public override void Load()
    {
        LoggerInstance = Log;
        _enabled = Config.Bind("General", "Enabled", true, "Skips the startup intro video and jumps to the title flow.");
        if (!_enabled.Value)
        {
            Log.LogInfo("LongYin Skip Intro loaded with intro skipping disabled.");
            return;
        }

        _harmony = new Harmony("codex.longyin.skipintro");
        PatchOptional("Start", nameof(EnterSceneStartPostfix));
        PatchOptional("Update", nameof(EnterSceneUpdatePostfix));
        Log.LogInfo("LongYin Skip Intro 1.0.1 loaded. Startup intro video will be skipped.");
    }

    private void PatchOptional(string methodName, string postfixName)
    {
        var target = typeof(EnterSceneController)
            .GetMethods(BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic)
            .FirstOrDefault(method => method.Name == methodName && method.GetParameters().Length == 0);
        var postfix = AccessTools.Method(typeof(LongYinSkipIntroPlugin), postfixName);
        if (target == null || postfix == null)
        {
            Log.LogInfo($"Compatibility: EnterSceneController.{methodName} is unavailable; this skip path is disabled.");
            return;
        }

        _harmony.Patch(target, postfix: new HarmonyMethod(postfix));
    }

    private static void EnterSceneStartPostfix(EnterSceneController __instance)
    {
        TrySkipStartupIntro(__instance, "Start");
    }

    private static void EnterSceneUpdatePostfix(EnterSceneController __instance)
    {
        if (!_startupIntroSkipped && __instance != null && !__instance.videoPlayFinished)
        {
            TrySkipStartupIntro(__instance, "Update");
        }
    }

    private static void TrySkipStartupIntro(EnterSceneController controller, string source)
    {
        if (_startupIntroSkipped || !_enabled.Value || controller == null)
        {
            return;
        }

        try
        {
            VideoPlayer videoPlayer = controller.logoVideo;
            if (videoPlayer == null)
            {
                return;
            }

            try
            {
                videoPlayer.Stop();
            }
            catch (Exception ex)
            {
                LoggerInstance.LogDebug($"Skip Intro could not stop the logo video cleanly: {ex.Message}");
            }

            controller.VideoPlayFinished(videoPlayer);
            _startupIntroSkipped = true;
            LoggerInstance.LogInfo($"Skipped startup intro video via EnterSceneController.{source}.");
        }
        catch (Exception ex)
        {
            LoggerInstance.LogWarning($"Skip Intro failed during EnterSceneController.{source}: {ex.Message}");
        }
    }
}
