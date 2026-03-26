using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text.Json;
using BepInEx;
using BepInEx.Configuration;
using BepInEx.Logging;
using BepInEx.Unity.IL2CPP;
using HarmonyLib;
using UnityEngine;
using UnityEngine.Events;
using UnityEngine.EventSystems;
using UnityEngine.UI;

[BepInPlugin("codex.longyin.staminalock", "LongYin Stamina Lock", "1.29.0")]
public sealed class LongYinStaminaLockPlugin : BasePlugin
{
    private const string TreasureChestChoiceParamPrefix = "codex_chest_choice:";
    private const string TreasureChestChoicePlotCallbackName = nameof(PlotController.ChangePlotDataBase);
    private const string LoverChoiceTextKeyword = "结缘";
    private const string LoverLimitReachedText = "情侣数已达上限";
    private const int DailySkillInsightMaxLevel = 10;
    private const int LuckyMoneyMinPercent = 1;
    private const int LuckyMoneyMaxPercent = 30;
    private const int TeachSkillSplashMinPercentFloor = 0;
    private const int TeachSkillSplashMaxPercentCeiling = 500;
    private const KeyCode ViewedHeroFavorTestHotkey = KeyCode.K;
    private const float TeamFameShareRatio = 0.3f;
    private const float TeachSkillSideTabDurationSeconds = 4.5f;
    private const string TeachSkillSideTabAtlasName = "IconAtlas";
    private const string TeachSkillSideTabIconName = "1";
    private const string TeachSkillSideTabSoundName = "Woosh";
    private const float TeachSkillSideTabSoundVolume = 1f;
    private const float DrinkFillMatchTolerance = 0.02f;
    private const float DrinkFillDeltaTolerance = 0.005f;
    private const string ThresholdTalentSource = "codex.threshold-talent";
    private const string ThresholdTalentCategory = "Pro Max";
    private const string ThresholdTalentMarker = "codex.threshold-talent";
    private const string DefaultThresholdTalentName = "天人感应";
    private const float ThresholdTalentEvaluationIntervalSeconds = 0.5f;
    private const string CustomTalentCategory = "Pro Max Custom";
    private const string CustomTalentMarkerPrefix = "codex.custom-talent:";
    private const string CustomTalentSource = "codex.custom-talent";
    private const string CustomTalentConfigFileName = "codex.longyin.custom-talents.json";
    private const float CustomTalentEvaluationIntervalSeconds = 0.5f;
    private const int ShopOwnershipBuyPrice = 500;
    private const int ShopOwnershipSaveVersion = 1;
    private const string ShopOwnershipSaveFolderName = "codex.longyin.shop-ownership";
    private const string ShopOwnershipOverlayPanelName = "CodexShopOwnershipOverlay";
    private const string ShopOwnershipBuyButtonName = "CodexShopOwnershipBuyButton";
    private const int ExternalOverlayProtocolVersion = 1;
    private const string ExternalOverlayStateFileName = "codex.longyin.overlay-state.json";
    private const string ExternalOverlayCommandFileName = "codex.longyin.overlay-command.json";
    private const float ExternalOverlaySyncIntervalSeconds = 0.25f;
    private static readonly string[] RelationshipBonusMessages =
    {
        "你今天比较帅，好感有多加 {0}",
        "你让他心情很好 ， 好感多加 {0}"
    };
    private static readonly float[] OutsideBattleSpeedCycle = { 1f, 2f, 3f, 5f, 10f };

    internal static ManualLogSource LoggerInstance = null!;

    private static ConfigEntry<bool> _lockExploreStamina = null!;
    private static ConfigEntry<bool> _revealExtraFogOnMove = null!;
    private static ConfigEntry<int> _moveRevealRadius = null!;
    private static ConfigEntry<bool> _revealAllOnStepTile = null!;
    private static ConfigEntry<bool> _treasureChestChoiceEnabled = null!;
    private static ConfigEntry<bool> _treasureChestAutoPickMostValuable = null!;
    private static ConfigEntry<int> _treasureChestChoiceOptions = null!;
    private static ConfigEntry<int> _treasureChestTotalItems = null!;
    private static ConfigEntry<int> _bookExpMultiplier = null!;
    private static ConfigEntry<float> _studySkillCostMultiplier = null!;
    private static ConfigEntry<int> _battleSkillExpMultiplier = null!;
    private static ConfigEntry<int> _creationPointMultiplier = null!;
    private static ConfigEntry<int> _battleSpeedMultiplier = null!;
    private static ConfigEntry<float> _horseBaseSpeedMultiplier = null!;
    private static ConfigEntry<float> _horseTurboSpeedMultiplier = null!;
    private static ConfigEntry<float> _horseTurboDurationMultiplier = null!;
    private static ConfigEntry<float> _horseTurboCooldownMultiplier = null!;
    private static ConfigEntry<bool> _lockHorseTurboStamina = null!;
    private static ConfigEntry<float> _carryWeightCap = null!;
    private static ConfigEntry<bool> _ignoreCarryWeight = null!;
    private static ConfigEntry<int> _merchantCarryCash = null!;
    private static ConfigEntry<bool> _treasureTradeHelperEnabled = null!;
    private static ConfigEntry<bool> _treasureAutoTradeEnabled = null!;
    private static ConfigEntry<bool> _treasureIdentifyHighlightCorrect = null!;
    private static ConfigEntry<bool> _treasureIdentifyForceCorrectSelection = null!;
    private static ConfigEntry<int> _luckyMoneyHitChancePercent = null!;
    private static ConfigEntry<int> _extraRelationshipGainChancePercent = null!;
    private static ConfigEntry<bool> _teamAutoFavorEnabled = null!;
    private static ConfigEntry<float> _teamAutoFavorPerDay = null!;
    private static ConfigEntry<int> _maxLoverCount = null!;
    private static ConfigEntry<bool> _blockOverflowLoverHomeBattle = null!;
    private static ConfigEntry<float> _debatePlayerDamageTakenMultiplier = null!;
    private static ConfigEntry<float> _debateEnemyDamageTakenMultiplier = null!;
    private static ConfigEntry<bool> _craftRandomPickUpgradeEnabled = null!;
    private static ConfigEntry<int> _craftTier1ExtraItems = null!;
    private static ConfigEntry<int> _craftTier2ExtraItems = null!;
    private static ConfigEntry<int> _craftTier3ExtraItems = null!;
    private static ConfigEntry<int> _craftTier4ExtraItems = null!;
    private static ConfigEntry<int> _craftTier5ExtraItems = null!;
    private static ConfigEntry<float> _drinkPlayerPowerCostMultiplier = null!;
    private static ConfigEntry<float> _drinkEnemyPowerCostMultiplier = null!;
    private static ConfigEntry<int> _dailySkillInsightHitChancePercent = null!;
    private static ConfigEntry<float> _dailySkillInsightExpPercent = null!;
    private static ConfigEntry<bool> _dailySkillInsightUseRarityScaling = null!;
    private static ConfigEntry<float> _dailySkillInsightRealtimeIntervalSeconds = null!;
    private static ConfigEntry<bool> _teachSkillSameSectAreaShareEnabled = null!;
    private static ConfigEntry<int> _teachSkillSameSectAreaShareMinPercent = null!;
    private static ConfigEntry<int> _teachSkillSameSectAreaShareMaxPercent = null!;
    private static ConfigEntry<bool> _thresholdTalentEnabled = null!;
    private static ConfigEntry<string> _thresholdTalentName = null!;
    private static ConfigEntry<BaseAttriType> _thresholdTalentRequirementAttribute = null!;
    private static ConfigEntry<float> _thresholdTalentRequirementValue = null!;
    private static ConfigEntry<HeroSpeAddDataType> _thresholdTalentBuffType = null!;
    private static ConfigEntry<float> _thresholdTalentBuffValue = null!;
    private static ConfigEntry<float> _thresholdTalentDuration = null!;
    private static ConfigEntry<bool> _thresholdTalentShowInfo = null!;
    private static ConfigEntry<float> _dialogMonthlyLimitMultiplier = null!;
    private static ConfigEntry<bool> _dialogFastForwardAssistEnabled = null!;
    private static ConfigEntry<KeyCode> _dialogFastForwardAssistHotkey = null!;
    private static ConfigEntry<bool> _traceMode = null!;
    private static ConfigEntry<bool> _traceBattleSkillExp = null!;
    private static ConfigEntry<bool> _traceDialogFastForward = null!;
    private static ConfigEntry<bool> _traceTreasureChestEvents = null!;
    private static ConfigEntry<bool> _traceLoverBattlePrep = null!;
    private static ConfigEntry<bool> _freezeDate = null!;
    private static ConfigEntry<KeyCode> _freezeDateHotkey = null!;
    private static ConfigEntry<KeyCode> _outsideBattleSpeedHotkey = null!;
    private static readonly string[] HorseCurrentPowerMemberNames = { "power", "nowPower", "horsePower", "stamina", "nowStamina", "leftPower" };
    private static readonly string[] HorseMaxPowerMemberNames = { "maxPower", "powerMax", "maxStamina", "horseMaxPower" };
    private static readonly string[] DrinkPlayerFillAmountMemberNames = { "playerFillAmount" };
    private static readonly string[] DrinkEnemyFillAmountMemberNames = { "enemyFillAmount" };
    private static readonly System.Random Random = new();
    private static bool _applyingLuckyMoneyRefund;
    private static bool _applyingDailySkillInsightExp;
    private static bool _applyingTeamAutoFavor;
    private static bool _applyingTeamFameShare;
    private static bool _studySkillTaskScalingActive;
    private static bool _studySkillTimeScalingActive;
    private static bool _studySkillInjectingExtraDay;
    private static bool _bookWriterCountdownOverrideArmed;
    private static bool _bookWriterTaskScalingActive;
    private static bool _readBookCountdownOverrideArmed;
    private static bool _grantingCraftBonusItems;
    private static bool _repeatingCraftChoiceReward;
    private static bool _exploreFullRevealConsumed;
    private static bool _grantingTreasureChestChoiceReward;
    private static bool _grantingTreasureChestBonusItems;
    private static bool _treasureChestChoiceClosingPlot;
    private static bool _dailySkillInsightBaselineReady;
    private static float _studySkillUnitDayBudget;
    private static float _studySkillExtraDayCarry;
    private static TimeData? _studySkillTaskStartDate;
    private static TimeData? _bookWriterTaskStartDate;
    private static TimeData? _readBookCountdownStartDate;
    private static int _bookWriterTaskTargetDays;
    private static BookWriterData? _bookWriterTaskData;
    private static float _nextRealtimeDailySkillInsightAt = -1f;
    private static TimeData? _lastObservedWorldDate;
    private static int _lastDrinkControllerInstanceId;
    private static float _lastDrinkPlayerFillAmount = float.NaN;
    private static float _lastDrinkEnemyFillAmount = float.NaN;
    private static bool? _lastResolvedDrinkTargetIsPlayer;
    private static bool _preferredBattleTimeScaleCaptured;
    private static float _preferredBattleTimeScale = 1f;
    private static readonly Dictionary<string, int> _dialogMonthlyUseCounts = new(StringComparer.Ordinal);
    private static HeroData? _activeDialogHero;
    private static int _activeDialogHeroId = -1;
    private static HeroData? _activeHeroDetailHero;
    private static int _activeHeroDetailHeroId = -1;
    private static bool _dialogFastForwardAssistOwnsSkip;
    private static readonly List<KungfuSkillLvData> _dailySkillInsightCandidateBuffer = new();
    private static readonly List<RegisteredCustomTalent> _customTalents = new();
    private static int _thresholdTalentTagId = -1;
    private static string _thresholdTalentTagName = DefaultThresholdTalentName;
    private static float _nextThresholdTalentEvaluationAt = -1f;
    private static float _nextCustomTalentEvaluationAt = -1f;
    private static bool _thresholdTalentRegistrationWarned;
    private static MethodInfo? _heroChangeFameMethod;
    private Harmony? _harmony;

    private sealed class MoneyChangeState
    {
        public bool IsEligible { get; init; }
        public int RequestedDelta { get; init; }
        public int? MoneyBefore { get; init; }
        public bool IsSpend { get; init; }
        public bool IsIncome { get; init; }
    }

    private sealed class FameChangeState
    {
        public bool IsEligible { get; init; }
        public float RequestedDelta { get; init; }
        public float? FameBefore { get; init; }
    }

    private sealed class CalendarChangeState
    {
        public string BeforeText { get; init; } = "Date: unavailable";
        public TimeData? BeforeDate { get; init; }
    }

    private sealed class TeachSkillSplashState
    {
        public bool IsEligible { get; init; }
        public HeroData? SourceHero { get; init; }
        public HeroData? TargetHero { get; init; }
        public int SkillId { get; init; }
        public string SkillName { get; init; } = string.Empty;
        public float TargetBookProgressBefore { get; init; }
        public float TargetFightProgressBefore { get; init; }
    }

    private sealed class TeachSkillRecipientResult
    {
        public string HeroName { get; init; } = string.Empty;
        public string SkillName { get; init; } = string.Empty;
        public float Exp { get; init; }
        public int Percent { get; init; }
    }

    private sealed class ExploreHealingState
    {
        public HeroData? Player { get; init; }
        public float ExternalInjuryBefore { get; init; }
        public float InternalInjuryBefore { get; init; }
        public float PoisonInjuryBefore { get; init; }
        public bool IsHealingTile { get; init; }
    }

    private sealed class CustomTalentPackFile
    {
        public int version { get; set; }
        public List<CustomTalentDefinitionFile>? talents { get; set; }
    }

    private sealed class CustomTalentDefinitionFile
    {
        public string? id { get; set; }
        public bool enabled { get; set; }
        public string? name { get; set; }
        public int durationDays { get; set; }
        public List<CustomTalentConditionFile>? conditions { get; set; }
        public List<CustomTalentEffectFile>? effects { get; set; }
    }

    private sealed class CustomTalentConditionFile
    {
        public string? type { get; set; }
        public string? stat { get; set; }
        public float min { get; set; }
    }

    private sealed class CustomTalentEffectFile
    {
        public string? effectType { get; set; }
        public float value { get; set; }
    }

    private enum CustomTalentConditionKind
    {
        PlayerStatMin,
        TeamStatSumMin
    }

    private sealed class RegisteredCustomTalentCondition
    {
        public CustomTalentConditionKind Kind { get; init; }
        public BaseAttriType Stat { get; init; }
        public float Minimum { get; init; }
    }

    private sealed class RegisteredCustomTalent
    {
        public string Id { get; init; } = string.Empty;
        public bool Enabled { get; init; }
        public string Name { get; init; } = string.Empty;
        public int DurationDays { get; init; }
        public string Marker { get; init; } = string.Empty;
        public HeroSpeAddData BuffData { get; init; } = null!;
        public List<RegisteredCustomTalentCondition> Conditions { get; init; } = new();
        public int RuntimeTagId { get; set; } = -1;
    }

    private sealed class ShopOwnershipSaveFile
    {
        public int version { get; set; }
        public List<ShopOwnershipSaveEntry>? shops { get; set; }
    }

    private sealed class ShopOwnershipSaveEntry
    {
        public string? shopKey { get; set; }
        public string? shopName { get; set; }
        public int areaId { get; set; }
        public int buildingId { get; set; }
        public int buyPrice { get; set; }
        public string? purchasedOn { get; set; }
    }

    private sealed class OwnedShopRecord
    {
        public string ShopKey { get; init; } = string.Empty;
        public string ShopName { get; init; } = string.Empty;
        public int AreaId { get; init; }
        public int BuildingId { get; init; }
        public int BuyPrice { get; init; }
        public string PurchasedOn { get; init; } = string.Empty;
    }

    private sealed class ShopOwnershipContext
    {
        public TradeUIController TradeUi { get; init; } = null!;
        public AreaBuildingData Building { get; init; } = null!;
        public HeroData? Player { get; init; }
        public string ShopKey { get; init; } = string.Empty;
        public string ShopName { get; init; } = string.Empty;
        public int AreaId { get; init; }
        public int BuildingId { get; init; }
    }

    private sealed class ExternalOverlayStateFile
    {
        public int version { get; set; }
        public string updatedAtUtc { get; set; } = string.Empty;
        public string statusMessage { get; set; } = string.Empty;
        public string statusChangedAtUtc { get; set; } = string.Empty;
        public string worldDate { get; set; } = string.Empty;
        public int saveSlotId { get; set; }
        public int ownedShopCount { get; set; }
        public int? playerMoney { get; set; }
        public bool inShop { get; set; }
        public string? shopKey { get; set; }
        public string? shopName { get; set; }
        public bool shopOwned { get; set; }
        public bool canBuyShop { get; set; }
        public int buyPrice { get; set; }
        public string? purchasedOn { get; set; }
        public string? lastProcessedRequestId { get; set; }
    }

    private sealed class ExternalOverlayCommandFile
    {
        public int version { get; set; }
        public string? requestId { get; set; }
        public string? action { get; set; }
        public string? shopKey { get; set; }
    }

    private sealed class TreasureChestChoiceSession
    {
        public HeroData? Player { get; init; }
        public List<ItemData> Options { get; init; } = new();
        public bool SkipManageItemPoison { get; init; }
        public bool Resolved { get; set; }
        public float OpenedAtRealtime { get; init; }
        public string? LastObservedChoiceParam { get; set; }
        public bool PendingClickConfirm { get; set; }
        public int PendingClickConfirmFrames { get; set; }
        public bool PendingAutoPick { get; set; }
        public int PendingAutoPickFrames { get; set; }
    }

    private sealed class TreasureTradeOpportunity
    {
        public ItemData Item { get; init; } = null!;
        public ItemIconController Icon { get; init; } = null!;
        public TradeIconType IconType { get; init; }
        public int BuyPrice { get; init; }
        public int CurrentSellPrice { get; init; }
        public int IdentifiedSellPrice { get; init; }
        public int IdentifyCost { get; init; }
        public int RealValue { get; init; }
        public float SkillBuyFactor { get; init; }
        public float SkillSellFactor { get; init; }
        public int NetProfit => IdentifiedSellPrice - BuyPrice - IdentifyCost;
        public int IdentifyGain => IdentifiedSellPrice - CurrentSellPrice - IdentifyCost;
    }

    private sealed class CraftRewardSelection
    {
        public int ResultItemId { get; init; }
        public int ResultItemLv { get; init; }
        public int ResultRareLv { get; init; }
        public string ResultName { get; init; } = string.Empty;
    }

    private sealed class CraftRewardBonusState
    {
        public string MaterialName { get; init; } = string.Empty;
        public int MaterialMajorTier { get; init; }
        public int ExtraItemCount { get; init; }
        public bool Consumed { get; set; }
    }

    private sealed class PlotItemGrantState
    {
        public ItemData? ItemBefore { get; init; }
        public string Source { get; init; } = string.Empty;
    }

    private static TreasureChestChoiceSession? _activeTreasureChestChoiceSession;
    private static CraftRewardSelection? _pendingCraftSelection;
    private static CraftRewardBonusState? _activeCraftRewardBonus;
    private static ItemIconController? _selectedTreasureTradeIcon;
    private static Text? _treasureTradeOverlayLabel;
    private static GameObject? _shopOwnershipOverlayRoot;
    private static Text? _shopOwnershipOverlayLabel;
    private static Button? _shopOwnershipBuyButton;
    private static Text? _shopOwnershipBuyButtonLabel;
    private static float _treasureTradeShopOpenedAtRealtime = -1f;
    private static bool _treasureTradeAutoProcessed;
    private static bool _treasureTradeBusy;
    private static readonly HashSet<string> _treasureTradeLoggedSignatures = new(StringComparer.Ordinal);
    private static readonly Dictionary<string, OwnedShopRecord> _ownedShops = new(StringComparer.Ordinal);
    private static int _currentShopOwnershipSaveSlotId = -1;
    private static int _loadedShopOwnershipSourceSlotId = -1;
    private static int _pendingShopOwnershipSaveSlotId = -1;
    private static float _lastExternalOverlaySyncRealtime = -1f;
    private static string _lastExternalOverlayRequestId = string.Empty;
    private static string _externalOverlayStatusMessage = "模组已启动，等待存档载入。";
    private static string _externalOverlayStatusChangedAtUtc = DateTime.UtcNow.ToString("O");

    public override void Load()
    {
        LoggerInstance = Log;
        LoggerInstance.LogInfo($"External overlay state path: {GetExternalOverlayStatePath()}");
        LoggerInstance.LogInfo($"External overlay command path: {GetExternalOverlayCommandPath()}");
        _lockExploreStamina = Config.Bind("Exploration", "LockStamina", true, "Prevents exploration stamina from decreasing.");
        _revealExtraFogOnMove = Config.Bind("Exploration", "RevealExtraFogOnMove", false, "Legacy compatibility toggle for the old per-move reveal experiment. No longer used.");
        _moveRevealRadius = Config.Bind("Exploration", "MoveRevealRadius", 2, "Legacy compatibility value for the old per-move reveal experiment. No longer used.");
        _revealAllOnStepTile = Config.Bind("Exploration", "RevealAllOnStepTile", true, "Reveal the whole exploration map once, after the first completed move in each exploration run.");
        _treasureChestChoiceEnabled = Config.Bind("Exploration", "TreasureChestChoiceEnabled", true, "When true, exploration treasure chests show several reward items and let you choose 1.");
        _treasureChestAutoPickMostValuable = Config.Bind("Exploration", "TreasureChestAutoPickMostValuable", true, "When true, treasure chest choice mode automatically takes the highest-value option.");
        _treasureChestChoiceOptions = Config.Bind("Exploration", "TreasureChestChoiceOptions", 3, "How many reward options each exploration treasure chest should show when choice mode is enabled.");
        _treasureChestTotalItems = Config.Bind("Exploration", "TreasureChestTotalItems", 2, "Total item rewards to grant from exploration treasure chests. Set to 1 for vanilla behavior.");
        _bookExpMultiplier = Config.Bind("ReadBook", "ExpMultiplier", 1, "Multiplies EXP gained from reading books.");
        _studySkillCostMultiplier = Config.Bind("StudySkill", "CostMultiplier", 1f, "Multiplies both silver and time costs for martial-skill book writing / transcription.");
        _battleSkillExpMultiplier = Config.Bind("Battle", "SkillExpMultiplier", 1, "Multiplies martial-skill EXP gained from battle actions for every combatant, including enemies.");
        _creationPointMultiplier = Config.Bind("CharacterCreation", "PointMultiplier", 1, "Multiplies the remaining point pools during character creation.");
        _battleSpeedMultiplier = Config.Bind("Battle", "SpeedMultiplier", 2, "Multiplies the selected in-battle speed option.");
        _horseBaseSpeedMultiplier = Config.Bind("WorldMapHorse", "BaseSpeedMultiplier", 1f, "Multiplies the player horse's normal world-map travel speed.");
        _horseTurboSpeedMultiplier = Config.Bind("WorldMapHorse", "TurboSpeedMultiplier", 1f, "Multiplies the player horse's turbo speed bonus on the world map.");
        _horseTurboDurationMultiplier = Config.Bind("WorldMapHorse", "TurboDurationMultiplier", 1f, "Multiplies how long horse turbo lasts on the world map.");
        _horseTurboCooldownMultiplier = Config.Bind("WorldMapHorse", "TurboCooldownMultiplier", 1f, "Multiplies horse turbo cooldown duration. Set below 1 for a shorter cooldown.");
        _lockHorseTurboStamina = Config.Bind("WorldMapHorse", "LockTurboStamina", true, "Keeps world-map horse stamina available so turbo does not end early from stamina depletion.");
        _carryWeightCap = Config.Bind("Inventory", "CarryWeightCap", 100000f, "Minimum carry-weight cap applied to the player inventory. Set to 0 to disable.");
        _ignoreCarryWeight = Config.Bind("Inventory", "IgnoreCarryWeight", false, "When true, forces the player inventory's current carried weight to 0.");
        _merchantCarryCash = Config.Bind("Commerce", "MerchantCarryCash", 100000, "Minimum cash carried by NPC shop merchants while a Shop trade window is open. Set to 0 to disable.");
        _treasureTradeHelperEnabled = Config.Bind("Commerce", "TreasureTradeHelperEnabled", true, "Shows current treasure resale estimates and skill factors inside trade shops that list treasure items.");
        _treasureAutoTradeEnabled = Config.Bind("Commerce", "TreasureAutoTradeEnabled", true, "Automatically adds profitable unidentified treasure items from the shop sell list into the trade cart when a trade shop opens.");
        _treasureIdentifyHighlightCorrect = Config.Bind("TreasureIdentify", "HighlightCorrectTreasure", false, "Auto-selects the correct treasure in the identify mini-game without pressing confirm.");
        _treasureIdentifyForceCorrectSelection = Config.Bind("TreasureIdentify", "ForceCorrectTreasureSelection", true, "Replaces any clicked treasure with the correct one before the game processes the choice.");
        _luckyMoneyHitChancePercent = Config.Bind("MoneyLuck", "LuckyHitChancePercent", 0, "Chance from 0 to 100 that a player money transaction triggers a lucky bonus.");
        _extraRelationshipGainChancePercent = Config.Bind("Relationship", "ExtraRelationshipGainChancePercent", 0, "Chance from 0 to 100 that positive relationship gain becomes double.");
        _teamAutoFavorEnabled = Config.Bind("Relationship", "TeamAutoFavorEnabled", true, "When true, current player teammates automatically gain favor each elapsed in-game day.");
        _teamAutoFavorPerDay = Config.Bind("Relationship", "TeamAutoFavorPerDay", 5f, "Favor granted to each current player teammate per elapsed in-game day.");
        _maxLoverCount = Config.Bind("Relationship", "MaxLoverCount", 8, "Overrides the maximum number of lovers/couples the player can have at the same time. Vanilla appears to be 4.");
        _blockOverflowLoverHomeBattle = Config.Bind("Relationship", "BlockOverflowLoverHomeBattle", true, "When true, suppresses the home-entry lover ambush battle entirely, because the current modded romance setup can crash during its battle prep.");
        _debatePlayerDamageTakenMultiplier = Config.Bind("Debate", "PlayerDamageTakenMultiplier", 1f, "Multiplies debate damage dealt to the player side when a round is lost.");
        _debateEnemyDamageTakenMultiplier = Config.Bind("Debate", "EnemyDamageTakenMultiplier", 1f, "Multiplies debate damage dealt to the enemy side when a round is won.");
        _craftRandomPickUpgradeEnabled = Config.Bind("Craft", "RandomPickUpgrade", true, "Adds extra crafted items based on the added crafting material's major tier.");
        _craftTier1ExtraItems = Config.Bind("Craft", "Tier1ExtraItems", 0, "Extra items granted when the added crafting material resolves to major tier 1.");
        _craftTier2ExtraItems = Config.Bind("Craft", "Tier2ExtraItems", 1, "Extra items granted when the added crafting material resolves to major tier 2.");
        _craftTier3ExtraItems = Config.Bind("Craft", "Tier3ExtraItems", 2, "Extra items granted when the added crafting material resolves to major tier 3.");
        _craftTier4ExtraItems = Config.Bind("Craft", "Tier4ExtraItems", 3, "Extra items granted when the added crafting material resolves to major tier 4.");
        _craftTier5ExtraItems = Config.Bind("Craft", "Tier5ExtraItems", 4, "Extra items granted when the added crafting material resolves to major tier 5.");
        _drinkPlayerPowerCostMultiplier = Config.Bind("Drink", "PlayerPowerCostMultiplier", 1f, "Multiplies Qi cost paid by the player side during the drinking minigame.");
        _drinkEnemyPowerCostMultiplier = Config.Bind("Drink", "EnemyPowerCostMultiplier", 1f, "Multiplies Qi cost paid by the enemy side during the drinking minigame.");
        _dailySkillInsightHitChancePercent = Config.Bind("DailySkillInsight", "HitChancePercent", 0, "Chance from 0 to 100 that each elapsed in-game day grants bonus skill EXP to one eligible martial skill.");
        _dailySkillInsightExpPercent = Config.Bind("DailySkillInsight", "ExpPercent", 5f, "Percent of the skill's current-level max EXP to grant when the bonus triggers.");
        _dailySkillInsightUseRarityScaling = Config.Bind("DailySkillInsight", "UseRarityScaling", true, "When true, multiplies the bonus by the skill's rarity EXP rate.");
        _dailySkillInsightRealtimeIntervalSeconds = Config.Bind("DailySkillInsight", "RealtimeIntervalSeconds", 0f, "When above 0, grants the same bonus every X real-time seconds while in game. Useful for testing.");
        _teachSkillSameSectAreaShareEnabled = Config.Bind("Teaching", "SameSectAreaShareEnabled", true, "When the player teaches martial-skill EXP to a same-sect NPC, other same-sect NPCs in the same area who already know that skill also gain EXP.");
        _teachSkillSameSectAreaShareMinPercent = Config.Bind("Teaching", "SameSectAreaShareMinPercent", 80, "Minimum percent of the original taught EXP shared to each additional same-sect NPC in the area.");
        _teachSkillSameSectAreaShareMaxPercent = Config.Bind("Teaching", "SameSectAreaShareMaxPercent", 120, "Maximum percent of the original taught EXP shared to each additional same-sect NPC in the area.");
        _thresholdTalentEnabled = Config.Bind("ThresholdTalent", "Enabled", true, "When true, the player automatically gains a custom talent while the chosen attribute stays at or above the configured threshold.");
        _thresholdTalentName = Config.Bind("ThresholdTalent", "TalentName", DefaultThresholdTalentName, "Display name for the custom threshold talent.");
        _thresholdTalentRequirementAttribute = Config.Bind("ThresholdTalent", "RequirementAttribute", BaseAttriType.Inte, "Hero attribute checked for the threshold talent.");
        _thresholdTalentRequirementValue = Config.Bind("ThresholdTalent", "RequirementValue", 10f, "Required current attribute value to activate the threshold talent.");
        _thresholdTalentBuffType = Config.Bind("ThresholdTalent", "BuffType", HeroSpeAddDataType.addAttri2, "Buff applied by the custom threshold talent while active.");
        _thresholdTalentBuffValue = Config.Bind("ThresholdTalent", "BuffValue", 10f, "Buff magnitude applied by the custom threshold talent while active.");
        _thresholdTalentDuration = Config.Bind("ThresholdTalent", "Duration", 999f, "Duration in days used when the custom threshold talent is applied. Set this very high for testing so the tag behaves like a long-lived talent entry.");
        _thresholdTalentShowInfo = Config.Bind("ThresholdTalent", "ShowInfo", false, "When true, the game also shows its normal add/remove talent popups for the threshold talent.");
        _dialogMonthlyLimitMultiplier = Config.Bind("DialogFlow", "MonthlyLimitMultiplier", 3f, "Scales the monthly per-NPC interaction quota used by talk, teach, and similar meet choices.");
        _dialogFastForwardAssistEnabled = Config.Bind("DialogFlow", "FastForwardAssistEnabled", false, "When true, the mod automatically turns on plot fast-forward (快进) whenever the current dialog actually exposes the skip button.");
        _dialogFastForwardAssistHotkey = Config.Bind("DialogFlow", "ToggleFastForwardAssistHotkey", KeyCode.P, "Hotkey that toggles the dialog fast-forward assist while in game.");
        _traceMode = Config.Bind("Debug", "TracerEnabled", false, "Master switch for all mod tracer logs. When false, trace helpers stay silent.");
        _traceBattleSkillExp = Config.Bind("Debug", "TraceBattleSkillExp", false, "When TracerEnabled is true, logs each in-battle martial-skill EXP award before and after the multiplier.");
        _traceDialogFastForward = Config.Bind("Debug", "TraceDialogFastForward", false, "When TracerEnabled is true, logs dialog fast-forward assist decisions and key PlotController fast-forward events.");
        _traceTreasureChestEvents = Config.Bind("Debug", "TraceTreasureChestEvents", false, "When TracerEnabled is true, logs treasure chest interception, choice UI, and reward resolution.");
        _traceLoverBattlePrep = Config.Bind("Debug", "TraceLoverBattlePrep", false, "When TracerEnabled is true, logs the lover-result battle setup payloads before the home-entry lover battle prepares teams.");
        _freezeDate = Config.Bind("Time", "FreezeDate", false, "Blocks in-game day, month, and year progression.");
        _freezeDateHotkey = Config.Bind("Time", "ToggleFreezeDateHotkey", KeyCode.F10, "Hotkey that toggles date freezing while in game.");
        _outsideBattleSpeedHotkey = Config.Bind("Time", "CycleOutsideBattleSpeedHotkey", KeyCode.F11, "Hotkey that cycles the test speed multiplier outside battle.");
        _harmony = new Harmony("codex.longyin.staminalock");
        PatchMethod(typeof(ExploreController), "ChangeMoveStep", new[] { typeof(int) }, nameof(ChangeMoveStepPrefix), null);
        PatchMethod(typeof(ExploreController), "ChangeMoveStep", new[] { typeof(int), typeof(bool) }, nameof(ChangeMoveStepWithBoolPrefix), null);
        PatchMethod(typeof(ExploreController), nameof(ExploreController.GenerateExploreMap), new[] { typeof(ExploreMapData), typeof(string), typeof(string) }, null, nameof(GenerateExploreMapPostfix));
        PatchMethod(typeof(ExploreController), nameof(ExploreController.ResetExploreMap), Type.EmptyTypes, null, nameof(ResetExploreMapPostfix));
        PatchMethod(typeof(ExploreController), nameof(ExploreController.PlayerFinishMove), Type.EmptyTypes, null, nameof(PlayerFinishMovePostfix));
        PatchMethod(typeof(ExploreController), nameof(ExploreController.ManageTileEvent), new[] { typeof(ExploreTileData) }, nameof(ManageTileEventPrefix), nameof(ManageTileEventPostfix));
        PatchMethod(typeof(HeroData), nameof(HeroData.GetItem), new[] { typeof(ItemData), typeof(bool), typeof(bool), typeof(int), typeof(bool) }, nameof(TreasureChestGetItemPrefix), nameof(TreasureChestGetItemPostfix));
        PatchMethod(typeof(HeroData), nameof(HeroData.GetItem), new[] { typeof(ItemData), typeof(bool) }, null, nameof(BasicGetItemPostfix));
        PatchMethod(typeof(ItemListData), nameof(ItemListData.GetItem), new[] { typeof(ItemData), typeof(bool) }, null, nameof(ItemListGetItemPostfix));
        PatchMethod(typeof(PlotController), nameof(PlotController.ChangePlotDataBase), new[] { typeof(string) }, nameof(TreasureChestChoicePlotCallbackPrefix), null);
        PatchMethod(typeof(PlotController), nameof(PlotController.PlotBackgroundClicked), Type.EmptyTypes, nameof(TreasureChestChoiceAdvancePrefix), null);
        PatchMethod(typeof(PlotController), nameof(PlotController.ChangeNextPlot), Type.EmptyTypes, nameof(TreasureChestChoiceAdvancePrefix), null);
        PatchMethod(typeof(PlotController), nameof(PlotController.GoNextPlot), Type.EmptyTypes, nameof(TreasureChestChoiceAdvancePrefix), null);
        PatchMethod(typeof(PlotController), nameof(PlotController.AutoPlotButtonClicked), Type.EmptyTypes, nameof(TreasureChestChoiceAdvancePrefix), null);
        PatchMethod(typeof(PlotController), nameof(PlotController.ShowPlot), new[] { typeof(PlotData) }, null, nameof(DialogFastForwardShowPlotPostfix));
        PatchMethod(typeof(PlotController), nameof(PlotController.ShowSinglePlot), new[] { typeof(SinglePlotData) }, null, nameof(DialogFastForwardShowSinglePlotPostfix));
        PatchMethod(typeof(PlotController), nameof(PlotController.PlotTextShowFinished), Type.EmptyTypes, null, nameof(DialogFastForwardPlotTextShowFinishedPostfix));
        PatchMethod(typeof(PlotController), nameof(PlotController.PlotChoiceShowFinished), Type.EmptyTypes, null, nameof(DialogFastForwardPlotChoiceShowFinishedPostfix));
        PatchMethod(typeof(PlotController), nameof(PlotController.SkipPlotButtonClicked), Type.EmptyTypes, null, nameof(DialogFastForwardSkipPlotButtonClickedPostfix));
        PatchMethod(typeof(PlotController), nameof(PlotController.SetSkipPlot), new[] { typeof(bool) }, null, nameof(DialogFastForwardSetSkipPlotPostfix));
        PatchMethod(typeof(PlotController), nameof(PlotController.ShowHeroInteractUI), new[] { typeof(HeroData) }, null, nameof(DialogHeroContextPostfix));
        PatchMethod(typeof(PlotController), nameof(PlotController.ManageMeetNpcPlot), new[] { typeof(HeroData) }, null, nameof(DialogHeroContextPostfix));
        PatchMethod(typeof(HeroDetailController), nameof(HeroDetailController.ShowHeroDetail), new[] { typeof(HeroData), typeof(bool) }, null, nameof(HeroDetailViewedHeroPostfix));
        PatchMethod(typeof(HeroDetailController), nameof(HeroDetailController.SetHeroDetail), new[] { typeof(HeroData) }, null, nameof(HeroDetailViewedHeroPostfix));
        PatchMethod(typeof(HeroDetailController), nameof(HeroDetailController.FreshNowHeroDetail), new[] { typeof(HeroData), typeof(bool) }, null, nameof(HeroDetailViewedHeroPostfix));
        PatchMethod(typeof(HeroDetailController), nameof(HeroDetailController.UnshowHeroDetail), Type.EmptyTypes, null, nameof(HeroDetailHiddenPostfix));
        PatchMethod(typeof(PlotController), nameof(PlotController.LoverInteractWithNPC), Type.EmptyTypes, nameof(MaxLoverCountSyncPrefix), null);
        PatchMethod(typeof(PlotController), nameof(PlotController.AskHeroToLover), Type.EmptyTypes, nameof(MaxLoverCountSyncPrefix), null);
        PatchMethod(typeof(PlotController), nameof(PlotController.StartAskHeroToLoverPlot), new[] { typeof(string) }, nameof(MaxLoverCountSyncPrefix), null);
        PatchMethod(typeof(PlotController), nameof(PlotController.SureHeroToLover), Type.EmptyTypes, nameof(MaxLoverCountSyncPrefix), null);
        PatchMethod(typeof(PlotController), nameof(PlotController.FinishHeroToLover), Type.EmptyTypes, nameof(MaxLoverCountSyncPrefix), null);
        PatchMethod(typeof(PlotController), nameof(PlotController.PlotStartLoverResultFight), Type.EmptyTypes, nameof(LoverBattlePlotStartPrefix), null);
        PatchMethod(typeof(PlotController), nameof(PlotController.PlotStartLoverResultFightResult), new[] { typeof(string) }, nameof(LoverBattlePlotResultPrefix), null);
        PatchMethod(typeof(PlotController), nameof(PlotController.CheckChoiceMeetRequire), new[] { typeof(Il2CppSystem.Collections.Generic.List<PlotChoiceRequirement>), typeof(bool) }, nameof(MaxLoverCountSyncPrefix), nameof(CheckChoiceMeetRequirePostfix));
        PatchMethod(typeof(PlotController), nameof(PlotController.CheckMeetRequire), new[] { typeof(ChoiceRequirementType), typeof(float), typeof(bool) }, nameof(MaxLoverCountSyncPrefix), null);
        PatchMethod(typeof(GlobalData), "get_MaxLoverNum", Type.EmptyTypes, null, nameof(GlobalDataMaxLoverNumPostfix));
        PatchMethod(typeof(GameController), nameof(GameController.MeetLoverResultRequire), Type.EmptyTypes, null, nameof(MeetLoverResultRequirePostfix));
        PatchMethod(typeof(BattleController), nameof(BattleController.PrepareBattleMap), new[] { typeof(BattleType), typeof(Il2CppSystem.Collections.Generic.List<HeroData>), typeof(Il2CppSystem.Collections.Generic.List<HeroData>), typeof(Il2CppSystem.Collections.Generic.List<HeroData>), typeof(Il2CppSystem.Collections.Generic.List<HeroData>), typeof(float), typeof(string), typeof(bool), typeof(bool), typeof(BattleMapTypeData), typeof(int), typeof(float) }, nameof(LoverBattlePrepareBattleMapDirectPrefix), null);
        PatchMethod(typeof(BattleController), nameof(BattleController.PrepareBattleMap), new[] { typeof(BattleType), typeof(Il2CppSystem.Collections.Generic.List<Il2CppSystem.Collections.Generic.List<HeroData>>), typeof(Il2CppSystem.Collections.Generic.List<Il2CppSystem.Collections.Generic.List<HeroData>>), typeof(float), typeof(string), typeof(bool), typeof(BattleMapTypeData), typeof(int), typeof(float) }, nameof(LoverBattlePrepareBattleMapGroupedPrefix), null);
        PatchMethod(typeof(BattleController), nameof(BattleController.BattleTeamPrepare), Type.EmptyTypes, nameof(LoverBattleTeamPreparePrefix), null);
        PatchMethod(typeof(PlotInteractController), nameof(PlotInteractController.Update), Type.EmptyTypes, null, nameof(DialogChoiceRowPostfix));
        PatchMethod(typeof(PlotInteractController), nameof(PlotInteractController.OnClick), Type.EmptyTypes, nameof(DialogChoiceClickPrefix), null);
        PatchMethod(typeof(BuildChoiceButtonController), nameof(BuildChoiceButtonController.OnClick), Type.EmptyTypes, null, nameof(TreasureChestChoiceButtonClickedPostfix));
        PatchMethod(typeof(UIButton), nameof(UIButton.OnClick), Type.EmptyTypes, null, nameof(TreasureChestChoiceButtonClickedPostfix));
        PatchMethod(typeof(UIButtonMessage), nameof(UIButtonMessage.OnClick), Type.EmptyTypes, null, nameof(TreasureChestChoiceButtonClickedPostfix));
        PatchMethod(typeof(ButtonClick), nameof(ButtonClick.OnPointerClick), new[] { typeof(PointerEventData) }, null, nameof(TreasureChestChoiceButtonClickedPostfix));
        PatchMethod(typeof(HeroData), nameof(HeroData.AddSkillBookExp), new[] { typeof(float), typeof(KungfuSkillLvData), typeof(bool) }, nameof(AddSkillBookExpPrefix), null);
        PatchMethod(typeof(HeroData), nameof(HeroData.BattleChangeSkillFightExp), new[] { typeof(float), typeof(KungfuSkillLvData), typeof(bool) }, nameof(BattleChangeSkillFightExpPrefix), null);
        PatchMethod(typeof(HeroData), nameof(HeroData.ChangeMoney), new[] { typeof(int), typeof(bool) }, nameof(ChangeMoneyPrefix), nameof(ChangeMoneyPostfix));
        PatchMethod(typeof(HeroData), nameof(HeroData.ChangeFavor), new[] { typeof(float), typeof(bool), typeof(float), typeof(float), typeof(bool) }, nameof(ChangeFavorPrefix), null);
        PatchHeroChangeFameMethod();
        PatchMethod(typeof(PlotController), nameof(PlotController.ManageTeachSkill), new[] { typeof(HeroData), typeof(HeroData), typeof(int), typeof(float), typeof(bool) }, nameof(ManageTeachSkillPrefix), nameof(ManageTeachSkillPostfix));
        PatchMethod(typeof(BattleController), nameof(BattleController.BattleTimeScaleButtonClicked), new[] { typeof(GameObject) }, null, nameof(BattleTimeScaleButtonClickedPostfix));
        PatchMethod(typeof(HorseData), nameof(HorseData.StartSprint), Type.EmptyTypes, null, nameof(HorseStartSprintPostfix));
        PatchMethod(typeof(HeroData), "GetHorseTravelSpeed", Type.EmptyTypes, null, nameof(GetHorseTravelSpeedPostfix));
        PatchMethod(typeof(HeroData), "GetHorseTravelSpeed", new[] { typeof(bool), typeof(bool) }, null, nameof(GetHorseTravelSpeedWithFlagsPostfix));
        PatchMethod(typeof(HeroData), "RefreshHorseState", Type.EmptyTypes, null, nameof(RefreshHorseStatePostfix));
        PatchMethod(typeof(BuildingUIController), nameof(BuildingUIController.ShowBuildingShop), Type.EmptyTypes, null, nameof(ShowBuildingShopPostfix));
        PatchMethod(typeof(TradeUIController), nameof(TradeUIController.ShowTradeUI), new[] { typeof(TradeUIType), typeof(ItemListData), typeof(ItemListData), typeof(bool) }, null, nameof(ShowTradeUiBasicPostfix));
        PatchMethod(typeof(TradeUIController), nameof(TradeUIController.ShowTradeUI), new[] { typeof(TradeUIType), typeof(ItemListType), typeof(ItemListData), typeof(ItemListData) }, null, nameof(ShowTradeUiTypedPostfix));
        PatchMethod(typeof(TradeUIController), nameof(TradeUIController.ShowTradeUI), new[] { typeof(TradeUIType), typeof(ItemListData), typeof(ItemListData), typeof(int), typeof(int) }, null, nameof(ShowTradeUiLevelRangePostfix));
        PatchMethod(typeof(TradeUIController), nameof(TradeUIController.ShowTradeUI), new[] { typeof(TradeUIType), typeof(ItemListType), typeof(ItemListData), typeof(ItemListData), typeof(int), typeof(int), typeof(bool), typeof(bool), typeof(float), typeof(float) }, null, nameof(ShowTradeUiFullPostfix));
        PatchMethod(typeof(TradeUIController), nameof(TradeUIController.HideTradeUI), Type.EmptyTypes, null, nameof(HideTradeUiPostfix));
        PatchMethod(typeof(ItemIconController), nameof(ItemIconController.OnClick), Type.EmptyTypes, null, nameof(ItemIconOnClickPostfix));
        PatchMethod(typeof(IdentifyMatchController), "set_correctTreasure", new[] { typeof(Il2CppSystem.Collections.Generic.List<GameObject>) }, null, nameof(IdentifyCorrectTreasurePostfix));
        PatchMethod(typeof(IdentifyMatchController), nameof(IdentifyMatchController.SetNowChooseTreasure), new[] { typeof(GameObject) }, nameof(IdentifySetNowChooseTreasurePrefix), null);
        PatchMethod(typeof(IdentifyMatchController), nameof(IdentifyMatchController.SureButtonClicked), Type.EmptyTypes, nameof(IdentifySureButtonClickedPrefix), null);
        PatchMethod(typeof(DebateUIController), nameof(DebateUIController.ChangePatient), new[] { typeof(bool), typeof(float) }, nameof(DebateChangePatientPrefix), null);
        PatchMethod(typeof(CraftUIController), nameof(CraftUIController.OpenCraftUI), new[] { typeof(CraftType), typeof(AreaBuildingData), typeof(bool) }, null, nameof(OpenCraftUiPostfix));
        PatchMethod(typeof(CraftUIController), nameof(CraftUIController.HideCraftUI), Type.EmptyTypes, null, nameof(HideCraftUiPostfix));
        PatchMethod(typeof(CraftUIController), nameof(CraftUIController.GetMaretialExtraCraftRate), Type.EmptyTypes, null, nameof(GetCraftMaterialExtraCraftRatePostfix));
        PatchMethod(typeof(CraftUIController), nameof(CraftUIController.CraftResultChoosen), new[] { typeof(int) }, null, nameof(CraftUiResultChoosenPostfix));
        PatchMethod(typeof(ItemData), nameof(ItemData.GetMaterialExtraCraftRate), Type.EmptyTypes, null, nameof(GetItemMaterialExtraCraftRatePostfix));
        PatchMethod(typeof(PlotController), nameof(PlotController.RealStartReadBook), Type.EmptyTypes, nameof(ReadBookTaskStartPrefix), null);
        PatchMethod(typeof(PlotController), nameof(PlotController.ReadBookChoosen), Type.EmptyTypes, nameof(ReadBookTracePrefix), null);
        PatchMethod(typeof(PlotController), nameof(PlotController.ChooseReadBook), new[] { typeof(string) }, nameof(ReadBookTracePrefix), null);
        PatchMethod(typeof(ReadBookController), nameof(ReadBookController.ShowReadBookPanel), Type.EmptyTypes, nameof(ReadBookTracePrefix), null);
        PatchMethod(typeof(ReadBookController), nameof(ReadBookController.GenerateReadBookPanel), Type.EmptyTypes, nameof(ReadBookTracePrefix), null);
        PatchMethod(typeof(ReadBookController), nameof(ReadBookController.ChangePatient), new[] { typeof(int) }, nameof(ReadBookTracePrefix), null);
        PatchMethod(typeof(ReadBookController), nameof(ReadBookController.AutoReadBook), Type.EmptyTypes, nameof(ReadBookTracePrefix), null);
        PatchMethod(typeof(ReadBookController), nameof(ReadBookController.Update), Type.EmptyTypes, null, nameof(ReadBookUpdatePostfix));
        PatchMethod(typeof(ReadBookController), nameof(ReadBookController.GetReadExp), new[] { typeof(float) }, nameof(ReadBookTracePrefix), null);
        PatchMethod(typeof(ReadBookController), nameof(ReadBookController.GetTotalExp), Type.EmptyTypes, nameof(ReadBookTracePrefix), null);
        PatchMethod(typeof(ReadBookController), nameof(ReadBookController.StartReadBook), new[] { typeof(HeroData), typeof(ItemData), typeof(bool), typeof(bool) }, nameof(ReadBookTracePrefix), null);
        PatchMethod(typeof(ReadBookController), nameof(ReadBookController.SureStartReadBook), Type.EmptyTypes, nameof(ReadBookTaskStartPrefix), null);
        PatchMethod(typeof(ReadBookController), nameof(ReadBookController.RealStartReadBook), Type.EmptyTypes, nameof(ReadBookTaskStartPrefix), null);
        PatchMethod(typeof(ReadBookController), nameof(ReadBookController.FinishRead), Type.EmptyTypes, null, nameof(ReadBookFinishPostfix));
        PatchMethod(typeof(BookWriterUIController), nameof(BookWriterUIController.SureButtonClicked), new[] { typeof(GameObject) }, nameof(BookWriterSureButtonPrefix), nameof(BookWriterSureButtonPostfix));
        PatchMethod(typeof(BookWriterData), nameof(BookWriterData.GetTotalTimeCost), Type.EmptyTypes, null, nameof(BookWriterTotalTimeCostPostfix));
        PatchMethod(typeof(BookWriterData), nameof(BookWriterData.GetEachDayWorkPercent), Type.EmptyTypes, null, nameof(BookWriterEachDayWorkPercentPostfix));
        PatchMethod(typeof(StudySkillController), nameof(StudySkillController.SureStartStudySkill), Type.EmptyTypes, nameof(RealStartStudySkillPrefix), null);
        PatchMethod(typeof(StudySkillController), "PlayerStudySkill", Type.EmptyTypes, nameof(StudySkillTracePrefix), null);
        PatchMethod(typeof(StudySkillController), "StartStudySkill", new[] { typeof(StudySkillType), typeof(KungfuSkillLvData), typeof(string), typeof(AreaBuildingData), typeof(bool) }, nameof(StudySkillTracePrefix), null);
        PatchMethod(typeof(StudySkillController), nameof(StudySkillController.GetAutoPracticeCost), Type.EmptyTypes, null, nameof(GetAutoPracticeCostPostfix));
        PatchMethod(typeof(KungfuSkillLvData), nameof(KungfuSkillLvData.StudyMoneyCost), Type.EmptyTypes, null, nameof(StudyMoneyCostPostfix));
        PatchMethod(typeof(KungfuSkillLvData), nameof(KungfuSkillLvData.StudyDayCost), Type.EmptyTypes, null, nameof(StudyDayCostPostfix));
        PatchMethod(typeof(StudyAttackSkillController), "StartStudyFightSkill", new[] { typeof(KungfuSkillLvData) }, nameof(StudySkillTracePrefix), null);
        PatchMethod(typeof(StudyDodgeSkillController), "StartStudyDodgeSkill", new[] { typeof(KungfuSkillLvData) }, nameof(StudySkillTracePrefix), null);
        PatchMethod(typeof(StudyInternalSkillController), "StartStudyInternalSkill", new[] { typeof(KungfuSkillLvData) }, nameof(StudySkillTracePrefix), null);
        PatchMethod(typeof(StudyUniqueSkillController), "StartStudyUniqueSkill", new[] { typeof(KungfuSkillLvData) }, nameof(StudySkillTracePrefix), null);
        PatchMethod(typeof(MailData), ".ctor", new[] { typeof(string), typeof(string), typeof(TimeData), typeof(bool), typeof(bool) }, null, nameof(MailDataCtorPostfix));
        PatchMethod(typeof(GameController), nameof(GameController.GetNewMail), new[] { typeof(MailData), typeof(HeroData) }, null, nameof(GetNewMailPostfix));
        PatchMethod(typeof(StudySkillController), nameof(StudySkillController.RealStartStudySkill), Type.EmptyTypes, nameof(RealStartStudySkillPrefix), null);
        PatchMethod(typeof(StudySkillController), nameof(StudySkillController.FinishStudySkill), new[] { typeof(float) }, null, nameof(FinishStudySkillPostfix));
        PatchMethod(typeof(PlotController), nameof(PlotController.CraftResultChoosen), new[] { typeof(ItemData) }, nameof(CraftResultChoosenPrefix), nameof(CraftResultChoosenPostfix));
        PatchMethod(typeof(PlotController), nameof(PlotController.SetPlotItem), new[] { typeof(ItemData), typeof(bool) }, null, nameof(SetPlotItemPostfix));
        PatchMethod(typeof(PlotController), nameof(PlotController.PlayerGetPlotItem), Type.EmptyTypes, nameof(PlayerGetPlotItemPrefix), nameof(PlayerGetPlotItemPostfix));
        PatchMethod(typeof(PlotController), nameof(PlotController.PlayerGetPlotItemSimple), Type.EmptyTypes, nameof(PlayerGetPlotItemSimplePrefix), nameof(PlayerGetPlotItemSimplePostfix));
        PatchMethod(typeof(PlotController), nameof(PlotController.FinishCraft), Type.EmptyTypes, nameof(FinishCraftPrefix), nameof(FinishCraftPostfix));
        PatchMethod(typeof(PlotController), nameof(PlotController.FinishCraftPoison), Type.EmptyTypes, nameof(FinishCraftPoisonPrefix), nameof(FinishCraftPoisonPostfix));
        PatchMethod(typeof(DrinkUIController), nameof(DrinkUIController.ShowDrinkUI), new[] { typeof(DrinkType), typeof(HeroData), typeof(ItemData), typeof(string) }, null, nameof(DrinkShowUiPostfix));
        PatchMethod(typeof(DrinkUIController), nameof(DrinkUIController.GetDrinkCost), new[] { typeof(float) }, null, nameof(DrinkGetCostPostfix));
        PatchMethod(typeof(DrinkUIController), nameof(DrinkUIController.HideDrinkUI), Type.EmptyTypes, null, nameof(DrinkHideUiPostfix));
        PatchMethod(typeof(StartMenuController), nameof(StartMenuController.SetAttriPreset), new[] { typeof(int) }, null, nameof(SetAttriPresetPostfix));
        PatchMethod(typeof(StartMenuController), nameof(StartMenuController.ResetPlayerAttri), Type.EmptyTypes, null, nameof(ResetPlayerAttriPostfix));
        PatchMethod(typeof(StartMenuController), nameof(StartMenuController.ShowStartMenu), Type.EmptyTypes, null, nameof(ShowStartMenuPostfix));
        PatchMethod(typeof(GameTitleController), nameof(GameTitleController.ShowMainMenu), Type.EmptyTypes, null, nameof(ShowMainMenuPostfix));
        PatchMethod(typeof(SaveLoadMenuController), nameof(SaveLoadMenuController.SaveSlotButtonClicked), new[] { typeof(int) }, nameof(SaveSlotButtonClickedPrefix), null);
        PatchMethod(typeof(SaveLoadMenuController), nameof(SaveLoadMenuController.SureSave), new[] { typeof(string) }, null, nameof(SureSavePostfix));
        PatchMethod(typeof(SaveLoadMenuController), nameof(SaveLoadMenuController.LoadRecentGame), Type.EmptyTypes, nameof(LoadRecentGamePrefix), null);
        PatchMethod(typeof(SaveLoadMenuController), nameof(SaveLoadMenuController.LoadGame), new[] { typeof(int) }, nameof(LoadGamePrefix), null);
        PatchMethod(typeof(GameDataController), nameof(GameDataController.LoadAllGameData), Type.EmptyTypes, null, nameof(LoadAllGameDataPostfix));
        PatchMethod(typeof(GameController), "Update", Type.EmptyTypes, null, nameof(GameControllerUpdatePostfix));
        PatchMethod(typeof(GameController), nameof(GameController.ChangeDay), Type.EmptyTypes, nameof(CalendarChangePrefix), nameof(CalendarChangePostfix));
        PatchMethod(typeof(GameController), nameof(GameController.ChangeDay), new[] { typeof(int) }, nameof(CalendarChangePrefix), nameof(CalendarChangePostfix));
        PatchMethod(typeof(GameController), nameof(GameController.ChangeDayDirect), new[] { typeof(int) }, nameof(CalendarChangePrefix), nameof(CalendarChangePostfix));
        PatchMethod(typeof(GameController), nameof(GameController.ChangeMonth), Type.EmptyTypes, nameof(CalendarChangePrefix), nameof(CalendarChangePostfix));
        PatchMethod(typeof(GameController), nameof(GameController.ChangeMonthDirect), new[] { typeof(int) }, nameof(CalendarChangePrefix), nameof(CalendarChangePostfix));
        PatchMethod(typeof(GameController), nameof(GameController.ChangeYear), Type.EmptyTypes, nameof(CalendarChangePrefix), nameof(CalendarChangePostfix));
        PatchMethod(typeof(GameController), nameof(GameController.ChangeYearDirect), new[] { typeof(int) }, nameof(CalendarChangePrefix), nameof(CalendarChangePostfix));
        PatchMethod(typeof(GameController), nameof(GameController.ChangeHour), new[] { typeof(float) }, nameof(HourChangePrefix), nameof(HourChangePostfix));

        Log.LogInfo("LongYin Stamina Lock loaded.");
        Log.LogInfo("Legacy in-game mod panel is disabled. External Mod Control is the supported UI path.");
        Log.LogInfo($"Exploration stamina lock starts {(_lockExploreStamina.Value ? "ON" : "OFF")}.");
        Log.LogInfo($"Exploration first-move full reveal starts {(_revealAllOnStepTile.Value ? "ON" : "OFF")}.");
        Log.LogInfo(
            $"Exploration treasure chest choice mode starts {(_treasureChestChoiceEnabled.Value ? "ON" : "OFF")} with a 3-5 option chest-only picker " +
            $"and highest-value auto-pick {(_treasureChestAutoPickMostValuable.Value ? "ON" : "OFF")}.");
        Log.LogInfo($"Exploration treasure chest rewards start at x{Math.Max(1, _treasureChestTotalItems.Value)} total items when choice mode is OFF.");
        Log.LogInfo($"Read-book EXP multiplier starts at x{Mathf.Max(1, _bookExpMultiplier.Value)}.");
        Log.LogInfo($"Book-writing cost multiplier starts at x{FormatConfigFloat(Math.Max(0f, _studySkillCostMultiplier.Value))}.");
        Log.LogInfo(
            $"Threshold talent prototype starts {(_thresholdTalentEnabled.Value ? "ON" : "OFF")}: " +
            $"{GetConfiguredThresholdTalentName()} on {_thresholdTalentRequirementAttribute.Value} >= {SafeFormatValue(_thresholdTalentRequirementValue.Value)} " +
            $"gives {_thresholdTalentBuffType.Value} {SafeFormatValue(_thresholdTalentBuffValue.Value)}.");
        Log.LogInfo($"Battle skill EXP multiplier starts at x{Mathf.Max(1, _battleSkillExpMultiplier.Value)}.");
        Log.LogInfo($"Character creation point multiplier starts at x{Math.Max(1, _creationPointMultiplier.Value)}.");
        Log.LogInfo($"Battle speed multiplier starts at x{Math.Max(1, _battleSpeedMultiplier.Value)}.");
        Log.LogInfo($"World-map horse base speed multiplier starts at x{FormatConfigFloat(_horseBaseSpeedMultiplier.Value)}.");
        Log.LogInfo($"World-map horse turbo speed multiplier starts at x{FormatConfigFloat(_horseTurboSpeedMultiplier.Value)}.");
        Log.LogInfo($"World-map horse turbo duration multiplier starts at x{FormatConfigFloat(_horseTurboDurationMultiplier.Value)}.");
        Log.LogInfo($"World-map horse turbo cooldown multiplier starts at x{FormatConfigFloat(_horseTurboCooldownMultiplier.Value)}.");
        Log.LogInfo($"World-map horse turbo stamina lock starts {(_lockHorseTurboStamina.Value ? "ON" : "OFF")}.");
        Log.LogInfo($"Carry-weight cap starts at {Math.Max(0f, _carryWeightCap.Value):0.###}.");
        Log.LogInfo($"Ignore carry weight starts {(_ignoreCarryWeight.Value ? "ON" : "OFF")}.");
        Log.LogInfo($"Merchant cash floor starts at {Math.Max(0, _merchantCarryCash.Value)}.");
        Log.LogInfo($"Treasure trade helper starts {(_treasureTradeHelperEnabled.Value ? "ON" : "OFF")}.");
        Log.LogInfo($"Treasure auto cart starts {(_treasureAutoTradeEnabled.Value ? "ON" : "OFF")}.");
        Log.LogInfo($"Treasure identify highlight starts {(_treasureIdentifyHighlightCorrect.Value ? "ON" : "OFF")}.");
        Log.LogInfo($"Treasure identify force-correct starts {(_treasureIdentifyForceCorrectSelection.Value ? "ON" : "OFF")}.");
        Log.LogInfo($"Lucky money hit chance starts at {ClampPercent(_luckyMoneyHitChancePercent.Value)}%.");
        Log.LogInfo($"Extra relationship gain chance starts at {ClampPercent(_extraRelationshipGainChancePercent.Value)}%.");
        Log.LogInfo($"Team auto favor starts {(_teamAutoFavorEnabled.Value ? "ON" : "OFF")} at +{FormatConfigFloat(Math.Max(0f, _teamAutoFavorPerDay.Value))}/day.");
        Log.LogInfo($"Team fame share starts at {FormatConfigFloat(TeamFameShareRatio * 100f)}% of player fame gains.");
        Log.LogInfo($"Max lover count override starts at {Math.Max(1, _maxLoverCount.Value)}.");
        Log.LogInfo($"Lover home battle blocker starts {(_blockOverflowLoverHomeBattle.Value ? "ON" : "OFF")}.");
        Log.LogInfo($"Debate player damage taken multiplier starts at x{FormatConfigFloat(_debatePlayerDamageTakenMultiplier.Value)}.");
        Log.LogInfo($"Debate enemy damage taken multiplier starts at x{FormatConfigFloat(_debateEnemyDamageTakenMultiplier.Value)}.");
        Log.LogInfo(
            $"Craft added-material quantity bonus starts {(_craftRandomPickUpgradeEnabled.Value ? "ON" : "OFF")} " +
            $"with tier bonuses [{GetCraftConfiguredExtraItems(1)},{GetCraftConfiguredExtraItems(2)},{GetCraftConfiguredExtraItems(3)},{GetCraftConfiguredExtraItems(4)},{GetCraftConfiguredExtraItems(5)}].");
        Log.LogInfo($"Drink player Qi cost multiplier starts at x{FormatConfigFloat(_drinkPlayerPowerCostMultiplier.Value)}.");
        Log.LogInfo($"Drink enemy Qi cost multiplier starts at x{FormatConfigFloat(_drinkEnemyPowerCostMultiplier.Value)}.");
        Log.LogInfo(
            $"Daily skill insight starts at {ClampPercent(_dailySkillInsightHitChancePercent.Value)}% for {Math.Max(0f, _dailySkillInsightExpPercent.Value):0.###}% max EXP " +
            $"with rarity scaling {(_dailySkillInsightUseRarityScaling.Value ? "ON" : "OFF")}.");
        Log.LogInfo($"Daily skill insight real-time test interval starts at {Math.Max(0f, _dailySkillInsightRealtimeIntervalSeconds.Value):0.###} seconds.");
        Log.LogInfo(
            $"Same-sect teaching splash starts {(_teachSkillSameSectAreaShareEnabled.Value ? "ON" : "OFF")} " +
            $"at {ClampTeachSkillSplashPercent(_teachSkillSameSectAreaShareMinPercent.Value)}%-{ClampTeachSkillSplashPercent(_teachSkillSameSectAreaShareMaxPercent.Value)}%.");
        Log.LogInfo($"Dialog monthly limit multiplier starts at x{FormatConfigFloat(_dialogMonthlyLimitMultiplier.Value)}.");
        Log.LogInfo($"Dialog fast-forward assist starts {(_dialogFastForwardAssistEnabled.Value ? "ON" : "OFF")} with hotkey {_dialogFastForwardAssistHotkey.Value}.");
        Log.LogInfo($"Tracer master starts {(_traceMode.Value ? "ON" : "OFF")}.");
        Log.LogInfo($"Battle skill EXP tracer starts {(_traceBattleSkillExp.Value ? "ON" : "OFF")}.");
        Log.LogInfo($"Dialog fast-forward tracer starts {(_traceDialogFastForward.Value ? "ON" : "OFF")}.");
        Log.LogInfo($"Treasure chest tracer starts {(_traceTreasureChestEvents.Value ? "ON" : "OFF")}.");
        Log.LogInfo($"Lover battle prep tracer starts {(_traceLoverBattlePrep.Value ? "ON" : "OFF")}.");
        Log.LogInfo($"Date freeze starts {(_freezeDate.Value ? "ON" : "OFF")} with hotkey {_freezeDateHotkey.Value}.");
        Log.LogInfo($"Outside-battle speed cycle hotkey is {_outsideBattleSpeedHotkey.Value}.");
    }

    private void PatchMethod(Type type, string methodName, Type[] parameterTypes, string? prefixName, string? postfixName)
    {
        MethodBase? target = string.Equals(methodName, ".ctor", StringComparison.Ordinal)
            ? AccessTools.Constructor(type, parameterTypes)
            : AccessTools.Method(type, methodName, parameterTypes);
        var prefix = prefixName == null ? null : AccessTools.Method(typeof(LongYinStaminaLockPlugin), prefixName);
        var postfix = postfixName == null ? null : AccessTools.Method(typeof(LongYinStaminaLockPlugin), postfixName);

        if (target == null)
        {
            Log.LogWarning($"Could not patch {type.Name}.{methodName}({parameterTypes.Length} params)");
            return;
        }

        _harmony!.Patch(
            target,
            prefix: prefix == null ? null : new HarmonyMethod(prefix),
            postfix: postfix == null ? null : new HarmonyMethod(postfix));
        Log.LogInfo($"Patched {type.Name}.{target.Name}({target.GetParameters().Length} params)");
    }

    private void PatchHeroChangeFameMethod()
    {
        var target = typeof(HeroData)
            .GetMethods(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance)
            .FirstOrDefault(method =>
            {
                if (!string.Equals(method.Name, nameof(HeroData.ChangeFame), StringComparison.Ordinal))
                {
                    return false;
                }

                var parameters = method.GetParameters();
                if (parameters.Length != 2 || parameters[1].ParameterType != typeof(bool))
                {
                    return false;
                }

                var firstParameterType = parameters[0].ParameterType;
                return firstParameterType == typeof(int) || firstParameterType == typeof(float) || firstParameterType == typeof(double);
            });

        if (target == null)
        {
            Log.LogWarning("Could not patch HeroData.ChangeFame(*) for team fame share.");
            return;
        }

        _heroChangeFameMethod = target;
        var prefix = AccessTools.Method(typeof(LongYinStaminaLockPlugin), nameof(ChangeFamePrefix));
        var postfix = AccessTools.Method(typeof(LongYinStaminaLockPlugin), nameof(ChangeFamePostfix));
        _harmony!.Patch(
            target,
            prefix: prefix == null ? null : new HarmonyMethod(prefix),
            postfix: postfix == null ? null : new HarmonyMethod(postfix));
        Log.LogInfo(
            $"Patched HeroData.{target.Name}({target.GetParameters().Length} params) for team fame share using {target.GetParameters()[0].ParameterType.Name} delta.");
    }

    private static void ChangeMoveStepPrefix(ref int num)
    {
        if (_lockExploreStamina.Value && num < 0)
        {
            num = 0;
        }
    }

    private static void ChangeMoveStepWithBoolPrefix(ref int num, bool showText)
    {
        ChangeMoveStepPrefix(ref num);
    }

    private static void GenerateExploreMapPostfix()
    {
        ResetExploreFullReveal("GenerateExploreMap");
    }

    private static void ResetExploreMapPostfix()
    {
        ResetExploreFullReveal("ResetExploreMap");
    }

    private static void PlayerFinishMovePostfix(ExploreController __instance)
    {
        TryRevealAllExploreFogAfterFirstMove(__instance);
    }

    private static void ManageTileEventPrefix(ExploreTileData targetTileData, out ExploreHealingState __state)
    {
        var player = TryGetPlayerHero();
        __state = new ExploreHealingState
        {
            Player = player,
            ExternalInjuryBefore = player?.externalInjury ?? 0f,
            InternalInjuryBefore = player?.internalInjury ?? 0f,
            PoisonInjuryBefore = player?.poisonInjury ?? 0f,
            IsHealingTile = IsHealingStateTile(targetTileData)
        };
    }

    private static void ManageTileEventPostfix(ExploreController __instance, ExploreTileData targetTileData, ExploreHealingState __state)
    {
        TryHandleHealingStateTile(targetTileData, __state);
    }

    private static bool TreasureChestGetItemPrefix(HeroData __instance, ItemData itemData, bool showPopInfo, bool showSpeGetItem, int treasureChestClickTime, bool skipManageItemPoison)
    {
        TraceTreasureChestEvent(
            "HeroData.GetItem prefix",
            __instance,
            itemData,
            treasureChestClickTime,
            skipManageItemPoison,
            $"showPopInfo={showPopInfo}, showSpeGetItem={showSpeGetItem}");
        return !TryStartTreasureChestChoice(__instance, itemData, treasureChestClickTime, skipManageItemPoison);
    }

    private static void TreasureChestGetItemPostfix(HeroData __instance, ItemData itemData, bool showPopInfo, bool showSpeGetItem, int treasureChestClickTime, bool skipManageItemPoison)
    {
        TraceTreasureChestEvent(
            "HeroData.GetItem postfix",
            __instance,
            itemData,
            treasureChestClickTime,
            skipManageItemPoison,
            $"showPopInfo={showPopInfo}, showSpeGetItem={showSpeGetItem}, choiceEnabled={_treasureChestChoiceEnabled.Value}");
        if (!_treasureChestChoiceEnabled.Value)
        {
            TryGrantTreasureChestBonusItems(__instance, itemData, treasureChestClickTime, skipManageItemPoison);
        }

        TryGrantCraftBonusItems(__instance, itemData, treasureChestClickTime, skipManageItemPoison);
    }

    private static void BasicGetItemPostfix(HeroData __instance, ItemData itemData, bool showPopInfo)
    {
        TryGrantCraftBonusItems(__instance, itemData, 0, false);
    }

    private static void ItemListGetItemPostfix(ItemListData __instance, ItemData targetItem, bool showPopInfo)
    {
        var bonusState = _activeCraftRewardBonus;
        if (!_craftRandomPickUpgradeEnabled.Value || bonusState == null || bonusState.ExtraItemCount <= 0)
        {
            return;
        }

        var playerInventory = TryGetPlayerHero()?.itemListData;
        LogCraftEvent(
            $"ItemListData.GetItem observed item={DescribeItemSummary(targetItem)}, activeBonus={bonusState.ExtraItemCount}, consumed={bonusState.Consumed}, playerInventory={SafeFormatValue(playerInventory != null && ReferenceEquals(playerInventory, __instance))}, replayingChoice={SafeFormatValue(_repeatingCraftChoiceReward)}");
    }

    private static void CraftUiResultChoosenPostfix(CraftUIController __instance, int id)
    {
        if (!_craftRandomPickUpgradeEnabled.Value || _repeatingCraftChoiceReward)
        {
            return;
        }

        var bonusState = ResolveCraftRewardBonusState(__instance);
        _activeCraftRewardBonus = bonusState;
        var craftResult = ResolveCraftResultByIndex(__instance, id);
        LogCraftEvent(
            $"CraftUIController.CraftResultChoosen observed id={id}, item={DescribeItemSummary(craftResult)}, activeBonus={(bonusState == null ? "none" : bonusState.ExtraItemCount.ToString())}, consumed={SafeFormatValue(bonusState?.Consumed)}");
    }

    private static bool TreasureChestChoicePlotCallbackPrefix(object[] __args)
    {
        var param = __args != null && __args.Length > 0 ? __args[0] as string : null;
        return !TryResolveTreasureChestChoiceFromPlot(param);
    }

    private static bool TreasureChestChoiceAdvancePrefix(PlotController? __instance)
    {
        if (_treasureChestChoiceClosingPlot)
        {
            return true;
        }

        var session = _activeTreasureChestChoiceSession;
        if (session != null && !session.Resolved)
        {
            TryResolveTreasureChestChoiceAndClose(__instance);
            return false;
        }

        return true;
    }

    private static void TreasureChestChoiceButtonClickedPostfix()
    {
        var session = _activeTreasureChestChoiceSession;
        if (session != null)
        {
            session.PendingClickConfirm = true;
        }
    }

    private static void TryHandleHealingStateTile(ExploreTileData? targetTileData, ExploreHealingState? healingState)
    {
        if (healingState == null)
        {
            return;
        }

        var player = healingState.Player ?? TryGetPlayerHero();
        if (player == null)
        {
            return;
        }

        var externalAfter = player.externalInjury;
        var internalAfter = player.internalInjury;
        var poisonAfter = player.poisonInjury;
        var anyHealingDetected =
            externalAfter + 0.001f < healingState.ExternalInjuryBefore ||
            internalAfter + 0.001f < healingState.InternalInjuryBefore ||
            poisonAfter + 0.001f < healingState.PoisonInjuryBefore;

        if (!healingState.IsHealingTile && !anyHealingDetected)
        {
            return;
        }

        var curedAnything = false;

        try
        {
            curedAnything |= TryClearHeroInjuryValue(player, player.externalInjury, static (hero, amount) => hero.ChangeExternalInjury(-amount, false, false, false), "externalInjury");
        }
        catch
        {
            curedAnything |= TrySetFloatMembers(player, new[] { "externalInjury", "ExternalInjury" }, 0f);
        }

        try
        {
            curedAnything |= TryClearHeroInjuryValue(player, player.internalInjury, static (hero, amount) => hero.ChangeInternalInjury(-amount, false, false, false), "internalInjury");
        }
        catch
        {
            curedAnything |= TrySetFloatMembers(player, new[] { "internalInjury", "InternalInjury" }, 0f);
        }

        try
        {
            curedAnything |= TryClearHeroInjuryValue(player, player.poisonInjury, static (hero, amount) => hero.ChangePoisonInjury(-amount, false, false, false), "poisonInjury");
        }
        catch
        {
            curedAnything |= TrySetFloatMembers(player, new[] { "poisonInjury", "PoisonInjury" }, 0f);
        }

        if (curedAnything)
        {
            PushPlayerLog("治疗地块额外清除了外伤、内伤、毒伤");
            LoggerInstance.LogInfo(
                $"Healing tile cleared all injury types: hero={TryGetHeroName(player)}, " +
                $"external={SafeFormatValue(player.externalInjury)}, internal={SafeFormatValue(player.internalInjury)}, poison={SafeFormatValue(player.poisonInjury)}.");
        }
    }

    private static bool TryStartTreasureChestChoice(HeroData? targetHero, ItemData? itemData, int treasureChestClickTime, bool skipManageItemPoison)
    {
        if (treasureChestClickTime > 0)
        {
            TraceTreasureChestEvent("TryStartTreasureChestChoice enter", targetHero, itemData, treasureChestClickTime, skipManageItemPoison);
        }

        if (!_treasureChestChoiceEnabled.Value || _grantingTreasureChestChoiceReward || _grantingTreasureChestBonusItems)
        {
            if (treasureChestClickTime > 0)
            {
                TraceTreasureChestEvent(
                    "TryStartTreasureChestChoice skip",
                    targetHero,
                    itemData,
                    treasureChestClickTime,
                    skipManageItemPoison,
                    $"choiceEnabled={_treasureChestChoiceEnabled.Value}, grantingChoiceReward={_grantingTreasureChestChoiceReward}, grantingBonusItems={_grantingTreasureChestBonusItems}");
            }
            return false;
        }

        if (treasureChestClickTime <= 0 || targetHero == null || itemData == null)
        {
            return false;
        }

        if (ShouldSkipTreasureChestChoiceForOriginalReward(itemData))
        {
            TraceTreasureChestEvent(
                "TryStartTreasureChestChoice skip original book/manual reward",
                targetHero,
                itemData,
                treasureChestClickTime,
                skipManageItemPoison,
                $"itemType={SafeFormatValue(TryGetItemTypeName(itemData))}");
            return false;
        }

        var player = TryGetPlayerHero();
        if (player == null || TryGetHeroId(targetHero) != TryGetHeroId(player))
        {
            TraceTreasureChestEvent(
                "TryStartTreasureChestChoice skip non-player",
                targetHero,
                itemData,
                treasureChestClickTime,
                skipManageItemPoison,
                $"player={TryGetHeroName(player)}/{SafeFormatValue(TryGetHeroId(player))}");
            return false;
        }

        if (_activeTreasureChestChoiceSession != null)
        {
            LoggerInstance.LogWarning("Skipped treasure chest choice because another chest choice session is already active.");
            TraceTreasureChestEvent("TryStartTreasureChestChoice skip active session", targetHero, itemData, treasureChestClickTime, skipManageItemPoison);
            return false;
        }

        var options = BuildTreasureChestChoiceOptions(itemData, player);
        if (options.Count <= 1)
        {
            TraceTreasureChestEvent(
                "TryStartTreasureChestChoice skip insufficient options",
                targetHero,
                itemData,
                treasureChestClickTime,
                skipManageItemPoison,
                $"options={DescribeItemSummaries(options)}");
            return false;
        }

        if (!TryShowTreasureChestChoicePlot(player, options, skipManageItemPoison))
        {
            TraceTreasureChestEvent(
                "TryStartTreasureChestChoice failed to show plot",
                targetHero,
                itemData,
                treasureChestClickTime,
                skipManageItemPoison,
                $"options={DescribeItemSummaries(options)}");
            return false;
        }

        TraceTreasureChestEvent(
            "TryStartTreasureChestChoice activated",
            targetHero,
            itemData,
            treasureChestClickTime,
            skipManageItemPoison,
            $"options={DescribeItemSummaries(options)}");
        LoggerInstance.LogInfo(
            $"Treasure chest opened as choose-one reward with {options.Count} options: " +
            $"{string.Join(", ", DescribeItemNames(options))}.");
        return true;
    }

    private static List<ItemData> BuildTreasureChestChoiceOptions(ItemData sourceItem, HeroData player)
    {
        var options = new List<ItemData>();
        var seenKeys = new HashSet<string>(StringComparer.Ordinal);

        AddTreasureChestChoiceOption(options, seenKeys, sourceItem);

        var maxChoiceCount = Math.Max(3, Math.Min(5, _treasureChestChoiceOptions.Value));
        var desiredCount = maxChoiceCount <= 3 ? 3 : Random.Next(3, maxChoiceCount + 1);
        var maxAttempts = Math.Max(desiredCount * 4, 8);
        for (var attempt = 0; attempt < maxAttempts && options.Count < desiredCount; attempt++)
        {
            var generated = TryCreateTreasureChestBonusItem(sourceItem, player);
            AddTreasureChestChoiceOption(options, seenKeys, generated);
        }

        TraceTreasureChestEvent(
            "BuildTreasureChestChoiceOptions result",
            player,
            sourceItem,
            1,
            false,
            $"desiredCount={desiredCount}, maxChoiceCount={maxChoiceCount}, options={DescribeItemSummaries(options)}");
        return options;
    }

    private static void AddTreasureChestChoiceOption(List<ItemData> options, HashSet<string> seenKeys, ItemData? item)
    {
        if (item == null)
        {
            return;
        }

        var key = $"{item.itemID}|{item.itemLv}|{item.rareLv}|{item.value}|{item.name}";
        if (!seenKeys.Add(key))
        {
            return;
        }

        options.Add(item);
    }

    private static bool TryShowTreasureChestChoicePlot(HeroData player, List<ItemData> options, bool skipManageItemPoison)
    {
        var plotController = PlotController.Instance;
        if (plotController == null)
        {
            LoggerInstance.LogWarning("Could not show treasure chest choice plot because PlotController was unavailable.");
            return false;
        }

        var choiceTexts = new Il2CppSystem.Collections.Generic.List<string>();
        foreach (var option in options)
        {
            choiceTexts.Add(option.name ?? $"id={option.itemID}");
        }

        _activeTreasureChestChoiceSession = new TreasureChestChoiceSession
        {
            Player = player,
            Options = options,
            SkipManageItemPoison = skipManageItemPoison,
            OpenedAtRealtime = Time.realtimeSinceStartup,
            PendingAutoPick = _treasureChestAutoPickMostValuable.Value,
            PendingAutoPickFrames = _treasureChestAutoPickMostValuable.Value ? 2 : 0
        };

        try
        {
            var choiceDataList = new Il2CppSystem.Collections.Generic.List<SinglePlotChoiceData>();
            for (var i = 0; i < options.Count; i++)
            {
                var choice = new SinglePlotChoiceData
                {
                    inited = true,
                    choiceText = options[i].name ?? $"id={options[i].itemID}",
                    callFuc = TreasureChestChoicePlotCallbackName,
                    callParam = TreasureChestChoiceParamPrefix + i,
                    describe = DescribeItemSummary(options[i])
                };
                choiceDataList.Add(choice);
            }

            var plot = new SinglePlotData
            {
                plotText = "宝箱里翻出几样东西，选一样带走。",
                noAutoJump = true,
                clickCallFuc = string.Empty,
                choices = choiceDataList
            };

            plotController.ChangePlot(plot);
            PushPlayerLog($"宝箱奖励改为 {options.Count} 选 1");
            TraceTreasureChestEvent(
                "TryShowTreasureChestChoicePlot shown",
                player,
                options.Count > 0 ? options[0] : null,
                1,
                skipManageItemPoison,
                $"options={DescribeItemSummaries(options)}");
            return true;
        }
        catch (Exception ex)
        {
            _activeTreasureChestChoiceSession = null;
            LoggerInstance.LogWarning($"Failed to show treasure chest choice plot: {ex.Message}");
            TraceTreasureChestEvent(
                "TryShowTreasureChestChoicePlot exception",
                player,
                options.Count > 0 ? options[0] : null,
                1,
                skipManageItemPoison,
                $"options={DescribeItemSummaries(options)}, exception={ex.Message}");
            return false;
        }
    }

    private static bool TryResolveTreasureChestChoiceFromPlot(string? param)
    {
        var session = _activeTreasureChestChoiceSession;
        if (session == null || session.Resolved)
        {
            return false;
        }

        if (string.IsNullOrWhiteSpace(param) || !param.StartsWith(TreasureChestChoiceParamPrefix, StringComparison.Ordinal))
        {
            return false;
        }

        if (!int.TryParse(param.Substring(TreasureChestChoiceParamPrefix.Length), out var index))
        {
            return false;
        }

        if (index < 0 || index >= session.Options.Count)
        {
            LoggerInstance.LogWarning($"Treasure chest choice index out of range: {index}");
            TraceTreasureChestEvent(
                "TryResolveTreasureChestChoiceFromPlot index out of range",
                session.Player,
                null,
                1,
                session.SkipManageItemPoison,
                $"param={SafeFormatValue(param)}, index={index}, options={session.Options.Count}");
            return true;
        }

        TraceTreasureChestEvent(
            "TryResolveTreasureChestChoiceFromPlot resolved",
            session.Player,
            session.Options[index],
            1,
            session.SkipManageItemPoison,
            $"param={SafeFormatValue(param)}, index={index}");
        GrantTreasureChestChoiceReward(session, session.Options[index], $"plot:{index}");
        return true;
    }

    private static bool TryResolveTreasureChestChoiceFromCurrentSelection(PlotController? plotController)
    {
        var session = _activeTreasureChestChoiceSession;
        if (session == null || session.Resolved || plotController == null)
        {
            return false;
        }

        try
        {
            var newChoiceParam = TryGetChoiceParam(plotController.newChoice);
            if (!string.IsNullOrWhiteSpace(newChoiceParam) &&
                TryResolveTreasureChestChoiceFromPlot(newChoiceParam))
            {
                return true;
            }

            var currentChoiceParam = TryGetChoiceParam(plotController.nowChoice);
            if (!string.IsNullOrWhiteSpace(currentChoiceParam) &&
                TryResolveTreasureChestChoiceFromPlot(currentChoiceParam))
            {
                return true;
            }

            return false;
        }
        catch (Exception ex)
        {
            LoggerInstance.LogWarning($"Failed to resolve treasure chest choice from current selection: {ex.Message}");
            return false;
        }
    }

    private static void TryResolveTreasureChestChoiceAndClose(PlotController? plotController)
    {
        if (plotController == null)
        {
            return;
        }

        if (!TryResolveTreasureChestChoiceFromCurrentSelection(plotController))
        {
            return;
        }

        TryCloseTreasureChestChoicePlot(plotController);
    }

    private static void TryCloseTreasureChestChoicePlot(PlotController plotController)
    {
        if (_treasureChestChoiceClosingPlot)
        {
            return;
        }

        _treasureChestChoiceClosingPlot = true;
        try
        {
            plotController.PlotTextShowFinished();
            plotController.PlotChoiceShowFinished();
            plotController.HideInteractUI();
        }
        catch (Exception ex)
        {
            LoggerInstance.LogWarning($"Failed to close treasure chest choice plot: {ex.Message}");
        }
        finally
        {
            _treasureChestChoiceClosingPlot = false;
        }
    }

    private static void GrantTreasureChestChoiceReward(TreasureChestChoiceSession session, ItemData chosenItem, string source)
    {
        if (session.Resolved)
        {
            return;
        }

        var player = session.Player ?? TryGetPlayerHero();
        if (player == null)
        {
            LoggerInstance.LogWarning($"Could not grant treasure chest choice reward from {source} because the player was unavailable.");
            session.Resolved = true;
            _activeTreasureChestChoiceSession = null;
            return;
        }

        session.Resolved = true;
        _grantingTreasureChestChoiceReward = true;
        TraceTreasureChestEvent(
            "GrantTreasureChestChoiceReward enter",
            player,
            chosenItem,
            1,
            session.SkipManageItemPoison,
            $"source={source}");

        try
        {
            player.GetItem(chosenItem, true, true, 0, session.SkipManageItemPoison);
            PushPlayerLog($"宝箱选择获得：{chosenItem.name}");
            LoggerInstance.LogInfo($"Treasure chest choice granted from {source}: {DescribeItemSummary(chosenItem)}");
            TraceTreasureChestEvent(
                "GrantTreasureChestChoiceReward success",
                player,
                chosenItem,
                0,
                session.SkipManageItemPoison,
                $"source={source}");
        }
        catch (Exception ex)
        {
            LoggerInstance.LogWarning($"Failed to grant chosen treasure chest item from {source}: {ex.Message}");
            TraceTreasureChestEvent(
                "GrantTreasureChestChoiceReward exception",
                player,
                chosenItem,
                0,
                session.SkipManageItemPoison,
                $"source={source}, exception={ex.Message}");
        }
        finally
        {
            _grantingTreasureChestChoiceReward = false;
            _activeTreasureChestChoiceSession = null;
        }
    }

    private static IEnumerable<string> DescribeItemNames(IEnumerable<ItemData> items)
    {
        foreach (var item in items)
        {
            yield return item?.name ?? "unknown";
        }
    }

    private static string? TryGetTreasureChestCurrentChoiceParam(PlotController? plotController)
    {
        if (plotController == null)
        {
            return null;
        }

        try
        {
            var param = TryGetChoiceParam(plotController.newChoice);
            if (!string.IsNullOrWhiteSpace(param))
            {
                return param;
            }

            return TryGetChoiceParam(plotController.nowChoice);
        }
        catch
        {
            return null;
        }
    }

    private static string? TryGetChoiceParam(SinglePlotChoiceData? choice)
    {
        if (choice == null)
        {
            return null;
        }

        try
        {
            var param = choice.callParam;
            return string.IsNullOrWhiteSpace(param) ? null : param;
        }
        catch
        {
            return null;
        }
    }

    private static void UpdateTreasureChestChoiceSession()
    {
        var session = _activeTreasureChestChoiceSession;
        if (session == null || session.Resolved)
        {
            return;
        }

        var plotController = PlotController.Instance;
        if (plotController == null)
        {
            return;
        }

        if (TryRunPendingTreasureChestAutoPick(session, plotController))
        {
            return;
        }

        var currentParam = TryGetTreasureChestCurrentChoiceParam(plotController);
        if (!string.IsNullOrWhiteSpace(currentParam))
        {
            if (string.IsNullOrWhiteSpace(session.LastObservedChoiceParam))
            {
                session.LastObservedChoiceParam = currentParam;
            }
            else if (!string.Equals(session.LastObservedChoiceParam, currentParam, StringComparison.Ordinal))
            {
                session.LastObservedChoiceParam = currentParam;
                session.PendingClickConfirm = true;
                session.PendingClickConfirmFrames = 2;
            }
        }

        if (Input.GetMouseButtonDown(0) && Time.realtimeSinceStartup - session.OpenedAtRealtime > 0.15f)
        {
            session.PendingClickConfirm = true;
            session.PendingClickConfirmFrames = Math.Max(session.PendingClickConfirmFrames, 2);
        }

        if (!session.PendingClickConfirm)
        {
            return;
        }

        if (session.PendingClickConfirmFrames > 0)
        {
            session.PendingClickConfirmFrames--;
            return;
        }

        session.PendingClickConfirm = false;
        plotController.AutoPlotButtonClicked();
    }

    private static bool TryRunPendingTreasureChestAutoPick(TreasureChestChoiceSession session, PlotController plotController)
    {
        if (!session.PendingAutoPick)
        {
            return false;
        }

        if (session.PendingAutoPickFrames > 0)
        {
            session.PendingAutoPickFrames--;
            return true;
        }

        session.PendingAutoPick = false;
        var bestIndex = FindBestTreasureChestChoiceIndex(session.Options);
        if (bestIndex < 0 || bestIndex >= session.Options.Count)
        {
            return false;
        }

        var chosenItem = session.Options[bestIndex];
        TraceTreasureChestEvent(
            "TryRunPendingTreasureChestAutoPick resolved",
            session.Player,
            chosenItem,
            1,
            session.SkipManageItemPoison,
            $"index={bestIndex}, options={DescribeItemSummaries(session.Options)}");
        GrantTreasureChestChoiceReward(session, chosenItem, $"auto:value:{bestIndex}");
        TryCloseTreasureChestChoicePlot(plotController);
        return true;
    }

    private static int FindBestTreasureChestChoiceIndex(IReadOnlyList<ItemData> options)
    {
        if (options == null || options.Count <= 0)
        {
            return -1;
        }

        var bestIndex = 0;
        for (var i = 1; i < options.Count; i++)
        {
            if (CompareTreasureChestChoicePriority(options[i], options[bestIndex]) > 0)
            {
                bestIndex = i;
            }
        }

        return bestIndex;
    }

    private static int CompareTreasureChestChoicePriority(ItemData? left, ItemData? right)
    {
        if (ReferenceEquals(left, right))
        {
            return 0;
        }

        if (left == null)
        {
            return -1;
        }

        if (right == null)
        {
            return 1;
        }

        var valueComparison = left.value.CompareTo(right.value);
        if (valueComparison != 0)
        {
            return valueComparison;
        }

        var rarityComparison = left.rareLv.CompareTo(right.rareLv);
        if (rarityComparison != 0)
        {
            return rarityComparison;
        }

        return left.itemLv.CompareTo(right.itemLv);
    }

    private static void IdentifyCorrectTreasurePostfix(IdentifyMatchController __instance)
    {
        if (!_treasureIdentifyHighlightCorrect.Value)
        {
            return;
        }

        TrySelectCorrectIdentifyTreasure(__instance, "correctTreasure");
    }

    private static void IdentifySetNowChooseTreasurePrefix(IdentifyMatchController __instance, ref GameObject targetTreasure)
    {
        if (!_treasureIdentifyForceCorrectSelection.Value)
        {
            return;
        }

        var correctTreasure = TryGetCorrectIdentifyTreasure(__instance);
        if (correctTreasure == null || ReferenceEquals(correctTreasure, targetTreasure))
        {
            return;
        }

        targetTreasure = correctTreasure;
        LoggerInstance.LogInfo($"Treasure identify forced correct treasure on click: {DescribeIdentifyTreasure(correctTreasure)}");
    }

    private static void IdentifySureButtonClickedPrefix(IdentifyMatchController __instance)
    {
        if (!_treasureIdentifyForceCorrectSelection.Value)
        {
            return;
        }

        TrySelectCorrectIdentifyTreasure(__instance, "submit");
    }

    private static bool TrySelectCorrectIdentifyTreasure(IdentifyMatchController? controller, string source)
    {
        var correctTreasure = TryGetCorrectIdentifyTreasure(controller);
        if (controller == null || correctTreasure == null)
        {
            return false;
        }

        if (ReferenceEquals(TryGetCurrentIdentifyTreasure(controller), correctTreasure))
        {
            return true;
        }

        try
        {
            controller.SetNowChooseTreasure(correctTreasure);
            LoggerInstance.LogInfo($"Treasure identify selected correct treasure from {source}: {DescribeIdentifyTreasure(correctTreasure)}");
            return true;
        }
        catch (Exception ex)
        {
            LoggerInstance.LogWarning($"Failed to auto-select correct identify treasure from {source}: {ex.Message}");
            return false;
        }
    }

    private static GameObject? TryGetCorrectIdentifyTreasure(IdentifyMatchController? controller)
    {
        if (controller == null)
        {
            return null;
        }

        try
        {
            var correctTreasure = controller.correctTreasure;
            if (correctTreasure != null && correctTreasure.Count > 0)
            {
                return correctTreasure[0];
            }
        }
        catch
        {
        }

        var value = SafeProperty(controller, "correctTreasure") ?? SafeField(controller, "correctTreasure");
        var count = TryGetCollectionCount(value);
        if (count <= 0)
        {
            return null;
        }

        return TryGetIndexedValue(value!, 0) as GameObject;
    }

    private static GameObject? TryGetCurrentIdentifyTreasure(IdentifyMatchController? controller)
    {
        if (controller == null)
        {
            return null;
        }

        try
        {
            return controller.nowChooseTreasure;
        }
        catch
        {
            return (SafeProperty(controller, "nowChooseTreasure") ?? SafeField(controller, "nowChooseTreasure")) as GameObject;
        }
    }

    private static string DescribeIdentifyTreasure(GameObject? treasure)
    {
        if (treasure == null)
        {
            return "<null>";
        }

        try
        {
            var icon = treasure.GetComponent<ItemIconController>();
            if (icon?.itemData != null)
            {
                return $"{treasure.name} => {DescribeItemSummary(icon.itemData)}";
            }
        }
        catch
        {
        }

        return treasure.name ?? "<unnamed-treasure>";
    }

    private static void TryGrantTreasureChestBonusItems(HeroData? targetHero, ItemData? itemData, int treasureChestClickTime, bool skipManageItemPoison)
    {
        if (_grantingTreasureChestBonusItems || treasureChestClickTime <= 0 || targetHero == null || itemData == null)
        {
            return;
        }

        var player = TryGetPlayerHero();
        if (player == null || TryGetHeroId(targetHero) != TryGetHeroId(player))
        {
            return;
        }

        var totalItems = Math.Max(1, _treasureChestTotalItems.Value);
        var extraItemCount = totalItems - 1;
        if (extraItemCount <= 0)
        {
            return;
        }

        var bonusNames = new List<string>();
        _grantingTreasureChestBonusItems = true;

        try
        {
            for (var i = 0; i < extraItemCount; i++)
            {
                var bonusItem = TryCreateTreasureChestBonusItem(itemData, player);
                if (bonusItem == null)
                {
                    continue;
                }

                player.GetItem(bonusItem, false, false, 0, skipManageItemPoison);
                bonusNames.Add(bonusItem.name ?? $"id={bonusItem.itemID}");
            }
        }
        catch (Exception ex)
        {
            LoggerInstance.LogWarning($"Failed to grant bonus treasure chest items: {ex.Message}");
        }
        finally
        {
            _grantingTreasureChestBonusItems = false;
        }

        if (bonusNames.Count <= 0)
        {
            return;
        }

        PushPlayerLog($"宝箱额外获得：{string.Join("、", bonusNames)}");
        LoggerInstance.LogInfo(
            $"Treasure chest granted {bonusNames.Count} bonus item(s): " +
            $"{string.Join(", ", bonusNames)}.");
    }

    private static void ShowBuildingShopPostfix(BuildingUIController __instance)
    {
        ApplyPlayerCarryWeightOverride("BuildingUI.ShowBuildingShop");
        ApplyMerchantCarryCash(TradeUIType.Shop, __instance?.targetBuildingData?.shopItemList, "BuildingUI.ShowBuildingShop");
        HandleTreasureTradeUiShown(TradeUIType.Shop, "BuildingUI.ShowBuildingShop");
    }

    private static void ShowTradeUiBasicPostfix(TradeUIType targetType, ItemListData leftItemList, ItemListData rightItemList, bool _useAreaItemPrice)
    {
        ApplyPlayerCarryWeightOverride("TradeUI.ShowTradeUI/basic");
        ApplyMerchantCarryCash(targetType, rightItemList, "TradeUI.ShowTradeUI/basic");
        HandleTreasureTradeUiShown(targetType, "TradeUI.ShowTradeUI/basic");
    }

    private static void ShowTradeUiTypedPostfix(TradeUIType targetType, ItemListType targetItemListType, ItemListData leftItemList, ItemListData rightItemList)
    {
        ApplyPlayerCarryWeightOverride("TradeUI.ShowTradeUI/typed");
        ApplyMerchantCarryCash(targetType, rightItemList, "TradeUI.ShowTradeUI/typed");
        HandleTreasureTradeUiShown(targetType, "TradeUI.ShowTradeUI/typed");
    }

    private static void ShowTradeUiLevelRangePostfix(TradeUIType targetType, ItemListData leftItemList, ItemListData rightItemList, int _minItemLv, int _maxItemLv)
    {
        ApplyPlayerCarryWeightOverride("TradeUI.ShowTradeUI/level-range");
        ApplyMerchantCarryCash(targetType, rightItemList, "TradeUI.ShowTradeUI/level-range");
        HandleTreasureTradeUiShown(targetType, "TradeUI.ShowTradeUI/level-range");
    }

    private static void ShowTradeUiFullPostfix(TradeUIType targetType, ItemListType targetItemListType, ItemListData leftItemList, ItemListData rightItemList, int _minItemLv, int _maxItemLv, bool _useAreaItemPrice, bool _noSell, float _speSellValueRate, float _speBuyValueRate)
    {
        ApplyPlayerCarryWeightOverride("TradeUI.ShowTradeUI/full");
        ApplyMerchantCarryCash(targetType, rightItemList, "TradeUI.ShowTradeUI/full");
        HandleTreasureTradeUiShown(targetType, "TradeUI.ShowTradeUI/full");
    }

    private static void HideTradeUiPostfix()
    {
        ResetTreasureTradeUiState("TradeUI.HideTradeUI");
        ResetShopOwnershipUiState("TradeUI.HideTradeUI");
    }

    private static void ItemIconOnClickPostfix(ItemIconController __instance)
    {
        CaptureTreasureTradeSelection(__instance);
    }

    private static void HandleTreasureTradeUiShown(TradeUIType targetType, string source)
    {
        if (targetType != TradeUIType.Shop)
        {
            ResetTreasureTradeUiState(source + "/non-shop");
            ResetShopOwnershipUiState(source + "/non-shop");
            return;
        }

        _treasureTradeShopOpenedAtRealtime = Time.realtimeSinceStartup;
        _treasureTradeAutoProcessed = false;
        _treasureTradeBusy = false;
        _selectedTreasureTradeIcon = null;
        _treasureTradeLoggedSignatures.Clear();
    }

    private static void ResetTreasureTradeUiState(string source)
    {
        _selectedTreasureTradeIcon = null;
        _treasureTradeShopOpenedAtRealtime = -1f;
        _treasureTradeAutoProcessed = false;
        _treasureTradeBusy = false;
        _treasureTradeLoggedSignatures.Clear();
        HideTreasureTradeOverlay();
    }

    private static void CaptureTreasureTradeSelection(ItemIconController? icon)
    {
        if (icon == null || !TryGetActiveShopTradeUi(out _))
        {
            return;
        }

        switch (icon.tradeIconType)
        {
            case TradeIconType.TradeLeft:
            case TradeIconType.TradeRight:
            case TradeIconType.TradeLeftOut:
            case TradeIconType.TradeRightOut:
                var changed = _selectedTreasureTradeIcon != icon;
                _selectedTreasureTradeIcon = icon;
                break;
        }
    }

    private static void UpdateTreasureTradeUiState()
    {
        if (!_treasureTradeHelperEnabled.Value && !_treasureAutoTradeEnabled.Value)
        {
            HideTreasureTradeOverlay();
            return;
        }

        if (!TryGetActiveShopTradeUi(out var tradeUi) ||
            !TryGetTreasureTradeShopContext(tradeUi, out _, out var identifyCost))
        {
            HideTreasureTradeOverlay();
            return;
        }

        if (_treasureTradeHelperEnabled.Value)
        {
            UpdateTreasureTradeOverlay(tradeUi, identifyCost);
        }
        else
        {
            HideTreasureTradeOverlay();
        }

        TryRunTreasureAutoTrade(tradeUi, identifyCost);
    }

    private static bool TryGetActiveShopTradeUi(out TradeUIController tradeUi)
    {
        tradeUi = TradeUIController.Instance;
        if (tradeUi == null)
        {
            return false;
        }

        try
        {
            if (tradeUi.tradeUIType != TradeUIType.Shop)
            {
                return false;
            }
        }
        catch
        {
            return false;
        }

        try
        {
            return tradeUi.tradeUI != null && tradeUi.tradeUI.activeInHierarchy;
        }
        catch
        {
            return false;
        }
    }

    private static bool TryGetTreasureTradeShopContext(TradeUIController tradeUi, out AreaBuildingData? building, out int identifyCost)
    {
        building = BuildingUIController.Instance?.targetBuildingData;
        identifyCost = 0;
        if (tradeUi == null)
        {
            return false;
        }

        return true;
    }

    private static void OpenCraftUiPostfix()
    {
        ResetCraftRewardTracking("CraftUI.OpenCraftUI");
    }

    private static void HideCraftUiPostfix()
    {
        ResetCraftRewardTracking("CraftUI.HideCraftUI");
    }

    private static void GetCraftMaterialExtraCraftRatePostfix(CraftUIController __instance, ref float __result)
    {
        if (_traceMode.Value)
        {
            LoggerInstance.LogInfo(
                $"Craft material extra rate preserved from controller: material={DescribeItemSummary(ResolveCraftAddedMaterial(__instance))}, vanillaRate={SafeFormatValue(__result)}.");
        }
    }

    private static void GetItemMaterialExtraCraftRatePostfix(ItemData __instance, ref float __result)
    {
        if (_traceMode.Value)
        {
            LoggerInstance.LogInfo(
                $"Craft material extra rate preserved from item: material={DescribeItemSummary(__instance)}, vanillaRate={SafeFormatValue(__result)}.");
        }
    }

    private static void SetPlotItemPostfix(PlotController __instance, ItemData targetItem, bool show)
    {
        if (!_craftRandomPickUpgradeEnabled.Value)
        {
            return;
        }

        LogCraftEvent($"SetPlotItem show={show}, target={DescribeItemSummary(targetItem)}, activePlotItem={DescribeItemSummary(__instance?.plotInteractItem)}");
    }

    private static void PlayerGetPlotItemPrefix(PlotController __instance, out PlotItemGrantState __state)
    {
        __state = new PlotItemGrantState
        {
            ItemBefore = __instance?.plotInteractItem,
            Source = nameof(PlotController.PlayerGetPlotItem)
        };

        if (_craftRandomPickUpgradeEnabled.Value)
        {
            LogCraftEvent($"PlayerGetPlotItem prefix item={DescribeItemSummary(__state.ItemBefore)}");
        }
    }

    private static void PlayerGetPlotItemPostfix(PlotController __instance, PlotItemGrantState __state)
    {
        TryRepeatCraftPlotItemReward(__instance, __state);
    }

    private static void PlayerGetPlotItemSimplePrefix(PlotController __instance, out PlotItemGrantState __state)
    {
        __state = new PlotItemGrantState
        {
            ItemBefore = __instance?.plotInteractItem,
            Source = nameof(PlotController.PlayerGetPlotItemSimple)
        };

        if (_craftRandomPickUpgradeEnabled.Value)
        {
            LogCraftEvent($"PlayerGetPlotItemSimple prefix item={DescribeItemSummary(__state.ItemBefore)}");
        }
    }

    private static void PlayerGetPlotItemSimplePostfix(PlotController __instance, PlotItemGrantState __state)
    {
        TryRepeatCraftPlotItemReward(__instance, __state);
    }

    private static void UpdateTreasureTradeOverlay(TradeUIController tradeUi, int identifyCost)
    {
        TryResolveCurrentShopOwnershipContext(out var shopContext);
        var opportunity = TryResolveTreasureTradeOpportunity(tradeUi, identifyCost);
        if (opportunity == null)
        {
            EnsureTreasureTradeOverlay(tradeUi);
            if (_treasureTradeOverlayLabel != null)
            {
                var baseText = identifyCost > 0
                    ? $"珍宝倒宝助手\n当前无未鉴定珍宝\n鉴定费: {identifyCost}"
                    : "珍宝倒宝助手\n当前无未鉴定珍宝";
                _treasureTradeOverlayLabel.text = AppendShopOwnershipOverlayText(baseText, shopContext);
                _treasureTradeOverlayLabel.gameObject.SetActive(true);
            }

            return;
        }

        EnsureTreasureTradeOverlay(tradeUi);
        if (_treasureTradeOverlayLabel == null)
        {
            return;
        }

        _treasureTradeOverlayLabel.text = AppendShopOwnershipOverlayText(BuildTreasureTradeOverlayText(opportunity), shopContext);
        _treasureTradeOverlayLabel.gameObject.SetActive(true);
    }

    private static string AppendShopOwnershipOverlayText(string baseText, ShopOwnershipContext? context)
    {
        if (context == null)
        {
            return baseText;
        }

        var isOwned = _ownedShops.TryGetValue(context.ShopKey, out var ownedRecord);
        var currentMoney = TryGetHeroMoney(context.Player) ?? 0;
        var saveSlotText = _currentShopOwnershipSaveSlotId >= 0
            ? $"存档槽: {_currentShopOwnershipSaveSlotId}"
            : _loadedShopOwnershipSourceSlotId >= 0
                ? $"存档槽: 未绑定（当前读取自 {_loadedShopOwnershipSourceSlotId}）"
                : "存档槽: 未绑定";
        var buyText = isOwned
            ? "状态: 你已买下此店"
            : $"状态: 未买下 | 价格: {ShopOwnershipBuyPrice} | 金钱: {currentMoney}";
        var purchasedText = ownedRecord == null || string.IsNullOrWhiteSpace(ownedRecord.PurchasedOn)
            ? string.Empty
            : $"\n买断记录: {ownedRecord.PurchasedOn}";

        return
            $"{baseText}\n\n" +
            $"店铺产业试验\n" +
            $"店铺: {context.ShopName}\n" +
            $"{buyText}\n" +
            $"{saveSlotText}" +
            purchasedText;
    }

    private static TreasureTradeOpportunity? TryResolveTreasureTradeOpportunity(TradeUIController tradeUi, int identifyCost)
    {
        if (tradeUi == null)
        {
            return null;
        }

        if (TryAnalyzeTreasureTradeIcon(_selectedTreasureTradeIcon, identifyCost, out var selectedOpportunity))
        {
            return selectedOpportunity;
        }

        foreach (var icon in EnumerateTradeIcons(tradeUi.rightList))
        {
            if (TryAnalyzeTreasureTradeIcon(icon, identifyCost, out var rightOpportunity))
            {
                return rightOpportunity;
            }
        }

        foreach (var icon in EnumerateTradeIcons(tradeUi.leftList))
        {
            if (TryAnalyzeTreasureTradeIcon(icon, identifyCost, out var leftOpportunity))
            {
                return leftOpportunity;
            }
        }

        return null;
    }

    private static bool TryAnalyzeTreasureTradeIcon(ItemIconController? icon, int identifyCost, out TreasureTradeOpportunity? opportunity)
    {
        opportunity = null;
        if (icon == null)
        {
            return false;
        }

        var item = icon.itemData;
        if (!IsUnidentifiedTreasure(item))
        {
            return false;
        }

        var buyPrice = Math.Max(0, TryGetTradePriceForItem(icon, item, buy: true, fallback: 0));
        var currentSellPrice = Math.Max(0, TryGetTradePriceForItem(icon, item, buy: false, fallback: 0));
        if (buyPrice <= 0 && currentSellPrice <= 0)
        {
            return false;
        }

        var realValue = TryGetTreasureRealValue(item);
        if (realValue <= 0)
        {
            var identifiedClone = TryCloneAndIdentifyItem(item);
            if (identifiedClone != null)
            {
                realValue = TryGetTreasureRealValue(identifiedClone);
            }
        }

        if (realValue <= 0)
        {
            return false;
        }

        var identifiedSellPrice = EstimateTreasureSellPriceFromRealValue(item, currentSellPrice, realValue);

        opportunity = new TreasureTradeOpportunity
        {
            Item = item,
            Icon = icon,
            IconType = icon.tradeIconType,
            BuyPrice = buyPrice,
            CurrentSellPrice = currentSellPrice,
            IdentifiedSellPrice = identifiedSellPrice,
            IdentifyCost = Math.Max(0, identifyCost),
            RealValue = Math.Max(0, realValue),
            SkillBuyFactor = GetSkillTradeFactor(buy: true),
            SkillSellFactor = GetSkillTradeFactor(buy: false)
        };

        return true;
    }

    private static int EstimateTreasureSellPriceFromRealValue(ItemData item, int currentSellPrice, int realValue)
    {
        if (realValue <= 0)
        {
            return Math.Max(0, currentSellPrice);
        }

        var baseValue = Math.Max(1, item.value);
        if (currentSellPrice <= 0)
        {
            return Math.Max(realValue, 0);
        }

        var sellRatio = Math.Max(0d, (double)currentSellPrice / baseValue);
        var estimated = (int)Math.Round(realValue * sellRatio, MidpointRounding.AwayFromZero);
        return Math.Max(currentSellPrice, estimated);
    }

    private static string BuildTreasureTradeOverlayText(TreasureTradeOpportunity opportunity)
    {
        var name = TryGetItemDisplayName(opportunity.Item);
        var priceLine = opportunity.IconType == TradeIconType.TradeRight || opportunity.IconType == TradeIconType.TradeRightOut
            ? $"卖价/买价: {opportunity.CurrentSellPrice} / {opportunity.BuyPrice}"
            : $"当前卖价: {opportunity.CurrentSellPrice}";
        var profitLine = opportunity.IconType == TradeIconType.TradeRight || opportunity.IconType == TradeIconType.TradeRightOut
            ? $"鉴定费/净利: {opportunity.IdentifyCost} / {FormatSignedInt(opportunity.NetProfit)}"
            : $"鉴定费/净增: {opportunity.IdentifyCost} / {FormatSignedInt(opportunity.IdentifyGain)}";

        return
            $"珍宝倒宝助手\n" +
            $"{name}\n" +
            $"{priceLine}\n" +
            $"技能买/卖系数: x{opportunity.SkillBuyFactor:0.###} / x{opportunity.SkillSellFactor:0.###}\n" +
            $"鉴后卖价: {opportunity.IdentifiedSellPrice}\n" +
            $"{profitLine}";
    }

    private static void EnsureTreasureTradeOverlay(TradeUIController tradeUi)
    {
        if (tradeUi == null)
        {
            return;
        }

        if (_treasureTradeOverlayLabel != null)
        {
            return;
        }

        var template = tradeUi.deltaResourceLabel ?? tradeUi.leftResourceLabel ?? tradeUi.rightResourceLabel;
        if (template == null)
        {
            return;
        }

        try
        {
            var overlayObject = UnityEngine.Object.Instantiate(template.gameObject, template.transform.parent);
            overlayObject.name = "CodexTreasureTradeOverlay";
            var overlayLabel = overlayObject.GetComponent<Text>();
            if (overlayLabel == null)
            {
                UnityEngine.Object.Destroy(overlayObject);
                return;
            }

            overlayLabel.fontSize = Math.Max(16, template.fontSize - 2);
            overlayLabel.resizeTextForBestFit = false;
            overlayLabel.raycastTarget = false;
            overlayLabel.supportRichText = true;
            overlayLabel.color = new Color(1f, 0.95f, 0.78f, 1f);

            var templateRect = template.GetComponent<RectTransform>();
            var overlayRect = overlayLabel.GetComponent<RectTransform>();
            if (templateRect != null && overlayRect != null)
            {
                overlayRect.anchorMin = templateRect.anchorMin;
                overlayRect.anchorMax = templateRect.anchorMax;
                overlayRect.pivot = templateRect.pivot;
                overlayRect.anchoredPosition = templateRect.anchoredPosition + new Vector2(0f, -120f);
                overlayRect.sizeDelta = new Vector2(Mathf.Max(templateRect.sizeDelta.x, 380f), Mathf.Max(140f, templateRect.sizeDelta.y * 4f));
            }

            _treasureTradeOverlayLabel = overlayLabel;
        }
        catch (Exception ex)
        {
            LoggerInstance.LogWarning($"Could not create treasure trade overlay: {ex.Message}");
        }
    }

    private static void HideTreasureTradeOverlay()
    {
        if (_treasureTradeOverlayLabel != null)
        {
            try
            {
                _treasureTradeOverlayLabel.gameObject.SetActive(false);
            }
            catch
            {
            }
        }
    }

    private static void ResetShopOwnershipUiState(string source)
    {
        HideShopOwnershipOverlay();
    }

    private static void HideShopOwnershipOverlay()
    {
        if (_shopOwnershipOverlayRoot != null)
        {
            try
            {
                _shopOwnershipOverlayRoot.SetActive(false);
            }
            catch
            {
            }
        }

        if (_shopOwnershipBuyButton != null)
        {
            try
            {
                _shopOwnershipBuyButton.gameObject.SetActive(false);
            }
            catch
            {
            }
        }
    }

    private static void UpdateShopOwnershipUiState()
    {
        if (!TryResolveCurrentShopOwnershipContext(out var context))
        {
            HideShopOwnershipOverlay();
            return;
        }

        EnsureShopOwnershipOverlay(context.TradeUi);
        if (_shopOwnershipOverlayRoot == null ||
            _shopOwnershipOverlayLabel == null ||
            _shopOwnershipBuyButton == null ||
            _shopOwnershipBuyButtonLabel == null)
        {
            return;
        }

        _shopOwnershipOverlayRoot.SetActive(true);
        _shopOwnershipBuyButton.gameObject.SetActive(true);

        var isOwned = _ownedShops.TryGetValue(context.ShopKey, out var ownedRecord);
        var currentMoney = TryGetHeroMoney(context.Player) ?? 0;
        var canBuy = !isOwned && context.Player != null && currentMoney >= ShopOwnershipBuyPrice;

        _shopOwnershipOverlayLabel.text = BuildShopOwnershipOverlayText(context, ownedRecord);
        _shopOwnershipBuyButton.interactable = canBuy;
        _shopOwnershipBuyButtonLabel.text = isOwned
            ? "已买下此店"
            : canBuy
                ? $"花费 {ShopOwnershipBuyPrice} 文钱买下此店"
                : $"银钱不足 ({currentMoney}/{ShopOwnershipBuyPrice})";

        var buttonImage = _shopOwnershipBuyButton.GetComponent<Image>();
        if (buttonImage != null)
        {
            buttonImage.color = isOwned
                ? new Color(0.28f, 0.32f, 0.22f, 0.95f)
                : canBuy
                    ? new Color(0.62f, 0.33f, 0.12f, 0.95f)
                    : new Color(0.26f, 0.26f, 0.26f, 0.95f);
        }

        if (_traceMode.Value)
        {
            LoggerInstance.LogInfo(
                $"Shop ownership UI refreshed: shop={context.ShopKey}, owned={isOwned}, money={currentMoney}, slot={_currentShopOwnershipSaveSlotId}.");
        }
    }

    private static bool TryResolveCurrentShopOwnershipContext(out ShopOwnershipContext context)
    {
        context = null!;
        if (!TryGetActiveShopTradeUi(out var tradeUi))
        {
            return false;
        }

        var building = BuildingUIController.Instance?.targetBuildingData;
        if (building == null)
        {
            return false;
        }

        var areaId = Math.Max(0, building.areaID);
        var buildingId = Math.Max(0, building.buildingID);
        var shopName = TryGetShopDisplayName(building);
        var shopKey = $"area-{areaId}-building-{buildingId}";

        context = new ShopOwnershipContext
        {
            TradeUi = tradeUi,
            Building = building,
            Player = TryGetPlayerHero(),
            ShopKey = shopKey,
            ShopName = shopName,
            AreaId = areaId,
            BuildingId = buildingId
        };
        return true;
    }

    private static string TryGetShopDisplayName(AreaBuildingData? building)
    {
        if (building == null)
        {
            return "未知店铺";
        }

        try
        {
            var name = building.Name(false);
            if (!string.IsNullOrWhiteSpace(name))
            {
                return name;
            }
        }
        catch
        {
        }

        try
        {
            var detail = building.GetBuildingText(true, false, false);
            if (!string.IsNullOrWhiteSpace(detail))
            {
                return detail;
            }
        }
        catch
        {
        }

        return $"店铺 area={building.areaID} building={building.buildingID}";
    }

    private static string BuildShopOwnershipOverlayText(ShopOwnershipContext context, OwnedShopRecord? ownedRecord)
    {
        var ownershipText = ownedRecord == null ? "未买下" : "你已买下此店";
        var purchasedText = ownedRecord == null
            ? "买断价格: 500 文钱"
            : string.IsNullOrWhiteSpace(ownedRecord.PurchasedOn)
                ? $"买断价格: {ownedRecord.BuyPrice} 文钱"
                : $"买断记录: {ownedRecord.PurchasedOn} / {ownedRecord.BuyPrice} 文钱";
        var saveSlotText = _currentShopOwnershipSaveSlotId >= 0
            ? $"当前绑定存档槽: {_currentShopOwnershipSaveSlotId}"
            : _loadedShopOwnershipSourceSlotId >= 0
                ? $"当前未绑定存档槽: 当前读取自 {_loadedShopOwnershipSourceSlotId}，买下后请记得保存"
                : "当前未绑定存档槽: 买下后请记得保存";

        return
            $"店铺产业试验\n" +
            $"店铺: {context.ShopName}\n" +
            $"产权状态: {ownershipText}\n" +
            $"{purchasedText}\n" +
            $"{saveSlotText}";
    }

    private static void EnsureShopOwnershipOverlay(TradeUIController tradeUi)
    {
        if (tradeUi == null)
        {
            return;
        }

        if (_shopOwnershipOverlayRoot != null &&
            _shopOwnershipOverlayLabel != null &&
            _shopOwnershipBuyButton != null &&
            _shopOwnershipBuyButtonLabel != null)
        {
            return;
        }

        var template = tradeUi.deltaResourceLabel ?? tradeUi.leftResourceLabel ?? tradeUi.rightResourceLabel;
        if (template == null)
        {
            return;
        }

        try
        {
            var templateRect = template.GetComponent<RectTransform>();
            if (templateRect == null)
            {
                return;
            }

            var labelObject = UnityEngine.Object.Instantiate(template.gameObject, template.transform.parent);
            labelObject.name = ShopOwnershipOverlayPanelName;
            labelObject.SetActive(false);

            var label = labelObject.GetComponent<Text>();
            var labelRect = labelObject.GetComponent<RectTransform>();
            if (label == null || labelRect == null)
            {
                UnityEngine.Object.Destroy(labelObject);
                return;
            }

            label.fontSize = Math.Max(16, template.fontSize - 1);
            label.resizeTextForBestFit = false;
            label.supportRichText = true;
            label.color = new Color(1f, 0.95f, 0.8f, 1f);
            label.raycastTarget = false;
            labelRect.anchorMin = templateRect.anchorMin;
            labelRect.anchorMax = templateRect.anchorMax;
            labelRect.pivot = templateRect.pivot;
            labelRect.anchoredPosition = templateRect.anchoredPosition + new Vector2(0f, -140f);
            labelRect.sizeDelta = new Vector2(Mathf.Max(templateRect.sizeDelta.x, 420f), Mathf.Max(120f, templateRect.sizeDelta.y * 3.5f));

            var buttonObject = UnityEngine.Object.Instantiate(template.gameObject, template.transform.parent);
            buttonObject.name = ShopOwnershipBuyButtonName;
            buttonObject.SetActive(false);

            var button = buttonObject.GetComponent<Button>();
            var buttonImage = buttonObject.GetComponent<Image>();
            var buttonRect = buttonObject.GetComponent<RectTransform>();
            var buttonLabel = buttonObject.GetComponent<Text>();
            if (button == null)
            {
                button = buttonObject.AddComponent<Button>();
            }

            if (buttonImage == null)
            {
                buttonImage = buttonObject.AddComponent<Image>();
            }

            if (button == null || buttonImage == null || buttonRect == null)
            {
                UnityEngine.Object.Destroy(labelObject);
                UnityEngine.Object.Destroy(buttonObject);
                return;
            }

            buttonImage.color = new Color(0.62f, 0.33f, 0.12f, 0.95f);
            button.targetGraphic = buttonImage;
            button.onClick.RemoveAllListeners();
            button.onClick.AddListener((UnityAction)OnShopOwnershipBuyButtonClicked);
            buttonRect.anchorMin = templateRect.anchorMin;
            buttonRect.anchorMax = templateRect.anchorMax;
            buttonRect.pivot = templateRect.pivot;
            buttonRect.anchoredPosition = templateRect.anchoredPosition + new Vector2(0f, -240f);
            buttonRect.sizeDelta = new Vector2(Mathf.Max(templateRect.sizeDelta.x, 420f), 42f);
            if (buttonLabel == null)
            {
                UnityEngine.Object.Destroy(labelObject);
                UnityEngine.Object.Destroy(buttonObject);
                return;
            }

            buttonLabel.fontSize = Math.Max(15, template.fontSize);
            buttonLabel.resizeTextForBestFit = false;
            buttonLabel.color = Color.white;
            buttonLabel.raycastTarget = false;

            _shopOwnershipOverlayRoot = labelObject;
            _shopOwnershipOverlayLabel = label;
            _shopOwnershipBuyButton = button;
            _shopOwnershipBuyButtonLabel = buttonLabel;

            if (_traceMode.Value)
            {
                LoggerInstance.LogInfo("Shop ownership overlay widgets created.");
            }
        }
        catch (Exception ex)
        {
            LoggerInstance.LogWarning($"Could not create shop ownership overlay: {ex.Message}");
        }
    }

    private static void OnShopOwnershipBuyButtonClicked()
    {
        var bought = TryBuyCurrentShop(expectedShopKey: null, out var message, out var tradeUi);
        PushPlayerLog(message);

        if (tradeUi != null)
        {
            RefreshTradeUi(tradeUi);
        }

        if (!bought)
        {
            UpdateShopOwnershipUiState();
            return;
        }

        UpdateShopOwnershipUiState();
    }

    private static bool TryBuyCurrentShop(string? expectedShopKey, out string message, out TradeUIController? tradeUi)
    {
        tradeUi = null;
        if (!TryResolveCurrentShopOwnershipContext(out var context))
        {
            message = "产业试验：当前无法识别店铺，买断失败。";
            SetExternalOverlayStatusMessage(message);
            return false;
        }

        tradeUi = context.TradeUi;

        if (!string.IsNullOrWhiteSpace(expectedShopKey) &&
            !string.Equals(expectedShopKey, context.ShopKey, StringComparison.Ordinal))
        {
            message = $"产业试验：当前店铺已切换为【{context.ShopName}】，请在目标店铺重新尝试。";
            SetExternalOverlayStatusMessage(message);
            return false;
        }

        return TryBuyShop(context, out message);
    }

    private static bool TryBuyShop(ShopOwnershipContext context, out string message)
    {
        if (_ownedShops.ContainsKey(context.ShopKey))
        {
            message = $"产业试验：你已经买下了【{context.ShopName}】。";
            SetExternalOverlayStatusMessage(message);
            return false;
        }

        var player = context.Player;
        if (player == null)
        {
            message = "产业试验：当前无法识别玩家角色，买断失败。";
            SetExternalOverlayStatusMessage(message);
            return false;
        }

        var currentMoney = TryGetHeroMoney(player) ?? 0;
        if (currentMoney < ShopOwnershipBuyPrice)
        {
            message = $"产业试验：买下【{context.ShopName}】需要 {ShopOwnershipBuyPrice} 文钱。";
            SetExternalOverlayStatusMessage(message);
            return false;
        }

        try
        {
            player.ChangeMoney(-ShopOwnershipBuyPrice, true);
        }
        catch (Exception ex)
        {
            message = $"产业试验：扣除买断费用失败，原因：{ex.Message}";
            SetExternalOverlayStatusMessage(message);
            return false;
        }

        _ownedShops[context.ShopKey] = new OwnedShopRecord
        {
            ShopKey = context.ShopKey,
            ShopName = context.ShopName,
            AreaId = context.AreaId,
            BuildingId = context.BuildingId,
            BuyPrice = ShopOwnershipBuyPrice,
            PurchasedOn = FormatDate(TryGetWorldDateSnapshot())
        };

        if (_currentShopOwnershipSaveSlotId >= 0)
        {
            SaveOwnedShopsForSlot(_currentShopOwnershipSaveSlotId, "ShopBuyout");
            message = $"产业试验：你已花费 {ShopOwnershipBuyPrice} 文钱买下【{context.ShopName}】。";
        }
        else
        {
            message = $"产业试验：你已花费 {ShopOwnershipBuyPrice} 文钱买下【{context.ShopName}】。当前尚未绑定存档槽，保存游戏后会写入模组存档。";
        }

        SetExternalOverlayStatusMessage(message);
        return true;
    }

    private static void TryRunTreasureAutoTrade(TradeUIController tradeUi, int identifyCost)
    {
        if (!_treasureAutoTradeEnabled.Value || _treasureTradeBusy || _treasureTradeAutoProcessed)
        {
            return;
        }

        if (_treasureTradeShopOpenedAtRealtime >= 0f &&
            Time.realtimeSinceStartup < _treasureTradeShopOpenedAtRealtime + 0.35f)
        {
            return;
        }

        var shopTargetCount = CountItemListItems(tradeUi.rightList?.targetItemList);
        var shopIconCount = EnumerateTradeIcons(tradeUi.rightList).Count();
        if (shopTargetCount <= 0 && shopIconCount <= 0)
        {
            return;
        }

        if (shopTargetCount > 0 && shopIconCount <= 0)
        {
            return;
        }

        var opportunities = new List<TreasureTradeOpportunity>();
        foreach (var icon in EnumerateTradeIcons(tradeUi.rightList))
        {
            if (!TryAnalyzeTreasureTradeIcon(icon, identifyCost, out var opportunity) || opportunity == null)
            {
                continue;
            }

            if (opportunity.NetProfit > 0)
            {
                opportunities.Add(opportunity);
            }
        }

        if (opportunities.Count <= 0)
        {
            _treasureTradeAutoProcessed = true;
            return;
        }

        _treasureTradeAutoProcessed = true;
        QueueTreasureTradeCartItems(tradeUi, opportunities);
    }

    private static void QueueTreasureTradeCartItems(TradeUIController tradeUi, List<TreasureTradeOpportunity> opportunities)
    {
        if (tradeUi == null || opportunities.Count == 0)
        {
            return;
        }

        _treasureTradeBusy = true;
        var queuedCount = 0;

        try
        {
            foreach (var opportunity in opportunities.OrderByDescending(static entry => entry.NetProfit))
            {
                if (opportunity.Icon == null || opportunity.Icon.gameObject == null)
                {
                    continue;
                }

                tradeUi.TradeIconClicked(opportunity.Icon.gameObject);
                queuedCount++;
                LoggerInstance.LogInfo(
                    $"Treasure trade cart add item={TryGetItemDisplayName(opportunity.Item)}, buy={opportunity.BuyPrice}, " +
                    $"sellIdentified={opportunity.IdentifiedSellPrice}, net={opportunity.NetProfit}.");
            }
        }
        catch (Exception ex)
        {
            LoggerInstance.LogWarning($"Treasure cart auto-queue failed: {ex.Message}");
        }
        finally
        {
            _treasureTradeBusy = false;
            RefreshTradeUi(tradeUi);
        }

        if (queuedCount > 0)
        {
            PushPlayerLog($"【珍宝购物车】：已加入 {queuedCount} 件可盈利珍宝");
            LoggerInstance.LogInfo(
                $"Treasure cart auto-queue finished: count={queuedCount}.");
        }
    }

    private static void RefreshTradeUi(TradeUIController? tradeUi)
    {
        if (tradeUi == null)
        {
            return;
        }

        try
        {
            tradeUi.leftList?.RefreshItemList(resetPos: false);
        }
        catch
        {
        }

        try
        {
            tradeUi.rightList?.RefreshItemList(resetPos: false);
        }
        catch
        {
        }

        try
        {
            tradeUi.leftOutList?.RefreshItemList(resetPos: false);
        }
        catch
        {
        }

        try
        {
            tradeUi.rightOutList?.RefreshItemList(resetPos: false);
        }
        catch
        {
        }

        try
        {
            tradeUi.FreshResourceLabel();
        }
        catch
        {
        }
    }

    private static IEnumerable<ItemIconController> EnumerateTradeIcons(ItemListController? listController)
    {
        if (listController?.itemGrid == null)
        {
            yield break;
        }

        ItemIconController[]? icons;
        try
        {
            icons = listController.itemGrid.GetComponentsInChildren<ItemIconController>(includeInactive: true);
        }
        catch
        {
            yield break;
        }

        if (icons == null)
        {
            yield break;
        }

        foreach (var icon in icons)
        {
            if (icon != null && icon.itemData != null)
            {
                yield return icon;
            }
        }
    }

    private static int TryGetTradePriceForItem(ItemIconController? probeIcon, ItemData? item, bool buy, int fallback)
    {
        if (probeIcon == null || item == null)
        {
            return fallback;
        }

        ItemData? originalItem = null;
        try
        {
            originalItem = probeIcon.itemData;
            probeIcon.itemData = item;
            return Math.Max(0, probeIcon.GetItemPrice(buy));
        }
        catch
        {
            return fallback;
        }
        finally
        {
            try
            {
                if (originalItem != null)
                {
                    probeIcon.itemData = originalItem;
                }

                probeIcon.needRefreshPriceIcon = true;
            }
            catch
            {
            }
        }
    }

    private static ItemData? TryCloneAndIdentifyItem(ItemData? item)
    {
        if (item == null)
        {
            return null;
        }

        ItemData? clone;
        try
        {
            clone = item.Clone() as ItemData;
        }
        catch
        {
            return null;
        }

        if (clone == null)
        {
            return null;
        }

        return TryFullIdentifyTreasure(clone) ? clone : null;
    }

    private static bool TryFullIdentifyTreasure(ItemData? item)
    {
        if (item == null || !IsTreasureItem(item))
        {
            return false;
        }

        try
        {
            item.FullIdentify();
        }
        catch (Exception ex)
        {
            LoggerInstance.LogWarning($"Treasure full identify failed for {TryGetItemDisplayName(item)}: {ex.Message}");
            return false;
        }

        try
        {
            item.RecountRareLv();
        }
        catch
        {
        }

        return IsTreasureFullyIdentified(item);
    }

    private static bool IsUnidentifiedTreasure(ItemData? item)
    {
        return IsTreasureItem(item) && !IsTreasureFullyIdentified(item);
    }

    private static bool IsTreasureItem(ItemData? item)
    {
        if (item == null)
        {
            return false;
        }

        try
        {
            return item.type == ItemType.Treasure;
        }
        catch
        {
            return string.Equals(TryGetItemTypeName(item), nameof(ItemType.Treasure), StringComparison.OrdinalIgnoreCase);
        }
    }

    private static bool IsTreasureFullyIdentified(ItemData? item)
    {
        var treasureData = item?.treasureData;
        if (treasureData == null)
        {
            return false;
        }

        try
        {
            if (treasureData.fullIdentified)
            {
                return true;
            }
        }
        catch
        {
        }

        var identifiedList = treasureData.identified;
        var count = TryGetCollectionCount(identifiedList);
        if (count <= 0)
        {
            return false;
        }

        for (var i = 0; i < count; i++)
        {
            if (!(TryConvertToBool(TryGetIndexedValue(identifiedList, i)) ?? false))
            {
                return false;
            }
        }

        return true;
    }

    private static int TryGetTreasureRealValue(ItemData? item)
    {
        if (item == null)
        {
            return 0;
        }

        try
        {
            return Math.Max(0, item.GetTreasureRealValue());
        }
        catch
        {
            return Math.Max(0, item.value);
        }
    }

    private static float GetSkillTradeFactor(bool buy)
    {
        var player = TryGetPlayerHero();
        if (player == null)
        {
            return 1f;
        }

        try
        {
            return Math.Max(0.01f, player.GetTradeValueRate(buy, true));
        }
        catch
        {
        }

        try
        {
            return Math.Max(0.01f, player.GetTradeValueRate(buy));
        }
        catch
        {
            return 1f;
        }
    }

    private static int CountItemListItems(ItemListData? itemList)
    {
        return itemList?.allItem == null ? 0 : Math.Max(0, TryGetCollectionCount(itemList.allItem));
    }

    private static bool ItemListContainsItem(ItemListData? itemList, ItemData? targetItem)
    {
        if (itemList == null || targetItem == null)
        {
            return false;
        }

        var allItems = itemList.allItem;
        var count = TryGetCollectionCount(allItems);
        if (count <= 0)
        {
            return false;
        }

        for (var i = 0; i < count; i++)
        {
            if (ReferenceEquals(TryGetIndexedValue(allItems, i), targetItem))
            {
                return true;
            }
        }

        return false;
    }

    private static int CountMatchingItems(ItemListData? itemList, ItemData? targetItem)
    {
        if (itemList == null || targetItem == null)
        {
            return 0;
        }

        var allItems = itemList.allItem;
        var count = TryGetCollectionCount(allItems);
        if (count <= 0)
        {
            return 0;
        }

        var matches = 0;
        for (var i = 0; i < count; i++)
        {
            if (AreItemsEquivalent(TryGetIndexedValue(allItems, i) as ItemData, targetItem))
            {
                matches++;
            }
        }

        return matches;
    }

    private static bool AreItemsEquivalent(ItemData? left, ItemData? right)
    {
        if (left == null || right == null)
        {
            return false;
        }

        if (ReferenceEquals(left, right))
        {
            return true;
        }

        if (left.itemID > 0 && right.itemID > 0)
        {
            return left.itemID == right.itemID && left.itemLv == right.itemLv && left.rareLv == right.rareLv;
        }

        return string.Equals(left.name, right.name, StringComparison.Ordinal) &&
               left.itemLv == right.itemLv &&
               left.rareLv == right.rareLv;
    }

    private static void AdjustItemListMoney(ItemListData? itemList, int delta)
    {
        if (itemList == null || delta == 0)
        {
            return;
        }

        var currentMoney = TryGetItemListMoney(itemList) ?? 0;
        var targetMoney = Math.Max(0, currentMoney + delta);
        TrySetMemberValue(itemList, "money", targetMoney);
    }

    private static string TryGetItemDisplayName(ItemData? item)
    {
        if (item == null)
        {
            return "未知珍宝";
        }

        try
        {
            var name = item.Name(false);
            if (!string.IsNullOrWhiteSpace(name))
            {
                return name;
            }
        }
        catch
        {
        }

        return string.IsNullOrWhiteSpace(item.name) ? $"珍宝{item.itemID}" : item.name;
    }

    private static string FormatSignedInt(int value)
    {
        return value > 0 ? $"+{value}" : value.ToString();
    }

    private static void AddSkillBookExpPrefix(HeroData __instance, ref float num)
    {
        if (_applyingDailySkillInsightExp)
        {
            return;
        }

        var multiplier = Mathf.Max(1, _bookExpMultiplier.Value);
        if (multiplier <= 1 || num <= 0f)
        {
            return;
        }

        var player = TryGetPlayerHero();
        if (player == null || __instance != player)
        {
            return;
        }

        num *= multiplier;
    }

    private static void RealStartStudySkillPrefix()
    {
        BeginStudyTaskScaling("RealStartStudySkill");
    }

    private static void ReadBookTaskStartPrefix()
    {
        ArmReadBookCountdownOverride("RealStartReadBook");
    }

    private static bool BookWriterSureButtonPrefix(MethodBase __originalMethod, object[] __args)
    {
        ArmBookWriterTaskScaling("BookWriterUIController.SureButtonClicked");
        return true;
    }

    private static void BookWriterSureButtonPostfix()
    {
    }

    private static void BookWriterTotalTimeCostPostfix(BookWriterData __instance, ref int __result)
    {
        if (__instance == null)
        {
            return;
        }

        if (TryApplyBookWriterStatScaling(__instance, __result, "GetTotalTimeCost", out var sourceHero, out var inte, out var agl, out var wil, out var x, out var y, out var scaledDays))
        {
            __result = scaledDays;
        }
    }

    private static void BookWriterEachDayWorkPercentPostfix(BookWriterData __instance, ref float __result)
    {
        if (__instance == null)
        {
            return;
        }

        var baseDays = __result <= 0.01f
            ? 1
            : Math.Max(1, Mathf.CeilToInt(100f / __result));

        if (TryApplyBookWriterStatScaling(__instance, baseDays, "GetEachDayWorkPercent", out var sourceHero, out var inte, out var agl, out var wil, out var x, out var y, out var scaledDays))
        {
            __result = Mathf.Max(1f, 100f / scaledDays);
        }
    }

    private static void ArmBookWriterTaskScaling(string source)
    {
        var writerUI = SafeGetBookWriterUI();
        if (writerUI == null)
        {
            ClearBookWriterTaskScaling($"{source}:no-ui");
            return;
        }

        var writerList = writerUI.targetBookWriterList;
        var count = TryGetCollectionCount(writerList);
        if (writerList == null || count <= 0)
        {
            ClearBookWriterTaskScaling($"{source}:no-list");
            return;
        }

        var activeWriter = ResolveActiveBookWriterData(writerUI, writerList, count);
        if (activeWriter == null)
        {
            ClearBookWriterTaskScaling($"{source}:no-active");
            return;
        }

        try
        {
            _bookWriterTaskTargetDays = Math.Max(1, activeWriter.GetTotalTimeCost());
            _bookWriterTaskData = activeWriter;
            _bookWriterTaskStartDate = TryGetWorldDateSnapshot();
            _bookWriterTaskScalingActive = true;
            _bookWriterCountdownOverrideArmed = true;
        }
        catch (Exception ex)
        {
            LoggerInstance.LogWarning($"Failed to arm book writer scaling from {source}: {ex.Message}");
            ClearBookWriterTaskScaling($"{source}:arm-failed");
        }
    }

    private static BookWriterUIController? SafeGetBookWriterUI()
    {
        try
        {
            return BookWriterUIController.Instance;
        }
        catch
        {
            return null;
        }
    }

    private static bool TryApplyBookWriterStatScaling(BookWriterData? writerData, int baseDays, string source, out HeroData? sourceHero, out float inte, out float agl, out float wil, out float x, out float y, out int scaledDays)
    {
        sourceHero = null;
        inte = 0f;
        agl = 0f;
        wil = 0f;
        x = 0f;
        y = 100f;
        scaledDays = Math.Max(1, baseDays);

        if (writerData == null)
        {
            return false;
        }

        sourceHero = TryResolveBookWriterHero(writerData);

        if (sourceHero == null)
        {
            return false;
        }

        inte = TryReadHeroAttribute(sourceHero, BaseAttriType.Inte) ?? 0f;
        agl = TryReadHeroAttribute(sourceHero, BaseAttriType.Agl) ?? 0f;
        wil = TryReadHeroAttribute(sourceHero, BaseAttriType.Wil) ?? 0f;
        x = (inte * 0.5f) + ((agl + wil) * 0.25f);
        y = Math.Max(1f, 100f - x);
        scaledDays = Math.Max(1, Mathf.RoundToInt(baseDays * (y / 100f)));

        return true;
    }

    private static HeroData? TryResolveBookWriterHero(BookWriterData writerData)
    {
        try
        {
            var hero = writerData.GetBookWriterHero();
            if (hero != null)
            {
                return hero;
            }
        }
        catch
        {
        }

        var heroIdValue = SafeProperty(writerData, "bookWriterHeroID") ?? SafeField(writerData, "bookWriterHeroID");
        var heroId = TryConvertToInt(heroIdValue);
        if (!heroId.HasValue || heroId.Value < 0)
        {
            return null;
        }

        try
        {
            return GameController.Instance?.worldData?.GetHero(heroId.Value);
        }
        catch
        {
            return null;
        }
    }

    private static bool ReadBookTracePrefix(MethodBase __originalMethod, object[] __args)
    {
        if (IsReadBookCountdownStartMethod(__originalMethod))
        {
            ArmReadBookCountdownOverride(DescribeMethod(__originalMethod));
        }

        return true;
    }

    private static void ArmReadBookCountdownOverride(string source)
    {
        _readBookCountdownOverrideArmed = true;
        _readBookCountdownStartDate = TryGetWorldDateSnapshot();
    }

    private static void ReadBookFinishPostfix()
    {
        _readBookCountdownOverrideArmed = false;
        _readBookCountdownStartDate = null;
    }

    private static bool IsReadBookCountdownStartMethod(MethodBase originalMethod)
    {
        return string.Equals(originalMethod.Name, nameof(ReadBookController.StartReadBook), StringComparison.Ordinal) ||
            string.Equals(originalMethod.Name, nameof(ReadBookController.SureStartReadBook), StringComparison.Ordinal) ||
            string.Equals(originalMethod.Name, nameof(ReadBookController.RealStartReadBook), StringComparison.Ordinal) ||
            string.Equals(originalMethod.Name, nameof(PlotController.RealStartReadBook), StringComparison.Ordinal);
    }

    private static void TryForceReadBookCountdown(MailData mailData, string? mailTitle, string? mailText, string source)
    {
        if (!_readBookCountdownOverrideArmed)
        {
            return;
        }

        var startDate = _readBookCountdownStartDate ?? TryGetWorldDateSnapshot();
        if (startDate == null)
        {
            return;
        }

        var targetDate = TryBuildDateFromDelta(startDate, 1);
        if (targetDate == null)
        {
            return;
        }

        var originalDate = mailData.mailTime;
        mailData.mailTime = targetDate;
        _readBookCountdownOverrideArmed = false;
        _readBookCountdownStartDate = null;
    }

    private static void ReadBookUpdatePostfix(ReadBookController __instance)
    {
        if (__instance == null)
        {
            return;
        }

        TraceReadBookState(__instance, "Update");
    }

    private static void TraceReadBookState(ReadBookController __instance, string source)
    {
    }

    private static void FinishStudySkillPostfix(float expNum)
    {
        if (!_studySkillTimeScalingActive)
        {
            return;
        }

        _studySkillTaskScalingActive = false;
        _studySkillTaskStartDate = null;
        _studySkillTimeScalingActive = false;
        _studySkillInjectingExtraDay = false;
        _studySkillUnitDayBudget = 0f;
        _studySkillExtraDayCarry = 0f;
    }

    private static void GetAutoPracticeCostPostfix(ref int __result)
    {
        ScaleStudySkillCostResult(ref __result, "Martial-skill transcription auto practice cost");
    }

    private static void StudyMoneyCostPostfix(ref int __result)
    {
        ScaleStudySkillCostResult(ref __result, "Martial-skill transcription money cost");
    }

    private static void StudyDayCostPostfix(ref int __result)
    {
        ScaleStudySkillCostResult(ref __result, "Martial-skill transcription day cost");
    }

    private static bool StudySkillTracePrefix(MethodBase __originalMethod, object[] __args)
    {
        if (IsStudyTaskCreationMethod(__originalMethod))
        {
            BeginStudyTaskScaling(DescribeMethod(__originalMethod));
        }

        return true;
    }

    private static bool IsStudyTaskCreationMethod(MethodBase originalMethod)
    {
        return string.Equals(originalMethod.Name, "PlayerStudySkill", StringComparison.Ordinal) ||
            string.Equals(originalMethod.Name, "StartStudySkill", StringComparison.Ordinal) ||
            string.Equals(originalMethod.Name, "StartStudyFightSkill", StringComparison.Ordinal) ||
            string.Equals(originalMethod.Name, "StartStudyDodgeSkill", StringComparison.Ordinal) ||
            string.Equals(originalMethod.Name, "StartStudyInternalSkill", StringComparison.Ordinal) ||
            string.Equals(originalMethod.Name, "StartStudyUniqueSkill", StringComparison.Ordinal);
    }

    private static void BeginStudyTaskScaling(string source)
    {
        if (_studySkillTaskScalingActive)
        {
            return;
        }

        _studySkillTaskScalingActive = true;
        _studySkillTaskStartDate = TryGetWorldDateSnapshot();
    }

    private static void MailDataCtorPostfix(MailData __instance)
    {
        var mailTitle = SafeProperty(__instance, "mailTitle") as string;
        var mailText = SafeProperty(__instance, "mailText") as string;
        var mailTime = SafeProperty(__instance, "mailTime") as TimeData;

        TryForceReadBookCountdown(__instance, mailTitle, mailText, "MailData..ctor");
    }

    private static void GetNewMailPostfix(MailData targetMail, HeroData sourceHero)
    {
        TryForceReadBookCountdown(targetMail, targetMail?.mailTitle, targetMail?.mailText, "GameController.GetNewMail");
    }

    private static TimeData? TryBuildDateFromDelta(TimeData startDate, int deltaDays)
    {
        if (deltaDays <= 0)
        {
            return new TimeData(startDate.year, startDate.month, startDate.day);
        }

        var monthLengths = new[] { 30, 31, 29, 28 };
        foreach (var monthLength in monthLengths)
        {
            var year = startDate.year;
            var month = startDate.month;
            var day = startDate.day + deltaDays;

            while (day > monthLength)
            {
                day -= monthLength;
                month++;
                if (month > 12)
                {
                    month = 1;
                    year++;
                }
            }

            try
            {
                var candidate = new TimeData(year, month, day);
                if (GetElapsedDayCount(startDate, candidate) == deltaDays)
                {
                    return candidate;
                }
            }
            catch
            {
            }
        }

        return null;
    }

    private static void StudySkillGetTimeNeedPostfix(MethodBase __originalMethod, object[] __args, object __result)
    {
        TraceStudySkillResult("GetTimeNeed", __originalMethod, __args, __result);
    }

    private static void StudySkillTimePostfix(MethodBase __originalMethod, object[] __args, object __result)
    {
        TraceStudySkillResult("StudySkillTime", __originalMethod, __args, __result);
    }

    private static void BuildingStudySkillCostRatePostfix(MethodBase __originalMethod, object[] __args, object __result)
    {
        TraceStudySkillResult("BuildingStudySkillCostRate", __originalMethod, __args, __result);
    }

    private static void TraceStudySkillResult(string label, MethodBase __originalMethod, object[] __args, object __result)
    {
    }

    private static void ScaleStudySkillCostResult(ref int __result, string traceLabel)
    {
        var multiplier = Math.Max(0f, _studySkillCostMultiplier.Value);
        if (Math.Abs(multiplier - 1f) < 0.001f || __result <= 0)
        {
            return;
        }

        var original = __result;
        __result = Math.Max(0, Mathf.RoundToInt(original * multiplier));

        if (_traceMode.Value)
        {
            LoggerInstance.LogInfo(
                $"{traceLabel} scaled: {SafeFormatValue(original)} -> {SafeFormatValue(__result)} with x{FormatConfigFloat(multiplier)}.");
        }
    }

    private static void BattleChangeSkillFightExpPrefix(HeroData __instance, ref float num, KungfuSkillLvData targetSkill, bool showInfo)
    {
        var originalExp = num;
        var multiplier = Mathf.Max(1, _battleSkillExpMultiplier.Value);
        if (multiplier <= 1 || num <= 0f)
        {
            if (_traceMode.Value && _traceBattleSkillExp.Value && originalExp > 0f)
            {
                LoggerInstance.LogInfo(
                    $"Battle skill EXP trace: hero={TryGetHeroName(__instance)}, skill={TryGetSkillName(targetSkill)}, " +
                    $"baseExp={SafeFormatValue(originalExp)}, finalExp={SafeFormatValue(originalExp)}, multiplier=x{multiplier}, showInfo={showInfo}.");
            }
            return;
        }

        num *= multiplier;

        if (_traceMode.Value && _traceBattleSkillExp.Value)
        {
            LoggerInstance.LogInfo(
                $"Battle skill EXP trace: hero={TryGetHeroName(__instance)}, skill={TryGetSkillName(targetSkill)}, " +
                $"baseExp={SafeFormatValue(originalExp)}, finalExp={SafeFormatValue(num)}, multiplier=x{multiplier}, showInfo={showInfo}.");
        }
    }

    private static void ManageTeachSkillPrefix(HeroData sourceHero, HeroData targetHero, int skillID, float rate, bool showInfo, out TeachSkillSplashState __state)
    {
        __state = new TeachSkillSplashState();

        if (!_teachSkillSameSectAreaShareEnabled.Value)
        {
            return;
        }

        if (!IsPlayerHero(sourceHero))
        {
            return;
        }

        if (sourceHero == null || targetHero == null)
        {
            return;
        }

        var sourceForceId = ResolveHeroForceId(sourceHero);
        if (sourceForceId <= 0)
        {
            if (_traceMode.Value)
            {
                LoggerInstance.LogInfo($"Teach splash skipped: source hero {TryGetHeroName(sourceHero)} is not in a sect.");
            }

            return;
        }

        bool sameForce;
        try
        {
            sameForce = sourceHero.SameForce(targetHero);
        }
        catch
        {
            sameForce = false;
        }

        if (!sameForce)
        {
            if (_traceMode.Value)
            {
                LoggerInstance.LogInfo(
                    $"Teach splash skipped: target {TryGetHeroName(targetHero)} is not in the same sect as {TryGetHeroName(sourceHero)}.");
            }

            return;
        }

        var targetSkill = TryFindHeroSkill(targetHero, skillID);
        if (targetSkill == null)
        {
            if (_traceMode.Value)
            {
                LoggerInstance.LogInfo(
                    $"Teach splash skipped: target {TryGetHeroName(targetHero)} does not already know skill {skillID}.");
            }

            return;
        }

        __state = new TeachSkillSplashState
        {
            IsEligible = true,
            SourceHero = sourceHero,
            TargetHero = targetHero,
            SkillId = skillID,
            SkillName = TryGetSkillName(targetSkill),
            TargetBookProgressBefore = ResolveSkillExpProgress(targetSkill, useFightExp: false),
            TargetFightProgressBefore = ResolveSkillExpProgress(targetSkill, useFightExp: true)
        };

        if (_traceMode.Value)
        {
            LoggerInstance.LogInfo(
                $"Teach splash trace enter: source={TryGetHeroName(sourceHero)}, target={TryGetHeroName(targetHero)}, " +
                $"skill={__state.SkillName}/{skillID}, rate={SafeFormatValue(rate)}, showInfo={showInfo}, area={TryGetAreaName(sourceHero)}.");
        }
    }

    private static void ManageTeachSkillPostfix(HeroData sourceHero, HeroData targetHero, int skillID, float rate, bool showInfo, TeachSkillSplashState __state)
    {
        if (!__state.IsEligible || __state.SourceHero == null || __state.TargetHero == null)
        {
            return;
        }

        var targetSkill = TryFindHeroSkill(__state.TargetHero, __state.SkillId);
        if (targetSkill == null)
        {
            if (_traceMode.Value)
            {
                LoggerInstance.LogInfo(
                    $"Teach splash skipped after teach: target {TryGetHeroName(__state.TargetHero)} no longer has skill {__state.SkillId}.");
            }

            return;
        }

        var bookDelta = ResolveSkillExpProgress(targetSkill, useFightExp: false) - __state.TargetBookProgressBefore;
        var fightDelta = ResolveSkillExpProgress(targetSkill, useFightExp: true) - __state.TargetFightProgressBefore;
        var useFightExp = fightDelta > bookDelta;
        var baseExp = Mathf.Max(bookDelta, fightDelta);
        if (baseExp <= 0.001f)
        {
            if (_traceMode.Value)
            {
                LoggerInstance.LogInfo(
                    $"Teach splash skipped: target {TryGetHeroName(__state.TargetHero)} gained no tracked EXP for {__state.SkillName}/{__state.SkillId}.");
            }

            return;
        }

        var recipients = ApplyTeachSkillSameSectAreaShare(__state.SourceHero, __state.TargetHero, __state.SkillId, baseExp, useFightExp, out var recipientResults);
        if (recipients <= 0)
        {
            if (_traceMode.Value)
            {
                LoggerInstance.LogInfo(
                    $"Teach splash found no extra recipients: source={TryGetHeroName(__state.SourceHero)}, target={TryGetHeroName(__state.TargetHero)}, " +
                    $"skill={__state.SkillName}/{__state.SkillId}, baseExp={SafeFormatValue(baseExp)}, area={TryGetAreaName(__state.SourceHero)}.");
            }

            return;
        }

        PublishTeachSkillRecipientSideTabs(recipientResults, useFightExp);

        LoggerInstance.LogInfo(
            $"Teach splash applied: source={TryGetHeroName(__state.SourceHero)}, target={TryGetHeroName(__state.TargetHero)}, " +
            $"skill={__state.SkillName}/{__state.SkillId}, baseExp={SafeFormatValue(baseExp)}, expType={(useFightExp ? "fight" : "book")}, " +
            $"recipients={recipients}, area={TryGetAreaName(__state.SourceHero)}, detail=[{string.Join(", ", recipientResults.ConvertAll(FormatTeachSkillRecipientSummary))}].");
    }

    private static void ChangeMoneyPrefix(HeroData __instance, int num, out MoneyChangeState __state)
    {
        var isPlayerHero = IsPlayerHero(__instance);
        __state = new MoneyChangeState
        {
            IsEligible = !_applyingLuckyMoneyRefund && num != 0 && ClampPercent(_luckyMoneyHitChancePercent.Value) > 0 && isPlayerHero,
            RequestedDelta = num,
            MoneyBefore = TryGetHeroMoney(__instance),
            IsSpend = num < 0,
            IsIncome = num > 0
        };
    }

    private static void ChangeMoneyPostfix(HeroData __instance, int num, bool showInfo, MoneyChangeState __state)
    {
        if (!__state.IsEligible)
        {
            return;
        }

        var hitChancePercent = ClampPercent(_luckyMoneyHitChancePercent.Value);
        var roll = Random.Next(1, 101);
        if (roll > hitChancePercent)
        {
            if (_traceMode.Value)
            {
                LoggerInstance.LogInfo($"Lucky money miss: roll {roll} > {hitChancePercent} for delta {__state.RequestedDelta}.");
            }

            return;
        }

        var changedAmount = ResolveChangedAmount(__state.RequestedDelta, __state.MoneyBefore, TryGetHeroMoney(__instance), __state.IsSpend);
        if (changedAmount <= 0)
        {
            return;
        }

        var rebatePercent = Random.Next(LuckyMoneyMinPercent, LuckyMoneyMaxPercent + 1);
        var rebateAmount = Mathf.Clamp(Mathf.RoundToInt(changedAmount * (rebatePercent / 100f)), 1, changedAmount);
        if (rebateAmount <= 0)
        {
            return;
        }

        try
        {
            _applyingLuckyMoneyRefund = true;
            __instance.ChangeMoney(rebateAmount, false);
        }
        finally
        {
            _applyingLuckyMoneyRefund = false;
        }

        var popup = __state.IsSpend
            ? $"感谢你长期光顾，现金回扣 {rebateAmount}"
            : $"你这个东西比想象的好，多给你 {rebateAmount}";
        PushPlayerLog(popup);
        LoggerInstance.LogInfo(
            $"Lucky money bonus applied: kind={(__state.IsSpend ? "spend" : "income")}, base={changedAmount}, bonus={rebateAmount}, percent={rebatePercent}, chance={hitChancePercent}, roll={roll}.");
    }

    private static void ChangeFamePrefix(HeroData __instance, object? __0, out FameChangeState __state)
    {
        var requestedDelta = TryConvertToFloat(__0) ?? 0f;
        __state = new FameChangeState
        {
            IsEligible = !_applyingTeamFameShare && requestedDelta > 0f && IsPlayerHero(__instance),
            RequestedDelta = requestedDelta,
            FameBefore = TryReadFame(__instance)
        };
    }

    private static void ChangeFamePostfix(HeroData __instance, object? __0, FameChangeState __state)
    {
        if (!__state.IsEligible)
        {
            return;
        }

        var actualGain = ResolvePositiveFloatGain(__state.RequestedDelta, __state.FameBefore, TryReadFame(__instance));
        if (actualGain <= 0.001f)
        {
            return;
        }

        TryApplyTeamFameShare(__instance, actualGain);
    }

    private static void ChangeFavorPrefix(HeroData __instance, ref float num)
    {
        if (_applyingTeamAutoFavor || num <= 0f || IsPlayerHero(__instance))
        {
            return;
        }

        var hitChancePercent = ClampPercent(_extraRelationshipGainChancePercent.Value);
        if (hitChancePercent <= 0)
        {
            return;
        }

        var roll = Random.Next(1, 101);
        if (roll > hitChancePercent)
        {
            if (_traceMode.Value)
            {
                LoggerInstance.LogInfo($"Relationship bonus miss: roll {roll} > {hitChancePercent} for favor gain {SafeFormatValue(num)}.");
            }

            return;
        }

        var originalGain = num;
        num *= 2f;

        var messageTemplate = RelationshipBonusMessages[Random.Next(RelationshipBonusMessages.Length)];
        var message = string.Format(messageTemplate, SafeFormatValue(originalGain));
        PushPlayerLog(message);
        LoggerInstance.LogInfo(
            $"Relationship bonus applied: hero={TryGetHeroName(__instance)}, gain {SafeFormatValue(originalGain)} -> {SafeFormatValue(num)}, chance={hitChancePercent}, roll={roll}.");
    }

    private static void DebateChangePatientPrefix(bool isPlayer, ref float num)
    {
        if (num >= 0f)
        {
            return;
        }

        var multiplier = Mathf.Max(0f, isPlayer
            ? _debatePlayerDamageTakenMultiplier.Value
            : _debateEnemyDamageTakenMultiplier.Value);
        if (Math.Abs(multiplier - 1f) < 0.001f)
        {
            return;
        }

        var original = num;
        num *= multiplier;

        if (_traceMode.Value)
        {
            LoggerInstance.LogInfo(
                $"Debate damage scaled for {(isPlayer ? "player" : "enemy")}: {SafeFormatValue(original)} -> {SafeFormatValue(num)} with x{FormatConfigFloat(multiplier)}.");
        }
    }

    private static void CraftResultChoosenPrefix(ref ItemData craftResult)
    {
        if (!_craftRandomPickUpgradeEnabled.Value)
        {
            ResetCraftRewardTracking("PlotController.CraftResultChoosen disabled");
            return;
        }

        RememberCraftSelection(craftResult);
    }

    private static void CraftResultChoosenPostfix(PlotController __instance, ItemData craftResult)
    {
        if (!_craftRandomPickUpgradeEnabled.Value || _repeatingCraftChoiceReward)
        {
            return;
        }

        var bonusState = _activeCraftRewardBonus ?? ResolveCraftRewardBonusState();
        LogCraftEvent(
            $"PlotController.CraftResultChoosen observed item={DescribeItemSummary(craftResult)}, activeBonus={(bonusState == null ? "none" : bonusState.ExtraItemCount.ToString())}, consumed={SafeFormatValue(bonusState?.Consumed)}, replayingChoice={SafeFormatValue(_repeatingCraftChoiceReward)}");

        if (bonusState == null || bonusState.ExtraItemCount <= 0 || craftResult == null)
        {
            return;
        }

        var player = TryGetPlayerHero();
        if (player == null)
        {
            LogCraftEvent("PlotController.CraftResultChoosen direct grant skipped: player unavailable");
            return;
        }

        var grantedCount = 0;
        _grantingCraftBonusItems = true;

        try
        {
            for (var i = 0; i < bonusState.ExtraItemCount; i++)
            {
                var bonusItem = TryCreateCraftBonusItem(craftResult, player);
                if (bonusItem == null)
                {
                    continue;
                }

                player.GetItem(bonusItem, false, false, 0, false);
                grantedCount++;
            }
        }
        catch (Exception ex)
        {
            LoggerInstance.LogWarning($"PlotController.CraftResultChoosen direct grant failed: {ex.Message}");
        }
        finally
        {
            _grantingCraftBonusItems = false;
            _activeCraftRewardBonus = null;
            _pendingCraftSelection = null;
        }

        if (grantedCount <= 0)
        {
            LogCraftEvent($"PlotController.CraftResultChoosen direct grant produced no extra items for {DescribeItemSummary(craftResult)}");
            return;
        }

        PushPlayerLog($"【巧手增产】：加入【{bonusState.MaterialName}】后，额外获得 {grantedCount} 个【{craftResult.name ?? $"id={craftResult.itemID}"}】");
        LogCraftEvent(
            $"PlotController.CraftResultChoosen directly granted {grantedCount}x item={DescribeItemSummary(craftResult)} using material={bonusState.MaterialName}, majorTier={bonusState.MaterialMajorTier}");
    }

    private static void FinishCraftPrefix()
    {
        ActivateCraftRewardBonus("PlotController.FinishCraft");
    }

    private static void FinishCraftPostfix()
    {
        if (_activeCraftRewardBonus != null)
        {
            LogCraftEvent($"FinishCraft postfix activeBonus={_activeCraftRewardBonus.ExtraItemCount}, plotItem={DescribeItemSummary(PlotController.Instance?.plotInteractItem)}");
        }
    }

    private static void FinishCraftPoisonPrefix()
    {
        ActivateCraftRewardBonus("PlotController.FinishCraftPoison");
    }

    private static void FinishCraftPoisonPostfix()
    {
        FinishCraftPostfix();
    }

    private static void DrinkShowUiPostfix(DrinkUIController __instance)
    {
        ResetDrinkTracking(__instance);
    }

    private static void DrinkHideUiPostfix(DrinkUIController __instance)
    {
        ResetDrinkTracking(null);
    }

    private static void DrinkGetCostPostfix(DrinkUIController __instance, float fillAmount, ref float __result)
    {
        if (__result >= 0f)
        {
            UpdateDrinkTracking(__instance);
            return;
        }

        var targetIsPlayer = ResolveDrinkCostTargetIsPlayer(__instance, fillAmount);
        var multiplier = ResolveDrinkPowerCostMultiplier(targetIsPlayer);
        UpdateDrinkTracking(__instance);

        if (Math.Abs(multiplier - 1f) < 0.001f)
        {
            return;
        }

        var original = __result;
        __result *= multiplier;

        if (_traceMode.Value)
        {
            var targetLabel = targetIsPlayer.HasValue
                ? (targetIsPlayer.Value ? "player" : "enemy")
                : "unknown";
            LoggerInstance.LogInfo(
                $"Drink Qi cost scaled for {targetLabel}: {SafeFormatValue(original)} -> {SafeFormatValue(__result)} with x{FormatConfigFloat(multiplier)} at fill {SafeFormatValue(fillAmount)}.");
        }
    }

    private static void SetAttriPresetPostfix(StartMenuController __instance, int presetID)
    {
        ApplyCharacterCreationPointMultiplier(__instance, $"preset {presetID}");
    }

    private static void ResetPlayerAttriPostfix(StartMenuController __instance)
    {
        ApplyCharacterCreationPointMultiplier(__instance, "reset");
    }

    private static void BattleTimeScaleButtonClickedPostfix()
    {
        var multiplier = Math.Max(1, _battleSpeedMultiplier.Value);
        if (multiplier <= 1)
        {
            return;
        }

        var worldData = GameController.Instance?.worldData;
        if (worldData == null)
        {
            return;
        }

        var selectedSpeed = worldData.battleTimeScale;
        var adjustedSpeed = Mathf.Max(1f, selectedSpeed * multiplier);
        if (Math.Abs(adjustedSpeed - selectedSpeed) < 0.01f)
        {
            return;
        }

        worldData.battleTimeScale = adjustedSpeed;
        RememberPreferredBattleTimeScale(adjustedSpeed, "BattleTimeScaleButtonClicked");
        LoggerInstance.LogInfo($"Battle speed adjusted from x{selectedSpeed:0.###} to x{adjustedSpeed:0.###} using multiplier x{multiplier}.");
    }

    private static void HorseStartSprintPostfix(HorseData __instance)
    {
        if (!IsPlayerHorse(__instance))
        {
            return;
        }

        var durationMultiplier = Math.Max(0.01f, _horseTurboDurationMultiplier.Value);
        var cooldownMultiplier = Math.Max(0.01f, _horseTurboCooldownMultiplier.Value);
        var originalDuration = __instance.sprintTimeLeft;
        var originalCooldown = __instance.sprintTimeCd;
        var changed = false;

        if (Math.Abs(durationMultiplier - 1f) > 0.001f && originalDuration > 0f)
        {
            __instance.sprintTimeLeft = Mathf.Max(0f, originalDuration * durationMultiplier);
            changed = true;
        }

        if (Math.Abs(cooldownMultiplier - 1f) > 0.001f && originalCooldown > 0f)
        {
            __instance.sprintTimeCd = Mathf.Max(0f, originalCooldown * cooldownMultiplier);
            changed = true;
        }

        if (!changed)
        {
            return;
        }

        LoggerInstance.LogInfo(
            $"Horse turbo adjusted: duration {originalDuration:0.###}->{__instance.sprintTimeLeft:0.###}, " +
            $"cooldown {originalCooldown:0.###}->{__instance.sprintTimeCd:0.###}, " +
            $"base x{FormatConfigFloat(_horseBaseSpeedMultiplier.Value)}, turbo x{FormatConfigFloat(_horseTurboSpeedMultiplier.Value)}.");

        KeepPlayerHorseTurboReady("StartSprint");
    }

    private static void GetHorseTravelSpeedPostfix(HeroData __instance, ref float __result)
    {
        if (!IsPlayerHero(__instance))
        {
            return;
        }

        __result = ApplyHorseTravelMultiplier(__instance, __result, IsHorseTurboActive(TryGetPlayerHorse()));
    }

    private static void GetHorseTravelSpeedWithFlagsPostfix(HeroData __instance, bool havePower, bool isSprint, ref float __result)
    {
        if (!IsPlayerHero(__instance))
        {
            return;
        }

        __result = ApplyHorseTravelMultiplier(__instance, __result, ResolveHorseTurboTravelState(havePower, isSprint));
    }

    private static void RefreshHorseStatePostfix(HeroData __instance)
    {
        if (!IsPlayerHero(__instance))
        {
            return;
        }

        KeepPlayerHorseTurboReady("RefreshHorseState");
    }

    private static bool CalendarChangePrefix(MethodBase __originalMethod, object[] __args, out CalendarChangeState __state)
    {
        __state = new CalendarChangeState
        {
            BeforeText = GetWorldDateText(includeHour: true),
            BeforeDate = TryGetWorldDateSnapshot()
        };

        if (_traceMode.Value)
        {
            LoggerInstance.LogInfo($"TRACE DATE ENTER {DescribeMethod(__originalMethod)} dateBefore={__state.BeforeText} args={DescribeArgs(__args)}");
        }

        if (_freezeDate.Value)
        {
            if (_traceMode.Value)
            {
                LoggerInstance.LogInfo($"Freeze Date blocked {DescribeMethod(__originalMethod)} at {__state.BeforeText}.");
            }

            return false;
        }

        if (TryApplyStudySkillTimeScaling(__originalMethod, __args, out var skipOriginalCall))
        {
            if (skipOriginalCall)
            {
                return false;
            }
        }

        return true;
    }

    private static void CalendarChangePostfix(MethodBase __originalMethod, object[] __args, CalendarChangeState __state)
    {
        var afterText = GetWorldDateText(includeHour: true);
        if (_traceMode.Value)
        {
            LoggerInstance.LogInfo($"TRACE DATE EXIT  {DescribeMethod(__originalMethod)} dateBefore={__state.BeforeText} dateAfter={afterText}");
        }

        HandleDailySkillInsightDateProgress(__state.BeforeDate, TryGetWorldDateSnapshot(), DescribeMethod(__originalMethod));
        HandleTeamAutoFavorDateProgress(__state.BeforeDate, TryGetWorldDateSnapshot(), DescribeMethod(__originalMethod));

        if (_studySkillTimeScalingActive && !_studySkillInjectingExtraDay)
        {
            var multiplier = Math.Max(0f, _studySkillCostMultiplier.Value);
            if (multiplier > 1f && IsStudyDayChangeMethod(__originalMethod) && __args.Length == 0)
            {
                _studySkillExtraDayCarry += multiplier - 1f;
                while (_studySkillExtraDayCarry >= 1f)
                {
                    _studySkillExtraDayCarry -= 1f;
                    try
                    {
                        _studySkillInjectingExtraDay = true;
                        GameController.Instance?.ChangeDay();
                    }
                    catch (Exception ex)
                    {
                        LoggerInstance.LogWarning($"Failed to apply study skill extra day scaling: {ex.Message}");
                        _studySkillExtraDayCarry = 0f;
                        break;
                    }
                    finally
                    {
                        _studySkillInjectingExtraDay = false;
                    }
                }
            }
        }
    }

    private static bool HourChangePrefix(MethodBase __originalMethod, object[] __args, out string __state)
    {
        __state = GetWorldDateText(includeHour: true);

        if (_traceMode.Value)
        {
            LoggerInstance.LogInfo($"TRACE TIME ENTER {DescribeMethod(__originalMethod)} dateBefore={__state} args={DescribeArgs(__args)}");
        }

        TryApplyStudyHourScaling(__originalMethod, __args);

        return true;
    }

    private static void HourChangePostfix(MethodBase __originalMethod, object[] __args, string __state)
    {
        if (_traceMode.Value)
        {
            LoggerInstance.LogInfo($"TRACE TIME EXIT  {DescribeMethod(__originalMethod)} dateBefore={__state} dateAfter={GetWorldDateText(includeHour: true)}");
        }
    }

    private static void ShowStartMenuPostfix()
    {
        ClearShopOwnershipRuntimeState("StartMenu.ShowStartMenu");
        ResetStudySkillTimeScalingState("StartMenu.ShowStartMenu");
    }

    private static void ShowMainMenuPostfix()
    {
        ClearShopOwnershipRuntimeState("GameTitle.ShowMainMenu");
        ResetStudySkillTimeScalingState("GameTitle.ShowMainMenu");
    }

    private static bool TryApplyStudySkillTimeScaling(MethodBase originalMethod, object[] args, out bool skipOriginalCall)
    {
        skipOriginalCall = false;

        if (!_studySkillTimeScalingActive || _studySkillInjectingExtraDay)
        {
            return false;
        }

        var multiplier = Math.Max(0f, _studySkillCostMultiplier.Value);
        if (Math.Abs(multiplier - 1f) < 0.001f || multiplier <= 0f)
        {
            return false;
        }

        if (!IsStudyDayChangeMethod(originalMethod))
        {
            return false;
        }

        if (args.Length == 0)
        {
            if (multiplier < 1f)
            {
                _studySkillUnitDayBudget += multiplier;
                if (_studySkillUnitDayBudget < 1f)
                {
                    skipOriginalCall = true;
                }
                else
                {
                    _studySkillUnitDayBudget -= 1f;
                }
            }

            return true;
        }

        var originalDelta = TryConvertToInt(args[0]) ?? 0;
        if (originalDelta <= 0)
        {
            return false;
        }

        if (multiplier < 1f && originalDelta == 1)
        {
            _studySkillUnitDayBudget += multiplier;
            if (_studySkillUnitDayBudget < 1f)
            {
                skipOriginalCall = true;
                return true;
            }

            _studySkillUnitDayBudget -= 1f;
            return true;
        }

        var scaled = multiplier < 1f
            ? Mathf.FloorToInt(originalDelta * multiplier)
            : Mathf.CeilToInt(originalDelta * multiplier);
        if (scaled <= 0)
        {
            skipOriginalCall = true;
            return true;
        }

        if (scaled != originalDelta)
        {
            args[0] = scaled;
        }

        return true;
    }

    private static bool TryApplyStudyHourScaling(MethodBase originalMethod, object[] args)
    {
        if (!_studySkillTimeScalingActive || _studySkillInjectingExtraDay)
        {
            return false;
        }

        var multiplier = Math.Max(0f, _studySkillCostMultiplier.Value);
        if (Math.Abs(multiplier - 1f) < 0.001f || multiplier <= 0f)
        {
            return false;
        }

        if (!string.Equals(originalMethod.Name, nameof(GameController.ChangeHour), StringComparison.Ordinal))
        {
            return false;
        }

        if (args.Length == 0)
        {
            return false;
        }

        var originalHours = TryConvertToFloat(args[0]) ?? 0f;
        if (originalHours <= 0f)
        {
            return false;
        }

        args[0] = originalHours * multiplier;

        return true;
    }

    private static bool IsStudyDayChangeMethod(MethodBase originalMethod)
    {
        return string.Equals(originalMethod.Name, nameof(GameController.ChangeDay), StringComparison.Ordinal) ||
            string.Equals(originalMethod.Name, nameof(GameController.ChangeDayDirect), StringComparison.Ordinal);
    }

    private static void ResetStudySkillTimeScalingState(string source)
    {
        if (!_studySkillTimeScalingActive && Math.Abs(_studySkillUnitDayBudget) < 0.001f && Math.Abs(_studySkillExtraDayCarry) < 0.001f)
        {
            return;
        }

        _studySkillTimeScalingActive = false;
        _studySkillInjectingExtraDay = false;
        _studySkillUnitDayBudget = 0f;
        _studySkillExtraDayCarry = 0f;
    }

    private static void SaveSlotButtonClickedPrefix(int saveID)
    {
        _pendingShopOwnershipSaveSlotId = saveID;
    }

    private static void SureSavePostfix(string param)
    {
        var saveSlotId = TryResolveSaveSlotId(param) ?? (_pendingShopOwnershipSaveSlotId >= 0 ? _pendingShopOwnershipSaveSlotId : null);
        _pendingShopOwnershipSaveSlotId = -1;
        if (!saveSlotId.HasValue)
        {
            LoggerInstance.LogWarning("Shop ownership save sync skipped because the confirmed save slot could not be resolved.");
            SetExternalOverlayStatusMessage("模组档案同步失败：无法识别当前存档槽。");
            return;
        }

        _currentShopOwnershipSaveSlotId = saveSlotId.Value;
        _loadedShopOwnershipSourceSlotId = saveSlotId.Value;
        SaveOwnedShopsForSlot(saveSlotId.Value, "SaveLoadMenu.SureSave");
        SetExternalOverlayStatusMessage($"模组档案已同步到存档槽 {saveSlotId.Value}。");
    }

    private static void LoadRecentGamePrefix(SaveLoadMenuController __instance)
    {
        int? saveSlotId = null;
        try
        {
            saveSlotId = __instance?.GetRecentSaveSlotID();
        }
        catch
        {
        }

        if (!saveSlotId.HasValue || saveSlotId.Value < 0)
        {
            LoggerInstance.LogWarning("Shop ownership load sync skipped because the recent save slot could not be resolved.");
            SetExternalOverlayStatusMessage("读取最近存档失败：无法识别存档槽。");
            return;
        }

        LoadOwnedShopsForSlot(saveSlotId.Value, "SaveLoadMenu.LoadRecentGame");
    }

    private static void LoadGamePrefix(int saveID)
    {
        if (saveID < 0)
        {
            LoggerInstance.LogWarning($"Shop ownership load sync skipped because load slot {saveID} is invalid.");
            SetExternalOverlayStatusMessage("读取存档失败：存档槽编号无效。");
            return;
        }

        LoadOwnedShopsForSlot(saveID, "SaveLoadMenu.LoadGame");
    }

    private static void ClearShopOwnershipRuntimeState(string source)
    {
        _currentShopOwnershipSaveSlotId = -1;
        _loadedShopOwnershipSourceSlotId = -1;
        _pendingShopOwnershipSaveSlotId = -1;
        _ownedShops.Clear();
        _lastExternalOverlayRequestId = string.Empty;
        HideShopOwnershipOverlay();
        SetExternalOverlayStatusMessage("已回到标题界面，等待新的存档载入。");

        if (_traceMode.Value)
        {
            LoggerInstance.LogInfo($"Shop ownership runtime state cleared from {source}.");
        }
    }

    private static string GetOwnedShopSavePath(int saveSlotId)
    {
        var folder = Path.Combine(Paths.ConfigPath, ShopOwnershipSaveFolderName);
        return Path.Combine(folder, $"slot-{saveSlotId}.json");
    }

    private static void LoadOwnedShopsForSlot(int saveSlotId, string source)
    {
        _loadedShopOwnershipSourceSlotId = saveSlotId;
        _currentShopOwnershipSaveSlotId = -1;
        _pendingShopOwnershipSaveSlotId = -1;
        _ownedShops.Clear();

        var path = GetOwnedShopSavePath(saveSlotId);
        if (!File.Exists(path))
        {
            SetExternalOverlayStatusMessage($"已从存档槽 {saveSlotId} 读取，当前没有店铺产业记录。下次保存时才会绑定新的写入存档槽。");
            if (_traceMode.Value)
            {
                LoggerInstance.LogInfo($"Shop ownership load found no sidecar for slot {saveSlotId} at {path} from {source}.");
            }

            return;
        }

        try
        {
            var text = File.ReadAllText(path);
            var payload = JsonSerializer.Deserialize<ShopOwnershipSaveFile>(
                text,
                new JsonSerializerOptions
                {
                    PropertyNameCaseInsensitive = true
                });

            if (payload == null)
            {
                LoggerInstance.LogWarning($"Shop ownership sidecar at {path} was empty. Starting with no owned shops.");
                return;
            }

            if (payload.version != ShopOwnershipSaveVersion)
            {
                LoggerInstance.LogWarning(
                    $"Shop ownership sidecar at {path} has unsupported version {payload.version}. Expected {ShopOwnershipSaveVersion}.");
                return;
            }

            if (payload.shops == null)
            {
                return;
            }

            foreach (var entry in payload.shops)
            {
                if (entry == null || string.IsNullOrWhiteSpace(entry.shopKey))
                {
                    continue;
                }

                _ownedShops[entry.shopKey] = new OwnedShopRecord
                {
                    ShopKey = entry.shopKey,
                    ShopName = entry.shopName?.Trim() ?? entry.shopKey,
                    AreaId = entry.areaId,
                    BuildingId = entry.buildingId,
                    BuyPrice = Math.Max(0, entry.buyPrice),
                    PurchasedOn = entry.purchasedOn?.Trim() ?? string.Empty
                };
            }

            LoggerInstance.LogInfo(
                $"Shop ownership loaded {_ownedShops.Count} owned shop(s) for slot {saveSlotId} from {path} via {source}.");
            SetExternalOverlayStatusMessage($"已从存档槽 {saveSlotId} 读取到 {_ownedShops.Count} 间已买下的店铺。下次保存时才会绑定新的写入存档槽。");
        }
        catch (Exception ex)
        {
            LoggerInstance.LogWarning($"Failed to load shop ownership sidecar for slot {saveSlotId} from {path}: {ex.Message}");
            SetExternalOverlayStatusMessage($"读取模组店铺档案失败：{ex.Message}");
        }
    }

    private static void SaveOwnedShopsForSlot(int saveSlotId, string source)
    {
        if (saveSlotId < 0)
        {
            LoggerInstance.LogWarning($"Shop ownership save skipped from {source} because slot {saveSlotId} is invalid.");
            return;
        }

        var path = GetOwnedShopSavePath(saveSlotId);
        try
        {
            var directory = Path.GetDirectoryName(path);
            if (!string.IsNullOrWhiteSpace(directory))
            {
                Directory.CreateDirectory(directory);
            }

            if (_ownedShops.Count == 0)
            {
                if (File.Exists(path))
                {
                    File.Delete(path);
                }

                if (_traceMode.Value)
                {
                    LoggerInstance.LogInfo($"Shop ownership save removed empty sidecar for slot {saveSlotId} via {source}.");
                }

                return;
            }

            var payload = new ShopOwnershipSaveFile
            {
                version = ShopOwnershipSaveVersion,
                shops = _ownedShops.Values
                    .OrderBy(static entry => entry.ShopKey, StringComparer.Ordinal)
                    .Select(
                        static entry => new ShopOwnershipSaveEntry
                        {
                            shopKey = entry.ShopKey,
                            shopName = entry.ShopName,
                            areaId = entry.AreaId,
                            buildingId = entry.BuildingId,
                            buyPrice = entry.BuyPrice,
                            purchasedOn = entry.PurchasedOn
                        })
                    .ToList()
            };

            File.WriteAllText(
                path,
                JsonSerializer.Serialize(
                    payload,
                    new JsonSerializerOptions
                    {
                        WriteIndented = true
                    }));
            LoggerInstance.LogInfo(
                $"Shop ownership saved {_ownedShops.Count} owned shop(s) for slot {saveSlotId} to {path} via {source}.");
        }
        catch (Exception ex)
        {
            LoggerInstance.LogWarning($"Failed to save shop ownership sidecar for slot {saveSlotId} to {path}: {ex.Message}");
        }
    }

    private static void TrySyncExternalOverlay()
    {
        var now = Time.realtimeSinceStartup;
        if (_lastExternalOverlaySyncRealtime >= 0f &&
            now < _lastExternalOverlaySyncRealtime + ExternalOverlaySyncIntervalSeconds)
        {
            return;
        }

        _lastExternalOverlaySyncRealtime = now;
        TryProcessExternalOverlayCommand();
        WriteExternalOverlayState();
    }

    private static void TryProcessExternalOverlayCommand()
    {
        var path = GetExternalOverlayCommandPath();
        if (!File.Exists(path))
        {
            return;
        }

        ExternalOverlayCommandFile? payload;
        try
        {
            payload = JsonSerializer.Deserialize<ExternalOverlayCommandFile>(
                File.ReadAllText(path),
                new JsonSerializerOptions
                {
                    PropertyNameCaseInsensitive = true
                });
        }
        catch (Exception ex)
        {
            LoggerInstance.LogWarning($"Failed to parse external overlay command from {path}: {ex.Message}");
            SetExternalOverlayStatusMessage($"外部浮窗指令读取失败：{ex.Message}");
            TryDeleteFile(path);
            return;
        }

        if (payload == null ||
            payload.version != ExternalOverlayProtocolVersion ||
            string.IsNullOrWhiteSpace(payload.requestId) ||
            string.IsNullOrWhiteSpace(payload.action))
        {
            SetExternalOverlayStatusMessage("外部浮窗指令格式无效，已忽略。");
            TryDeleteFile(path);
            return;
        }

        if (string.Equals(payload.requestId, _lastExternalOverlayRequestId, StringComparison.Ordinal))
        {
            TryDeleteFile(path);
            return;
        }

        _lastExternalOverlayRequestId = payload.requestId;

        switch (payload.action.Trim().ToLowerInvariant())
        {
            case "buy-shop":
                TryBuyCurrentShop(payload.shopKey, out var message, out var tradeUi);
                PushPlayerLog(message);
                if (tradeUi != null)
                {
                    RefreshTradeUi(tradeUi);
                }

                UpdateShopOwnershipUiState();

                break;
            default:
                SetExternalOverlayStatusMessage($"外部浮窗指令不受支持：{payload.action}");
                break;
        }

        TryDeleteFile(path);
    }

    private static void WriteExternalOverlayState()
    {
        try
        {
            var player = TryGetPlayerHero();
            var playerMoney = TryGetHeroMoney(player);
            var inShop = TryResolveCurrentShopOwnershipContext(out var context);
            OwnedShopRecord? ownedRecord = null;
            var isOwned = inShop && _ownedShops.TryGetValue(context.ShopKey, out ownedRecord);
            var canBuy = inShop && !isOwned && playerMoney.GetValueOrDefault() >= ShopOwnershipBuyPrice;

            var payload = new ExternalOverlayStateFile
            {
                version = ExternalOverlayProtocolVersion,
                updatedAtUtc = DateTime.UtcNow.ToString("O"),
                statusMessage = _externalOverlayStatusMessage,
                statusChangedAtUtc = _externalOverlayStatusChangedAtUtc,
                worldDate = FormatDate(TryGetWorldDateSnapshot()),
                saveSlotId = _currentShopOwnershipSaveSlotId >= 0
                    ? _currentShopOwnershipSaveSlotId
                    : _loadedShopOwnershipSourceSlotId,
                ownedShopCount = _ownedShops.Count,
                playerMoney = playerMoney,
                inShop = inShop,
                shopKey = inShop ? context.ShopKey : null,
                shopName = inShop ? context.ShopName : null,
                shopOwned = isOwned,
                canBuyShop = canBuy,
                buyPrice = ShopOwnershipBuyPrice,
                purchasedOn = isOwned && ownedRecord != null ? ownedRecord.PurchasedOn : null,
                lastProcessedRequestId = string.IsNullOrWhiteSpace(_lastExternalOverlayRequestId) ? null : _lastExternalOverlayRequestId
            };

            WriteJsonAtomically(GetExternalOverlayStatePath(), payload);
        }
        catch (Exception ex)
        {
            LoggerInstance.LogWarning($"Failed to write external overlay state: {ex.Message}");
        }
    }

    private static void SetExternalOverlayStatusMessage(string message)
    {
        _externalOverlayStatusMessage = string.IsNullOrWhiteSpace(message) ? "状态未知" : message.Trim();
        _externalOverlayStatusChangedAtUtc = DateTime.UtcNow.ToString("O");
    }

    private static string GetExternalOverlayRootPath()
    {
        return Paths.ConfigPath;
    }

    private static string GetExternalOverlayStatePath()
    {
        return Path.Combine(GetExternalOverlayRootPath(), ExternalOverlayStateFileName);
    }

    private static string GetExternalOverlayCommandPath()
    {
        return Path.Combine(GetExternalOverlayRootPath(), ExternalOverlayCommandFileName);
    }

    private static void WriteJsonAtomically<TPayload>(string path, TPayload payload)
    {
        var directory = Path.GetDirectoryName(path);
        if (!string.IsNullOrWhiteSpace(directory))
        {
            Directory.CreateDirectory(directory);
        }

        var tempPath = path + ".tmp";
        File.WriteAllText(
            tempPath,
            JsonSerializer.Serialize(
                payload,
                new JsonSerializerOptions
                {
                    WriteIndented = true
                }));
        File.Move(tempPath, path, true);
    }

    private static void TryDeleteFile(string path)
    {
        try
        {
            if (File.Exists(path))
            {
                File.Delete(path);
            }
        }
        catch
        {
        }
    }

    private static int? TryResolveSaveSlotId(string? text)
    {
        if (string.IsNullOrWhiteSpace(text))
        {
            return null;
        }

        var digits = new string(text.Where(char.IsDigit).ToArray());
        if (digits.Length == 0 || !int.TryParse(digits, out var slotId))
        {
            return null;
        }

        return slotId;
    }

    private static void GameControllerUpdatePostfix()
    {
        ApplyConfiguredMaxLoverCount("GameController.Update");
        EnsureDailySkillInsightBaseline();
        TryRunRealtimeSkillInsight();
        TryEvaluateCustomTalents();
        TryEvaluateThresholdTalent();
        TryUpdateBookWriterScaling("GameController.Update");
        UpdateTreasureChestChoiceSession();
        UpdateDialogFastForwardAssist();
        KeepPlayerHorseTurboReady("Update");
        ApplyPlayerCarryWeightOverride("Update");
        UpdateTreasureTradeUiState();
        TrySyncExternalOverlay();

        if (Input.GetKeyDown(_dialogFastForwardAssistHotkey.Value))
        {
            ToggleDialogFastForwardAssist("hotkey");
        }

        if (Input.GetKeyDown(_freezeDateHotkey.Value))
        {
            ToggleFreezeDate("hotkey");
        }

        if (Input.GetKeyDown(_outsideBattleSpeedHotkey.Value))
        {
            CycleOutsideBattleSpeed();
        }

        if (Input.GetKeyDown(ViewedHeroFavorTestHotkey))
        {
            GrantTeamIntelligenceMoneyTest();
            ApplyViewedHeroFavorTest();
        }

    }

    private static void TryUpdateBookWriterScaling(string source)
    {
        BookWriterUIController? writerUI;
        try
        {
            writerUI = BookWriterUIController.Instance;
        }
        catch
        {
            return;
        }

        if (writerUI == null)
        {
            return;
        }

        var writerList = writerUI.targetBookWriterList;
        if (writerList == null)
        {
            return;
        }

        var count = TryGetCollectionCount(writerList);
        if (count <= 0)
        {
            return;
        }

        var activeWriter = ResolveActiveBookWriterData(writerUI, writerList, count);
        if (activeWriter == null)
        {
            return;
        }

        if (!_bookWriterTaskScalingActive)
        {
            return;
        }

        if (!_bookWriterCountdownOverrideArmed || !ReferenceEquals(activeWriter, _bookWriterTaskData))
        {
            _bookWriterTaskData = activeWriter;
            _bookWriterCountdownOverrideArmed = true;
            _bookWriterTaskStartDate = _bookWriterTaskStartDate ?? TryGetWorldDateSnapshot();
        }

        var started = activeWriter.workStarted;
        var progress = activeWriter.workPercent;
        if (!started)
        {
            return;
        }

        var currentDate = TryGetWorldDateSnapshot();
        var startDate = _bookWriterTaskStartDate;
        if (startDate == null || currentDate == null)
        {
            return;
        }

        var elapsedDays = GetElapsedDayCount(startDate, currentDate);
        if (elapsedDays < _bookWriterTaskTargetDays)
        {
            return;
        }

        activeWriter.workPercent = 1f;

        ClearBookWriterTaskScaling($"{source}:completed");
    }

    private static void ClearBookWriterTaskScaling(string source)
    {
        if (!_bookWriterTaskScalingActive && !_bookWriterCountdownOverrideArmed && _bookWriterTaskData == null)
        {
            return;
        }

        _bookWriterTaskScalingActive = false;
        _bookWriterCountdownOverrideArmed = false;
        _bookWriterTaskStartDate = null;
        _bookWriterTaskTargetDays = 0;
        _bookWriterTaskData = null;
    }

    private static BookWriterData? ResolveActiveBookWriterData(BookWriterUIController writerUI, object writerList, int count)
    {
        var activeId = SafeProperty(writerUI, "activeID") ?? SafeField(writerUI, "activeID");
        var activeIndex = TryConvertToInt(activeId) ?? -1;

        if (activeIndex >= 0 && activeIndex < count)
        {
            return TryGetIndexedValue(writerList, activeIndex) as BookWriterData;
        }

        for (var i = 0; i < count; i++)
        {
            if (TryGetIndexedValue(writerList, i) is BookWriterData writerData && writerData.workStarted)
            {
                return writerData;
            }
        }

        for (var i = 0; i < count; i++)
        {
            if (TryGetIndexedValue(writerList, i) is BookWriterData writerData)
            {
                return writerData;
            }
        }

        return null;
    }

    private static void LoadAllGameDataPostfix()
    {
        LoadCustomTalentPackFromDisk();
        EnsureCustomTalentDefinitionsRegistered("LoadAllGameData");
        EnsureThresholdTalentRegistered("LoadAllGameData");
    }

    private static void LoadCustomTalentPackFromDisk()
    {
        _customTalents.Clear();

        var configPath = GetCustomTalentConfigPath();
        if (!File.Exists(configPath))
        {
            LoggerInstance.LogInfo($"Custom talent config not found at {configPath}. Starting with no JSON-driven custom talents.");
            return;
        }

        try
        {
            var text = File.ReadAllText(configPath);
            var pack = JsonSerializer.Deserialize<CustomTalentPackFile>(
                text,
                new JsonSerializerOptions
                {
                    PropertyNameCaseInsensitive = true
                });

            if (pack == null)
            {
                LoggerInstance.LogWarning($"Custom talent config was empty at {configPath}.");
                return;
            }

            if (pack.version != 1)
            {
                LoggerInstance.LogWarning($"Custom talent config version {pack.version} is unsupported. Expected version 1.");
                return;
            }

            if (pack.talents == null || pack.talents.Count == 0)
            {
                LoggerInstance.LogInfo("Custom talent config loaded successfully with 0 talents.");
                return;
            }

            var seenIds = new HashSet<string>(StringComparer.Ordinal);
            for (var i = 0; i < pack.talents.Count; i++)
            {
                var talentFile = pack.talents[i];
                if (!TryBuildRegisteredCustomTalent(talentFile, seenIds, out var registered, out var error))
                {
                    LoggerInstance.LogWarning($"Skipped custom talent entry #{i + 1}: {error}");
                    continue;
                }

                _customTalents.Add(registered);
            }

            LoggerInstance.LogInfo($"Loaded {_customTalents.Count} JSON-driven custom talents from {configPath}.");
        }
        catch (Exception ex)
        {
            LoggerInstance.LogWarning($"Failed to load custom talent config from {configPath}: {ex.Message}");
        }
    }

    private static string GetCustomTalentConfigPath()
    {
        return Path.Combine(Paths.ConfigPath, CustomTalentConfigFileName);
    }

    private static bool TryBuildRegisteredCustomTalent(
        CustomTalentDefinitionFile? talentFile,
        HashSet<string> seenIds,
        out RegisteredCustomTalent registered,
        out string error)
    {
        registered = null!;
        error = string.Empty;

        if (talentFile == null)
        {
            error = "entry was null";
            return false;
        }

        var id = talentFile.id?.Trim();
        if (string.IsNullOrWhiteSpace(id))
        {
            error = "missing id";
            return false;
        }

        if (!seenIds.Add(id))
        {
            error = $"duplicate id '{id}'";
            return false;
        }

        var name = talentFile.name?.Trim();
        if (string.IsNullOrWhiteSpace(name))
        {
            error = $"talent '{id}' is missing name";
            return false;
        }

        if (talentFile.conditions == null || talentFile.conditions.Count == 0)
        {
            error = $"talent '{id}' has no conditions";
            return false;
        }

        if (talentFile.effects == null || talentFile.effects.Count == 0)
        {
            error = $"talent '{id}' has no effects";
            return false;
        }

        var conditions = new List<RegisteredCustomTalentCondition>();
        for (var i = 0; i < talentFile.conditions.Count; i++)
        {
            var conditionFile = talentFile.conditions[i];
            if (conditionFile == null)
            {
                error = $"talent '{id}' has null condition #{i + 1}";
                return false;
            }

            CustomTalentConditionKind conditionKind;
            if (string.Equals(conditionFile.type, "stat_min", StringComparison.Ordinal))
            {
                conditionKind = CustomTalentConditionKind.PlayerStatMin;
            }
            else if (string.Equals(conditionFile.type, "team_stat_sum_min", StringComparison.Ordinal))
            {
                conditionKind = CustomTalentConditionKind.TeamStatSumMin;
            }
            else
            {
                error = $"talent '{id}' has unsupported condition type '{conditionFile.type}'";
                return false;
            }

            if (!Enum.TryParse(conditionFile.stat, ignoreCase: false, out BaseAttriType stat))
            {
                error = $"talent '{id}' has invalid stat '{conditionFile.stat}'";
                return false;
            }

            conditions.Add(
                new RegisteredCustomTalentCondition
                {
                    Kind = conditionKind,
                    Stat = stat,
                    Minimum = conditionFile.min
                });
        }

        var buffData = new HeroSpeAddData();
        for (var i = 0; i < talentFile.effects.Count; i++)
        {
            var effectFile = talentFile.effects[i];
            if (effectFile == null)
            {
                error = $"talent '{id}' has null effect #{i + 1}";
                return false;
            }

            if (!Enum.TryParse(effectFile.effectType, ignoreCase: false, out HeroSpeAddDataType effectType))
            {
                error = $"talent '{id}' has invalid effect type '{effectFile.effectType}'";
                return false;
            }

            buffData.Set(effectType, effectFile.value);
        }

        registered = new RegisteredCustomTalent
        {
            Id = id,
            Enabled = talentFile.enabled,
            Name = name,
            DurationDays = Math.Max(1, talentFile.durationDays),
            Marker = CustomTalentMarkerPrefix + id,
            BuffData = buffData,
            Conditions = conditions
        };
        return true;
    }

    private static bool EnsureCustomTalentDefinitionsRegistered(string source)
    {
        if (_customTalents.Count == 0)
        {
            return true;
        }

        var gameData = GameDataController.Instance;
        var database = gameData?.heroTagDataBase;
        if (gameData == null || database == null)
        {
            LoggerInstance.LogWarning($"Custom talent registration skipped from {source} because GameDataController or heroTagDataBase is unavailable.");
            return false;
        }

        foreach (var talent in _customTalents)
        {
            try
            {
                var existingId = FindTagIdByMarker(database, talent.Marker);
                if (existingId >= 0)
                {
                    talent.RuntimeTagId = existingId;
                    var existing = database[existingId];
                    if (existing != null)
                    {
                        ApplyCustomTalentDefinition(existing, talent, existingId);
                    }
                }
                else
                {
                    var customTag = new HeroTagDataBase();
                    var newId = database.Count;
                    ApplyCustomTalentDefinition(customTag, talent, newId);
                    database.Add(customTag);
                    talent.RuntimeTagId = newId;
                }
            }
            catch (Exception ex)
            {
                LoggerInstance.LogWarning($"Failed to register custom talent '{talent.Name}' ({talent.Id}) from {source}: {ex.Message}");
            }
        }

        return true;
    }

    private static int FindTagIdByMarker(Il2CppSystem.Collections.Generic.List<HeroTagDataBase> database, string marker)
    {
        if (database == null || string.IsNullOrWhiteSpace(marker))
        {
            return -1;
        }

        for (var i = 0; i < database.Count; i++)
        {
            try
            {
                var entry = database[i];
                if (entry != null &&
                    string.Equals(entry.category, CustomTalentCategory, StringComparison.Ordinal) &&
                    string.Equals(entry.sameMeaning, marker, StringComparison.Ordinal))
                {
                    return i;
                }
            }
            catch
            {
            }
        }

        return -1;
    }

    private static void ApplyCustomTalentDefinition(HeroTagDataBase tag, RegisteredCustomTalent talent, int order)
    {
        if (tag == null)
        {
            return;
        }

        tag.name = talent.Name;
        tag.value = 0;
        tag.effectTarget = SkillTargetType.Self;
        tag.sameMeaning = talent.Marker;
        tag.oppositeMeaning = string.Empty;
        tag.canRandom = false;
        tag.category = CustomTalentCategory;
        tag.showRightLine = true;
        tag.order = Math.Max(0, order);
        tag.requirement = new Il2CppSystem.Collections.Generic.List<string>();
        tag.replaceTag = new Il2CppSystem.Collections.Generic.List<string>();
        tag.buffData = talent.BuffData;
    }

    private static void TryEvaluateCustomTalents()
    {
        if (Time.realtimeSinceStartup < _nextCustomTalentEvaluationAt)
        {
            return;
        }

        _nextCustomTalentEvaluationAt = Time.realtimeSinceStartup + CustomTalentEvaluationIntervalSeconds;

        if (_customTalents.Count == 0)
        {
            return;
        }

        var player = TryGetPlayerHero();
        if (player == null)
        {
            return;
        }

        foreach (var talent in _customTalents)
        {
            if (talent.RuntimeTagId < 0)
            {
                continue;
            }

            var alreadyHasTag = CountCustomTalentInstances(player, talent) > 0;
            var shouldHaveTag = talent.Enabled && AreCustomTalentConditionsMet(player, talent);

            if (shouldHaveTag == alreadyHasTag)
            {
                continue;
            }

            if (shouldHaveTag)
            {
                GrantCustomTalent(player, talent);
            }
            else
            {
                RemoveCustomTalent(player, talent, talent.Enabled ? "conditions-failed" : "disabled");
            }
        }
    }

    private static bool AreCustomTalentConditionsMet(HeroData hero, RegisteredCustomTalent talent)
    {
        if (talent.Conditions.Count == 0)
        {
            return false;
        }

        foreach (var condition in talent.Conditions)
        {
            float? currentValue;
            switch (condition.Kind)
            {
                case CustomTalentConditionKind.TeamStatSumMin:
                    currentValue = TryReadTeamAttributeSum(hero, condition.Stat);
                    break;
                default:
                    currentValue = TryReadHeroAttribute(hero, condition.Stat);
                    break;
            }

            if (!currentValue.HasValue || currentValue.Value < condition.Minimum)
            {
                return false;
            }
        }

        return true;
    }

    private static float? TryReadTeamAttributeSum(HeroData player, BaseAttriType attriType)
    {
        var teamMembers = new List<HeroData> { player };
        teamMembers.AddRange(GetPlayerTeamMembers(player));

        var total = 0f;
        var foundAny = false;
        foreach (var member in teamMembers)
        {
            var currentValue = TryReadHeroAttribute(member, attriType);
            if (!currentValue.HasValue)
            {
                continue;
            }

            total += currentValue.Value;
            foundAny = true;
        }

        return foundAny ? total : null;
    }

    private static void GrantCustomTalent(HeroData hero, RegisteredCustomTalent talent)
    {
        try
        {
            if (CountCustomTalentInstances(hero, talent) > 0)
            {
                return;
            }

            var definition = TryGetCustomTalentDefinition(talent);
            if (definition == null)
            {
                LoggerInstance.LogWarning($"Could not grant custom talent {talent.Name} because its definition was unavailable.");
                return;
            }

            hero.AddTempTag(definition, talent.DurationDays, false);

            var appliedCount = CountCustomTalentInstances(hero, talent);
            if (appliedCount <= 0 && talent.RuntimeTagId >= 0)
            {
                hero.AddTag(talent.RuntimeTagId, talent.DurationDays, CustomTalentSource, false, true);
                appliedCount = CountCustomTalentInstances(hero, talent);
            }

            if (appliedCount <= 0)
            {
                LoggerInstance.LogWarning($"Custom talent {talent.Name} grant did not produce a visible hero tag entry for {TryGetHeroName(hero)}.");
                return;
            }

            LoggerInstance.LogInfo($"Custom talent granted to {TryGetHeroName(hero)}: {talent.Name} ({talent.Id}).");
            PushPlayerSideTabLog($"{talent.Name} 生效");
            TryRefreshHeroDetail(hero);
        }
        catch (Exception ex)
        {
            LoggerInstance.LogWarning($"Failed to grant custom talent {talent.Name} ({talent.Id}) to {TryGetHeroName(hero)}: {ex.Message}");
        }
    }

    private static void RemoveCustomTalent(HeroData hero, RegisteredCustomTalent talent, string reason)
    {
        try
        {
            var removedAny = false;
            for (var attempt = 0; attempt < 32; attempt++)
            {
                var tagId = TryGetFirstCustomTalentTagId(hero, talent);
                if (!tagId.HasValue)
                {
                    break;
                }

                hero.RemoveTag(tagId.Value, false);
                removedAny = true;
            }

            if (!removedAny)
            {
                return;
            }

            LoggerInstance.LogInfo($"Custom talent removed from {TryGetHeroName(hero)}: {talent.Name} ({talent.Id}), reason={reason}.");
            PushPlayerSideTabLog($"{talent.Name} 失效");
            TryRefreshHeroDetail(hero);
        }
        catch (Exception ex)
        {
            LoggerInstance.LogWarning($"Failed to remove custom talent {talent.Name} ({talent.Id}) from {TryGetHeroName(hero)}: {ex.Message}");
        }
    }

    private static HeroTagDataBase? TryGetCustomTalentDefinition(RegisteredCustomTalent talent)
    {
        try
        {
            var database = GameDataController.Instance?.heroTagDataBase;
            if (database == null)
            {
                return null;
            }

            if (talent.RuntimeTagId >= 0 && talent.RuntimeTagId < database.Count)
            {
                return database[talent.RuntimeTagId];
            }

            var existingId = FindTagIdByMarker(database, talent.Marker);
            if (existingId >= 0)
            {
                talent.RuntimeTagId = existingId;
                return database[existingId];
            }
        }
        catch
        {
        }

        return null;
    }

    private static int CountCustomTalentInstances(HeroData hero, RegisteredCustomTalent talent)
    {
        var count = 0;

        try
        {
            var tagData = hero.heroTagData;
            if (tagData == null)
            {
                return 0;
            }

            for (var i = 0; i < tagData.Count; i++)
            {
                if (MatchesCustomTalent(tagData[i], talent))
                {
                    count++;
                }
            }
        }
        catch
        {
        }

        return count;
    }

    private static int? TryGetFirstCustomTalentTagId(HeroData hero, RegisteredCustomTalent talent)
    {
        try
        {
            var tagData = hero.heroTagData;
            if (tagData == null)
            {
                return null;
            }

            for (var i = 0; i < tagData.Count; i++)
            {
                var tag = tagData[i];
                if (MatchesCustomTalent(tag, talent))
                {
                    return tag.tagID;
                }
            }
        }
        catch
        {
        }

        return null;
    }

    private static bool MatchesCustomTalent(HeroTagData? tag, RegisteredCustomTalent talent)
    {
        if (tag == null)
        {
            return false;
        }

        try
        {
            var dataBase = tag.DataBase();
            return dataBase != null &&
                string.Equals(dataBase.category, CustomTalentCategory, StringComparison.Ordinal) &&
                string.Equals(dataBase.sameMeaning, talent.Marker, StringComparison.Ordinal);
        }
        catch
        {
            return false;
        }
    }

    private static void TryEvaluateThresholdTalent()
    {
        if (Time.realtimeSinceStartup < _nextThresholdTalentEvaluationAt)
        {
            return;
        }

        _nextThresholdTalentEvaluationAt = Time.realtimeSinceStartup + ThresholdTalentEvaluationIntervalSeconds;

        var player = TryGetPlayerHero();
        if (player == null)
        {
            return;
        }

        if (!EnsureThresholdTalentRegistered("GameController.Update"))
        {
            return;
        }

        if (_thresholdTalentTagId < 0)
        {
            return;
        }

        RemoveLegacyThresholdTalentInstances(player);

        var alreadyHasTag = CountThresholdTalentInstances(player) > 0;
        if (!_thresholdTalentEnabled.Value)
        {
            if (alreadyHasTag)
            {
                RemoveThresholdTalent(player, "feature-disabled");
            }

            return;
        }

        var currentValue = TryReadHeroAttribute(player, _thresholdTalentRequirementAttribute.Value);
        if (!currentValue.HasValue)
        {
            return;
        }

        var meetsThreshold = currentValue.Value >= _thresholdTalentRequirementValue.Value;
        if (meetsThreshold == alreadyHasTag)
        {
            return;
        }

        if (meetsThreshold)
        {
            GrantThresholdTalent(player, currentValue.Value);
        }
        else
        {
            RemoveThresholdTalent(player, "threshold-lost");
        }
    }

    private static bool EnsureThresholdTalentRegistered(string source)
    {
        _thresholdTalentTagName = GetConfiguredThresholdTalentName();

        var gameData = GameDataController.Instance;
        var database = gameData?.heroTagDataBase;
        if (gameData == null || database == null)
        {
            if (!_thresholdTalentRegistrationWarned && _thresholdTalentEnabled.Value)
            {
                LoggerInstance.LogWarning($"Threshold talent registration skipped from {source} because GameDataController or heroTagDataBase is unavailable.");
                _thresholdTalentRegistrationWarned = true;
            }

            return false;
        }

        _thresholdTalentRegistrationWarned = false;

        var existingId = FindThresholdTagId(database);
        if (existingId >= 0)
        {
            _thresholdTalentTagId = existingId;

            try
            {
                var existing = database[existingId];
                if (existing != null)
                {
                    ApplyThresholdTalentDefinition(existing, existingId);
                }
            }
            catch (Exception ex)
            {
                LoggerInstance.LogWarning($"Threshold talent definition refresh failed for existing tag {_thresholdTalentTagName} (id={existingId}): {ex.Message}");
            }

            return true;
        }

        try
        {
            var customTag = new HeroTagDataBase();
            var newId = database.Count;
            ApplyThresholdTalentDefinition(customTag, newId);
            database.Add(customTag);
            _thresholdTalentTagId = newId;
            LoggerInstance.LogInfo(
                $"Registered threshold talent '{_thresholdTalentTagName}' with runtime id={_thresholdTalentTagId}, " +
                $"buff={_thresholdTalentBuffType.Value}:{SafeFormatValue(_thresholdTalentBuffValue.Value)}, " +
                $"requirement={_thresholdTalentRequirementAttribute.Value}>={SafeFormatValue(_thresholdTalentRequirementValue.Value)}.");
            return true;
        }
        catch (Exception ex)
        {
            LoggerInstance.LogWarning($"Failed to register threshold talent '{_thresholdTalentTagName}' from {source}: {ex.Message}");
            return false;
        }
    }

    private static void ApplyThresholdTalentDefinition(HeroTagDataBase tag, int order)
    {
        if (tag == null)
        {
            return;
        }

        tag.name = _thresholdTalentTagName;
        tag.value = 0;
        tag.effectTarget = SkillTargetType.Self;
        tag.sameMeaning = ThresholdTalentMarker;
        tag.oppositeMeaning = string.Empty;
        tag.canRandom = false;
        tag.category = ThresholdTalentCategory;
        tag.showRightLine = true;
        tag.order = Math.Max(0, order);
        tag.requirement = new Il2CppSystem.Collections.Generic.List<string>();
        tag.replaceTag = new Il2CppSystem.Collections.Generic.List<string>();

        var buffData = new HeroSpeAddData();
        buffData.Set(_thresholdTalentBuffType.Value, _thresholdTalentBuffValue.Value);
        tag.buffData = buffData;
    }

    private static int FindThresholdTagId(Il2CppSystem.Collections.Generic.List<HeroTagDataBase> database)
    {
        if (database == null)
        {
            return -1;
        }

        for (var i = 0; i < database.Count; i++)
        {
            try
            {
                var entry = database[i];
                if (MatchesThresholdTalentDefinition(entry))
                {
                    return i;
                }
            }
            catch
            {
            }
        }

        return -1;
    }

    private static void GrantThresholdTalent(HeroData hero, float currentValue)
    {
        try
        {
            if (CountThresholdTalentInstances(hero) > 0)
            {
                return;
            }

            var definition = TryGetThresholdTalentDefinition();
            if (definition == null)
            {
                LoggerInstance.LogWarning($"Could not grant threshold talent {_thresholdTalentTagName} because its definition was unavailable.");
                return;
            }

            hero.AddTempTag(
                definition,
                ResolveThresholdTalentDurationDays(),
                _thresholdTalentShowInfo.Value);

            var appliedCount = CountThresholdTalentInstances(hero);
            if (appliedCount <= 0 && _thresholdTalentTagId >= 0)
            {
                hero.AddTag(
                    _thresholdTalentTagId,
                    Mathf.Max(1f, _thresholdTalentDuration.Value),
                    ThresholdTalentSource,
                    _thresholdTalentShowInfo.Value,
                    true);
                appliedCount = CountThresholdTalentInstances(hero);
            }

            if (appliedCount <= 0)
            {
                LoggerInstance.LogWarning($"Threshold talent {_thresholdTalentTagName} grant did not produce a visible hero tag entry for {TryGetHeroName(hero)}.");
                return;
            }

            LoggerInstance.LogInfo(
                $"Threshold talent granted to {TryGetHeroName(hero)}: " +
                $"tag={_thresholdTalentTagName} (id={_thresholdTalentTagId}), " +
                $"current={SafeFormatValue(currentValue)}, requirement={_thresholdTalentRequirementAttribute.Value}>={SafeFormatValue(_thresholdTalentRequirementValue.Value)}.");
            PushPlayerSideTabLog($"{_thresholdTalentTagName} 生效");
            TryRefreshHeroDetail(hero);
        }
        catch (Exception ex)
        {
            LoggerInstance.LogWarning($"Failed to grant threshold talent {_thresholdTalentTagName} to {TryGetHeroName(hero)}: {ex.Message}");
        }
    }

    private static void RemoveThresholdTalent(HeroData hero, string reason)
    {
        try
        {
            var removedAny = false;
            for (var attempt = 0; attempt < 32; attempt++)
            {
                var tagId = TryGetFirstThresholdTalentTagId(hero);
                if (!tagId.HasValue)
                {
                    break;
                }

                hero.RemoveTag(tagId.Value, _thresholdTalentShowInfo.Value);
                removedAny = true;
            }

            if (!removedAny)
            {
                return;
            }

            LoggerInstance.LogInfo(
                $"Threshold talent removed from {TryGetHeroName(hero)}: " +
                $"tag={_thresholdTalentTagName} (id={_thresholdTalentTagId}), reason={reason}.");
            PushPlayerSideTabLog($"{_thresholdTalentTagName} 失效");
            TryRefreshHeroDetail(hero);
        }
        catch (Exception ex)
        {
            LoggerInstance.LogWarning($"Failed to remove threshold talent {_thresholdTalentTagName} from {TryGetHeroName(hero)}: {ex.Message}");
        }
    }

    private static void TryRefreshHeroDetail(HeroData hero)
    {
        try
        {
            hero.RefreshMaxAttriAndSkill();
        }
        catch
        {
        }

        try
        {
            hero.CheckHeroDetailDirty(true);
        }
        catch
        {
        }
    }

    private static HeroTagDataBase? TryGetThresholdTalentDefinition()
    {
        try
        {
            var gameData = GameDataController.Instance;
            var database = gameData?.heroTagDataBase;
            if (database == null)
            {
                return null;
            }

            if (_thresholdTalentTagId >= 0 && _thresholdTalentTagId < database.Count)
            {
                return database[_thresholdTalentTagId];
            }

            var existingId = FindThresholdTagId(database);
            if (existingId >= 0)
            {
                _thresholdTalentTagId = existingId;
                return database[existingId];
            }
        }
        catch
        {
        }

        return null;
    }

    private static int ResolveThresholdTalentDurationDays()
    {
        return Math.Max(1, Mathf.RoundToInt(_thresholdTalentDuration.Value));
    }

    private static int CountThresholdTalentInstances(HeroData hero)
    {
        var count = 0;

        try
        {
            var tagData = hero.heroTagData;
            if (tagData == null)
            {
                return 0;
            }

            for (var i = 0; i < tagData.Count; i++)
            {
                if (MatchesThresholdTalent(tagData[i]))
                {
                    count++;
                }
            }
        }
        catch
        {
        }

        return count;
    }

    private static int? TryGetFirstThresholdTalentTagId(HeroData hero)
    {
        try
        {
            var tagData = hero.heroTagData;
            if (tagData == null)
            {
                return null;
            }

            for (var i = 0; i < tagData.Count; i++)
            {
                var tag = tagData[i];
                if (MatchesThresholdTalent(tag))
                {
                    return tag.tagID;
                }
            }
        }
        catch
        {
        }

        return null;
    }

    private static bool MatchesThresholdTalent(HeroTagData? tag)
    {
        return MatchesCurrentThresholdTalent(tag);
    }

    private static bool MatchesCurrentThresholdTalent(HeroTagData? tag)
    {
        if (tag == null)
        {
            return false;
        }

        try
        {
            var dataBase = tag.DataBase();
            return dataBase != null &&
                string.Equals(dataBase.sameMeaning, ThresholdTalentMarker, StringComparison.Ordinal) &&
                string.Equals(dataBase.category, ThresholdTalentCategory, StringComparison.Ordinal);
        }
        catch
        {
            return false;
        }
    }

    private static bool MatchesAnyThresholdTalent(HeroTagData? tag)
    {
        if (tag == null)
        {
            return false;
        }

        try
        {
            return MatchesThresholdTalentDefinition(tag.DataBase());
        }
        catch
        {
            return false;
        }
    }

    private static bool MatchesThresholdTalentDefinition(HeroTagDataBase? dataBase)
    {
        return dataBase != null &&
            (string.Equals(dataBase.sameMeaning, ThresholdTalentMarker, StringComparison.Ordinal) ||
             string.Equals(dataBase.category, ThresholdTalentCategory, StringComparison.Ordinal));
    }

    private static void RemoveLegacyThresholdTalentInstances(HeroData hero)
    {
        try
        {
            var removedAny = false;
            for (var attempt = 0; attempt < 32; attempt++)
            {
                var tagData = hero.heroTagData;
                if (tagData == null)
                {
                    break;
                }

                int? staleTagId = null;
                for (var i = 0; i < tagData.Count; i++)
                {
                    var tag = tagData[i];
                    if (MatchesAnyThresholdTalent(tag) && !MatchesCurrentThresholdTalent(tag))
                    {
                        staleTagId = tag.tagID;
                        break;
                    }
                }

                if (!staleTagId.HasValue)
                {
                    break;
                }

                hero.RemoveTag(staleTagId.Value, false);
                removedAny = true;
            }

            if (removedAny)
            {
                LoggerInstance.LogInfo($"Removed stale threshold talent instances from {TryGetHeroName(hero)}.");
                TryRefreshHeroDetail(hero);
            }
        }
        catch (Exception ex)
        {
            LoggerInstance.LogWarning($"Failed to remove stale threshold talents from {TryGetHeroName(hero)}: {ex.Message}");
        }
    }

    private static string GetConfiguredThresholdTalentName()
    {
        var configured = _thresholdTalentName.Value?.Trim();
        if (string.IsNullOrWhiteSpace(configured))
        {
            return DefaultThresholdTalentName;
        }

        if (configured.Contains('�'))
        {
            return DefaultThresholdTalentName;
        }

        for (var i = 0; i < configured.Length; i++)
        {
            if (char.IsControl(configured[i]))
            {
                return DefaultThresholdTalentName;
            }
        }

        return configured;
    }

    private static void DialogHeroContextPostfix(HeroData __0)
    {
        CacheActiveDialogHero(__0);
    }

    private static void HeroDetailViewedHeroPostfix(HeroData __0)
    {
        CacheActiveHeroDetailHero(__0);
    }

    private static void HeroDetailHiddenPostfix()
    {
        CacheActiveHeroDetailHero(null);
    }

    private static void GlobalDataMaxLoverNumPostfix(ref int __result)
    {
        ApplyConfiguredMaxLoverCount("GlobalData.get_MaxLoverNum");
        var configured = Math.Max(1, _maxLoverCount.Value);
        if (__result < configured)
        {
            __result = configured;
        }
    }

    private static void MeetLoverResultRequirePostfix(ref bool __result)
    {
        ApplyConfiguredMaxLoverCount("GameController.MeetLoverResultRequire");
        if (__result)
        {
            return;
        }

        var player = TryGetPlayerHero();
        if (player == null)
        {
            return;
        }

        var configured = Math.Max(1, _maxLoverCount.Value);
        var currentCount = GetPlayerLoverCount(player);
        if (currentCount < configured)
        {
            __result = true;
            LoggerInstance.LogInfo($"Lover limit override allowed romance result: current={currentCount}, configuredMax={configured}.");
        }
    }

    private static void MaxLoverCountSyncPrefix()
    {
        ApplyConfiguredMaxLoverCount("lover-flow");
    }

    private static void LoverBattlePlotStartPrefix(PlotController __instance)
    {
        var player = TryGetPlayerHero();
        var loverCount = player == null ? -1 : GetPlayerLoverCount(player);
        if (player != null && _blockOverflowLoverHomeBattle.Value)
        {
            LoggerInstance.LogWarning(
                $"Lover home battle detected at PlotStartLoverResultFight: loverCount={loverCount}. Battle prep will be bypassed when PrepareBattleMap runs.");
        }

        if (!IsLoverBattlePrepTraceEnabled())
        {
            return;
        }

        LoggerInstance.LogInfo(
            $"[TRACE][LoverBattle] PlotStartLoverResultFight: " +
            $"player={DescribeHeroForLoverBattleTrace(player)}, loverCount={loverCount}, " +
            $"playerList={DescribeHeroListForLoverBattleTrace(SafeGetMemberValue(__instance, "playerList"))}, " +
            $"playerSupportList={DescribeHeroListForLoverBattleTrace(SafeGetMemberValue(__instance, "playerSupportList"))}, " +
            $"enemyList={DescribeHeroListForLoverBattleTrace(SafeGetMemberValue(__instance, "enemyList"))}, " +
            $"enemySupportList={DescribeHeroListForLoverBattleTrace(SafeGetMemberValue(__instance, "enemySupportList"))}.");
    }

    private static void LoverBattlePlotResultPrefix(string winTeamID)
    {
        if (!ShouldTraceLoverBattlePrepare(nameof(PlotController.PlotStartLoverResultFightResult)))
        {
            return;
        }

        LoggerInstance.LogInfo($"[TRACE][LoverBattle] PlotStartLoverResultFightResult: winTeamID={SafeFormatValue(winTeamID)}.");
    }

    private static bool LoverBattlePrepareBattleMapDirectPrefix(
        BattleController __instance,
        Il2CppSystem.Collections.Generic.List<HeroData>? __1,
        Il2CppSystem.Collections.Generic.List<HeroData>? __2,
        Il2CppSystem.Collections.Generic.List<HeroData>? __3,
        Il2CppSystem.Collections.Generic.List<HeroData>? __4,
        string? __6,
        int __10)
    {
        if (TryBypassOverflowLoverHomeBattle(__instance, __6, "PrepareBattleMap-direct"))
        {
            return false;
        }

        if (!ShouldTraceLoverBattlePrepare(__6))
        {
            return true;
        }

        LoggerInstance.LogInfo(
            $"[TRACE][LoverBattle] PrepareBattleMap-direct: " +
            $"fightEndCall={SafeFormatValue(__6)}, maxHeroNum={__10}, " +
            $"player={DescribeHeroListForLoverBattleTrace(__1)}, playerSupport={DescribeHeroListForLoverBattleTrace(__2)}, " +
            $"enemy={DescribeHeroListForLoverBattleTrace(__3)}, enemySupport={DescribeHeroListForLoverBattleTrace(__4)}, " +
            $"battleState={DescribeBattleControllerForLoverBattleTrace(__instance)}.");
        return true;
    }

    private static bool LoverBattlePrepareBattleMapGroupedPrefix(
        BattleController __instance,
        Il2CppSystem.Collections.Generic.List<Il2CppSystem.Collections.Generic.List<HeroData>>? __1,
        Il2CppSystem.Collections.Generic.List<Il2CppSystem.Collections.Generic.List<HeroData>>? __2,
        string? __4,
        int __7)
    {
        if (TryBypassOverflowLoverHomeBattle(__instance, __4, "PrepareBattleMap-grouped"))
        {
            return false;
        }

        if (!ShouldTraceLoverBattlePrepare(__4))
        {
            return true;
        }

        LoggerInstance.LogInfo(
            $"[TRACE][LoverBattle] PrepareBattleMap-grouped: " +
            $"fightEndCall={SafeFormatValue(__4)}, maxHeroNum={__7}, " +
            $"fightMemData={DescribeHeroGroupListForLoverBattleTrace(__1)}, " +
            $"fightSupportData={DescribeHeroGroupListForLoverBattleTrace(__2)}, " +
            $"battleState={DescribeBattleControllerForLoverBattleTrace(__instance)}.");
        return true;
    }

    private static void LoverBattleTeamPreparePrefix(BattleController __instance)
    {
        CaptureOrRestorePreferredBattleTimeScale("BattleTeamPrepare");

        if (!ShouldTraceLoverBattlePrepare(TryReadStringMember(__instance, new[] { "fightEndCallFuc" })))
        {
            return;
        }

        LoggerInstance.LogInfo(
            $"[TRACE][LoverBattle] BattleTeamPrepare: {DescribeBattleControllerForLoverBattleTrace(__instance)}, " +
            $"teamMemPrepareData={DescribeTeamPrepareDataForLoverBattleTrace(SafeGetMemberValue(__instance, "teamMemPrepareData"))}, " +
            $"teamSupportPrepareData={DescribeTeamPrepareDataForLoverBattleTrace(SafeGetMemberValue(__instance, "teamSupportPrepareData"))}.");
    }

    private static void CheckChoiceMeetRequirePostfix(ref bool __result)
    {
        ApplyConfiguredMaxLoverCount("PlotController.CheckChoiceMeetRequire");
        if (__result)
        {
            return;
        }

        var choice = PlotController.Instance?.newChoice ?? PlotController.Instance?.nowChoice;
        if (!IsLoverChoice(choice))
        {
            return;
        }

        var player = TryGetPlayerHero();
        if (player == null)
        {
            return;
        }

        var configured = Math.Max(1, _maxLoverCount.Value);
        var currentCount = GetPlayerLoverCount(player);
        if (currentCount < configured)
        {
            __result = true;
            TrySanitizeLoverChoiceDescribe(choice);
            LoggerInstance.LogInfo($"Lover choice meet requirement override allowed romance choice: current={currentCount}, configuredMax={configured}.");
        }
    }

    private static void DialogChoiceRowPostfix(PlotInteractController __instance)
    {
        if (__instance?.choiceData == null)
        {
            return;
        }

        ApplyDialogMonthlyQuota(__instance, __instance.choiceData, consume: false);
        TryOverrideLoverChoiceAvailability(__instance, __instance.choiceData, sanitizeDescribe: true);
    }

    private static bool DialogChoiceClickPrefix(PlotInteractController __instance)
    {
        if (__instance?.choiceData == null)
        {
            return true;
        }

        ApplyDialogMonthlyQuota(__instance, __instance.choiceData, consume: true);
        TryOverrideLoverChoiceAvailability(__instance, __instance.choiceData, sanitizeDescribe: true);
        if (TryHandleTreasureChestChoiceClick(__instance.choiceData))
        {
            return false;
        }

        return true;
    }

    private static void DialogFastForwardShowPlotPostfix(PlotController __instance)
    {
        TraceDialogFastForwardEvent("ShowPlot", __instance);
    }

    private static void DialogFastForwardShowSinglePlotPostfix(PlotController __instance)
    {
        TraceDialogFastForwardEvent("ShowSinglePlot", __instance);
    }

    private static void DialogFastForwardPlotTextShowFinishedPostfix(PlotController __instance)
    {
        TraceDialogFastForwardEvent("PlotTextShowFinished", __instance);
    }

    private static void DialogFastForwardPlotChoiceShowFinishedPostfix(PlotController __instance)
    {
        TraceDialogFastForwardEvent("PlotChoiceShowFinished", __instance);
    }

    private static void DialogFastForwardSkipPlotButtonClickedPostfix(PlotController __instance)
    {
        TraceDialogFastForwardEvent("SkipPlotButtonClicked", __instance);
    }

    private static void DialogFastForwardSetSkipPlotPostfix(PlotController __instance, bool _skip)
    {
        TraceDialogFastForwardEvent("SetSkipPlot", __instance, $"requestedSkip={_skip}");
    }

    private static void CacheActiveDialogHero(HeroData? hero)
    {
        _activeDialogHero = hero;
        _activeDialogHeroId = TryGetHeroId(hero) ?? -1;
    }

    private static void CacheActiveHeroDetailHero(HeroData? hero)
    {
        _activeHeroDetailHero = hero;
        _activeHeroDetailHeroId = TryGetHeroId(hero) ?? -1;
    }

    private static HeroData? TryGetViewedHeroDetailHero()
    {
        try
        {
            var heroDetailController = HeroDetailController.Instance;
            if (heroDetailController != null)
            {
                foreach (var memberName in new[] { "nowShowHero", "targetHero", "mainShowHero", "nowChooseHero" })
                {
                    var hero = SafeProperty(heroDetailController, memberName) as HeroData
                               ?? SafeField(heroDetailController, memberName) as HeroData;
                    if (hero != null)
                    {
                        CacheActiveHeroDetailHero(hero);
                        return hero;
                    }
                }

                if (heroDetailController.gameObject != null && heroDetailController.gameObject.activeInHierarchy)
                {
                    var playerHero = TryGetPlayerHero();
                    if (playerHero != null)
                    {
                        CacheActiveHeroDetailHero(playerHero);
                        return playerHero;
                    }
                }
            }
        }
        catch
        {
        }

        if (_activeHeroDetailHero != null)
        {
            return _activeHeroDetailHero;
        }

        if (_activeHeroDetailHeroId > 0)
        {
            try
            {
                return GameController.Instance?.worldData?.GetHero(_activeHeroDetailHeroId);
            }
            catch
            {
            }
        }

        return null;
    }

    private static float? TryReadFame(HeroData? hero)
    {
        if (hero == null)
        {
            return null;
        }

        foreach (var memberName in new[] { "fame", "Fame", "hornor", "Hornor" })
        {
            var value = SafeProperty(hero, memberName) ?? SafeField(hero, memberName);
            var floatValue = TryConvertToFloat(value);
            if (floatValue.HasValue)
            {
                return floatValue.Value;
            }
        }

        return null;
    }

    private static int? TryReadHeroForceLv(HeroData? hero)
    {
        if (hero == null)
        {
            return null;
        }

        var value = SafeProperty(hero, "heroForceLv") ?? SafeField(hero, "heroForceLv");
        return TryConvertToInt(value);
    }

    private static bool IsSectlessHero(HeroData? hero)
    {
        if (hero == null)
        {
            return false;
        }

        try
        {
            if (hero.GetForce(false) == null)
            {
                return true;
            }
        }
        catch
        {
        }

        var belongForceId = TryConvertToInt(SafeProperty(hero, "belongForceID") ?? SafeField(hero, "belongForceID"));
        if (belongForceId.GetValueOrDefault() <= 0)
        {
            return true;
        }

        var outsideForce = TryConvertToBool(SafeProperty(hero, "outsideForce") ?? SafeField(hero, "outsideForce"));
        return outsideForce == true;
    }

    private static bool TryPromoteSectlessHeroForceLvFromFame(HeroData hero, int? beforeForceLv, out int? targetForceLv)
    {
        targetForceLv = beforeForceLv;
        if (hero == null || !beforeForceLv.HasValue || !IsSectlessHero(hero))
        {
            return false;
        }

        float computedForceLv;
        try
        {
            computedForceLv = hero.GetFameForceLv();
        }
        catch
        {
            return false;
        }

        var desiredForceLv = Mathf.Max(beforeForceLv.Value, Mathf.FloorToInt(computedForceLv + 0.001f));
        if (desiredForceLv <= beforeForceLv.Value)
        {
            return false;
        }

        try
        {
            hero.ChangeHeroForceLv(desiredForceLv - beforeForceLv.Value, false);
        }
        catch
        {
            try
            {
                hero.SetHeroForceLv(desiredForceLv);
            }
            catch
            {
                return false;
            }
        }

        targetForceLv = TryReadHeroForceLv(hero) ?? desiredForceLv;
        return targetForceLv.Value > beforeForceLv.Value;
    }

    private static bool TryHandleTreasureChestChoiceClick(SinglePlotChoiceData choice)
    {
        var choiceParam = TryGetChoiceParam(choice);
        if (string.IsNullOrWhiteSpace(choiceParam) ||
            !choiceParam.StartsWith(TreasureChestChoiceParamPrefix, StringComparison.Ordinal))
        {
            return false;
        }

        TryResolveTreasureChestChoiceFromPlot(choiceParam);

        var plotController = PlotController.Instance;
        if (plotController != null)
        {
            TryCloseTreasureChestChoicePlot(plotController);
        }

        return true;
    }

    private static void ApplyDialogMonthlyQuota(PlotInteractController controller, SinglePlotChoiceData choice, bool consume)
    {
        var timeNeedValue = SafeGetMemberValue(choice, "playerInteractionTimeNeed");
        var timeNeed = SafeFormatValue(timeNeedValue);
        if (string.IsNullOrEmpty(timeNeed) || string.Equals(timeNeed, "None", StringComparison.Ordinal))
        {
            return;
        }

        var heroId = _activeDialogHeroId;
        if (heroId < 0)
        {
            return;
        }

        var monthKey = GetCurrentWorldMonthKey();
        var key = $"{monthKey}|hero={heroId}|type={timeNeed}";
        var used = _dialogMonthlyUseCounts.TryGetValue(key, out var currentUsed) ? currentUsed : 0;
        var limit = GetDialogMonthlyLimit(heroId, timeNeed);
        var allowed = used < limit;

        if (consume && allowed)
        {
            used++;
            _dialogMonthlyUseCounts[key] = used;
        }

        SyncVanillaDialogMonthlyUsage(choice, timeNeedValue, Math.Max(0, limit - used));
        controller.meetCost = allowed;
    }

    private static void TryOverrideLoverChoiceAvailability(PlotInteractController controller, SinglePlotChoiceData choice, bool sanitizeDescribe)
    {
        if (!IsLoverChoice(choice))
        {
            return;
        }

        var player = TryGetPlayerHero();
        if (player == null)
        {
            return;
        }

        var configured = Math.Max(1, _maxLoverCount.Value);
        var currentCount = GetPlayerLoverCount(player);
        if (currentCount >= configured)
        {
            return;
        }

        controller.meetRequire = true;
        if (sanitizeDescribe)
        {
            TrySanitizeLoverChoiceDescribe(choice);
        }
    }

    private static bool IsLoverChoice(SinglePlotChoiceData? choice)
    {
        if (choice == null)
        {
            return false;
        }

        var choiceText = TryReadStringMember(choice, new[] { "choiceText" });
        if (!string.IsNullOrWhiteSpace(choiceText) &&
            choiceText.Contains(LoverChoiceTextKeyword, StringComparison.Ordinal))
        {
            return true;
        }

        var callFuc = TryReadStringMember(choice, new[] { "callFuc" });
        if (!string.IsNullOrWhiteSpace(callFuc) &&
            callFuc.IndexOf("Lover", StringComparison.OrdinalIgnoreCase) >= 0)
        {
            return true;
        }

        var callParam = TryReadStringMember(choice, new[] { "callParam" });
        if (!string.IsNullOrWhiteSpace(callParam) &&
            callParam.IndexOf("Lover", StringComparison.OrdinalIgnoreCase) >= 0)
        {
            return true;
        }

        var describe = TryReadStringMember(choice, new[] { "describe" });
        return !string.IsNullOrWhiteSpace(describe) &&
               describe.Contains(LoverLimitReachedText, StringComparison.Ordinal);
    }

    private static void TrySanitizeLoverChoiceDescribe(SinglePlotChoiceData choice)
    {
        var describe = TryReadStringMember(choice, new[] { "describe" });
        if (string.IsNullOrWhiteSpace(describe) ||
            !describe.Contains(LoverLimitReachedText, StringComparison.Ordinal))
        {
            return;
        }

        var sanitized = describe.Replace(LoverLimitReachedText + "!", string.Empty, StringComparison.Ordinal)
                                .Replace(LoverLimitReachedText, string.Empty, StringComparison.Ordinal)
                                .Replace("，，", "，", StringComparison.Ordinal)
                                .Trim();

        sanitized = sanitized.TrimEnd('，', ',', ' ', '\t');
        TrySetMemberValue(choice, "describe", sanitized);
    }

    private static int GetDialogMonthlyLimit(int heroId, string timeNeed)
    {
        var multiplier = _dialogMonthlyLimitMultiplier.Value;
        if (multiplier <= 0f)
        {
            return 0;
        }

        var scaled = (int)Math.Ceiling(multiplier);
        return Math.Max(1, scaled);
    }

    private static string GetCurrentWorldMonthKey()
    {
        try
        {
            var worldData = GameController.Instance?.worldData;
            var worldTime = SafeGetMemberValue(worldData, "worldTime");
            if (worldTime == null)
            {
                return "unknown-month";
            }

            var year = SafeGetMemberValue(worldTime, "year");
            var month = SafeGetMemberValue(worldTime, "month");
            return $"{SafeFormatValue(year)}-{SafeFormatValue(month)}";
        }
        catch
        {
            return "unknown-month";
        }
    }

    private static void SyncVanillaDialogMonthlyUsage(SinglePlotChoiceData choice, object? timeNeedValue, int remaining)
    {
        var playerInteractionTimeData = SafeGetMemberValue(_activeDialogHero, "playerInteractionTimeData");
        if (playerInteractionTimeData == null || timeNeedValue == null)
        {
            return;
        }

        var list = SafeGetMemberValue(playerInteractionTimeData, "playerInteractTimeList");
        if (list == null)
        {
            return;
        }

        var timeNeedName = SafeFormatValue(timeNeedValue);
        if (string.IsNullOrEmpty(timeNeedName) || string.Equals(timeNeedName, "None", StringComparison.Ordinal))
        {
            return;
        }

        if (!Enum.TryParse(timeNeedName, out PlayerInteractionTimeType parsedType))
        {
            return;
        }

        TrySetIndexedValue(list, (int)parsedType, Math.Max(0, remaining));
    }

    private static void UpdateDialogFastForwardAssist()
    {
        var plotController = PlotController.Instance;
        if (plotController == null)
        {
            _dialogFastForwardAssistOwnsSkip = false;
            return;
        }

        var shouldEnableSkip = _dialogFastForwardAssistEnabled.Value && IsDialogFastForwardCurrentlyAvailable(plotController);
        var isCurrentlySkipping = plotController.plotSkipping;
        TraceDialogFastForwardEvent(
            "AssistUpdate",
            plotController,
            $"assistEnabled={_dialogFastForwardAssistEnabled.Value}, shouldEnable={shouldEnableSkip}, ownsSkip={_dialogFastForwardAssistOwnsSkip}, isCurrentlySkipping={isCurrentlySkipping}");

        if (shouldEnableSkip)
        {
            if (!isCurrentlySkipping)
            {
                TriggerDialogFastForward(plotController, enable: true);
                _dialogFastForwardAssistOwnsSkip = true;
            }

            return;
        }

        if (_dialogFastForwardAssistOwnsSkip && isCurrentlySkipping)
        {
            TriggerDialogFastForward(plotController, enable: false);
        }

        _dialogFastForwardAssistOwnsSkip = false;
    }

    private static void TriggerDialogFastForward(PlotController plotController, bool enable)
    {
        try
        {
            var skipButton = plotController.plotSkipButton;
            var canUseButtonPath = skipButton != null && skipButton.activeInHierarchy;
            TraceDialogFastForwardEvent(
                "AssistTrigger",
                plotController,
                $"enable={enable}, canUseButtonPath={canUseButtonPath}, currentSkipping={plotController.plotSkipping}");
            if (enable && canUseButtonPath)
            {
                plotController.SkipPlotButtonClicked();
                return;
            }
        }
        catch (Exception ex)
        {
            LoggerInstance.LogWarning($"Dialog fast-forward assist button path failed: {ex.Message}");
        }

        plotController.SetSkipPlot(enable);
    }

    private static bool IsDialogFastForwardTraceEnabled()
    {
        return _traceMode.Value && _traceDialogFastForward.Value;
    }

    private static bool IsDialogFastForwardCurrentlyAvailable(PlotController plotController)
    {
        try
        {
            var skipButton = plotController.plotSkipButton;
            return skipButton != null && skipButton.activeInHierarchy;
        }
        catch (Exception ex)
        {
            LoggerInstance.LogWarning($"Dialog fast-forward assist availability check failed: {ex.Message}");
            return false;
        }
    }

    private static void ToggleDialogFastForwardAssist(string source)
    {
        _dialogFastForwardAssistEnabled.Value = !_dialogFastForwardAssistEnabled.Value;
        if (!_dialogFastForwardAssistEnabled.Value)
        {
            UpdateDialogFastForwardAssist();
        }

        TraceDialogFastForwardEvent(
            "AssistToggle",
            PlotController.Instance,
            $"source={source}, enabled={_dialogFastForwardAssistEnabled.Value}, ownsSkip={_dialogFastForwardAssistOwnsSkip}");
        LoggerInstance.LogInfo($"Dialog fast-forward assist {(_dialogFastForwardAssistEnabled.Value ? "enabled" : "disabled")} from {source}.");
        PushPlayerLog($"Mod: 快进辅助 {(_dialogFastForwardAssistEnabled.Value ? "ON" : "OFF")}");
    }

    private static void ToggleFreezeDate(string source)
    {
        _freezeDate.Value = !_freezeDate.Value;
        LoggerInstance.LogInfo($"Freeze Date {(_freezeDate.Value ? "enabled" : "disabled")} from {source} at {GetWorldDateText(includeHour: true)}.");
        PushPlayerLog($"Mod: Freeze Date {(_freezeDate.Value ? "ON" : "OFF")}");
    }

    private static void CycleOutsideBattleSpeed()
    {
        var worldData = GameController.Instance?.worldData;
        if (worldData == null)
        {
            LoggerInstance.LogWarning("Outside-battle speed hotkey ignored because world data is unavailable.");
            return;
        }

        if (IsBattleUiActive())
        {
            LoggerInstance.LogInfo("Outside-battle speed hotkey ignored because battle UI is active.");
            PushPlayerLog("Mod: Outside battle speed only works outside battle");
            return;
        }

        var current = worldData.battleTimeScale;
        var next = GetNextOutsideBattleSpeed(current);
        worldData.battleTimeScale = next;

        LoggerInstance.LogInfo($"Outside-battle speed changed from x{current:0.###} to x{next:0.###}.");
        PushPlayerLog($"Mod: Outside battle speed x{next:0.###}");
    }

    private static void GrantTeamIntelligenceMoneyTest()
    {
        var player = TryGetPlayerHero();
        if (player == null)
        {
            LoggerInstance.LogWarning("Team intelligence money test hotkey ignored because the player hero is unavailable.");
            PushPlayerLog("Mod测试: 当前无法找到玩家角色");
            return;
        }

        var teamMembers = new List<HeroData> { player };
        teamMembers.AddRange(GetPlayerTeamMembers(player));

        var totalIntelligence = 0;
        var contributors = 0;
        var preview = new List<string>();
        foreach (var member in teamMembers)
        {
            var intelligence = TryReadHeroAttribute(member, BaseAttriType.Inte);
            if (!intelligence.HasValue)
            {
                continue;
            }

            var roundedIntelligence = Mathf.Max(0, Mathf.RoundToInt(intelligence.Value));
            totalIntelligence += roundedIntelligence;
            contributors++;

            if (preview.Count < 6)
            {
                preview.Add($"{TryGetHeroName(member)}:{roundedIntelligence}");
            }
        }

        if (contributors <= 0 || totalIntelligence <= 0)
        {
            LoggerInstance.LogWarning("Team intelligence money test hotkey found no readable intelligence values.");
            PushPlayerLog("Mod测试: 当前队伍无法读取智慧属性");
            return;
        }

        try
        {
            _applyingLuckyMoneyRefund = true;
            player.ChangeMoney(totalIntelligence, true);
        }
        finally
        {
            _applyingLuckyMoneyRefund = false;
        }

        LoggerInstance.LogInfo(
            $"Team intelligence money test granted {totalIntelligence} money from {contributors} contributors: {string.Join(", ", preview)}.");
        PushPlayerLog($"Mod测试: 队伍智慧总和 {totalIntelligence}，获得 {totalIntelligence} 文钱");
    }

    private static void ApplyViewedHeroFavorTest()
    {
        var viewedHero = TryGetViewedHeroDetailHero();
        if (viewedHero == null)
        {
            return;
        }

        var heroId = TryGetHeroId(viewedHero);
        var beforeValue = TryReadFame(viewedHero);
        var beforeForceLv = TryReadHeroForceLv(viewedHero);
        string? beforeForceLvText = null;
        try
        {
            beforeForceLvText = viewedHero.GetHeroForceLvDescribeSimplify();
        }
        catch
        {
        }

        if (!beforeValue.HasValue)
        {
            LoggerInstance.LogWarning($"Viewed hero reputation test hotkey could not read fame for {TryGetHeroName(viewedHero)}.");
            PushPlayerLog($"Mod测试: 无法读取当前角色 {TryGetHeroName(viewedHero)} 的声望");
            return;
        }

        var reputationDelta = Random.Next(200, 601);

        try
        {
            viewedHero.ChangeFame(reputationDelta, false);
            viewedHero.CheckHeroFameForceLv();
        }
        catch (Exception ex)
        {
            LoggerInstance.LogWarning($"Viewed hero fame test hotkey failed for {TryGetHeroName(viewedHero)}: {ex.Message}");
            PushPlayerLog($"Mod测试: 修改 {TryGetHeroName(viewedHero)} 的声望失败");
            return;
        }

        var sectlessTierPromotionApplied = TryPromoteSectlessHeroForceLvFromFame(viewedHero, beforeForceLv, out _);

        try
        {
            var heroDetailController = HeroDetailController.Instance;
            if (heroDetailController != null)
            {
                heroDetailController.FreshNowHeroDetail(viewedHero, false);
            }
        }
        catch
        {
        }

        var afterValue = TryReadFame(viewedHero);
        var afterForceLv = TryReadHeroForceLv(viewedHero);
        string? afterForceLvText = null;
        try
        {
            afterForceLvText = viewedHero.GetHeroForceLvDescribeSimplify();
        }
        catch
        {
        }

        if (!afterValue.HasValue)
        {
            afterValue = beforeValue.Value + reputationDelta;
        }

        var appliedDelta = afterValue.Value - beforeValue.Value;
        var appliedDeltaText = appliedDelta >= 0f
            ? $"+{SafeFormatValue(appliedDelta)}"
            : SafeFormatValue(appliedDelta);
        var tierChanged = afterForceLv.HasValue && beforeForceLv.HasValue && afterForceLv.Value != beforeForceLv.Value;
        var tierSummary = $"tier {SafeFormatValue(beforeForceLv)} {SafeFormatValue(beforeForceLvText)} -> {SafeFormatValue(afterForceLv)} {SafeFormatValue(afterForceLvText)}";

        LoggerInstance.LogInfo(
            $"Viewed hero reputation test applied to {TryGetHeroName(viewedHero)} (id={SafeFormatValue(heroId)}): " +
            $"kind=fame, before={SafeFormatValue(beforeValue.Value)}, requestedDelta={reputationDelta}, after={SafeFormatValue(afterValue.Value)}, appliedDelta={SafeFormatValue(appliedDelta)}, {tierSummary}, tierChanged={tierChanged}, sectlessPromotionApplied={sectlessTierPromotionApplied}.");
        PushPlayerLog(
            $"Mod测试: 当前查看角色 {TryGetHeroName(viewedHero)}(ID {SafeFormatValue(heroId)}) 声望 {SafeFormatValue(beforeValue.Value)} -> {SafeFormatValue(afterValue.Value)} ({appliedDeltaText})，{tierSummary}");
    }

    private static void PushPlayerLog(string text)
    {
        var delivered = false;
        var deliveredChannels = new List<string>();

        try
        {
            var infoController = InfoController.Instance;
            if (infoController != null)
            {
                infoController.AddInfo(InfoType.WorldInfo, text);
                infoController.AddInfo(InfoType.PersonalInfo, text);
                infoController.BuildInfoList();
                delivered = true;
                deliveredChannels.Add("InfoController");
            }
        }
        catch (Exception ex)
        {
            LoggerInstance.LogWarning($"Player log via InfoController failed: {ex.Message}");
        }

        try
        {
            var gameController = GameController.Instance;
            if (gameController != null)
            {
                gameController.ShowTextOnMouse(text, 28, Color.yellow);
                delivered = true;
                deliveredChannels.Add("ShowTextOnMouse");
            }
        }
        catch (Exception ex)
        {
            LoggerInstance.LogWarning($"Player log via ShowTextOnMouse failed: {ex.Message}");
        }

        try
        {
            var player = TryGetPlayerHero();
            if (player != null)
            {
                player.AddLog(text);
                delivered = true;
                deliveredChannels.Add("HeroData");
            }
        }
        catch (Exception ex)
        {
            LoggerInstance.LogWarning($"Player log via HeroData failed: {ex.Message}");
        }

        try
        {
            var areaController = AreaController.Instance;
            var areaData = areaController?.areaData;
            if (areaController != null && areaData != null)
            {
                areaData.AddLog(text);
                areaData.areaInfoDirty = true;
                var areaLog = areaController.areaLog;
                if (areaLog != null)
                {
                    areaLog.text = areaData.GetRecordLog();
                }

                areaController.FreshAreaInfo(true);
                delivered = true;
                deliveredChannels.Add("AreaData");
            }
        }
        catch (Exception ex)
        {
            LoggerInstance.LogWarning($"Player log via AreaData failed: {ex.Message}");
        }

        if (!delivered)
        {
            LoggerInstance.LogWarning($"PLAYER LOG SKIPPED: {text}");
            return;
        }

        if (_traceMode.Value)
        {
            LoggerInstance.LogInfo($"PLAYER LOG DELIVERED via {string.Join(", ", deliveredChannels)}: {text}");
        }
    }

    private static void PushPlayerSideTabLog(string text)
    {
        var delivered = false;

        try
        {
            var infoController = InfoController.Instance;
            if (infoController != null)
            {
                infoController.AddInfoTab(
                    text,
                    TeachSkillSideTabAtlasName,
                    TeachSkillSideTabIconName,
                    TeachSkillSideTabSoundName,
                    TeachSkillSideTabSoundVolume,
                    TeachSkillSideTabDurationSeconds,
                    Color.clear);
                delivered = true;
            }
        }
        catch (Exception ex)
        {
            LoggerInstance.LogWarning($"Player side-tab log failed: {ex.Message}");
        }

        if (_traceMode.Value)
        {
            LoggerInstance.LogInfo($"{(delivered ? "PLAYER SIDE TAB DELIVERED" : "PLAYER SIDE TAB SKIPPED")}: {text}");
        }
    }

    private static string DescribeMethod(MethodBase method)
    {
        return $"{method.DeclaringType?.Name}.{method.Name}";
    }

    private static int ClampPercent(int value)
    {
        return Mathf.Clamp(value, 0, 100);
    }

    private static void RememberCraftSelection(ItemData? craftResult)
    {
        if (craftResult == null)
        {
            _pendingCraftSelection = null;
            return;
        }

        _pendingCraftSelection = new CraftRewardSelection
        {
            ResultItemId = craftResult.itemID,
            ResultItemLv = craftResult.itemLv,
            ResultRareLv = craftResult.rareLv,
            ResultName = craftResult.name ?? $"id={craftResult.itemID}"
        };

        if (_traceMode.Value)
        {
            LoggerInstance.LogInfo($"Craft result selected: {DescribeItemSummary(craftResult)}.");
        }
    }

    private static void ActivateCraftRewardBonus(string source)
    {
        _activeCraftRewardBonus = null;

        if (!_craftRandomPickUpgradeEnabled.Value)
        {
            return;
        }

        var bonusState = ResolveCraftRewardBonusState();
        if (bonusState == null)
        {
            if (_traceMode.Value)
            {
                LoggerInstance.LogInfo($"Craft quantity bonus skipped from {source}: no eligible added crafting material bonus was found.");
            }

            return;
        }

        _activeCraftRewardBonus = bonusState;

        var controller = CraftUIController.Instance;

        LogCraftEvent(
            $"armed from {source}: material={bonusState.MaterialName}, majorTier={bonusState.MaterialMajorTier}, extraItems={bonusState.ExtraItemCount}, primary={DescribeItemSummary(controller?.craftMaterialData)}, secondary={DescribeItemSummary(controller?.craftMaterialDataSub)}");
    }

    private static CraftRewardBonusState? ResolveCraftRewardBonusState()
    {
        return ResolveCraftRewardBonusState(CraftUIController.Instance);
    }

    private static CraftRewardBonusState? ResolveCraftRewardBonusState(CraftUIController? controller)
    {
        var addedMaterial = ResolveCraftAddedMaterial(controller);
        if (addedMaterial == null)
        {
            return null;
        }

        var extraItemCount = GetCraftExtraItemCountFromMaterial(addedMaterial);
        if (extraItemCount <= 0)
        {
            return null;
        }

        return new CraftRewardBonusState
        {
            MaterialName = addedMaterial.name ?? $"id={addedMaterial.itemID}",
            MaterialMajorTier = GetCraftMajorTier(addedMaterial),
            ExtraItemCount = extraItemCount
        };
    }

    private static string DescribeItemSummary(ItemData? item)
    {
        if (item == null)
        {
            return "null";
        }

        return $"{item.name} (id={item.itemID}, itemLv={item.itemLv}, rare={item.rareLv}, value={item.value}, type={SafeFormatValue(TryGetItemTypeName(item))})";
    }

    private static ItemData? ResolveCraftAddedMaterial(CraftUIController? controller)
    {
        if (controller == null)
        {
            return null;
        }

        var primary = controller.craftMaterialData;
        var secondary = controller.craftMaterialDataSub;
        var primaryRate = TryGetCraftMaterialExtraRate(primary);
        var secondaryRate = TryGetCraftMaterialExtraRate(secondary);

        if (secondary != null && secondaryRate > primaryRate)
        {
            return secondary;
        }

        if (primary != null && primaryRate > 0f)
        {
            return primary;
        }

        return secondary ?? primary;
    }

    private static ItemData? ResolveCraftResultByIndex(CraftUIController? controller, int index)
    {
        if (controller == null || index < 0)
        {
            return null;
        }

        var craftResultList = SafeProperty(controller, "craftResultList") ?? SafeField(controller, "craftResultList");
        if (craftResultList == null)
        {
            return null;
        }

        return TryGetIndexedValue(craftResultList, index) as ItemData;
    }

    private static int GetCraftExtraItemCountFromMaterial(ItemData? material)
    {
        return GetCraftConfiguredExtraItems(GetCraftMajorTier(material));
    }

    private static int GetCraftConfiguredExtraItems(int majorTier)
    {
        return majorTier switch
        {
            1 => Math.Max(0, _craftTier1ExtraItems.Value),
            2 => Math.Max(0, _craftTier2ExtraItems.Value),
            3 => Math.Max(0, _craftTier3ExtraItems.Value),
            4 => Math.Max(0, _craftTier4ExtraItems.Value),
            5 => Math.Max(0, _craftTier5ExtraItems.Value),
            _ => 0
        };
    }

    private static float TryGetCraftMaterialExtraRate(ItemData? material)
    {
        if (material == null)
        {
            return 0f;
        }

        try
        {
            return Mathf.Max(0f, material.GetMaterialExtraCraftRate());
        }
        catch
        {
            return 0f;
        }
    }

    private static void TryGrantCraftBonusItems(HeroData? targetHero, ItemData? itemData, int treasureChestClickTime, bool skipManageItemPoison)
    {
        var bonusState = _activeCraftRewardBonus;
        if (bonusState == null || bonusState.ExtraItemCount <= 0)
        {
            return;
        }

        LogCraftEvent(
            $"HeroData.GetItem observed item={DescribeItemSummary(itemData)}, chestClick={treasureChestClickTime}, activeBonus={bonusState.ExtraItemCount}, consumed={bonusState.Consumed}, hero={TryGetHeroName(targetHero)}");

        if (!_craftRandomPickUpgradeEnabled.Value || bonusState.Consumed || itemData == null || _grantingCraftBonusItems)
        {
            return;
        }

        var player = TryGetPlayerHero();
        if (player == null || targetHero == null || !ReferenceEquals(player, targetHero))
        {
            return;
        }

        if (treasureChestClickTime > 0)
        {
            return;
        }

        var grantedCount = 0;
        bonusState.Consumed = true;
        _grantingCraftBonusItems = true;

        try
        {
            for (var i = 0; i < bonusState.ExtraItemCount; i++)
            {
                var bonusItem = TryCreateCraftBonusItem(itemData, targetHero);
                if (bonusItem == null)
                {
                    continue;
                }

                targetHero.GetItem(bonusItem, false, false, 0, skipManageItemPoison);
                grantedCount++;
            }
        }
        catch (Exception ex)
        {
            LoggerInstance.LogWarning($"Failed to grant crafted bonus items from HeroData.GetItem: {ex.Message}");
        }
        finally
        {
            _grantingCraftBonusItems = false;
            _activeCraftRewardBonus = null;
            _pendingCraftSelection = null;
        }

        if (grantedCount <= 0)
        {
            LogCraftEvent($"HeroData.GetItem bonus grant produced no extra items for {DescribeItemSummary(itemData)}");
            return;
        }

        PushPlayerLog($"【巧手增产】：加入【{bonusState.MaterialName}】后，额外获得 {grantedCount} 个【{itemData.name ?? $"id={itemData.itemID}"}】");
        LogCraftEvent(
            $"HeroData.GetItem granted {grantedCount}x item={DescribeItemSummary(itemData)} using material={bonusState.MaterialName}, majorTier={bonusState.MaterialMajorTier}");
    }

    private static void TryRepeatCraftPlotItemReward(PlotController? plotController, PlotItemGrantState? state)
    {
        if (!_craftRandomPickUpgradeEnabled.Value)
        {
            return;
        }

        var bonusState = _activeCraftRewardBonus;
        var item = state?.ItemBefore;
        LogCraftEvent(
            $"{state?.Source ?? "PlotItem"} postfix itemBefore={DescribeItemSummary(item)}, itemAfter={DescribeItemSummary(plotController?.plotInteractItem)}, activeBonus={(bonusState == null ? "none" : bonusState.ExtraItemCount.ToString())}, consumed={SafeFormatValue(bonusState?.Consumed)}");

        if (bonusState == null || bonusState.ExtraItemCount <= 0 || bonusState.Consumed || item == null || _grantingCraftBonusItems)
        {
            return;
        }

        var player = TryGetPlayerHero();
        if (player == null)
        {
            LogCraftEvent("repeat skipped: player unavailable");
            return;
        }

        var grantedCount = 0;
        bonusState.Consumed = true;
        _grantingCraftBonusItems = true;

        try
        {
            for (var i = 0; i < bonusState.ExtraItemCount; i++)
            {
                var bonusItem = TryCreateCraftBonusItem(item, player);
                if (bonusItem == null)
                {
                    continue;
                }

                player.GetItem(bonusItem, false);
                grantedCount++;
            }
        }
        catch (Exception ex)
        {
            LoggerInstance.LogWarning($"Failed to repeat crafted plot item reward: {ex.Message}");
        }
        finally
        {
            _grantingCraftBonusItems = false;
            _activeCraftRewardBonus = null;
            _pendingCraftSelection = null;
        }

        if (grantedCount <= 0)
        {
            LogCraftEvent($"repeat finished with no cloned rewards for {DescribeItemSummary(item)}");
            return;
        }

        PushPlayerLog($"【巧手增产】：加入【{bonusState.MaterialName}】后，额外获得 {grantedCount} 个【{item.name ?? $"id={item.itemID}"}】");
        LogCraftEvent(
            $"repeat granted {grantedCount}x item={DescribeItemSummary(item)} using material={bonusState.MaterialName}, majorTier={bonusState.MaterialMajorTier}");
    }

    private static void LogCraftEvent(string message)
    {
        LoggerInstance.LogInfo($"[CraftTrace] {message}");
    }

    private static ItemData? TryCreateCraftBonusItem(ItemData? sourceItem, HeroData? targetHero)
    {
        if (sourceItem == null)
        {
            return null;
        }

        if (IsEquipmentItem(sourceItem))
        {
            var rerolled = TryGenerateDistinctCraftEquipment(sourceItem, targetHero);
            if (rerolled != null)
            {
                return rerolled;
            }
        }

        return TryCloneItem(sourceItem) ?? sourceItem;
    }

    private static ItemData? TryGenerateDistinctCraftEquipment(ItemData sourceItem, HeroData? targetHero)
    {
        var gameController = GameController.Instance;
        if (gameController == null || targetHero == null)
        {
            return null;
        }

        var controller = CraftUIController.Instance;
        var targetItemType = (int)sourceItem.type;
        var targetSubType = sourceItem.subType;
        var targetLittleType = sourceItem.equipmentData?.littleType ?? 0;
        var targetItemLv = sourceItem.itemLv;
        var targetWeaponType = controller?.targetWeaponType ?? 0;
        var bossLv = Mathf.Max(1f, controller?.targetBuilding?.lv ?? Math.Max(1, sourceItem.itemLv + 1));
        var baseValue = Math.Max(1, sourceItem.value);
        var valueMultipliers = new[] { 1f, 1.08f, 1.2f, 1.35f, 1.55f, 1.8f, 2.1f, 2.5f, 3f };
        ItemData? bestFamilyMatch = null;

        foreach (var multiplier in valueMultipliers)
        {
            var targetValue = Mathf.Max(baseValue, Mathf.RoundToInt(baseValue * multiplier));
            ItemData? candidate = null;

            try
            {
                candidate = gameController.GenerateRandomItemValue(
                    targetValue,
                    targetItemType,
                    bossLv,
                    targetSubType,
                    targetLittleType,
                    targetHero,
                    targetWeaponType);
            }
            catch (Exception ex)
            {
                if (_traceMode.Value)
                {
                    LoggerInstance.LogWarning($"Craft bonus reroll failed at value {targetValue}: {ex.Message}");
                }

                continue;
            }

            if (candidate == null)
            {
                continue;
            }

            if (!IsCompatibleCraftBonusCandidate(sourceItem, candidate))
            {
                if (_traceMode.Value)
                {
                    LoggerInstance.LogInfo(
                        $"Craft bonus reroll rejected candidate {DescribeItemSummary(candidate)} for source {DescribeItemSummary(sourceItem)}.");
                }

                continue;
            }

            if (bestFamilyMatch == null)
            {
                bestFamilyMatch = candidate;
            }

            if (IsPreferredCraftBonusCandidate(sourceItem, candidate, bestFamilyMatch))
            {
                bestFamilyMatch = candidate;
            }

            if (IsExactCraftBonusCandidate(sourceItem, candidate))
            {
                if (_traceMode.Value)
                {
                    LoggerInstance.LogInfo(
                        $"Craft bonus reroll exact match: source={DescribeItemSummary(sourceItem)}, generated={DescribeItemSummary(candidate)}.");
                }

                return candidate;
            }
        }

        if (_traceMode.Value && bestFamilyMatch != null)
        {
            LoggerInstance.LogInfo(
                $"Craft bonus reroll family match fallback: source={DescribeItemSummary(sourceItem)}, generated={DescribeItemSummary(bestFamilyMatch)}.");
        }

        return bestFamilyMatch;
    }

    private static bool IsCompatibleCraftBonusCandidate(ItemData sourceItem, ItemData candidate)
    {
        if (sourceItem.type != candidate.type || sourceItem.subType != candidate.subType || sourceItem.itemLv != candidate.itemLv)
        {
            return false;
        }

        return (sourceItem.equipmentData?.littleType ?? 0) == (candidate.equipmentData?.littleType ?? 0);
    }

    private static bool IsExactCraftBonusCandidate(ItemData sourceItem, ItemData candidate)
    {
        if (!IsCompatibleCraftBonusCandidate(sourceItem, candidate))
        {
            return false;
        }

        if (sourceItem.itemID > 0 && candidate.itemID > 0)
        {
            return sourceItem.itemID == candidate.itemID;
        }

        return string.Equals(sourceItem.name, candidate.name, StringComparison.Ordinal);
    }

    private static bool IsPreferredCraftBonusCandidate(ItemData sourceItem, ItemData candidate, ItemData currentBest)
    {
        if (!IsCompatibleCraftBonusCandidate(sourceItem, candidate))
        {
            return false;
        }

        if (IsExactCraftBonusCandidate(sourceItem, candidate))
        {
            return !IsExactCraftBonusCandidate(sourceItem, currentBest) ||
                   candidate.rareLv >= currentBest.rareLv ||
                   candidate.value >= currentBest.value;
        }

        if (IsExactCraftBonusCandidate(sourceItem, currentBest))
        {
            return false;
        }

        if (candidate.rareLv != currentBest.rareLv)
        {
            return candidate.rareLv > currentBest.rareLv;
        }

        return candidate.value > currentBest.value;
    }

    private static ItemData? TryCloneItem(ItemData? item)
    {
        if (item == null)
        {
            return null;
        }

        try
        {
            return item.Clone() as ItemData;
        }
        catch
        {
            return null;
        }
    }

    private static bool IsEquipmentItem(ItemData? item)
    {
        if (item == null)
        {
            return false;
        }

        try
        {
            if (item.type == ItemType.Equip)
            {
                return true;
            }
        }
        catch
        {
        }

        return string.Equals(TryGetItemTypeName(item), nameof(ItemType.Equip), StringComparison.OrdinalIgnoreCase);
    }

    private static void ResetCraftRewardTracking(string source)
    {
        if (_traceMode.Value && (_pendingCraftSelection != null || _activeCraftRewardBonus != null))
        {
            LoggerInstance.LogInfo($"Craft reward tracking reset from {source}.");
        }

        _pendingCraftSelection = null;
        _activeCraftRewardBonus = null;
    }

    private static string DescribeItemSummaries(IEnumerable<ItemData> items)
    {
        if (items == null)
        {
            return "none";
        }

        var parts = new List<string>();
        foreach (var item in items)
        {
            parts.Add(DescribeItemSummary(item));
        }

        return parts.Count > 0 ? string.Join(" || ", parts) : "none";
    }

    private static bool IsTreasureChestTraceEnabled()
    {
        return _traceMode.Value && _traceTreasureChestEvents.Value;
    }

    private static bool ShouldSkipTreasureChestChoiceForOriginalReward(ItemData? item)
    {
        if (item == null)
        {
            return false;
        }

        try
        {
            if (item.type == ItemType.Book)
            {
                return true;
            }
        }
        catch
        {
        }

        var itemTypeName = TryGetItemTypeName(item);
        if (string.Equals(itemTypeName, nameof(ItemType.Book), StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }

        var itemName = item.name;
        return !string.IsNullOrWhiteSpace(itemName) &&
               (itemName.Contains("秘籍", StringComparison.Ordinal) ||
                itemName.Contains("秘笈", StringComparison.Ordinal) ||
                itemName.Contains("功法", StringComparison.Ordinal));
    }

    private static string? TryGetItemTypeName(ItemData? item)
    {
        if (item == null)
        {
            return null;
        }

        try
        {
            return Enum.GetName(typeof(ItemType), item.type) ?? item.type.ToString();
        }
        catch
        {
        }

        return SafeGetMemberValue(item, "type")?.ToString();
    }

    private static void TraceTreasureChestEvent(string stage, HeroData? targetHero, ItemData? itemData, int treasureChestClickTime, bool? skipManageItemPoison, string? extra = null)
    {
        if (!IsTreasureChestTraceEnabled())
        {
            return;
        }

        var player = TryGetPlayerHero();
        var plotController = PlotController.Instance;
        var session = _activeTreasureChestChoiceSession;
        var sessionSummary = session == null
            ? "inactive"
            : $"active(resolved={session.Resolved}, options={session.Options.Count}, pending={session.PendingClickConfirm}, lastChoice={SafeFormatValue(session.LastObservedChoiceParam)})";
        var plotSummary = plotController == null
            ? "plot=unavailable"
            : $"plotChoiceNow={SafeFormatValue(TryGetChoiceParam(plotController.nowChoice))}, plotChoiceNew={SafeFormatValue(TryGetChoiceParam(plotController.newChoice))}, plotText={SafeFormatValue(TryReadPlotText(plotController))}";

        LoggerInstance.LogInfo(
            $"[TRACE][TreasureChest] {stage}: " +
            $"target={TryGetHeroName(targetHero)}/{SafeFormatValue(TryGetHeroId(targetHero))}, " +
            $"player={TryGetHeroName(player)}/{SafeFormatValue(TryGetHeroId(player))}, " +
            $"item={DescribeItemSummary(itemData)}, chestClick={treasureChestClickTime}, " +
            $"skipManageItemPoison={SafeFormatValue(skipManageItemPoison)}, session={sessionSummary}, {plotSummary}" +
            $"{(string.IsNullOrWhiteSpace(extra) ? string.Empty : $", {extra}")}");
    }

    private static void TraceDialogFastForwardEvent(string stage, PlotController? plotController, string? extra = null)
    {
        if (!IsDialogFastForwardTraceEnabled())
        {
            return;
        }

        var summary = plotController == null
            ? "plot=unavailable"
            : $"skipButtonActive={SafeFormatValue(plotController.plotSkipButton != null && plotController.plotSkipButton.activeInHierarchy)}, " +
              $"plotSkipping={SafeFormatValue(plotController.plotSkipping)}, plotChoiceShowing={SafeFormatValue(plotController.plotChoiceShowing)}, " +
              $"choiceNow={SafeFormatValue(TryGetChoiceParam(plotController.nowChoice))}, choiceNew={SafeFormatValue(TryGetChoiceParam(plotController.newChoice))}, " +
              $"plotText={SafeFormatValue(TryReadPlotText(plotController))}";

        LoggerInstance.LogInfo(
            $"[TRACE][DialogFastForward] {stage}: {summary}" +
            $"{(string.IsNullOrWhiteSpace(extra) ? string.Empty : $", {extra}")}");
    }

    private static bool IsLoverBattlePrepTraceEnabled()
    {
        return _traceMode.Value && _traceLoverBattlePrep.Value;
    }

    private static bool ShouldTraceLoverBattlePrepare(string? fightEndCall)
    {
        return IsLoverBattlePrepTraceEnabled() &&
               string.Equals(fightEndCall, nameof(PlotController.PlotStartLoverResultFightResult), StringComparison.Ordinal);
    }

    private static bool TryBypassOverflowLoverHomeBattle(BattleController? controller, string? fightEndCall, string source)
    {
        if (!_blockOverflowLoverHomeBattle.Value ||
            !string.Equals(fightEndCall, nameof(PlotController.PlotStartLoverResultFightResult), StringComparison.Ordinal))
        {
            return false;
        }

        var player = TryGetPlayerHero();
        if (player == null)
        {
            return false;
        }

        var loverCount = GetPlayerLoverCount(player);

        var plotController = PlotController.Instance;
        if (plotController == null)
        {
            LoggerInstance.LogWarning(
                $"Overflow lover home battle bypass could not resolve because PlotController.Instance is unavailable from {source}. loverCount={loverCount}.");
            return false;
        }

        var playerTeamId = 0;
        try
        {
            if (controller != null)
            {
                playerTeamId = controller.GetPlayerControlTeamID();
            }
        }
        catch
        {
        }

        var winTeamId = playerTeamId.ToString();
        try
        {
            LoggerInstance.LogWarning(
                $"Blocked lover home battle from {source}: loverCount={loverCount}, syntheticWinTeamID={winTeamId}.");
            PushPlayerLog("Mod: 已拦截回家情缘围攻事件");
            plotController.PlotStartLoverResultFightResult(winTeamId);
            return true;
        }
        catch (Exception ex)
        {
            LoggerInstance.LogWarning(
                $"Lover home battle bypass failed from {source}: loverCount={loverCount}, syntheticWinTeamID={winTeamId}, error={ex.Message}.");
            return false;
        }
    }

    private static string DescribeBattleControllerForLoverBattleTrace(BattleController? controller)
    {
        if (controller == null)
        {
            return "battle=unavailable";
        }

        var maxHeroNum = TryConvertToInt(SafeGetMemberValue(controller, "maxHeroNum"));
        var fightEndCall = TryReadStringMember(controller, new[] { "fightEndCallFuc" });
        return
            $"fightEndCall={SafeFormatValue(fightEndCall)}, " +
            $"maxHeroNum={SafeFormatValue(maxHeroNum)}, " +
            $"teamMemJoinBattleNum={DescribeSimpleCollectionForLoverBattleTrace(SafeGetMemberValue(controller, "teamMemJoinBattleNum"))}";
    }

    private static string DescribeHeroGroupListForLoverBattleTrace(object? groups)
    {
        if (groups == null)
        {
            return "null";
        }

        if (groups is not System.Collections.IEnumerable enumerable)
        {
            return SafeFormatValue(groups);
        }

        var parts = new List<string>();
        var index = 0;
        foreach (var group in enumerable)
        {
            parts.Add($"{index}:{DescribeHeroListForLoverBattleTrace(group)}");
            index++;
        }

        var count = TryGetCollectionCount(groups);
        return $"count={(count >= 0 ? count : index)}, groups=[{string.Join(" || ", parts)}]";
    }

    private static string DescribeHeroListForLoverBattleTrace(object? heroes)
    {
        if (heroes == null)
        {
            return "null";
        }

        if (heroes is not System.Collections.IEnumerable enumerable)
        {
            return SafeFormatValue(heroes);
        }

        var parts = new List<string>();
        var index = 0;
        foreach (var entry in enumerable)
        {
            parts.Add($"{index}:{DescribeHeroForLoverBattleTrace(entry as HeroData)}");
            index++;
        }

        var count = TryGetCollectionCount(heroes);
        return $"count={(count >= 0 ? count : index)}, heroes=[{string.Join(" || ", parts)}]";
    }

    private static string DescribeTeamPrepareDataForLoverBattleTrace(object? prepareData)
    {
        if (prepareData == null)
        {
            return "null";
        }

        if (prepareData is not System.Collections.IEnumerable enumerable)
        {
            return SafeFormatValue(prepareData);
        }

        var parts = new List<string>();
        var index = 0;
        foreach (var entry in enumerable)
        {
            var hero = SafeGetMemberValue(entry, "heroData") as HeroData;
            var teamId = TryConvertToInt(SafeGetMemberValue(entry, "teamID"));
            var enterBattle = TryConvertToBool(SafeGetMemberValue(entry, "enterBattle"));
            var enterBattleTime = TryConvertToFloat(SafeGetMemberValue(entry, "enterBattleTime"));
            parts.Add(
                $"{index}:team={SafeFormatValue(teamId)}, enter={SafeFormatValue(enterBattle)}, " +
                $"enterTime={SafeFormatValue(enterBattleTime)}, hero={DescribeHeroForLoverBattleTrace(hero)}");
            index++;
        }

        var count = TryGetCollectionCount(prepareData);
        return $"count={(count >= 0 ? count : index)}, entries=[{string.Join(" || ", parts)}]";
    }

    private static string DescribeSimpleCollectionForLoverBattleTrace(object? value)
    {
        if (value == null)
        {
            return "null";
        }

        if (value is not System.Collections.IEnumerable enumerable || value is string)
        {
            return SafeFormatValue(value);
        }

        var parts = new List<string>();
        foreach (var entry in enumerable)
        {
            parts.Add(SafeFormatValue(entry));
        }

        var count = TryGetCollectionCount(value);
        return $"count={(count >= 0 ? count : parts.Count)}, values=[{string.Join(", ", parts)}]";
    }

    private static string DescribeHeroForLoverBattleTrace(HeroData? hero)
    {
        if (hero == null)
        {
            return "null";
        }

        var dead = TryConvertToBool(SafeGetMemberValue(hero, "dead"));
        var lover = TryConvertToBool(SafeGetMemberValue(hero, "Lover"));
        var preLovers = SafeGetMemberValue(hero, "PreLovers");
        var preLoverCount = TryGetCollectionCount(preLovers);
        var teamLeader = TryConvertToInt(SafeGetMemberValue(hero, "teamLeader"));

        return
            $"{TryGetHeroName(hero)}/{SafeFormatValue(TryGetHeroId(hero))}" +
            $"(inTeam={SafeFormatValue(TryIsHeroInTeam(hero))}, recruit={SafeFormatValue(TryIsHeroRecruitedByPlayer(hero))}, " +
            $"dead={SafeFormatValue(dead)}, lover={SafeFormatValue(lover)}, preLovers={SafeFormatValue(preLoverCount >= 0 ? preLoverCount : null)}, " +
            $"teamLeader={SafeFormatValue(teamLeader)})";
    }

    private static string? TryReadPlotText(PlotController? plotController)
    {
        if (plotController == null)
        {
            return null;
        }

        var directText = TryReadStringMember(plotController, new[] { "plotText", "PlotText" });
        if (!string.IsNullOrWhiteSpace(directText))
        {
            return directText;
        }

        foreach (var memberName in new[] { "nowPlot", "newPlot", "plotData", "nowPlotData", "showPlotData" })
        {
            var plotData = SafeGetMemberValue(plotController, memberName);
            var plotText = TryReadStringMember(plotData, new[] { "plotText", "PlotText" });
            if (!string.IsNullOrWhiteSpace(plotText))
            {
                return plotText;
            }
        }

        return null;
    }

    private static int GetCraftMajorTier(ItemData? item)
    {
        if (item == null)
        {
            return int.MinValue;
        }

        return item.itemLv + 1;
    }

    private static void ResetDrinkTracking(DrinkUIController? controller)
    {
        _lastDrinkControllerInstanceId = controller == null ? 0 : controller.GetInstanceID();
        _lastDrinkPlayerFillAmount = TryReadFloatMember(controller, DrinkPlayerFillAmountMemberNames) ?? float.NaN;
        _lastDrinkEnemyFillAmount = TryReadFloatMember(controller, DrinkEnemyFillAmountMemberNames) ?? float.NaN;
        _lastResolvedDrinkTargetIsPlayer = null;
    }

    private static void UpdateDrinkTracking(DrinkUIController? controller)
    {
        if (controller == null)
        {
            return;
        }

        EnsureDrinkTracking(controller);
        _lastDrinkPlayerFillAmount = TryReadFloatMember(controller, DrinkPlayerFillAmountMemberNames) ?? float.NaN;
        _lastDrinkEnemyFillAmount = TryReadFloatMember(controller, DrinkEnemyFillAmountMemberNames) ?? float.NaN;
    }

    private static bool? ResolveDrinkCostTargetIsPlayer(DrinkUIController? controller, float fillAmount)
    {
        if (controller == null)
        {
            return _lastResolvedDrinkTargetIsPlayer;
        }

        EnsureDrinkTracking(controller);

        var playerFillAmount = TryReadFloatMember(controller, DrinkPlayerFillAmountMemberNames);
        var enemyFillAmount = TryReadFloatMember(controller, DrinkEnemyFillAmountMemberNames);
        bool? resolved = null;

        var playerMatch = playerFillAmount.HasValue && Math.Abs(playerFillAmount.Value - fillAmount) <= DrinkFillMatchTolerance;
        var enemyMatch = enemyFillAmount.HasValue && Math.Abs(enemyFillAmount.Value - fillAmount) <= DrinkFillMatchTolerance;
        if (playerMatch ^ enemyMatch)
        {
            resolved = playerMatch;
        }

        if (!resolved.HasValue)
        {
            var playerDelta = playerFillAmount.HasValue && !float.IsNaN(_lastDrinkPlayerFillAmount)
                ? Math.Abs(playerFillAmount.Value - _lastDrinkPlayerFillAmount)
                : 0f;
            var enemyDelta = enemyFillAmount.HasValue && !float.IsNaN(_lastDrinkEnemyFillAmount)
                ? Math.Abs(enemyFillAmount.Value - _lastDrinkEnemyFillAmount)
                : 0f;

            var playerChanged = playerDelta > DrinkFillDeltaTolerance;
            var enemyChanged = enemyDelta > DrinkFillDeltaTolerance;
            if (playerChanged ^ enemyChanged)
            {
                resolved = playerChanged;
            }
            else if (playerChanged && enemyChanged)
            {
                resolved = playerDelta >= enemyDelta;
            }
        }

        if (!resolved.HasValue && playerFillAmount.HasValue && enemyFillAmount.HasValue)
        {
            var playerDiff = Math.Abs(playerFillAmount.Value - fillAmount);
            var enemyDiff = Math.Abs(enemyFillAmount.Value - fillAmount);
            if (playerDiff + DrinkFillMatchTolerance < enemyDiff)
            {
                resolved = true;
            }
            else if (enemyDiff + DrinkFillMatchTolerance < playerDiff)
            {
                resolved = false;
            }
        }

        if (resolved.HasValue)
        {
            _lastResolvedDrinkTargetIsPlayer = resolved;
        }

        return resolved ?? _lastResolvedDrinkTargetIsPlayer;
    }

    private static void EnsureDrinkTracking(DrinkUIController controller)
    {
        var instanceId = controller.GetInstanceID();
        if (_lastDrinkControllerInstanceId == instanceId)
        {
            return;
        }

        ResetDrinkTracking(controller);
    }

    private static void CaptureOrRestorePreferredBattleTimeScale(string source)
    {
        var worldData = GameController.Instance?.worldData;
        if (worldData == null)
        {
            return;
        }

        var current = Mathf.Max(0.01f, worldData.battleTimeScale);
        if (!_preferredBattleTimeScaleCaptured)
        {
            RememberPreferredBattleTimeScale(current, $"{source}-initial");
            return;
        }

        if (Math.Abs(current - _preferredBattleTimeScale) < 0.01f)
        {
            return;
        }

        worldData.battleTimeScale = _preferredBattleTimeScale;
        LoggerInstance.LogInfo(
            $"Battle speed restored from x{current:0.###} to x{_preferredBattleTimeScale:0.###} at {source}.");
    }

    private static void RememberPreferredBattleTimeScale(float speed, string source)
    {
        var normalized = Mathf.Max(0.01f, speed);
        var changed = !_preferredBattleTimeScaleCaptured || Math.Abs(_preferredBattleTimeScale - normalized) >= 0.01f;
        _preferredBattleTimeScale = normalized;
        _preferredBattleTimeScaleCaptured = true;

        if (changed)
        {
            LoggerInstance.LogInfo($"Battle speed preference captured at x{normalized:0.###} from {source}.");
        }
    }

    private static float ResolveDrinkPowerCostMultiplier(bool? targetIsPlayer)
    {
        if (!targetIsPlayer.HasValue)
        {
            var sharedMultiplier = Mathf.Max(0f, _drinkPlayerPowerCostMultiplier.Value);
            return Math.Abs(sharedMultiplier - Mathf.Max(0f, _drinkEnemyPowerCostMultiplier.Value)) < 0.001f
                ? sharedMultiplier
                : 1f;
        }

        return Mathf.Max(0f, targetIsPlayer.Value
            ? _drinkPlayerPowerCostMultiplier.Value
            : _drinkEnemyPowerCostMultiplier.Value);
    }

    private static float GetNextOutsideBattleSpeed(float current)
    {
        for (var i = 0; i < OutsideBattleSpeedCycle.Length; i++)
        {
            if (Math.Abs(current - OutsideBattleSpeedCycle[i]) < 0.01f)
            {
                return OutsideBattleSpeedCycle[(i + 1) % OutsideBattleSpeedCycle.Length];
            }
        }

        return OutsideBattleSpeedCycle[0];
    }

    private static bool IsBattleUiActive()
    {
        try
        {
            var battleUi = BattleController.Instance?.battleTimeUI;
            return battleUi != null && battleUi.activeInHierarchy;
        }
        catch
        {
            return false;
        }
    }

    private static void ApplyCharacterCreationPointMultiplier(StartMenuController? controller, string source)
    {
        var multiplier = Math.Max(1, _creationPointMultiplier.Value);
        if (controller == null || multiplier <= 1)
        {
            return;
        }

        var attri = controller.leftAttriPoint;
        var fight = controller.leftFightSkillPoint;
        var living = controller.leftLivingSkillPoint;

        controller.leftAttriPoint = attri * multiplier;
        controller.leftFightSkillPoint = fight * multiplier;
        controller.leftLivingSkillPoint = living * multiplier;

        LoggerInstance.LogInfo(
            $"Character creation points multiplied x{multiplier} from {source}: " +
            $"Attri {attri}->{controller.leftAttriPoint}, " +
            $"Fight {fight}->{controller.leftFightSkillPoint}, " +
            $"Living {living}->{controller.leftLivingSkillPoint}.");
    }

    private static int TryGetCollectionCount(object? value)
    {
        if (value is System.Collections.ICollection collection)
        {
            return collection.Count;
        }

        return -1;
    }

    private static string DescribeArgs(object[]? args)
    {
        if (args == null || args.Length == 0)
        {
            return "[]";
        }

        var parts = new string[args.Length];
        for (var i = 0; i < args.Length; i++)
        {
            parts[i] = $"{i}:{SafeFormatValue(args[i])}";
        }

        return "[" + string.Join(", ", parts) + "]";
    }

    private static int ApplyTeachSkillSameSectAreaShare(HeroData sourceHero, HeroData directTarget, int skillId, float baseExp, bool useFightExp, out List<TeachSkillRecipientResult> recipientResults)
    {
        recipientResults = new List<TeachSkillRecipientResult>();
        if (baseExp <= 0f)
        {
            return 0;
        }

        var candidateHeroes = GetHeroesInSameArea(sourceHero);
        if (candidateHeroes.Count == 0)
        {
            return 0;
        }

        var minPercent = ClampTeachSkillSplashPercent(_teachSkillSameSectAreaShareMinPercent.Value);
        var maxPercent = ClampTeachSkillSplashPercent(_teachSkillSameSectAreaShareMaxPercent.Value);
        if (maxPercent < minPercent)
        {
            (minPercent, maxPercent) = (maxPercent, minPercent);
        }

        var recipientCount = 0;
        foreach (var candidate in candidateHeroes)
        {
            if (candidate == null || candidate == sourceHero || candidate == directTarget)
            {
                continue;
            }

            bool sameForce;
            try
            {
                sameForce = sourceHero.SameForce(candidate);
            }
            catch
            {
                sameForce = false;
            }

            if (!sameForce)
            {
                continue;
            }

            var recipientSkill = TryFindHeroSkill(candidate, skillId);
            if (recipientSkill == null)
            {
                if (_traceMode.Value)
                {
                    LoggerInstance.LogInfo($"Teach splash candidate skipped: {TryGetHeroName(candidate)} does not know skill {skillId}.");
                }

                continue;
            }

            if (useFightExp ? !CanGainFightExp(recipientSkill) : !CanGainBookExp(recipientSkill))
            {
                if (_traceMode.Value)
                {
                    LoggerInstance.LogInfo(
                        $"Teach splash candidate skipped: {TryGetHeroName(candidate)} cannot gain more {(useFightExp ? "fight" : "book")} EXP for {TryGetSkillName(recipientSkill)}.");
                }

                continue;
            }

            var sharePercent = Random.Next(minPercent, maxPercent + 1);
            var sharedExp = baseExp * (sharePercent / 100f);
            if (sharedExp <= 0f)
            {
                continue;
            }

            try
            {
                if (useFightExp)
                {
                    candidate.AddSkillFightExp(sharedExp, recipientSkill, false);
                }
                else
                {
                    candidate.AddSkillBookExp(sharedExp, recipientSkill, false);
                }
            }
            catch (Exception ex)
            {
                LoggerInstance.LogWarning(
                    $"Teach splash failed for {TryGetHeroName(candidate)} on skill {TryGetSkillName(recipientSkill)}: {ex.Message}");
                continue;
            }

            recipientCount++;
            recipientResults.Add(new TeachSkillRecipientResult
            {
                HeroName = TryGetHeroName(candidate),
                SkillName = TryGetSkillName(recipientSkill),
                Exp = sharedExp,
                Percent = sharePercent
            });
        }

        return recipientCount;
    }

    private static void PublishTeachSkillRecipientSideTabs(List<TeachSkillRecipientResult> recipientResults, bool useFightExp)
    {
        if (recipientResults.Count == 0)
        {
            return;
        }

        foreach (var result in recipientResults)
        {
            PushPlayerSideTabLog(BuildTeachSkillRecipientSideTabText(result, useFightExp));
        }
    }

    private static string BuildTeachSkillRecipientSideTabText(TeachSkillRecipientResult result, bool useFightExp)
    {
        var expLabel = useFightExp ? "实战经验" : "理论经验";
        return $"<color=#78BE00>{result.HeroName}</color><color=#8C8C8C>{result.SkillName}</color><color=#00B400>{expLabel}+{FormatTeachSkillExp(result.Exp)}</color>({result.Percent}%)";
    }

    private static string FormatTeachSkillRecipientSummary(TeachSkillRecipientResult result)
    {
        return $"{result.HeroName}:{SafeFormatValue(result.Exp)}({result.Percent}%)";
    }

    private static string FormatTeachSkillExp(float exp)
    {
        return Math.Abs(exp - Mathf.Round(exp)) <= 0.001f
            ? Mathf.RoundToInt(exp).ToString()
            : exp.ToString("0.##");
    }

    private static List<HeroData> GetHeroesInSameArea(HeroData sourceHero)
    {
        var results = new List<HeroData>();
        var seenHeroIds = new HashSet<int>();

        void AddHero(HeroData? hero)
        {
            if (hero == null)
            {
                return;
            }

            var heroId = TryGetHeroId(hero);
            if (!heroId.HasValue)
            {
                results.Add(hero);
                return;
            }

            if (seenHeroIds.Add(heroId.Value))
            {
                results.Add(hero);
            }
        }

        try
        {
            var area = sourceHero.GetArea();
            if (area != null)
            {
                var insideHeros = area.insideHeros;
                if (insideHeros != null)
                {
                    for (var i = 0; i < insideHeros.Count; i++)
                    {
                        AddHero(GameController.Instance?.worldData?.GetHero(insideHeros[i]));
                    }
                }
            }
        }
        catch
        {
        }

        if (results.Count > 0)
        {
            return results;
        }

        var sourceAreaId = TryGetHeroAreaId(sourceHero);
        if (!sourceAreaId.HasValue)
        {
            return results;
        }

        try
        {
            var worldHeroes = GameController.Instance?.worldData?.Heros;
            if (worldHeroes != null)
            {
                for (var i = 0; i < worldHeroes.Count; i++)
                {
                    var hero = worldHeroes[i];
                    if (hero != null && TryGetHeroAreaId(hero) == sourceAreaId)
                    {
                        AddHero(hero);
                    }
                }
            }
        }
        catch
        {
        }

        return results;
    }

    private static KungfuSkillLvData? TryFindHeroSkill(HeroData? hero, int skillId)
    {
        if (hero == null)
        {
            return null;
        }

        try
        {
            return hero.FindSkill(skillId);
        }
        catch
        {
            return null;
        }
    }

    private static int ClampTeachSkillSplashPercent(int value)
    {
        return Mathf.Clamp(value, TeachSkillSplashMinPercentFloor, TeachSkillSplashMaxPercentCeiling);
    }

    private static float ResolveSkillExpProgress(KungfuSkillLvData? skill, bool useFightExp)
    {
        if (skill == null)
        {
            return 0f;
        }

        int level;
        try
        {
            level = Math.Max(1, skill.lv);
        }
        catch
        {
            level = 1;
        }

        var progress = 0f;
        for (var currentLevel = 1; currentLevel < level; currentLevel++)
        {
            progress += TryGetSkillLevelMaxExp(skill, currentLevel);
        }

        try
        {
            progress += Mathf.Max(0f, useFightExp ? skill.fightExp : skill.bookExp);
        }
        catch
        {
        }

        return progress;
    }

    private static float TryGetSkillLevelMaxExp(KungfuSkillLvData skill, int level)
    {
        try
        {
            return Mathf.Max(0f, skill.SkillGetMaxExp(Math.Max(1, level)));
        }
        catch
        {
            return 0f;
        }
    }

    private static bool CanGainFightExp(KungfuSkillLvData skill)
    {
        try
        {
            return !skill.FightExpFull();
        }
        catch
        {
            return true;
        }
    }

    private static string GetWorldDateText(bool includeHour)
    {
        try
        {
            var worldData = GameController.Instance?.worldData;
            var worldTime = worldData?.worldTime;
            if (worldTime == null)
            {
                return "Date: unavailable";
            }

            var dateText = $"Date: Y{worldTime.year} M{worldTime.month} D{worldTime.day}";
            if (!includeHour)
            {
                return dateText;
            }

            return $"{dateText} H{worldData?.hour.ToString("0.##") ?? "?"}";
        }
        catch
        {
            return "Date: unavailable";
        }
    }

    private static string SafeFormatValue(object? value)
    {
        if (value == null)
        {
            return "null";
        }

        return value switch
        {
            float f => f.ToString("0.###"),
            double d => d.ToString("0.###"),
            _ => value.ToString() ?? "<null-string>"
        };
    }

    private static string FormatConfigFloat(float value)
    {
        return value.ToString("0.###");
    }

    private static bool ResolveHorseTurboTravelState(bool havePower, bool isSprint)
    {
        if (isSprint)
        {
            return havePower || _lockHorseTurboStamina.Value;
        }

        return _lockHorseTurboStamina.Value && IsHorseTurboActive(TryGetPlayerHorse());
    }

    private static float ApplyHorseTravelMultiplier(HeroData hero, float speed, bool turboActive)
    {
        if (speed <= 0f)
        {
            return speed;
        }

        var multiplier = Math.Max(0.01f, _horseBaseSpeedMultiplier.Value);
        if (turboActive)
        {
            multiplier *= Math.Max(0.01f, _horseTurboSpeedMultiplier.Value);
        }

        return speed * multiplier;
    }

    private static HeroData? TryGetPlayerHero()
    {
        try
        {
            return GameController.Instance?.worldData?.Player();
        }
        catch
        {
            return null;
        }
    }

    private static bool IsPlayerHero(HeroData? hero)
    {
        var player = TryGetPlayerHero();
        return player != null && hero != null && player == hero;
    }

    private static void ApplyConfiguredMaxLoverCount(string source)
    {
        var configured = Math.Max(1, _maxLoverCount.Value);
        if (TrySetStaticMemberValue(typeof(GlobalData), "MaxLoverNum", configured))
        {
            return;
        }

        if (_traceMode.Value)
        {
            LoggerInstance.LogWarning($"Max lover count override could not sync GlobalData.MaxLoverNum from {source}.");
        }
    }

    private static int GetPlayerLoverCount(HeroData player)
    {
        var loverIds = new HashSet<int>();

        try
        {
            if (player.Lover > 0)
            {
                loverIds.Add(player.Lover);
            }
        }
        catch
        {
            var loverId = TryConvertToInt(SafeProperty(player, "Lover") ?? SafeField(player, "Lover") ?? SafeProperty(player, "lover") ?? SafeField(player, "lover"));
            if (loverId.GetValueOrDefault() > 0)
            {
                loverIds.Add(loverId.Value);
            }
        }

        try
        {
            var preLovers = player.PreLovers;
            if (preLovers != null)
            {
                for (var i = 0; i < preLovers.Count; i++)
                {
                    if (preLovers[i] > 0)
                    {
                        loverIds.Add(preLovers[i]);
                    }
                }
            }
        }
        catch
        {
            var preLovers = SafeProperty(player, "PreLovers") ?? SafeField(player, "PreLovers");
            if (preLovers != null)
            {
                try
                {
                    var count = TryConvertToInt(SafeProperty(preLovers, "Count") ?? SafeField(preLovers, "_size"));
                    if (count.HasValue)
                    {
                        for (var i = 0; i < count.Value; i++)
                        {
                            var entry = TryGetIndexedValue(preLovers, i);
                            var loverId = TryConvertToInt(entry);
                            if (loverId.GetValueOrDefault() > 0)
                            {
                                loverIds.Add(loverId.Value);
                            }
                        }
                    }
                }
                catch
                {
                }
            }
        }

        return loverIds.Count;
    }

    private static HorseData? TryGetPlayerHorse()
    {
        var player = TryGetPlayerHero();
        if (player == null)
        {
            return null;
        }

        return SafeProperty(player, "horse") as HorseData
               ?? SafeField(player, "horse") as HorseData
               ?? SafeProperty(player, "Horse") as HorseData
               ?? SafeField(player, "Horse") as HorseData;
    }

    private static bool IsPlayerHorse(HorseData? horse)
    {
        var playerHorse = TryGetPlayerHorse();
        return playerHorse != null && horse != null && playerHorse == horse;
    }

    private static bool IsHorseTurboActive(HorseData? horse)
    {
        return horse != null && horse.sprintTimeLeft > 0f;
    }

    private static void KeepPlayerHorseTurboReady(string source)
    {
        if (!_lockHorseTurboStamina.Value)
        {
            return;
        }

        var horse = TryGetPlayerHorse();
        if (horse == null)
        {
            return;
        }

        var changed = false;
        var maxPower = TryReadFloatMember(horse, HorseMaxPowerMemberNames);
        if (maxPower.HasValue && maxPower.Value > 0f)
        {
            changed |= TrySetFloatMembers(horse, HorseCurrentPowerMemberNames, maxPower.Value);
            changed |= TrySetFloatMembers(TryGetPlayerHero(), new[] { "horsePower" }, maxPower.Value);
        }
        else
        {
            var currentPower = TryReadFloatMember(horse, HorseCurrentPowerMemberNames);
            if (currentPower.HasValue && currentPower.Value < 1f)
            {
                changed |= TrySetFloatMembers(horse, HorseCurrentPowerMemberNames, 1f);
                changed |= TrySetFloatMembers(TryGetPlayerHero(), new[] { "horsePower" }, 1f);
            }
        }

        changed |= TrySetBoolMembers(horse, new[] { "havePower" }, true);

        if (_traceMode.Value && changed && source != "Update")
        {
            LoggerInstance.LogInfo($"Horse turbo stamina refreshed from {source}.");
        }
    }

    private static int ResolveChangedAmount(int requestedDelta, int? moneyBefore, int? moneyAfter, bool isSpend)
    {
        var requestedAmount = Math.Abs(requestedDelta);
        if (moneyBefore.HasValue && moneyAfter.HasValue)
        {
            var actualAmount = isSpend
                ? Math.Max(0, moneyBefore.Value - moneyAfter.Value)
                : Math.Max(0, moneyAfter.Value - moneyBefore.Value);
            if (actualAmount > 0)
            {
                return actualAmount;
            }
        }

        return requestedAmount;
    }

    private static int? TryGetHeroMoney(HeroData? hero)
    {
        if (hero == null)
        {
            return null;
        }

        foreach (var memberName in new[] { "money", "Money", "nowMoney", "coin", "Coin", "gold", "Gold" })
        {
            var value = SafeProperty(hero, memberName) ?? SafeField(hero, memberName);
            var intValue = TryConvertToInt(value);
            if (intValue.HasValue)
            {
                return intValue.Value;
            }
        }

        var inventoryMoney = TryGetItemListMoney(
            SafeProperty(hero, "itemListData") as ItemListData
            ?? SafeField(hero, "itemListData") as ItemListData
            ?? SafeProperty(hero, "ItemListData") as ItemListData
            ?? SafeField(hero, "ItemListData") as ItemListData);
        if (inventoryMoney.HasValue)
        {
            return inventoryMoney.Value;
        }

        if (IsPlayerHero(hero))
        {
            var playerInventoryMoney = TryGetItemListMoney(TryGetPlayerHero()?.itemListData);
            if (playerInventoryMoney.HasValue)
            {
                return playerInventoryMoney.Value;
            }
        }

        return null;
    }

    private static int? TryGetItemListMoney(ItemListData? itemList)
    {
        if (itemList == null)
        {
            return null;
        }

        var value = SafeProperty(itemList, "money") ?? SafeField(itemList, "money") ?? SafeProperty(itemList, "Money") ?? SafeField(itemList, "Money");
        return TryConvertToInt(value);
    }

    private static float? TryGetItemListWeight(ItemListData? itemList)
    {
        if (itemList == null)
        {
            return null;
        }

        var value = SafeProperty(itemList, "weight") ?? SafeField(itemList, "weight") ?? SafeProperty(itemList, "Weight") ?? SafeField(itemList, "Weight");
        return TryConvertToFloat(value);
    }

    private static float? TryGetItemListMaxWeight(ItemListData? itemList)
    {
        if (itemList == null)
        {
            return null;
        }

        var value = SafeProperty(itemList, "maxWeight") ?? SafeField(itemList, "maxWeight") ?? SafeProperty(itemList, "MaxWeight") ?? SafeField(itemList, "MaxWeight");
        return TryConvertToFloat(value);
    }

    private static int? TryConvertToInt(object? value)
    {
        return value switch
        {
            null => null,
            int intValue => intValue,
            float floatValue => Mathf.RoundToInt(floatValue),
            double doubleValue => (int)Math.Round(doubleValue),
            long longValue when longValue <= int.MaxValue && longValue >= int.MinValue => (int)longValue,
            _ => null
        };
    }

    private static bool? TryConvertToBool(object? value)
    {
        return value switch
        {
            null => null,
            bool boolValue => boolValue,
            int intValue => intValue != 0,
            long longValue => longValue != 0,
            float floatValue => Math.Abs(floatValue) > 0.001f,
            double doubleValue => Math.Abs(doubleValue) > 0.001,
            _ => null
        };
    }

    private static float? TryReadFloatMember(object? target, IEnumerable<string> memberNames)
    {
        if (target == null)
        {
            return null;
        }

        foreach (var memberName in memberNames)
        {
            var value = SafeProperty(target, memberName) ?? SafeField(target, memberName);
            var floatValue = TryConvertToFloat(value);
            if (floatValue.HasValue)
            {
                return floatValue.Value;
            }
        }

        return null;
    }

    private static string? TryReadStringMember(object? target, IEnumerable<string> memberNames)
    {
        if (target == null)
        {
            return null;
        }

        foreach (var memberName in memberNames)
        {
            var value = SafeProperty(target, memberName) ?? SafeField(target, memberName);
            var stringValue = value?.ToString();
            if (!string.IsNullOrWhiteSpace(stringValue))
            {
                return stringValue;
            }
        }

        return null;
    }

    private static float? TryConvertToFloat(object? value)
    {
        return value switch
        {
            null => null,
            float floatValue => floatValue,
            double doubleValue => (float)doubleValue,
            int intValue => intValue,
            long longValue => longValue,
            _ => null
        };
    }

    private static string TryGetHeroName(HeroData? hero)
    {
        if (hero == null)
        {
            return "unknown";
        }

        var nameValue = SafeProperty(hero, "heroName") ?? SafeProperty(hero, "HeroName") ?? SafeField(hero, "heroName");
        return nameValue?.ToString() ?? "unknown";
    }

    private static float? TryReadFavor(HeroData? hero)
    {
        if (hero == null)
        {
            return null;
        }

        try
        {
            return hero.favor;
        }
        catch
        {
        }

        try
        {
            return hero.Favor(false);
        }
        catch
        {
        }

        var value = SafeProperty(hero, "favor") ?? SafeField(hero, "favor") ?? SafeProperty(hero, "Favor");
        return TryConvertToFloat(value);
    }

    private static float? TryReadHeroAttribute(HeroData? hero, BaseAttriType attriType)
    {
        if (hero == null)
        {
            return null;
        }

        var attriIndex = (int)attriType;
        if (attriIndex >= 0)
        {
            try
            {
                var totalAttri = hero.totalAttri;
                if (totalAttri != null && attriIndex < totalAttri.Count)
                {
                    return totalAttri[attriIndex];
                }
            }
            catch
            {
            }
        }

        try
        {
            return hero.GetBaseAttriNum(attriType);
        }
        catch
        {
        }

        if (attriIndex >= 0)
        {
            try
            {
                var baseAttri = hero.baseAttri;
                if (baseAttri != null && attriIndex < baseAttri.Count)
                {
                    return baseAttri[attriIndex];
                }
            }
            catch
            {
            }
        }

        return null;
    }

    private static int? TryGetHeroId(HeroData? hero)
    {
        if (hero == null)
        {
            return null;
        }

        var value = SafeProperty(hero, "heroID") ?? SafeField(hero, "heroID") ?? SafeProperty(hero, "HeroID") ?? SafeField(hero, "HeroID");
        return TryConvertToInt(value);
    }

    private static bool TryIsHeroInTeam(HeroData? hero)
    {
        if (hero == null)
        {
            return false;
        }

        try
        {
            return hero.inTeam;
        }
        catch
        {
            var value = SafeProperty(hero, "inTeam") ?? SafeField(hero, "inTeam");
            return TryConvertToBool(value) ?? false;
        }
    }

    private static bool TryIsHeroRecruitedByPlayer(HeroData? hero)
    {
        if (hero == null)
        {
            return false;
        }

        try
        {
            return hero.recruitByPlayer;
        }
        catch
        {
            var value = SafeProperty(hero, "recruitByPlayer") ?? SafeField(hero, "recruitByPlayer");
            return TryConvertToBool(value) ?? false;
        }
    }

    private static int? TryGetHeroTeamLeaderId(HeroData? hero)
    {
        if (hero == null)
        {
            return null;
        }

        try
        {
            return hero.teamLeader;
        }
        catch
        {
            var value = SafeProperty(hero, "teamLeader") ?? SafeField(hero, "teamLeader");
            return TryConvertToInt(value);
        }
    }

    private static int? TryGetHeroAreaId(HeroData? hero)
    {
        if (hero == null)
        {
            return null;
        }

        try
        {
            return hero.atAreaID;
        }
        catch
        {
            var value = SafeProperty(hero, "atAreaID") ?? SafeField(hero, "atAreaID");
            return TryConvertToInt(value);
        }
    }

    private static int ResolveHeroForceId(HeroData? hero)
    {
        if (hero == null)
        {
            return 0;
        }

        try
        {
            if (hero.belongForceID > 0)
            {
                return hero.belongForceID;
            }

            if (hero.servantForceID > 0)
            {
                return hero.servantForceID;
            }
        }
        catch
        {
        }

        var belongForce = TryConvertToInt(SafeProperty(hero, "belongForceID") ?? SafeField(hero, "belongForceID"));
        if (belongForce.GetValueOrDefault() > 0)
        {
            return belongForce.GetValueOrDefault();
        }

        var servantForce = TryConvertToInt(SafeProperty(hero, "servantForceID") ?? SafeField(hero, "servantForceID"));
        return Math.Max(0, servantForce.GetValueOrDefault());
    }

    private static string TryGetAreaName(HeroData? hero)
    {
        if (hero == null)
        {
            return "unknown";
        }

        try
        {
            var area = hero.GetArea();
            if (area != null && !string.IsNullOrWhiteSpace(area.areaName))
            {
                return area.areaName;
            }
        }
        catch
        {
        }

        try
        {
            var areaName = hero.AtAreaName();
            if (!string.IsNullOrWhiteSpace(areaName))
            {
                return areaName;
            }
        }
        catch
        {
        }

        return "unknown";
    }

    private static object? SafeGetMemberValue(object? target, string name)
    {
        if (target == null)
        {
            return null;
        }

        return SafeProperty(target, name) ?? SafeField(target, name);
    }

    private static object? SafeProperty(object target, string name)
    {
        try
        {
            var property = target.GetType().GetProperty(name, BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static);
            return property?.GetValue(target);
        }
        catch
        {
            return null;
        }
    }

    private static object? SafeField(object target, string name)
    {
        try
        {
            var field = target.GetType().GetField(name, BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static);
            return field?.GetValue(target);
        }
        catch
        {
            return null;
        }
    }

    private static bool TrySetFloatMembers(object? target, IEnumerable<string> memberNames, float value)
    {
        var changed = false;
        foreach (var memberName in memberNames)
        {
            changed |= TrySetMemberValue(target, memberName, value);
        }

        return changed;
    }

    private static bool TrySetBoolMembers(object? target, IEnumerable<string> memberNames, bool value)
    {
        var changed = false;
        foreach (var memberName in memberNames)
        {
            changed |= TrySetMemberValue(target, memberName, value);
        }

        return changed;
    }

    private static bool TrySetMemberValue(object? target, string name, object value)
    {
        if (target == null)
        {
            return false;
        }

        const BindingFlags Flags = BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static;

        try
        {
            var property = target.GetType().GetProperty(name, Flags);
            if (property != null && property.CanWrite && TryConvertMemberValue(property.PropertyType, value, out var convertedPropertyValue))
            {
                property.SetValue(target, convertedPropertyValue);
                return true;
            }
        }
        catch
        {
        }

        try
        {
            var field = target.GetType().GetField(name, Flags);
            if (field != null && TryConvertMemberValue(field.FieldType, value, out var convertedFieldValue))
            {
                field.SetValue(target, convertedFieldValue);
                return true;
            }
        }
        catch
        {
        }

        return false;
    }

    private static bool TrySetStaticMemberValue(Type targetType, string name, object value)
    {
        const BindingFlags Flags = BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static;

        try
        {
            var property = targetType.GetProperty(name, Flags);
            if (property != null && property.CanWrite && TryConvertMemberValue(property.PropertyType, value, out var convertedPropertyValue))
            {
                property.SetValue(null, convertedPropertyValue);
                return true;
            }
        }
        catch
        {
        }

        try
        {
            var field = targetType.GetField(name, Flags);
            if (field != null && TryConvertMemberValue(field.FieldType, value, out var convertedFieldValue))
            {
                field.SetValue(null, convertedFieldValue);
                return true;
            }
        }
        catch
        {
        }

        return false;
    }

    private static bool TrySetIndexedValue(object list, int index, object value)
    {
        try
        {
            var property = list.GetType().GetProperty("Item", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance);
            if (property != null && property.CanWrite)
            {
                property.SetValue(list, value, new object[] { index });
                return true;
            }
        }
        catch
        {
        }

        try
        {
            var method = list.GetType().GetMethod("set_Item", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance);
            if (method != null)
            {
                method.Invoke(list, new object[] { index, value });
                return true;
            }
        }
        catch
        {
        }

        return false;
    }

    private static object? TryGetIndexedValue(object list, int index)
    {
        try
        {
            var property = list.GetType().GetProperty("Item", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance);
            if (property != null && property.CanRead)
            {
                return property.GetValue(list, new object[] { index });
            }
        }
        catch
        {
        }

        try
        {
            var method = list.GetType().GetMethod("get_Item", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance);
            if (method != null)
            {
                return method.Invoke(list, new object[] { index });
            }
        }
        catch
        {
        }

        return null;
    }

    private static void ApplyMerchantCarryCash(TradeUIType targetType, ItemListData? merchantItemList, string source)
    {
        var targetCash = Math.Max(0, _merchantCarryCash.Value);
        if (targetCash <= 0 || targetType != TradeUIType.Shop || merchantItemList == null)
        {
            return;
        }

        var currentCash = TryGetItemListMoney(merchantItemList) ?? 0;
        if (currentCash >= targetCash)
        {
            return;
        }

        if (!TrySetMemberValue(merchantItemList, "money", targetCash))
        {
            if (_traceMode.Value)
            {
                LoggerInstance.LogWarning($"Merchant cash floor could not be applied from {source}.");
            }

            return;
        }

        if (_traceMode.Value)
        {
            LoggerInstance.LogInfo($"Merchant cash floor applied from {currentCash} to {targetCash} via {source}.");
        }
    }

    private static void ApplyPlayerCarryWeightOverride(string source)
    {
        var playerInventory = TryGetPlayerHero()?.itemListData;
        if (playerInventory == null)
        {
            return;
        }

        var changed = false;
        var carryWeightCap = Math.Max(0f, _carryWeightCap.Value);
        var currentMaxWeight = TryGetItemListMaxWeight(playerInventory) ?? 0f;
        if (carryWeightCap > 0f && currentMaxWeight < carryWeightCap)
        {
            changed |= TrySetMemberValue(playerInventory, "maxWeight", carryWeightCap);
        }

        if (_ignoreCarryWeight.Value)
        {
            var currentWeight = TryGetItemListWeight(playerInventory) ?? 0f;
            if (Math.Abs(currentWeight) > 0.001f)
            {
                changed |= TrySetMemberValue(playerInventory, "weight", 0f);
            }
        }

        if (changed && _traceMode.Value && source != "Update")
        {
            LoggerInstance.LogInfo(
                $"Player carry weight override applied from {source}: weight={SafeFormatValue(TryGetItemListWeight(playerInventory))}, max={SafeFormatValue(TryGetItemListMaxWeight(playerInventory))}.");
        }
    }

    private static bool TryConvertMemberValue(Type targetType, object value, out object? convertedValue)
    {
        convertedValue = null;

        if (targetType == typeof(float))
        {
            var floatValue = TryConvertToFloat(value);
            if (floatValue.HasValue)
            {
                convertedValue = floatValue.Value;
                return true;
            }
        }
        else if (targetType == typeof(double))
        {
            var floatValue = TryConvertToFloat(value);
            if (floatValue.HasValue)
            {
                convertedValue = (double)floatValue.Value;
                return true;
            }
        }
        else if (targetType == typeof(int))
        {
            var intValue = TryConvertToInt(value);
            if (intValue.HasValue)
            {
                convertedValue = intValue.Value;
                return true;
            }
        }
        else if (targetType == typeof(long))
        {
            var intValue = TryConvertToInt(value);
            if (intValue.HasValue)
            {
                convertedValue = (long)intValue.Value;
                return true;
            }
        }
        else if (targetType == typeof(bool) && value is bool boolValue)
        {
            convertedValue = boolValue;
            return true;
        }

        return false;
    }

    private static void EnsureDailySkillInsightBaseline()
    {
        if (_dailySkillInsightBaselineReady)
        {
            return;
        }

        var currentDate = TryGetWorldDateSnapshot();
        if (currentDate == null)
        {
            return;
        }

        _lastObservedWorldDate = currentDate;
        _dailySkillInsightBaselineReady = true;

        if (_traceMode.Value)
        {
            LoggerInstance.LogInfo($"Daily skill insight baseline initialized at {FormatDate(currentDate)}.");
        }
    }

    private static void HandleDailySkillInsightDateProgress(TimeData? beforeDate, TimeData? afterDate, string source)
    {
        if (afterDate == null)
        {
            return;
        }

        if (!_dailySkillInsightBaselineReady || _lastObservedWorldDate == null)
        {
            _lastObservedWorldDate = afterDate;
            _dailySkillInsightBaselineReady = true;
            return;
        }

        if (beforeDate != null && !AreDatesEqual(beforeDate, _lastObservedWorldDate) && !AreDatesEqual(afterDate, _lastObservedWorldDate))
        {
            if (_traceMode.Value)
            {
                LoggerInstance.LogInfo(
                    $"Daily skill insight baseline resynced from {FormatDate(_lastObservedWorldDate)} to {FormatDate(afterDate)} because {source} started from {FormatDate(beforeDate)}.");
            }

            _lastObservedWorldDate = afterDate;
            return;
        }

        var elapsedDays = GetElapsedDayCount(_lastObservedWorldDate, afterDate);
        _lastObservedWorldDate = afterDate;
        if (elapsedDays <= 0)
        {
            return;
        }

        for (var i = 0; i < elapsedDays; i++)
        {
            TryRollDailySkillInsight(i + 1, elapsedDays, source);
        }
    }

    private static void HandleTeamAutoFavorDateProgress(TimeData? beforeDate, TimeData? afterDate, string source)
    {
        if (!_teamAutoFavorEnabled.Value || beforeDate == null || afterDate == null)
        {
            return;
        }

        var elapsedDays = GetElapsedDayCount(beforeDate, afterDate);
        if (elapsedDays <= 0)
        {
            return;
        }

        TryApplyTeamAutoFavor(elapsedDays, source);
    }

    private static void TryApplyTeamAutoFavor(int elapsedDays, string source)
    {
        var perDayFavor = Math.Max(0f, _teamAutoFavorPerDay.Value);
        if (elapsedDays <= 0 || perDayFavor <= 0f)
        {
            return;
        }

        var player = TryGetPlayerHero();
        if (player == null)
        {
            return;
        }

        var teammates = GetPlayerTeamMembers(player);
        if (teammates.Count == 0)
        {
            if (_traceMode.Value)
            {
                LoggerInstance.LogInfo($"Team auto favor skipped from {source}: no current player teammates for {elapsedDays} elapsed days.");
            }

            return;
        }

        var favorToGrant = perDayFavor * elapsedDays;
        var affectedCount = 0;
        var totalApplied = 0f;
        var preview = new List<string>();

        foreach (var teammate in teammates)
        {
            var applied = TryApplyAutoFavorGain(teammate, favorToGrant);
            if (applied <= 0.001f)
            {
                continue;
            }

            affectedCount++;
            totalApplied += applied;
            if (preview.Count < 3)
            {
                preview.Add($"{TryGetHeroName(teammate)}+{SafeFormatValue(applied)}");
            }
        }

        if (affectedCount <= 0)
        {
            if (_traceMode.Value)
            {
                LoggerInstance.LogInfo(
                    $"Team auto favor found teammates but no favor changed from {source}: days={elapsedDays}, perDay={SafeFormatValue(perDayFavor)}.");
            }

            return;
        }

        var previewText = preview.Count == 0 ? $"共{affectedCount}人" : string.Join("、", preview);
        if (affectedCount > preview.Count)
        {
            previewText += $"等{affectedCount}人";
        }

        PushPlayerLog($"【同伴情谊】：{previewText}（{elapsedDays}天）");
        LoggerInstance.LogInfo(
            $"Team auto favor applied from {source}: days={elapsedDays}, perDay={SafeFormatValue(perDayFavor)}, recipients={affectedCount}, totalApplied={SafeFormatValue(totalApplied)}.");
    }

    private static float TryApplyAutoFavorGain(HeroData teammate, float favorToGrant)
    {
        if (teammate == null || favorToGrant <= 0f)
        {
            return 0f;
        }

        var beforeFavor = TryReadFavor(teammate);
        if (!beforeFavor.HasValue)
        {
            return 0f;
        }

        var targetFavor = beforeFavor.Value + favorToGrant;
        try
        {
            var maxFavor = teammate.GetMaxFavor(targetFavor);
            if (maxFavor > 0f)
            {
                targetFavor = Mathf.Min(targetFavor, maxFavor);
            }
        }
        catch
        {
        }

        try
        {
            _applyingTeamAutoFavor = true;
            teammate.SetFavor(targetFavor, false);
        }
        catch (Exception ex)
        {
            LoggerInstance.LogWarning($"Team auto favor failed for {TryGetHeroName(teammate)}: {ex.Message}");
            return 0f;
        }
        finally
        {
            _applyingTeamAutoFavor = false;
        }

        var afterFavor = TryReadFavor(teammate);
        if (afterFavor.HasValue)
        {
            return Mathf.Max(0f, afterFavor.Value - beforeFavor.Value);
        }

        return 0f;
    }

    private static List<HeroData> GetPlayerTeamMembers(HeroData player)
    {
        var results = new List<HeroData>();
        var seenHeroIds = new HashSet<int>();
        var playerId = TryGetHeroId(player);

        void AddHero(HeroData? hero, bool listedByPlayer)
        {
            if (hero == null || IsPlayerHero(hero))
            {
                return;
            }

            if (!TryIsHeroInTeam(hero))
            {
                return;
            }

            if (!listedByPlayer && !IsCurrentPlayerTeamMate(hero, playerId))
            {
                return;
            }

            var heroId = TryGetHeroId(hero);
            if (heroId.HasValue && !seenHeroIds.Add(heroId.Value))
            {
                return;
            }

            results.Add(hero);
        }

        try
        {
            var teamMateIds = player.teamMates;
            if (teamMateIds != null)
            {
                for (var i = 0; i < teamMateIds.Count; i++)
                {
                    AddHero(GameController.Instance?.worldData?.GetHero(teamMateIds[i]), listedByPlayer: true);
                }
            }
        }
        catch
        {
        }

        try
        {
            var worldHeroes = GameController.Instance?.worldData?.Heros;
            if (worldHeroes != null)
            {
                for (var i = 0; i < worldHeroes.Count; i++)
                {
                    AddHero(worldHeroes[i], listedByPlayer: false);
                }
            }
        }
        catch
        {
        }

        return results;
    }

    private static bool IsCurrentPlayerTeamMate(HeroData hero, int? playerId)
    {
        if (hero == null || !TryIsHeroInTeam(hero))
        {
            return false;
        }

        if (TryIsHeroRecruitedByPlayer(hero))
        {
            return true;
        }

        var teamLeader = TryGetHeroTeamLeaderId(hero);
        return playerId.HasValue && teamLeader.HasValue && teamLeader.Value == playerId.Value;
    }

    private static float ResolvePositiveFloatGain(float requestedDelta, float? beforeValue, float? afterValue)
    {
        if (beforeValue.HasValue && afterValue.HasValue)
        {
            return Mathf.Max(0f, afterValue.Value - beforeValue.Value);
        }

        return Mathf.Max(0f, requestedDelta);
    }

    private static void TryApplyTeamFameShare(HeroData player, float playerFameGain)
    {
        if (player == null || playerFameGain <= 0.001f)
        {
            return;
        }

        var teammates = GetPlayerTeamMembers(player);
        if (teammates.Count == 0)
        {
            if (_traceMode.Value)
            {
                LoggerInstance.LogInfo($"Team fame share skipped: no current player teammates for fame gain {SafeFormatValue(playerFameGain)}.");
            }

            return;
        }

        var sharePerTeammate = playerFameGain * TeamFameShareRatio;
        if (sharePerTeammate <= 0.001f)
        {
            return;
        }

        var affectedCount = 0;
        var totalApplied = 0f;
        var preview = new List<string>();

        foreach (var teammate in teammates)
        {
            var applied = TryApplySharedFameGain(teammate, sharePerTeammate);
            if (applied <= 0.001f)
            {
                continue;
            }

            affectedCount++;
            totalApplied += applied;
            if (preview.Count < 3)
            {
                preview.Add($"{TryGetHeroName(teammate)}+{SafeFormatValue(applied)}");
            }
        }

        if (affectedCount <= 0)
        {
            if (_traceMode.Value)
            {
                LoggerInstance.LogInfo(
                    $"Team fame share found teammates but no fame changed: playerGain={SafeFormatValue(playerFameGain)}, share={SafeFormatValue(sharePerTeammate)}.");
            }

            return;
        }

        var previewText = preview.Count == 0 ? $"共{affectedCount}人" : string.Join("、", preview);
        if (affectedCount > preview.Count)
        {
            previewText += $"等{affectedCount}人";
        }

        PushPlayerLog($"【同队声望】：{previewText}（主角+{SafeFormatValue(playerFameGain)}）");
        LoggerInstance.LogInfo(
            $"Team fame share applied: player={TryGetHeroName(player)}, playerGain={SafeFormatValue(playerFameGain)}, share={SafeFormatValue(sharePerTeammate)}, recipients={affectedCount}, totalApplied={SafeFormatValue(totalApplied)}.");
    }

    private static float TryApplySharedFameGain(HeroData teammate, float fameToGrant)
    {
        if (teammate == null || fameToGrant <= 0.001f)
        {
            return 0f;
        }

        var beforeFame = TryReadFame(teammate);
        if (!beforeFame.HasValue)
        {
            return 0f;
        }

        var beforeForceLv = TryReadHeroForceLv(teammate);
        try
        {
            _applyingTeamFameShare = true;
            if (!TryInvokeChangeFame(teammate, fameToGrant, false))
            {
                return 0f;
            }
        }
        catch (Exception ex)
        {
            LoggerInstance.LogWarning($"Team fame share failed for {TryGetHeroName(teammate)}: {ex.Message}");
            return 0f;
        }
        finally
        {
            _applyingTeamFameShare = false;
        }

        try
        {
            teammate.CheckHeroFameForceLv();
        }
        catch
        {
        }

        TryPromoteSectlessHeroForceLvFromFame(teammate, beforeForceLv, out _);

        var afterFame = TryReadFame(teammate);
        if (afterFame.HasValue)
        {
            return Mathf.Max(0f, afterFame.Value - beforeFame.Value);
        }

        return 0f;
    }

    private static bool TryInvokeChangeFame(HeroData hero, float fameToGrant, bool showInfo)
    {
        if (hero == null || _heroChangeFameMethod == null)
        {
            return false;
        }

        var parameters = _heroChangeFameMethod.GetParameters();
        if (parameters.Length != 2)
        {
            return false;
        }

        object amount;
        var amountType = parameters[0].ParameterType;
        if (amountType == typeof(int))
        {
            var roundedAmount = Mathf.RoundToInt(fameToGrant);
            if (roundedAmount <= 0)
            {
                return false;
            }

            amount = roundedAmount;
        }
        else if (amountType == typeof(double))
        {
            amount = (double)fameToGrant;
        }
        else
        {
            amount = fameToGrant;
        }

        _heroChangeFameMethod.Invoke(hero, new[] { amount, (object)showInfo });
        return true;
    }

    private static void TryRollDailySkillInsight(int dayIndex, int totalDays, string source)
    {
        var hitChancePercent = ClampPercent(_dailySkillInsightHitChancePercent.Value);
        var expPercent = Math.Max(0f, _dailySkillInsightExpPercent.Value);
        if (hitChancePercent <= 0 || expPercent <= 0f)
        {
            return;
        }

        var player = TryGetPlayerHero();
        if (player == null)
        {
            return;
        }

        var eligibleSkills = GetDailySkillInsightCandidates(player);
        if (eligibleSkills.Count == 0)
        {
            if (_traceMode.Value)
            {
                LoggerInstance.LogInfo($"Daily skill insight skipped on day {dayIndex}/{totalDays} from {source}: no eligible skills.");
            }

            return;
        }

        var roll = Random.Next(1, 101);
        if (roll > hitChancePercent)
        {
            if (_traceMode.Value)
            {
                LoggerInstance.LogInfo($"Daily skill insight miss on day {dayIndex}/{totalDays} from {source}: roll {roll} > {hitChancePercent}.");
            }

            return;
        }

        if (!TryAwardDailySkillInsightExp(player, eligibleSkills, out var skillName, out var awardedExp, out var usedSkill))
        {
            if (_traceMode.Value)
            {
                LoggerInstance.LogInfo($"Daily skill insight hit on day {dayIndex}/{totalDays} from {source}, but no candidate accepted EXP.");
            }

            return;
        }

        var skillTierText = GetSkillTierText(usedSkill);
        PushPlayerLog($"【心得涌现】：【{skillTierText}{skillName}】获得 {FormatInsightExp(awardedExp)} 经验值");
        LoggerInstance.LogInfo(
            $"Daily skill insight applied on day {dayIndex}/{totalDays} from {source}: skill={skillName}, exp={SafeFormatValue(awardedExp)}, chance={hitChancePercent}, roll={roll}.");
    }

    private static void TryRunRealtimeSkillInsight()
    {
        var intervalSeconds = Math.Max(0f, _dailySkillInsightRealtimeIntervalSeconds.Value);
        if (intervalSeconds <= 0f)
        {
            _nextRealtimeDailySkillInsightAt = -1f;
            return;
        }

        var now = Time.realtimeSinceStartup;
        if (_nextRealtimeDailySkillInsightAt < 0f)
        {
            _nextRealtimeDailySkillInsightAt = now + intervalSeconds;
            return;
        }

        if (now < _nextRealtimeDailySkillInsightAt)
        {
            return;
        }

        _nextRealtimeDailySkillInsightAt = now + intervalSeconds;
        TryTriggerRealtimeSkillInsight(intervalSeconds);
    }

    private static void TryTriggerRealtimeSkillInsight(float intervalSeconds)
    {
        var expPercent = Math.Max(0f, _dailySkillInsightExpPercent.Value);
        if (expPercent <= 0f)
        {
            return;
        }

        var player = TryGetPlayerHero();
        if (player == null)
        {
            return;
        }

        FillDailySkillInsightCandidates(player, _dailySkillInsightCandidateBuffer);
        if (_dailySkillInsightCandidateBuffer.Count == 0)
        {
            if (_traceMode.Value)
            {
                LoggerInstance.LogInfo($"Realtime skill insight skipped: no eligible skills at interval {intervalSeconds:0.###} seconds.");
            }

            return;
        }

        if (!TryAwardDailySkillInsightExp(player, _dailySkillInsightCandidateBuffer, out var skillName, out var awardedExp, out var usedSkill))
        {
            if (_traceMode.Value)
            {
                LoggerInstance.LogInfo($"Realtime skill insight interval {intervalSeconds:0.###} seconds fired, but no candidate accepted EXP.");
            }

            return;
        }

        var skillTierText = GetSkillTierText(usedSkill);
        PushPlayerLog($"【心得涌现】：【{skillTierText}{skillName}】获得 {FormatInsightExp(awardedExp)} 经验值");
        if (_traceMode.Value)
        {
            LoggerInstance.LogInfo($"Realtime skill insight applied: interval={intervalSeconds:0.###}s, skill={skillName}, exp={SafeFormatValue(awardedExp)}.");
        }
    }

    private static List<KungfuSkillLvData> GetDailySkillInsightCandidates(HeroData player)
    {
        var candidates = new List<KungfuSkillLvData>();
        FillDailySkillInsightCandidates(player, candidates);
        return candidates;
    }

    private static void FillDailySkillInsightCandidates(HeroData player, List<KungfuSkillLvData> candidates)
    {
        candidates.Clear();

        try
        {
            var skills = player.kungfuSkills;
            if (skills == null)
            {
                return;
            }

            for (var i = 0; i < skills.Count; i++)
            {
                var skill = skills[i];
                if (skill == null || skill.lv >= DailySkillInsightMaxLevel)
                {
                    continue;
                }

                if (!CanGainBookExp(skill))
                {
                    continue;
                }

                candidates.Add(skill);
            }
        }
        catch (Exception ex)
        {
            LoggerInstance.LogWarning($"Failed to collect daily skill insight candidates: {ex.Message}");
        }
    }

    private static bool CanGainBookExp(KungfuSkillLvData skill)
    {
        try
        {
            return !skill.BookExpFull();
        }
        catch
        {
            return true;
        }
    }

    private static bool TryAwardDailySkillInsightExp(HeroData player, List<KungfuSkillLvData> candidates, out string skillName, out float awardedExp, out KungfuSkillLvData? usedSkill)
    {
        skillName = string.Empty;
        awardedExp = 0f;
        usedSkill = null;
        if (candidates.Count == 0)
        {
            return false;
        }

        var startIndex = candidates.Count == 1 ? 0 : Random.Next(candidates.Count);
        for (var offset = 0; offset < candidates.Count; offset++)
        {
            var skill = candidates[(startIndex + offset) % candidates.Count];
            var plannedExp = ResolveDailySkillInsightExp(player, skill);
            if (plannedExp <= 0f)
            {
                continue;
            }

            var beforeLevel = skill.lv;
            var beforeBookExp = skill.bookExp;

            try
            {
                _applyingDailySkillInsightExp = true;
                player.AddSkillBookExp(plannedExp, skill, false);
            }
            catch (Exception ex)
            {
                LoggerInstance.LogWarning($"Daily skill insight failed for skill {TryGetSkillName(skill)}: {ex.Message}");
                continue;
            }
            finally
            {
                _applyingDailySkillInsightExp = false;
            }

            if (skill.lv != beforeLevel || Math.Abs(skill.bookExp - beforeBookExp) > 0.001f)
            {
                skillName = TryGetSkillName(skill);
                awardedExp = plannedExp;
                usedSkill = skill;
                return true;
            }
        }

        return false;
    }

    private static float ResolveDailySkillInsightExp(HeroData player, KungfuSkillLvData skill)
    {
        var expPercent = Math.Max(0f, _dailySkillInsightExpPercent.Value);
        if (expPercent <= 0f)
        {
            return 0f;
        }

        float maxExp;
        try
        {
            maxExp = skill.SkillGetMaxExp(Math.Max(1, skill.lv));
        }
        catch (Exception ex)
        {
            LoggerInstance.LogWarning($"Could not read max EXP for skill {TryGetSkillName(skill)}: {ex.Message}");
            return 0f;
        }

        if (maxExp <= 0f)
        {
            return 0f;
        }

        var rarityMultiplier = 1f;
        if (_dailySkillInsightUseRarityScaling.Value)
        {
            rarityMultiplier = ResolveSkillRarityExpRate(player, skill);
        }

        var result = maxExp * (expPercent / 100f) * rarityMultiplier;
        return Mathf.Max(1f, result);
    }

    private static float ResolveSkillRarityExpRate(HeroData player, KungfuSkillLvData skill)
    {
        try
        {
            var skillData = skill.DataBase();
            if (skillData == null)
            {
                return 1f;
            }

            var rate = player.GetSkillRareLvExpRate(skillData.rareLv);
            return rate > 0f ? rate : 1f;
        }
        catch
        {
            return 1f;
        }
    }

    private static string GetSkillTierText(KungfuSkillLvData? skill)
    {
        if (skill == null)
        {
            return string.Empty;
        }

        try
        {
            var skillData = skill.DataBase();
            if (skillData == null)
            {
                return string.Empty;
            }

            return $"【{skillData.rareLv}阶】";
        }
        catch
        {
            return string.Empty;
        }
    }

    private static string TryGetSkillName(KungfuSkillLvData? skill)
    {
        if (skill == null)
        {
            return "未知技能";
        }

        try
        {
            var name = skill.Name(false);
            if (!string.IsNullOrWhiteSpace(name))
            {
                return name;
            }
        }
        catch
        {
        }

        return $"技能{skill.skillID}";
    }

    private static TimeData? TryGetWorldDateSnapshot()
    {
        try
        {
            var worldTime = GameController.Instance?.worldData?.worldTime;
            if (worldTime == null)
            {
                return null;
            }

            return new TimeData(worldTime.year, worldTime.month, worldTime.day);
        }
        catch
        {
            return null;
        }
    }

    private static int GetElapsedDayCount(TimeData fromDate, TimeData toDate)
    {
        if (CompareDates(toDate, fromDate) <= 0)
        {
            return 0;
        }

        try
        {
            var delta = toDate.DeltaDay(fromDate);
            if (delta > 0)
            {
                return delta;
            }
        }
        catch
        {
        }

        return ApproximateElapsedDayCount(fromDate, toDate);
    }

    private static int ApproximateElapsedDayCount(TimeData fromDate, TimeData toDate)
    {
        var fromSerial = ApproximateDateSerial(fromDate);
        var toSerial = ApproximateDateSerial(toDate);
        return Math.Max(0, toSerial - fromSerial);
    }

    private static int ApproximateDateSerial(TimeData date)
    {
        return (date.year * 372) + (date.month * 31) + date.day;
    }

    private static int CompareDates(TimeData left, TimeData right)
    {
        var yearCompare = left.year.CompareTo(right.year);
        if (yearCompare != 0)
        {
            return yearCompare;
        }

        var monthCompare = left.month.CompareTo(right.month);
        if (monthCompare != 0)
        {
            return monthCompare;
        }

        return left.day.CompareTo(right.day);
    }

    private static bool AreDatesEqual(TimeData? left, TimeData? right)
    {
        return left != null && right != null
            && left.year == right.year
            && left.month == right.month
            && left.day == right.day;
    }

    private static bool IsHealingStateTile(ExploreTileData? tile)
    {
        if (tile == null)
        {
            return false;
        }

        try
        {
            return tile.exploreTileEventType == 7;
        }
        catch
        {
            var eventTypeValue = TryConvertToInt(SafeProperty(tile, "exploreTileEventType") ?? SafeField(tile, "exploreTileEventType"));
            return eventTypeValue == 7;
        }
    }

    private static void TryRevealAllExploreFogAfterFirstMove(ExploreController? controller)
    {
        if (!_revealAllOnStepTile.Value || _exploreFullRevealConsumed)
        {
            return;
        }

        if (!TryRevealAllExploreFog(controller))
        {
            return;
        }

        _exploreFullRevealConsumed = true;
        LoggerInstance.LogInfo("Exploration fog fully revealed after first completed move.");
    }

    private static bool TryRevealAllExploreFog(ExploreController? controller)
    {
        if (controller == null)
        {
            return false;
        }

        try
        {
            controller.SeeAllTile();
            return true;
        }
        catch (Exception ex)
        {
            LoggerInstance.LogWarning($"Failed to reveal full exploration fog after Step(1): {ex.Message}");
            return false;
        }
    }

    private static ItemData? TryCreateTreasureChestBonusItem(ItemData sourceItem, HeroData targetHero)
    {
        try
        {
            var gameController = GameController.Instance;
            if (gameController != null)
            {
                var generated = gameController.GenerateRandomItemValue(
                    Math.Max(1f, sourceItem.value),
                    Math.Max(1f, sourceItem.itemLv),
                    targetHero);

                if (generated != null)
                {
                    return generated;
                }
            }
        }
        catch (Exception ex)
        {
            LoggerInstance.LogWarning($"Failed to reroll bonus treasure chest item: {ex.Message}");
        }

        try
        {
            return sourceItem.Clone() as ItemData;
        }
        catch (Exception ex)
        {
            LoggerInstance.LogWarning($"Failed to clone treasure chest item: {ex.Message}");
            return null;
        }
    }

    private static void ResetExploreFullReveal(string source)
    {
        if (_exploreFullRevealConsumed)
        {
            LoggerInstance.LogInfo($"Exploration full-reveal state reset from {source}.");
        }

        _exploreFullRevealConsumed = false;
    }

    private static bool TryClearHeroInjuryValue(HeroData hero, float currentValue, Func<HeroData, float, float> applyChange, string memberName)
    {
        if (currentValue <= 0.001f)
        {
            return false;
        }

        try
        {
            applyChange(hero, currentValue);
        }
        catch (Exception ex)
        {
            LoggerInstance.LogWarning($"Failed to clear {memberName} via change call: {ex.Message}");
        }

        return TrySetFloatMembers(hero, new[] { memberName, UppercaseFirst(memberName) }, 0f) || currentValue > 0.001f;
    }

    private static string UppercaseFirst(string value)
    {
        if (string.IsNullOrEmpty(value))
        {
            return value;
        }

        if (value.Length == 1)
        {
            return value.ToUpperInvariant();
        }

        return char.ToUpperInvariant(value[0]) + value.Substring(1);
    }

    private static string DescribeExploreTile(ExploreTileData? tile)
    {
        if (tile == null)
        {
            return "null";
        }

        var column = TryConvertToInt(SafeProperty(tile, "column") ?? SafeField(tile, "column"));
        var row = TryConvertToInt(SafeProperty(tile, "row") ?? SafeField(tile, "row"));
        var eventTypeValue = TryConvertToInt(SafeProperty(tile, "exploreTileEventType") ?? SafeField(tile, "exploreTileEventType"));
        var eventHandled = TryConvertToBool(SafeProperty(tile, "eventHappen") ?? SafeField(tile, "eventHappen"));
        return $"pos=({column?.ToString() ?? "?"},{row?.ToString() ?? "?"}), event={eventTypeValue?.ToString() ?? "?"}, eventHappen={eventHandled?.ToString() ?? "?"}";
    }

    private static string FormatDate(TimeData? date)
    {
        return date == null ? "Date: unavailable" : $"Y{date.year} M{date.month} D{date.day}";
    }

    private static string FormatInsightExp(float value)
    {
        return value >= 10f || Math.Abs(value - Mathf.Round(value)) < 0.001f
            ? Mathf.RoundToInt(value).ToString()
            : value.ToString("0.###");
    }
}
