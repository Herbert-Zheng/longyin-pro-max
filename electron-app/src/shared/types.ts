export const GAME_EXE_NAME = 'LongYinLiZhiZhuan.exe';
export const STEAM_APP_ID = '3202030';
export const RELEASE_MANIFEST_NAME = 'update-manifest.json';
export const APP_FOLDER_NAME = 'LongYinProMaxApp';
export const CUSTOM_TALENT_PACK_VERSION = 1 as const;
export const DEFAULT_CUSTOM_TALENT_DURATION_DAYS = 999;

export const BASE_ATTRI_TYPE_NAMES = [
  'Str',
  'Agl',
  'Inte',
  'Wil',
  'Con',
  'Mag',
  'Internal',
  'Dodge',
  'Unique',
  'Fist',
  'Sword',
  'Knife',
  'Long',
  'Strange',
  'Shoot',
  'Med',
  'Poison',
  'Knowledge',
  'Speech',
  'DigAndCut',
  'Plant',
  'CraftEquip',
  'CraftMed',
  'CraftFood'
] as const;

export type BaseAttriTypeName = typeof BASE_ATTRI_TYPE_NAMES[number];

export const HERO_SPE_ADD_DATA_TYPE_NAMES = [
  'attri0',
  'attri1',
  'attri2',
  'attri3',
  'attri4',
  'attri5',
  'fightSkill0',
  'fightSkill1',
  'fightSkill2',
  'fightSkill3',
  'fightSkill4',
  'fightSkill5',
  'fightSkill6',
  'fightSkill7',
  'fightSkill8',
  'fightSkillPower0',
  'fightSkillPower1',
  'fightSkillPower2',
  'fightSkillPower3',
  'fightSkillPower4',
  'fightSkillPower5',
  'fightSkillPower6',
  'fightSkillPower7',
  'fightSkillPower8',
  'livingSkill0',
  'livingSkill1',
  'livingSkill2',
  'livingSkill3',
  'livingSkill4',
  'livingSkill5',
  'livingSkill6',
  'livingSkill7',
  'livingSkill8',
  'maxAttri0',
  'maxAttri1',
  'maxAttri2',
  'maxAttri3',
  'maxAttri4',
  'maxAttri5',
  'maxFightSkill0',
  'maxFightSkill1',
  'maxFightSkill2',
  'maxFightSkill3',
  'maxFightSkill4',
  'maxFightSkill5',
  'maxFightSkill6',
  'maxFightSkill7',
  'maxFightSkill8',
  'maxLivingSkill0',
  'maxLivingSkill1',
  'maxLivingSkill2',
  'maxLivingSkill3',
  'maxLivingSkill4',
  'maxLivingSkill5',
  'maxLivingSkill6',
  'maxLivingSkill7',
  'maxLivingSkill8',
  'maxHp',
  'maxPower',
  'maxMana',
  'damage',
  'armor',
  'armorRate',
  'speed',
  'acc',
  'evade',
  'critRate',
  'antiCrit',
  'counter',
  'antiCounter',
  'comboRate',
  'antiCombo',
  'expRate',
  'recoverRate',
  'reduceReciveDamageRate',
  'addDebuffRate',
  'reduceDebuffRate',
  'woundResist',
  'clearMovePower',
  'recoverMovePower',
  'externalDamage',
  'internalDamage',
  'poisonDamage',
  'suckHp',
  'suckMana',
  'killMana',
  'recoverAll',
  'burn',
  'recoverHp',
  'bleed',
  'recoverMana',
  'elec',
  'recoverPower',
  'losePower',
  'frozen',
  'invincible',
  'stun',
  'hitHandPoint',
  'hitFootPoint',
  'hitChestPoint',
  'hitBackPoint',
  'hitHeadPoint',
  'reduceDamage',
  'addArmor',
  'reduceArmor',
  'addSpeed',
  'reduceSpeed',
  'addAcc',
  'reduceAcc',
  'addEvade',
  'reduceEvade',
  'reduceReciveDamage',
  'addReciveDamage',
  'crazy',
  'confusion',
  'deathFight',
  'minusArmor',
  'addAttri0',
  'reduceAttri0',
  'addAttri1',
  'reduceAttri1',
  'addAttri2',
  'reduceAttri2',
  'addAttri3',
  'reduceAttri3',
  'addAttri4',
  'reduceAttri4',
  'addAttri5',
  'reduceAttri5',
  'reborn',
  'backDamage',
  'backSuckMana',
  'backKillMana',
  'hitFar',
  'hitClose',
  'addCrit',
  'reduceCrit',
  'addAntiCrit',
  'reduceAntiCrit',
  'addBlock',
  'addAntiBlock',
  'addCombo',
  'reduceCombo',
  'addAntiCombo',
  'reduceAntiCombo',
  'addDamage',
  'addRecoverRate',
  'reduceRecoverRate',
  'addReduceDebuffRate',
  'reduceReduceDebuffRate',
  'internalTrueDamage',
  'trueDamage',
  'recoverHpPerRound',
  'recoverManaPerRound',
  'recoverPowerPerRound',
  'recoverWoundPerRound',
  'recoverPartPosture0',
  'recoverPartPosture1',
  'recoverPartPosture2',
  'recoverPartPosture3',
  'recoverPartPosture4',
  'recoverPartPosture5',
  'manaShield',
  'reboundDamage',
  'defenceDamage',
  'stopMove',
  'moveRange',
  'addMoveRange',
  'reduceMoveRange',
  'postureThrough',
  'postureBlock',
  'changeAttckTarget',
  'FameGainRate',
  'ContributionRate',
  'TravelSpeedRate',
  'CureWoundRate',
  'SkillFightExpRate',
  'SkillBookExpRate',
  'LivingSkillExpRate',
  'fightSkill0ExpRate',
  'fightSkill1ExpRate',
  'fightSkill2ExpRate',
  'fightSkill3ExpRate',
  'fightSkill4ExpRate',
  'fightSkill5ExpRate',
  'fightSkill6ExpRate',
  'fightSkill7ExpRate',
  'fightSkill8ExpRate',
  'livingSkill0ExpRate',
  'livingSkill1ExpRate',
  'livingSkill2ExpRate',
  'livingSkill3ExpRate',
  'livingSkill4ExpRate',
  'livingSkill5ExpRate',
  'livingSkill6ExpRate',
  'livingSkill7ExpRate',
  'livingSkill8ExpRate',
  'dealPriceRate',
  'fightSkillRange3',
  'fightSkillRange4',
  'fightSkillRange5',
  'fightSkillRange6',
  'fightSkillRange7',
  'fightSkillRange8',
  'horseAddAttri',
  'equipAddRate',
  'medResistReduce',
  'equipmentWeight',
  'summonDamage',
  'summonSpeed',
  'summonHp',
  'defenceBuildingHp',
  'favorRate',
  'selfForceSkillPower',
  'reduceBadFame'
] as const;

export type HeroSpeAddDataTypeName = typeof HERO_SPE_ADD_DATA_TYPE_NAMES[number];

export interface VisibleSettings {
  lockStamina: boolean;
  expMultiplier: number;
  battleSkillExpMultiplier: number;
  creationPointMultiplier: number;
  horseBaseSpeedMultiplier: number;
  horseTurboSpeedMultiplier: number;
  horseTurboDurationMultiplier: number;
  horseTurboCooldownMultiplier: number;
  lockHorseTurboStamina: boolean;
  horseStaminaMultiplier: number;
  carryWeightCap: number;
  ignoreCarryWeight: boolean;
  merchantCarryCash: number;
  treasureAutoTradeEnabled: boolean;
  luckyHitChancePercent: number;
  extraRelationshipGainChancePercent: number;
  teamAutoFavorEnabled: boolean;
  teamAutoFavorPerDay: number;
  maxLoverCount: number;
  debatePlayerDamageTakenMultiplier: number;
  debateEnemyDamageTakenMultiplier: number;
  craftRandomPickUpgrade: boolean;
  craftTier1ExtraItems: number;
  craftTier2ExtraItems: number;
  craftTier3ExtraItems: number;
  craftTier4ExtraItems: number;
  craftTier5ExtraItems: number;
  drinkPlayerPowerCostMultiplier: number;
  drinkEnemyPowerCostMultiplier: number;
  dialogMonthlyLimitMultiplier: number;
  dialogFastForwardAssistEnabled: boolean;
  dailySkillInsightChancePercent: number;
  dailySkillInsightExpPercent: number;
  dailySkillInsightUseRarityScaling: boolean;
  dailySkillInsightRealtimeIntervalSeconds: number;
  skillTalentEnabled: boolean;
  skillTalentLevelThreshold: number;
  skillTalentTierPointMultiplier: number;
  skillTalentPlayerOnly: boolean;
  freezeDate: boolean;
  freezeHotkey: string;
  outsideBattleSpeedHotkey: string;
  battleTurboEnabled: boolean;
  battleTurboHotkey: string;
}

export type CustomTalentConditionType = 'stat_min';

export interface CustomTalentCondition {
  type: CustomTalentConditionType;
  stat: BaseAttriTypeName;
  min: number;
}

export interface CustomTalentEffect {
  effectType: HeroSpeAddDataTypeName;
  value: number;
}

export interface CustomTalentDefinition {
  id: string;
  enabled: boolean;
  name: string;
  durationDays: number;
  conditions: CustomTalentCondition[];
  effects: CustomTalentEffect[];
}

export interface CustomTalentPack {
  version: typeof CUSTOM_TALENT_PACK_VERSION;
  talents: CustomTalentDefinition[];
}

export interface CustomTalentSaveResult {
  ok: boolean;
  message: string;
  pack: CustomTalentPack;
}

export interface UpdateManifest {
  version: string;
  zipAsset: string;
  sha256: string;
  preservePaths?: string[];
}

export interface UpdateReleaseAsset {
  name: string;
  browser_download_url: string;
  size: number;
}

export interface ReleaseHistoryItem {
  tagName: string;
  version: string;
  name: string;
  publishedAt?: string;
  body: string;
  htmlUrl?: string;
  isLatest: boolean;
}

export interface UpdateCheckResult {
  currentVersion: string;
  latestVersion: string;
  updateAvailable: boolean;
  releaseName?: string;
  publishedAt?: string;
  releaseBody?: string;
  releaseUrl?: string;
  manifest?: UpdateManifest;
  asset?: UpdateReleaseAsset;
  assetUrl?: string;
  status?: string;
}

export type LogFileKind = 'startup' | 'ota';

export interface UpdateProgressEvent {
  stage: 'checking' | 'downloading' | 'preparing' | 'applying' | 'complete' | 'error';
  detail: string;
  percent?: number;
  timestamp: string;
}

export interface HealthCheckResult {
  key: string;
  label: string;
  ok: boolean;
  detail: string;
}

export interface GameHealth {
  healthy: boolean;
  needsRepair: boolean;
  summary: string;
  driftedFiles: string[];
  checks: HealthCheckResult[];
}

export interface GameSnapshot {
  appVersion: string;
  payloadRoot: string;
  userDataRoot: string;
  startupLogPath: string;
  otaLogPath: string;
  gameRoot?: string;
  gameRootDetected: boolean;
  gameInstalled: boolean;
  health: GameHealth;
  gameRunning: boolean;
  launchReady: boolean;
  launchState: 'idle' | 'starting' | 'running';
  launchNote: string;
  visibleSettings: VisibleSettings;
  status: string;
  update: UpdateCheckResult;
}

export interface OperationResult {
  ok: boolean;
  message: string;
  gameRoot?: string;
  updatedSnapshot?: GameSnapshot;
}
