import { app, BrowserWindow, dialog, ipcMain, shell } from 'electron';
import path from 'node:path';
import fs from 'node:fs/promises';
import { execFile, spawn } from 'node:child_process';
import { promisify } from 'node:util';
import {
  ensureBepInExConsoleDisabled,
  ensureDoorstopEnabled,
  ensureGameFiles,
  ensureSteamAppId,
  getGamePaths,
  inspectGameHealth,
  readCustomTalentPack,
  readVisibleSettings,
  saveCustomTalentPack,
  saveVisibleSettings
} from './shared/config';
import { detectSteamGameRoot, isValidGameRoot } from './shared/steam';
import { installOwnedPayload, uninstallOwnedPayload } from './shared/payload';
import {
  checkGitHubRelease,
  fetchReleaseHistory,
  launchUpdaterApp,
  stageGitHubUpdate
} from './shared/updates';
import {
  APP_FOLDER_NAME,
  CustomTalentPack,
  CustomTalentSaveResult,
  GAME_EXE_NAME,
  GameHealth,
  GameSnapshot,
  LauncherPreferences,
  LogFileKind,
  OperationResult,
  ReleaseHistoryItem,
  SaveAndLaunchRequest,
  UpdateCheckResult,
  UpdateProgressEvent,
  VisibleSettings
} from './shared/types';

const execFileAsync = promisify(execFile);
const LAUNCH_GRACE_MS = 30_000;

const IS_PACKAGED = app.isPackaged;
const APP_ROOT = IS_PACKAGED ? path.dirname(process.execPath) : path.resolve(__dirname, '..', '..');
const APP_CONTENT_ROOT = IS_PACKAGED ? app.getAppPath() : path.resolve(__dirname, '..', '..');
const PAYLOAD_ROOT =
  process.env.LONGYIN_PAYLOAD_ROOT ??
  (IS_PACKAGED ? path.join(process.resourcesPath, 'payload') : path.resolve(APP_CONTENT_ROOT, '..', 'dist'));
const USER_DATA_ROOT = process.env.LONGYIN_USER_DATA_ROOT ?? path.join(APP_ROOT, 'user-data');
const SETTINGS_PATH = path.join(USER_DATA_ROOT, 'settings.json');
const STARTUP_LOG_PATH = path.join(USER_DATA_ROOT, 'startup.log');
const OTA_LOG_PATH = path.join(USER_DATA_ROOT, 'ota-update.log');
const OTA_COMPLETION_PATH = path.join(USER_DATA_ROOT, 'ota-update-complete.json');
const OTA_UPDATER_PATH = IS_PACKAGED
  ? path.join(process.resourcesPath, 'updater', 'LongYinUpdater.exe')
  : path.resolve(APP_CONTENT_ROOT, 'updater-dist', 'LongYinUpdater.exe');
const OVERLAY_EXE_NAME = 'LongYinOverlay.exe';

const DEFAULT_VISIBLE_SETTINGS: VisibleSettings = {
  lockStamina: true,
  revealAllOnStepTile: false,
  expMultiplier: 1,
  battleSkillExpMultiplier: 1,
  creationPointMultiplier: 1,
  horseBaseSpeedMultiplier: 1,
  horseTurboSpeedMultiplier: 1,
  horseTurboDurationMultiplier: 1,
  horseTurboCooldownMultiplier: 1,
  lockHorseTurboStamina: true,
  horseStaminaMultiplier: 1,
  carryWeightCap: 100000,
  ignoreCarryWeight: false,
  merchantCarryCash: 100000,
  treasureTradeHelperEnabled: true,
  treasureAutoTradeEnabled: true,
  materialAutoBuyEnabled: true,
  materialPurchaseMinRareLv: 0,
  materialPurchaseMinItemLv: 0,
  shopOwnershipEnabled: true,
  auctionEventAlwaysRedEnabled: true,
  auctionPreviewRefreshEnabled: true,
  auctionPreviewRefreshHotkey: 'R',
  auctionPreviewRefreshRequireAlt: true,
  treasureIdentifyBestValueAssistEnabled: true,
  treasureIdentifyBestValueHotkey: 'F',
  treasureIdentifyBestValueRequireAlt: true,
  luckyHitChancePercent: 0,
  extraRelationshipGainChancePercent: 0,
  teamAutoFavorEnabled: true,
  teamAutoFavorPerDay: 5,
  maxLoverCount: 8,
  debatePlayerDamageTakenMultiplier: 1,
  debateEnemyDamageTakenMultiplier: 1,
  craftRandomPickUpgrade: true,
  craftTier1ExtraItems: 0,
  craftTier2ExtraItems: 1,
  craftTier3ExtraItems: 2,
  craftTier4ExtraItems: 3,
  craftTier5ExtraItems: 4,
  drinkPlayerPowerCostMultiplier: 1,
  drinkEnemyPowerCostMultiplier: 1,
  dialogMonthlyLimitMultiplier: 3,
  dialogFastForwardAssistEnabled: false,
  dailySkillInsightChancePercent: 0,
  dailySkillInsightExpPercent: 5,
  dailySkillInsightUseRarityScaling: true,
  dailySkillInsightRealtimeIntervalSeconds: 0,
  skillTalentEnabled: true,
  skillTalentLevelThreshold: 10,
  skillTalentTierPointMultiplier: 2,
  skillTalentPlayerOnly: true,
  freezeDate: false,
  freezeHotkey: 'F1',
  outsideBattleSpeedHotkey: 'F11',
  battleTurboEnabled: true,
  battleTurboHotkey: 'F8'
};

type AppSettings = {
  gameRoot?: string;
  launchOverlayWithGame?: boolean;
};

const DEFAULT_LAUNCHER_PREFERENCES: LauncherPreferences = {
  launchOverlayWithGame: false
};

let mainWindow: BrowserWindow | null = null;
let cachedGameRoot: string | undefined;
let cachedUpdate: UpdateCheckResult = {
  currentVersion: app.getVersion(),
  latestVersion: app.getVersion(),
  updateAvailable: false,
  status: '更新检查尚未运行。'
};
let cachedReleaseHistory: ReleaseHistoryItem[] = [];
let lastLaunchAt = 0;
let overlayChild: ReturnType<typeof spawn> | null = null;
let overlayStartedForGame = false;
let gameLifecycleMonitor: Promise<void> | null = null;

function createEmptyHealth(summary: string): GameHealth {
  return {
    healthy: false,
    needsRepair: false,
    launchBlocked: false,
    summary,
    driftedFiles: [],
    checks: []
  };
}

async function writeStartupLog(message: string): Promise<void> {
  const line = `[${new Date().toISOString()}] ${message}\n`;
  await fs.mkdir(USER_DATA_ROOT, { recursive: true });
  await fs.appendFile(STARTUP_LOG_PATH, line, 'utf8').catch(() => undefined);
}

async function appendLog(filePath: string, message: string): Promise<void> {
  const line = `[${new Date().toISOString()}] ${message}\n`;
  await fs.mkdir(path.dirname(filePath), { recursive: true });
  await fs.appendFile(filePath, line, 'utf8').catch(() => undefined);
}

function emitUpdateProgress(stage: UpdateProgressEvent['stage'], detail: string, percent?: number): void {
  const payload: UpdateProgressEvent = {
    stage,
    detail,
    percent,
    timestamp: new Date().toISOString()
  };

  void writeStartupLog(`[UpdateProgress][${stage}] ${detail}`);
  if (stage === 'applying' || stage === 'complete' || stage === 'error') {
    void appendLog(OTA_LOG_PATH, `[${stage}] ${detail}`);
  }

  mainWindow?.webContents.send('app:update-progress', payload);
}

async function readLogFile(kind: LogFileKind): Promise<string> {
  const targetPath = kind === 'ota' ? OTA_LOG_PATH : STARTUP_LOG_PATH;

  try {
    const text = await fs.readFile(targetPath, 'utf8');
    const normalized = text.replace(/\r\n/g, '\n').trim();
    if (!normalized) {
      return '日志文件已存在，但当前没有内容。';
    }

    return normalized.split('\n').slice(-160).join('\n');
  }
  catch {
    return `尚未生成 ${kind === 'ota' ? 'ota-update.log' : 'startup.log'}。`;
  }
}

async function ensureAppDirectories(): Promise<void> {
  await fs.mkdir(USER_DATA_ROOT, { recursive: true });
}

async function consumeUpdateCompletion(): Promise<void> {
  const raw = await fs.readFile(OTA_COMPLETION_PATH, 'utf8').catch(() => undefined);
  if (!raw) {
    return;
  }

  try {
    const marker = JSON.parse(raw) as { version?: unknown; completedAtUtc?: unknown };
    const version = typeof marker.version === 'string' && marker.version.trim()
      ? marker.version.trim()
      : app.getVersion();
    await fs.rm(OTA_COMPLETION_PATH, { force: true });
    emitUpdateProgress('complete', `更新 ${version} 已完成并通过后台替换流程，应用已重新启动。`, 100);
  }
  catch (error) {
    const detail = error instanceof Error ? error.message : String(error);
    await writeStartupLog(`OTA 完成标记无效：${detail}`);
    await fs.rm(OTA_COMPLETION_PATH, { force: true });
  }
}

async function isGameProcessRunning(): Promise<boolean> {
  if (process.platform !== 'win32') {
    return false;
  }

  try {
    const { stdout } = await execFileAsync('tasklist', ['/FI', `IMAGENAME eq ${GAME_EXE_NAME}`, '/FO', 'CSV', '/NH']);
    return stdout.toLowerCase().includes(GAME_EXE_NAME.toLowerCase());
  }
  catch (error) {
    const detail = error instanceof Error ? error.message : String(error);
    throw new Error(`无法确认游戏进程状态；为避免运行中改写文件，已停止操作。${detail}`);
  }
}

async function isProcessRunning(imageName: string): Promise<boolean> {
  if (process.platform !== 'win32') {
    return false;
  }

  try {
    const { stdout } = await execFileAsync('tasklist', ['/FI', `IMAGENAME eq ${imageName}`, '/FO', 'CSV', '/NH']);
    return stdout.toLowerCase().includes(imageName.toLowerCase());
  }
  catch (error) {
    const detail = error instanceof Error ? error.message : String(error);
    throw new Error(`无法确认 ${imageName} 进程状态；已停止操作。${detail}`);
  }
}

async function getLauncherPreferences(): Promise<LauncherPreferences> {
  const settings = await readSettings();
  return {
    launchOverlayWithGame: settings.launchOverlayWithGame ?? DEFAULT_LAUNCHER_PREFERENCES.launchOverlayWithGame
  };
}

async function ensureGameStopped(actionLabel: string): Promise<void> {
  if (await isGameProcessRunning()) {
    throw new Error(`检测到游戏正在运行。请先关闭游戏，再执行“${actionLabel}”。`);
  }
}

function getOverlayExecutablePath(gameRoot: string): string {
  return path.join(gameRoot, 'LongYinOverlay', OVERLAY_EXE_NAME);
}

async function startOverlay(gameRoot: string, forGame = false): Promise<{ started: boolean; message: string }> {
  if (await isProcessRunning(OVERLAY_EXE_NAME)) {
    return { started: false, message: 'Overlay 已在运行，未重复启动。' };
  }

  const overlayExePath = getOverlayExecutablePath(gameRoot);
  const overlayStat = await fs.stat(overlayExePath).catch(() => undefined);
  if (!overlayStat?.isFile()) {
    throw new Error(`未找到游戏目录内的 Overlay 可执行文件：${overlayExePath}`);
  }

  const child = spawn(overlayExePath, [], {
    cwd: path.dirname(overlayExePath),
    detached: true,
    stdio: 'ignore'
  });
  overlayChild = child;
  overlayStartedForGame = forGame;
  await new Promise<void>((resolve, reject) => {
    child.once('spawn', resolve);
    child.once('error', reject);
  }).catch((error) => {
    overlayChild = null;
    overlayStartedForGame = false;
    throw error;
  });
  child.once('exit', () => {
    if (overlayChild?.pid === child.pid) {
      overlayChild = null;
      overlayStartedForGame = false;
    }
  });
  child.unref();
  await writeStartupLog(`已启动 Overlay，PID=${child.pid ?? 'unknown'}${forGame ? '（随游戏启动）' : ''}。`);
  return { started: true, message: 'Overlay 已启动。' };
}

async function stopOverlay(includeUnowned = false): Promise<{ stopped: boolean; message: string }> {
  const ownedPid = overlayChild?.pid;
  if (!ownedPid && !includeUnowned) {
    return { stopped: false, message: '没有需要随游戏关闭的 Overlay 实例。' };
  }

  if (process.platform === 'win32') {
    const args = ownedPid ? ['/PID', String(ownedPid), '/T', '/F'] : ['/IM', OVERLAY_EXE_NAME, '/T', '/F'];
    await execFileAsync('taskkill', args).catch(() => undefined);
  }
  else if (overlayChild) {
    overlayChild.kill();
  }

  overlayChild = null;
  overlayStartedForGame = false;
  const stillRunning = await isProcessRunning(OVERLAY_EXE_NAME);
  await writeStartupLog(stillRunning ? 'Overlay 关闭请求已发送，但进程仍在运行。' : 'Overlay 已关闭。');
  return stillRunning
    ? { stopped: false, message: 'Overlay 仍在运行，请稍后重试。' }
    : { stopped: true, message: 'Overlay 已关闭。' };
}

function delay(milliseconds: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

async function monitorGameExitAndCleanup(launchStartedAt: number): Promise<void> {
  let observedRunning = false;
  try {
    while (overlayStartedForGame) {
      try {
        const running = await isGameProcessRunning();
        if (running) {
          observedRunning = true;
        }
        else if (observedRunning || Date.now() - launchStartedAt >= LAUNCH_GRACE_MS) {
          break;
        }
      }
      catch (error) {
        await writeStartupLog(`游戏退出监视暂时无法读取进程状态：${error instanceof Error ? error.message : String(error)}`);
      }
      await delay(2_000);
    }

    if (overlayStartedForGame) {
      await stopOverlay(false);
    }
  }
  finally {
    gameLifecycleMonitor = null;
    if (BrowserWindow.getAllWindows().length === 0 && process.platform !== 'darwin') {
      app.quit();
    }
  }
}

function getLaunchState(gameRunning: boolean): {
  launchReady: boolean;
  launchState: 'idle' | 'starting' | 'running';
  launchNote: string;
} {
  const withinGrace = lastLaunchAt > 0 && Date.now() - lastLaunchAt < LAUNCH_GRACE_MS;

  if (withinGrace) {
    return {
      launchReady: false,
      launchState: 'starting',
      launchNote: '游戏正在启动中。BepInEx 首次注入通常需要 10 到 20 秒，请不要重复点击。'
    };
  }

  if (gameRunning) {
    return {
      launchReady: false,
      launchState: 'running',
      launchNote: '检测到游戏进程正在运行。如窗口尚未出现，请稍等片刻。'
    };
  }

  return {
    launchReady: true,
    launchState: 'idle',
    launchNote: '可以安全启动。首次加载模组时，游戏窗口可能会延迟 10 到 20 秒出现。'
  };
}

async function readSettings(): Promise<AppSettings> {
  try {
    const raw = await fs.readFile(SETTINGS_PATH, 'utf8');
    return JSON.parse(raw) as AppSettings;
  }
  catch {
    return {};
  }
}

async function writeSettings(nextSettings: AppSettings): Promise<void> {
  await fs.mkdir(path.dirname(SETTINGS_PATH), { recursive: true });
  const currentSettings = await readSettings();
  await fs.writeFile(SETTINGS_PATH, `${JSON.stringify({ ...currentSettings, ...nextSettings }, null, 2)}\n`, 'utf8');
}

async function inferInstalledGameRoot(): Promise<string | undefined> {
  const candidates = [
    process.env.LONGYIN_GAME_ROOT,
    IS_PACKAGED && path.basename(APP_ROOT).toLowerCase() === APP_FOLDER_NAME.toLowerCase()
      ? path.resolve(APP_ROOT, '..')
      : undefined,
    APP_ROOT
  ];

  for (const candidate of candidates) {
    if (!candidate) {
      continue;
    }

    if (await isValidGameRoot(candidate)) {
      return candidate;
    }
  }

  return undefined;
}

async function loadGameRoot(): Promise<string | undefined> {
  const settings = await readSettings();
  if (settings.gameRoot && (await isValidGameRoot(settings.gameRoot))) {
    return settings.gameRoot;
  }

  const installed = await inferInstalledGameRoot();
  if (installed) {
    await writeSettings({ gameRoot: installed });
    return installed;
  }

  const detected = await detectSteamGameRoot();
  if (detected) {
    await writeSettings({ gameRoot: detected });
    return detected;
  }

  return undefined;
}

async function selectGameRoot(): Promise<string | undefined> {
  const result = mainWindow
    ? await dialog.showOpenDialog(mainWindow, {
        title: '请选择包含 LongYinLiZhiZhuan.exe 的游戏目录',
        properties: ['openDirectory']
      })
    : await dialog.showOpenDialog({
      title: '请选择包含 LongYinLiZhiZhuan.exe 的游戏目录',
      properties: ['openDirectory']
    });

  if (result.canceled || result.filePaths.length === 0) {
    return undefined;
  }

  const candidate = result.filePaths[0];
  if (!(await isValidGameRoot(candidate))) {
    await dialog.showErrorBox('目录无效', `该目录不包含 ${GAME_EXE_NAME}。`);
    return undefined;
  }

  await writeSettings({ gameRoot: candidate });
  return candidate;
}

async function isGameInstalled(gameRoot: string): Promise<boolean> {
  const health = await inspectGameHealth(gameRoot, PAYLOAD_ROOT);
  return !health.needsRepair;
}

async function repairGameInstallationIfNeeded(
  gameRoot: string,
  actionLabel: string
): Promise<{ repaired: boolean; health: GameHealth }> {
  const currentHealth = await inspectGameHealth(gameRoot, PAYLOAD_ROOT);
  if (!currentHealth.needsRepair) {
    return { repaired: false, health: currentHealth };
  }

  const repairedHealth = await installPayload(gameRoot, actionLabel);

  return { repaired: true, health: repairedHealth };
}

async function installPayload(gameRoot: string, actionLabel = '安装或修复模组'): Promise<GameHealth> {
  await ensureGameStopped(actionLabel);
  const payloadExists = await fs.stat(PAYLOAD_ROOT).then((stat) => stat.isDirectory()).catch(() => false);
  if (!payloadExists) {
    throw new Error(`未找到模组载荷目录：${PAYLOAD_ROOT}`);
  }

  await installOwnedPayload(gameRoot, PAYLOAD_ROOT);
  await ensureGameFiles(gameRoot);
  await ensureDoorstopEnabled(gameRoot);
  await ensureSteamAppId(gameRoot);

  const health = await inspectGameHealth(gameRoot, PAYLOAD_ROOT);
  if (health.needsRepair) {
    throw new Error(`安装后仍未通过自检：${health.summary}`);
  }
  return health;
}

async function uninstallPayload(gameRoot: string): Promise<void> {
  await ensureGameStopped('卸载模组');
  const uninstallResult = await uninstallOwnedPayload(gameRoot, PAYLOAD_ROOT);

  const steamAppIdPath = path.join(gameRoot, 'steam_appid.txt');
  const backupPath = `${steamAppIdPath}.bak`;
  if (!uninstallResult.usedManifest && await fs.stat(backupPath).then(() => true).catch(() => false)) {
    await fs.copyFile(backupPath, steamAppIdPath);
    await fs.rm(backupPath, { force: true });
  }
}

async function launchGame(gameRoot: string): Promise<void> {
  const paths = getGamePaths(gameRoot);
  const repairResult = await repairGameInstallationIfNeeded(gameRoot, '启动游戏');
  if (repairResult.health.needsRepair) {
    throw new Error(repairResult.health.summary);
  }
  if (repairResult.health.launchBlocked) {
    throw new Error(`当前插件运行日志包含阻断性兼容错误：${repairResult.health.summary}`);
  }

  const gameRunning = await isGameProcessRunning();
  const launchState = getLaunchState(gameRunning);
  if (launchState.launchState !== 'idle') {
    throw new Error(launchState.launchNote);
  }

  await ensureBepInExConsoleDisabled(gameRoot);

  await fs.stat(paths.gameExePath).catch(() => {
    throw new Error(`未找到游戏可执行文件：${paths.gameExePath}`);
  });
  await writeStartupLog(`准备启动游戏：${paths.gameExePath}`);

  const launcherPreferences = await getLauncherPreferences();
  if (launcherPreferences.launchOverlayWithGame) {
    const overlayResult = await startOverlay(gameRoot, true);
    await writeStartupLog(overlayResult.message);
  }

  const child = spawn(paths.gameExePath, [], {
    cwd: gameRoot,
    detached: true,
    stdio: 'ignore'
  });
  await new Promise<void>((resolve, reject) => {
    child.once('spawn', resolve);
    child.once('error', reject);
  }).catch(async (error) => {
    if (overlayStartedForGame) {
      await stopOverlay(false);
    }
    throw error;
  });
  child.unref();
  await writeStartupLog(`已发送游戏启动请求，PID=${child.pid ?? 'unknown'}`);
  lastLaunchAt = Date.now();
  if (overlayStartedForGame && !gameLifecycleMonitor) {
    gameLifecycleMonitor = monitorGameExitAndCleanup(lastLaunchAt).catch(async (error) => {
      await writeStartupLog(`游戏退出后的 Overlay 清理失败：${error instanceof Error ? error.message : String(error)}`);
    });
  }
}

async function buildSnapshot(status = '准备就绪'): Promise<GameSnapshot> {
  const gameRoot = cachedGameRoot ?? (await loadGameRoot());
  cachedGameRoot = gameRoot;

  let visibleSettings = { ...DEFAULT_VISIBLE_SETTINGS };
  let gameInstalled = false;
  let health = createEmptyHealth(gameRoot ? '尚未检查安装状态。' : '未选择游戏目录。');
  const gameRunning = await isGameProcessRunning();
  const launchState = getLaunchState(gameRunning);
  const launcherPreferences = await getLauncherPreferences();
  const overlayRunning = await isProcessRunning(OVERLAY_EXE_NAME);

  if (gameRoot) {
    visibleSettings = await readVisibleSettings(gameRoot);
    health = await inspectGameHealth(gameRoot, PAYLOAD_ROOT);
    gameInstalled = !health.needsRepair;
  }

  const effectiveStatus = status === '准备就绪' && gameRoot && !health.healthy ? health.summary : status;

  return {
    appVersion: app.getVersion(),
    payloadRoot: PAYLOAD_ROOT,
    userDataRoot: USER_DATA_ROOT,
    startupLogPath: STARTUP_LOG_PATH,
    otaLogPath: OTA_LOG_PATH,
    gameRoot,
    gameRootDetected: Boolean(gameRoot),
    gameInstalled,
    health,
    gameRunning,
    launchReady: Boolean(gameRoot) && gameInstalled && !health.launchBlocked && launchState.launchReady,
    launchState: launchState.launchState,
    launchNote: launchState.launchNote,
    visibleSettings,
    launcherPreferences,
    overlayRunning,
    status: effectiveStatus,
    update: cachedUpdate
  };
}

type SavedPathState = {
  originalPath: string;
  backupPath: string;
  kind: 'absent' | 'file' | 'directory';
};

async function getSavedPathKind(filePath: string): Promise<SavedPathState['kind']> {
  try {
    const stat = await fs.stat(filePath);
    if (stat.isFile()) {
      return 'file';
    }
    if (stat.isDirectory()) {
      return 'directory';
    }
    throw new Error(`不支持备份此文件类型：${filePath}`);
  }
  catch (error) {
    const code = (error as NodeJS.ErrnoException).code;
    if (code === 'ENOENT' || code === 'ENOTDIR') {
      return 'absent';
    }
    throw error;
  }
}

async function beginSettingsTransaction(gameRoot: string): Promise<{
  commit: () => Promise<void>;
  rollback: () => Promise<void>;
}> {
  const paths = getGamePaths(gameRoot);
  const protectedPaths = [
    paths.mainConfigPath,
    paths.horseConfigPath,
    paths.questSnapshotConfigPath,
    paths.skillConfigPath,
    paths.battleConfigPath,
    paths.customTalentConfigPath,
    paths.steamAppIdPath,
    `${paths.steamAppIdPath}.bak`,
    paths.doorstopConfigPath,
    paths.legacyTraceConfigPath,
    paths.legacySkillConfigPath,
    ...[
      'LaunchGame.cmd',
      'LongYinModControl.cmd',
      'LongYinModControl.ps1',
      'Play.cmd',
      'RecoverGameWindow.cmd',
      'RecoverGameWindow.ps1',
      'BepInEx/plugins/LongYinGameplayTest.dll',
      'BepInEx/plugins/LongYinMoneyProbe.dll.disabled',
      'BepInEx/plugins/LongYinTraceData.dll',
      'BepInEx/plugins/LongYinSkillTalentTracer.dll',
      'BepInEx/config/codex.longyin.gameplaytest.cfg',
      'BepInEx/config/codex.longyin.moneyprobe.cfg.disabled'
    ].map((relativePath) => path.join(gameRoot, ...relativePath.split('/')))
  ];
  const transactionBase = path.join(USER_DATA_ROOT, 'save-transactions');
  await fs.mkdir(transactionBase, { recursive: true });
  const transactionRoot = await fs.mkdtemp(path.join(transactionBase, 'save-and-launch-'));
  const states: SavedPathState[] = [];

  for (const [index, originalPath] of protectedPaths.entries()) {
    const kind = await getSavedPathKind(originalPath);
    const backupPath = path.join(transactionRoot, 'files', String(index));
    if (kind !== 'absent') {
      await fs.mkdir(path.dirname(backupPath), { recursive: true });
      if (kind === 'file') {
        await fs.copyFile(originalPath, backupPath);
      }
      else {
        await fs.cp(originalPath, backupPath, { recursive: true });
      }
    }
    states.push({ originalPath, backupPath, kind });
  }

  return {
    commit: async () => {
      await fs.rm(transactionRoot, { recursive: true, force: true }).catch(() => undefined);
    },
    rollback: async () => {
      const failures: string[] = [];
      for (const state of [...states].reverse()) {
        try {
          await fs.rm(state.originalPath, { recursive: true, force: true }).catch((error: NodeJS.ErrnoException) => {
            if (error.code !== 'ENOENT' && error.code !== 'ENOTDIR') {
              throw error;
            }
          });
          if (state.kind !== 'absent') {
            await fs.mkdir(path.dirname(state.originalPath), { recursive: true });
            if (state.kind === 'file') {
              await fs.copyFile(state.backupPath, state.originalPath);
            }
            else {
              await fs.cp(state.backupPath, state.originalPath, { recursive: true });
            }
          }
        }
        catch (error) {
          failures.push(`${state.originalPath}: ${error instanceof Error ? error.message : String(error)}`);
        }
      }

      if (failures.length > 0) {
        throw new Error(`设置事务回滚未完全成功；恢复副本保留在 ${transactionRoot}。${failures.join('；')}`);
      }
      await fs.rm(transactionRoot, { recursive: true, force: true });
    }
  };
}

async function saveSettingsAndRefresh(settings: VisibleSettings): Promise<GameSnapshot> {
  const gameRoot = cachedGameRoot ?? (await loadGameRoot());
  if (!gameRoot) {
    throw new Error('请先选择游戏目录。');
  }

  const repairResult = await repairGameInstallationIfNeeded(gameRoot, '保存设置');
  await saveVisibleSettings(gameRoot, settings);
  return buildSnapshot(repairResult.repaired ? '已自动修复载荷漂移，并保存设置。' : '设置已保存。');
}

async function getCustomTalents(): Promise<CustomTalentPack> {
  const gameRoot = cachedGameRoot ?? (await loadGameRoot());
  if (!gameRoot) {
    throw new Error('请先选择游戏目录。');
  }

  cachedGameRoot = gameRoot;
  return readCustomTalentPack(gameRoot);
}

async function saveCustomTalents(pack: CustomTalentPack): Promise<CustomTalentSaveResult> {
  const gameRoot = cachedGameRoot ?? (await loadGameRoot());
  if (!gameRoot) {
    throw new Error('请先选择游戏目录。');
  }

  cachedGameRoot = gameRoot;
  const verified = await saveCustomTalentPack(gameRoot, pack);
  return {
    ok: true,
    message: '自定义天赋已写入配置文件，下次启动游戏生效。',
    pack: verified
  };
}

async function checkUpdates(): Promise<UpdateCheckResult> {
  await writeStartupLog('开始检查更新。');
  cachedUpdate = await checkGitHubRelease(app.getVersion()).catch((error: Error) => ({
    currentVersion: app.getVersion(),
    latestVersion: app.getVersion(),
    updateAvailable: false,
    status: `更新检查失败：${error.message}`
  }));
  await writeStartupLog(`更新检查完成：${cachedUpdate.status ?? '无状态'}`);
  return cachedUpdate;
}

async function getReleaseHistory(): Promise<ReleaseHistoryItem[]> {
  await writeStartupLog('开始拉取更新历史。');
  cachedReleaseHistory = await fetchReleaseHistory().catch(async (error: Error) => {
    await writeStartupLog(`更新历史拉取失败：${error.message}`);
    return cachedReleaseHistory;
  });
  await writeStartupLog(`更新历史拉取完成：${cachedReleaseHistory.length} 条。`);
  return cachedReleaseHistory;
}

async function applyUpdate(): Promise<OperationResult> {
  emitUpdateProgress('checking', '正在检查是否有新版本...', 0);

  try {
    const update = await checkUpdates();
    if (!update.updateAvailable || !update.manifest || !update.assetUrl) {
      throw new Error(update.status ?? '暂无可用更新。');
    }

    emitUpdateProgress('checking', `发现新版本 ${update.latestVersion}，准备下载更新包...`, 5);
    await writeStartupLog(`开始应用 OTA 更新：${update.currentVersion} -> ${update.latestVersion}`);
    const { stageRoot } = await stageGitHubUpdate(
      update.manifest,
      update.assetUrl,
      (detail, percent) => {
        emitUpdateProgress('downloading', detail, percent);
      }
    );
    await writeStartupLog(`OTA 暂存目录：${stageRoot}`);
    emitUpdateProgress('preparing', '下载和解压已完成，正在启动后台替换程序...', 100);
    await launchUpdaterApp(
      OTA_UPDATER_PATH,
      process.pid,
      stageRoot,
      APP_ROOT,
      path.basename(process.execPath),
      OTA_LOG_PATH,
      update.latestVersion
    );
    emitUpdateProgress('applying', '后台更新器已启动，应用即将退出并自动重启。', 100);
    const result: OperationResult = {
      ok: true,
      message: '更新包已下载。应用将退出，后台完成替换后会自动重启。',
      updatedSnapshot: await buildSnapshot('正在下载并应用更新，请等待自动重启。')
    };
    emitUpdateProgress('applying', '更新包已准备完成，正在退出并交给后台更新器；最终结果将在重启后确认。', 100);
    void setTimeout(() => app.quit(), 750);
    return result;
  }
  catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    emitUpdateProgress('error', `应用更新失败：${message}`);
    throw error;
  }
}

async function setGameRoot(nextGameRoot: string): Promise<GameSnapshot> {
  if (!(await isValidGameRoot(nextGameRoot))) {
    throw new Error(`该目录不包含 ${GAME_EXE_NAME}。`);
  }

  cachedGameRoot = nextGameRoot;
  await writeSettings({ gameRoot: nextGameRoot });
  return buildSnapshot('游戏目录已更新。');
}

function registerIpc(): void {
  ipcMain.handle('app:get-snapshot', async () => buildSnapshot());
  ipcMain.handle('app:pick-game-root', async () => {
    const selected = await selectGameRoot();
    if (selected) {
      cachedGameRoot = selected;
      return buildSnapshot('游戏目录已选择。');
    }

    return buildSnapshot('未发生更改。');
  });
  ipcMain.handle('app:set-game-root', async (_event, nextGameRoot: string) => setGameRoot(nextGameRoot));
  ipcMain.handle('app:save-settings', async (_event, settings: VisibleSettings) => saveSettingsAndRefresh(settings));
  ipcMain.handle('app:get-custom-talents', async () => getCustomTalents());
  ipcMain.handle('app:save-custom-talents', async (_event, pack: CustomTalentPack) => saveCustomTalents(pack));
  ipcMain.handle('app:set-launcher-preferences', async (_event, preferences: LauncherPreferences) => {
    await writeSettings({ launchOverlayWithGame: Boolean(preferences.launchOverlayWithGame) });
    return buildSnapshot('启动器设置已保存。');
  });
  ipcMain.handle('app:start-overlay', async () => {
    const gameRoot = cachedGameRoot ?? (await loadGameRoot());
    if (!gameRoot || !(await isValidGameRoot(gameRoot))) {
      throw new Error('请先选择有效的游戏目录，再启动 Overlay。');
    }
    const result = await startOverlay(gameRoot, false);
    return {
      ok: true,
      message: result.message,
      updatedSnapshot: await buildSnapshot(result.message)
    } satisfies OperationResult;
  });
  ipcMain.handle('app:stop-overlay', async () => {
    const result = await stopOverlay(true);
    return {
      ok: result.stopped,
      message: result.message,
      updatedSnapshot: await buildSnapshot(result.message)
    } satisfies OperationResult;
  });
  ipcMain.handle('app:install', async () => {
    const gameRoot = cachedGameRoot ?? (await loadGameRoot());
    if (!gameRoot) {
      throw new Error('请先选择游戏目录。');
    }

    await installPayload(gameRoot, '安装模组');
    return {
      ok: true,
      message: '模组载荷已安装，并已完成自检。',
      gameRoot,
      updatedSnapshot: await buildSnapshot('已安装并完成自检。')
    } satisfies OperationResult;
  });
  ipcMain.handle('app:uninstall', async () => {
    const gameRoot = cachedGameRoot ?? (await loadGameRoot());
    if (!gameRoot) {
      throw new Error('请先选择游戏目录。');
    }

    await uninstallPayload(gameRoot);
    return {
      ok: true,
      message: '模组载荷已卸载。',
      gameRoot,
      updatedSnapshot: await buildSnapshot('已卸载。')
    } satisfies OperationResult;
  });
  ipcMain.handle('app:launch', async () => {
    const gameRoot = cachedGameRoot ?? (await loadGameRoot());
    if (!gameRoot) {
      throw new Error('请先选择游戏目录。');
    }

    await launchGame(gameRoot);
    return {
      ok: true,
      message: '已发送启动请求。BepInEx 载入可能需要 10 到 20 秒，请不要重复点击。',
      gameRoot,
      updatedSnapshot: await buildSnapshot('启动中。')
    } satisfies OperationResult;
  });
  ipcMain.handle('app:save-and-launch', async (_event, request: SaveAndLaunchRequest) => {
    const gameRoot = cachedGameRoot ?? (await loadGameRoot());
    if (!gameRoot) {
      throw new Error('请先选择游戏目录。');
    }

    await ensureGameStopped('保存设置并启动游戏');
    const repairResult = await repairGameInstallationIfNeeded(gameRoot, '保存设置并启动游戏');
    await ensureGameStopped('保存设置并启动游戏');

    const transaction = await beginSettingsTransaction(gameRoot);
    let savedTalents: CustomTalentPack;
    try {
      await saveVisibleSettings(gameRoot, request.settings);
      savedTalents = await saveCustomTalentPack(gameRoot, request.customTalents);
    }
    catch (error) {
      try {
        await transaction.rollback();
      }
      catch (rollbackError) {
        const originalMessage = error instanceof Error ? error.message : String(error);
        const rollbackMessage = rollbackError instanceof Error ? rollbackError.message : String(rollbackError);
        throw new Error(`设置和自定义天赋保存失败：${originalMessage}；${rollbackMessage}`);
      }
      const message = error instanceof Error ? error.message : String(error);
      throw new Error(`设置和自定义天赋保存失败，已回滚至写入前状态。${message}`);
    }
    await transaction.commit();

    await launchGame(gameRoot);
    return {
      ok: true,
      message: `设置和 ${savedTalents.talents.length} 个自定义天赋已保存，并已发送启动请求。BepInEx 载入可能需要 10 到 20 秒。`,
      gameRoot,
      customTalents: savedTalents,
      updatedSnapshot: await buildSnapshot(repairResult.repaired ? '已自动修复载荷漂移、保存设置并启动。' : '启动中。')
    } satisfies OperationResult;
  });
  ipcMain.handle('app:check-updates', async () => checkUpdates());
  ipcMain.handle('app:get-release-history', async () => getReleaseHistory());
  ipcMain.handle('app:apply-update', async () => applyUpdate());
  ipcMain.handle('app:read-log-file', async (_event, kind: LogFileKind) => readLogFile(kind));
  ipcMain.handle('app:open-path', async (_event, targetPath: string) => {
    await shell.openPath(targetPath);
  });
  ipcMain.handle('app:open-external', async (_event, targetUrl: string) => {
    await shell.openExternal(targetUrl);
  });
}

async function createMainWindow(): Promise<void> {
  await writeStartupLog('开始创建主窗口。');
  mainWindow = new BrowserWindow({
    width: 1380,
    height: 940,
    minWidth: 1120,
    minHeight: 760,
    autoHideMenuBar: true,
    backgroundColor: '#f3efe6',
    title: '龙胤立志传 Pro Max',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: false
    }
  });
  let rendererReady = false;
  const rendererReadyTimer = setTimeout(() => {
    if (!rendererReady) {
      void writeStartupLog('渲染器准备超时：HTML 已加载，但未收到 renderer-ready 标记。');
    }
  }, 12000);
  mainWindow.once('closed', () => {
    clearTimeout(rendererReadyTimer);
    mainWindow = null;
  });

  mainWindow.webContents.on('did-fail-load', (_event, errorCode, errorDescription, validatedUrl, isMainFrame) => {
    if (isMainFrame) {
      void writeStartupLog(`渲染页面加载失败：code=${errorCode}, description=${errorDescription}, url=${validatedUrl}`);
    }
  });

  mainWindow.webContents.on('render-process-gone', (_event, details) => {
    void writeStartupLog(`渲染进程退出：reason=${details.reason}, exitCode=${details.exitCode}`);
  });

  mainWindow.webContents.on('console-message', (details) => {
    if (details.message === '[LongYin] renderer-ready') {
      rendererReady = true;
      clearTimeout(rendererReadyTimer);
      void writeStartupLog('渲染器准备完成。');
      return;
    }

    if (details.level === 'warning' || details.level === 'error') {
      void writeStartupLog(
        `渲染器控制台 ${details.level}：${details.message} (${details.sourceId}:${details.lineNumber})`
      );
    }
  });

  mainWindow.webContents.setWindowOpenHandler(({ url }) => {
    shell.openExternal(url).catch(() => undefined);
    return { action: 'deny' };
  });

  const rendererIndex = path.join(APP_CONTENT_ROOT, 'dist', 'renderer', 'index.html');
  await fs.stat(rendererIndex).catch(() => {
    throw new Error(`未找到渲染入口：${rendererIndex}`);
  });
  await writeStartupLog(`渲染入口：${rendererIndex}`);

  try {
    await mainWindow.loadFile(rendererIndex);
    await writeStartupLog('主窗口加载完成。');
  }
  catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    await writeStartupLog(`界面加载失败：${message}`);
    await dialog.showErrorBox('界面加载失败', message);
    throw error;
  }

  if (!IS_PACKAGED) {
    mainWindow.webContents.openDevTools({ mode: 'detach' });
  }
}

process.on('uncaughtException', (error) => {
  void writeStartupLog(`未捕获异常：${error.stack ?? error.message}`);
  dialog.showErrorBox('启动失败', error.message);
});

process.on('unhandledRejection', (reason) => {
  const message = reason instanceof Error ? reason.stack ?? reason.message : String(reason);
  void writeStartupLog(`未处理拒绝：${message}`);
});

app.whenReady().then(async () => {
  await writeStartupLog('应用启动。');
  await ensureAppDirectories();
  registerIpc();
  cachedGameRoot = await loadGameRoot();
  await writeStartupLog(`游戏目录：${cachedGameRoot ?? '未找到'}`);
  await createMainWindow();
  await consumeUpdateCompletion();
  void checkUpdates();
  void getReleaseHistory();
}).catch(async (error: Error) => {
  await writeStartupLog(`启动链失败：${error.stack ?? error.message}`);
  dialog.showErrorBox('启动失败', error.message);
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') {
    if (gameLifecycleMonitor) {
      void writeStartupLog('启动器窗口已关闭；主进程继续监视游戏退出并负责清理 Overlay。');
      return;
    }
    app.quit();
  }
});
