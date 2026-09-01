import { useEffect, useMemo, useRef, useState } from 'react';
import {
  BASE_ATTRI_TYPE_NAMES,
  CUSTOM_TALENT_CONDITION_TYPES,
  HERO_SPE_ADD_DATA_TYPE_NAMES
} from '../shared/types';
import type {
  BaseAttriTypeName,
  CustomTalentConditionType,
  CustomTalentDefinition,
  CustomTalentPack,
  HeroSpeAddDataTypeName,
  GameSnapshot,
  ReleaseHistoryItem,
  UpdateCheckResult,
  UpdateProgressEvent,
  VisibleSettings
} from '../shared/types';
import { reconcilePersistedValue } from '../shared/persisted-state';
import { deriveConfigurationStatus, deriveLaunchAvailability } from '../shared/launcher-state';
import { createDefaultVisibleSettings } from '../shared/visible-settings';
import {
  Card,
  CheckboxField,
  HOTKEY_OPTIONS,
  NumberField,
  SelectField,
  StatusPill,
  TextField,
  clampText,
  mergeSettings
} from './components';
import {
  cloneCustomTalentPack,
  createCustomTalent,
  createCustomTalentCondition,
  createCustomTalentEffect,
  createEmptyCustomTalentPack,
  duplicateCustomTalent,
  formatBaseAttriType,
  formatCustomTalentConditionType,
  formatHeroSpeAddDataType,
  validateCustomTalentPack
} from './customTalents';
import { SettingsWorkspace } from './settings/SettingsWorkspace';
import { ConfirmDialog, LaunchActions, SidebarNav, StatusCenter } from './layout';
import type { ConfirmRequest } from './layout';

type NavKey =
  | 'home'
  | 'updates'
  | 'systems'
  | 'expTalent'
  | 'customTalent'
  | 'worldExplore'
  | 'tradeCraft'
  | 'socialTeam'
  | 'battle';

type NavItem = {
  key: NavKey;
  label: string;
  eyebrow: string;
  title: string;
  description: string;
};

function launchTone(state: GameSnapshot['launchState']): 'good' | 'warn' | 'neutral' {
  if (state === 'running') {
    return 'good';
  }

  if (state === 'starting') {
    return 'warn';
  }

  return 'neutral';
}

function healthTone(snapshot: GameSnapshot | null): 'good' | 'warn' | 'neutral' {
  if (!snapshot?.gameRoot) {
    return 'neutral';
  }

  return snapshot.health.healthy ? 'good' : 'warn';
}

function formatReleaseDate(value?: string): string {
  if (!value) {
    return '日期未提供';
  }

  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return value;
  }

  return new Intl.DateTimeFormat('zh-CN', {
    year: 'numeric',
    month: '2-digit',
    day: '2-digit'
  }).format(date);
}

function releaseBodyLines(value?: string): string[] {
  if (!value || !value.trim()) {
    return ['本次发布暂未填写更新说明。'];
  }

  return value
    .split(/\r?\n/)
    .map((line) => line.trimEnd())
    .filter((line, index, all) => line.length > 0 || (index > 0 && all[index - 1].length > 0));
}

function formatProgressTimestamp(value: string): string {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return value;
  }

  return new Intl.DateTimeFormat('zh-CN', {
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit'
  }).format(date);
}

function optionsWithCurrent(current: string, options: string[]): string[] {
  const normalized = current.trim();
  return !normalized || options.includes(normalized) ? options : [normalized, ...options];
}

async function copyText(value: string): Promise<void> {
  await navigator.clipboard.writeText(value);
}

function CheckList(props: { items: string[]; empty: string }) {
  if (props.items.length === 0) {
    return <div className="empty-state">{props.empty}</div>;
  }

  return (
    <div className="check-list">
      {props.items.map((item) => (
        <div key={item} className="check-list__item">
          {item}
        </div>
      ))}
    </div>
  );
}

function LogPreview(props: { title: string; body: string }) {
  return (
    <div className="log-preview">
      <div className="log-preview__head">
        <strong>{props.title}</strong>
      </div>
      <pre className="log-preview__body">{props.body}</pre>
    </div>
  );
}

function summarizeCustomTalent(talent: CustomTalentDefinition): string {
  const firstCondition = talent.conditions[0];
  const firstEffect = talent.effects[0];
  const conditionSummary = firstCondition
    ? `首个条件：${formatCustomTalentConditionType(firstCondition.type)} · ${formatBaseAttriType(firstCondition.stat)} ≥ ${firstCondition.min}`
    : '暂无条件';
  const effectSummary = firstEffect
    ? `首个效果：${formatHeroSpeAddDataType(firstEffect.effectType)} ${firstEffect.value >= 0 ? '+' : ''}${firstEffect.value}`
    : '暂无效果';
  return `${talent.conditions.length} 条条件 · ${talent.effects.length} 条效果 · ${talent.durationDays} 天 · ${conditionSummary} · ${effectSummary}`;
}

export function App() {
  const [snapshot, setSnapshot] = useState<GameSnapshot | null>(null);
  const [settings, setSettings] = useState<VisibleSettings>(() => createDefaultVisibleSettings());
  const [savedSettingsText, setSavedSettingsText] = useState(() => JSON.stringify(createDefaultVisibleSettings()));
  const [activePage, setActivePage] = useState<NavKey>('home');
  const [working, setWorking] = useState<string | null>(null);
  const [message, setMessage] = useState('正在加载...');
  const [error, setError] = useState<string | null>(null);
  const [errorTime, setErrorTime] = useState<string | null>(null);
  const [update, setUpdate] = useState<UpdateCheckResult | null>(null);
  const [releaseHistory, setReleaseHistory] = useState<ReleaseHistoryItem[]>([]);
  const [startupLogText, setStartupLogText] = useState('正在读取 startup.log ...');
  const [otaLogText, setOtaLogText] = useState('正在读取 ota-update.log ...');
  const [logsBusy, setLogsBusy] = useState(false);
  const [copyNotice, setCopyNotice] = useState<string | null>(null);
  const [updateProgressEvents, setUpdateProgressEvents] = useState<UpdateProgressEvent[]>([]);
  const [customTalentPack, setCustomTalentPack] = useState<CustomTalentPack>(() => createEmptyCustomTalentPack());
  const [savedCustomTalentPackText, setSavedCustomTalentPackText] = useState(() => JSON.stringify(createEmptyCustomTalentPack()));
  const [selectedCustomTalentId, setSelectedCustomTalentId] = useState<string | null>(null);
  const [customTalentLoadError, setCustomTalentLoadError] = useState<string | null>(null);
  const [customTalentsReady, setCustomTalentsReady] = useState(false);
  const [initialLoadError, setInitialLoadError] = useState<string | null>(null);
  const [confirmRequest, setConfirmRequest] = useState<ConfirmRequest | null>(null);
  const pageTitleRef = useRef<HTMLHeadingElement>(null);

  const navItems = useMemo<NavItem[]>(
    () => [
      { key: 'home', label: '主页', eyebrow: 'Launcher', title: '主页', description: '集中处理安装、自检、保存配置与安全启动。' },
      { key: 'updates', label: '更新记录', eyebrow: 'OTA', title: '更新记录', description: '查看当前版本、GitHub Release 说明与 OTA 运行日志。' },
      { key: 'systems', label: '系统更改', eyebrow: 'Runtime', title: '系统更改', description: '整理全局运行控制、时间冻结与环境自检。' },
      { key: 'expTalent', label: '成长与天赋', eyebrow: 'Growth', title: '成长与天赋', description: '把经验成长、心悟机制与突破天赋放在同一页。' },
      { key: 'customTalent', label: '自定义天赋', eyebrow: 'Creator', title: '自定义天赋', description: '创建、编辑和管理多个自定义天赋，保存后下次启动游戏生效。' },
      { key: 'worldExplore', label: '探索与大地图', eyebrow: 'Explore', title: '探索与大地图', description: '专注探索体力、世界地图坐骑与移动体验。' },
      { key: 'tradeCraft', label: '交易与制造', eyebrow: 'Commerce', title: '交易与制造', description: '交易、背包与制造增产统一归档。' },
      { key: 'socialTeam', label: '社交与组队', eyebrow: 'Social', title: '社交与组队', description: '把聊天配额、关系提升与组队辅助集中展示。' },
      { key: 'battle', label: '战斗相关', eyebrow: 'Battle', title: '战斗相关', description: '收纳战斗数值、战斗节奏与战斗加速。' }
    ],
    []
  );

  const activeNav = navItems.find((item) => item.key === activePage) ?? navItems[0];

  const navigateTo = (page: NavKey) => {
    setActivePage(page);
  };

  useEffect(() => {
    window.scrollTo({ top: 0, left: 0, behavior: 'auto' });
    pageTitleRef.current?.focus({ preventScroll: true });
  }, [activePage]);

  const updateSetting = <K extends keyof VisibleSettings>(key: K, value: VisibleSettings[K]) => {
    setSettings((current) => mergeSettings(current, { [key]: value } as Partial<VisibleSettings>));
  };

  const acceptVisibleSettings = (nextSettings: VisibleSettings) => {
    setSettings(nextSettings);
    setSavedSettingsText(JSON.stringify(nextSettings));
  };

  const acceptVisibleSettingsIfUnchanged = (nextSettings: VisibleSettings, submittedText: string) => {
    setSavedSettingsText(JSON.stringify(nextSettings));
    setSettings((current) => reconcilePersistedValue(current, submittedText, nextSettings));
  };

  const replaceCustomTalentPack = (nextPack: CustomTalentPack) => {
    setCustomTalentPack(cloneCustomTalentPack(nextPack));
  };

  const acceptCustomTalentPackIfUnchanged = (nextPack: CustomTalentPack, submittedText: string) => {
    const persistedPack = cloneCustomTalentPack(nextPack);
    setSavedCustomTalentPackText(JSON.stringify(persistedPack));
    setCustomTalentPack((current) => reconcilePersistedValue(current, submittedText, persistedPack));
  };

  const updateSelectedTalent = (updater: (talent: CustomTalentDefinition) => CustomTalentDefinition) => {
    if (!selectedCustomTalentId) {
      return;
    }

    setCustomTalentPack((current) => ({
      version: current.version,
      talents: current.talents.map((talent) => (talent.id === selectedCustomTalentId ? updater(talent) : talent))
    }));
  };

  const showError = (nextError: string) => {
    setError(nextError);
    setErrorTime(new Date().toISOString());
  };

  const clearError = () => {
    setError(null);
    setErrorTime(null);
  };

  const refreshCustomTalents = async (targetGameRoot?: string) => {
    setCustomTalentsReady(false);
    setCustomTalentLoadError(null);
    if (!targetGameRoot) {
      const emptyPack = createEmptyCustomTalentPack();
      replaceCustomTalentPack(emptyPack);
      setSavedCustomTalentPackText(JSON.stringify(emptyPack));
      setSelectedCustomTalentId(null);
      setCustomTalentLoadError(null);
      setCustomTalentsReady(true);
      return emptyPack;
    }

    try {
      const nextPack = await window.longyin.getCustomTalents();
      replaceCustomTalentPack(nextPack);
      setSavedCustomTalentPackText(JSON.stringify(nextPack));
      setCustomTalentLoadError(null);
      setCustomTalentsReady(true);
      return nextPack;
    }
    catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      const emptyPack = createEmptyCustomTalentPack();
      replaceCustomTalentPack(emptyPack);
      setSavedCustomTalentPackText(JSON.stringify(emptyPack));
      setCustomTalentLoadError(message);
      return emptyPack;
    }
  };

  const refresh = async (nextMessage?: string, preserveMessage = false, syncSettings = true) => {
    const next = await window.longyin.getSnapshot();
    setSnapshot(next);
    setInitialLoadError(null);
    if (syncSettings) {
      acceptVisibleSettings(next.visibleSettings);
    }
    setUpdate(next.update);
    if (!preserveMessage) {
      setMessage(nextMessage ?? next.status ?? '准备就绪');
    }
    return next;
  };

  const refreshLogs = async (silent = false) => {
    if (!silent) {
      setLogsBusy(true);
    }

    try {
      const [nextStartupLog, nextOtaLog] = await Promise.all([
        window.longyin.readLogFile('startup'),
        window.longyin.readLogFile('ota')
      ]);
      setStartupLogText(nextStartupLog);
      setOtaLogText(nextOtaLog);
    }
    finally {
      if (!silent) {
        setLogsBusy(false);
      }
    }
  };

  const handleCopy = async (label: string, value: string) => {
    await copyText(value);
    setCopyNotice(`${label}已复制到剪贴板。`);
  };

  const refreshReleaseHistory = async (preserveMessage = false) => {
    const nextHistory = await window.longyin.getReleaseHistory();
    setReleaseHistory(nextHistory);
    if (!preserveMessage) {
      setMessage(nextHistory.length > 0 ? '更新记录已刷新。' : '当前还没有可展示的更新记录。');
    }
    return nextHistory;
  };

  const run = async (label: string, action: () => Promise<any>, syncSettings = false) => {
    const submittedSettingsText = JSON.stringify(settings);
    setWorking(label);
    clearError();
    try {
      const result = await action();
      if (result?.updatedSnapshot) {
        setSnapshot(result.updatedSnapshot);
        if (syncSettings) {
          acceptVisibleSettingsIfUnchanged(result.updatedSnapshot.visibleSettings, submittedSettingsText);
        }
        setUpdate(result.updatedSnapshot.update);
        setMessage(result.message ?? label);
      }
      else {
        const nextSnapshot = await refresh(label, false, false);
        if (syncSettings) {
          acceptVisibleSettingsIfUnchanged(nextSnapshot.visibleSettings, submittedSettingsText);
        }
      }
      return result;
    }
    catch (err) {
      showError(err instanceof Error ? err.message : String(err));
      setMessage(`无法完成${label}。`);
      return undefined;
    }
    finally {
      setWorking(null);
    }
  };

  useEffect(() => {
    void refresh().catch((err: Error) => {
      showError(err.message);
      setInitialLoadError(err.message);
      setMessage('加载状态失败。');
    });
    void refreshReleaseHistory(true).catch(() => undefined);
    void refreshLogs(true).catch(() => undefined);
  }, []);

  useEffect(() => {
    void refreshCustomTalents(snapshot?.gameRoot ?? '').catch(() => undefined);
  }, [snapshot?.gameRoot]);

  useEffect(() => {
    if (!snapshot) {
      return undefined;
    }

    const timer = window.setInterval(() => {
      void refresh(undefined, true, false).catch(() => undefined);
    }, 3000);

    return () => window.clearInterval(timer);
  }, [snapshot]);

  useEffect(() => {
    const unsubscribe = window.longyin.onUpdateProgress((event) => {
      setUpdateProgressEvents((current) => [...current.slice(-7), event]);
      setMessage(event.detail);

      if (event.stage === 'error') {
        showError(event.detail);
      }
    });

    return unsubscribe;
  }, []);

  useEffect(() => {
    if (!copyNotice) {
      return undefined;
    }

    const timer = window.setTimeout(() => setCopyNotice(null), 2200);
    return () => window.clearTimeout(timer);
  }, [copyNotice]);

  useEffect(() => {
    const latestEvent = updateProgressEvents[updateProgressEvents.length - 1] ?? null;
    const needsLiveLogRefresh =
      working === '下载更新中' ||
      (latestEvent !== null && ['checking', 'downloading', 'preparing', 'applying'].includes(latestEvent.stage));

    if (!needsLiveLogRefresh) {
      return undefined;
    }

    const timer = window.setInterval(() => {
      void refreshLogs(true).catch(() => undefined);
    }, 1200);

    return () => window.clearInterval(timer);
  }, [working, updateProgressEvents]);

  useEffect(() => {
    if (customTalentPack.talents.length === 0) {
      if (selectedCustomTalentId !== null) {
        setSelectedCustomTalentId(null);
      }
      return;
    }

    if (!selectedCustomTalentId || !customTalentPack.talents.some((talent) => talent.id === selectedCustomTalentId)) {
      setSelectedCustomTalentId(customTalentPack.talents[0].id);
    }
  }, [customTalentPack, selectedCustomTalentId]);

  const gameRoot = snapshot?.gameRoot ?? '';
  const gameInstalled = snapshot?.gameInstalled ?? false;
  const health =
    snapshot?.health ?? { healthy: false, needsRepair: false, launchBlocked: false, summary: '正在加载自检状态。', driftedFiles: [], checks: [] };
  const payloadRoot = snapshot?.payloadRoot ?? '';
  const userDataRoot = snapshot?.userDataRoot ?? '';
  const startupLogPath = snapshot?.startupLogPath ?? '';
  const otaLogPath = snapshot?.otaLogPath ?? '';
  const launchReady = snapshot?.launchReady ?? false;
  const launchBusy = snapshot?.launchState === 'starting' || snapshot?.launchState === 'running';
  const latestRelease = releaseHistory.find((release) => release.isLatest) ?? releaseHistory[0] ?? null;
  const latestProgress = updateProgressEvents[updateProgressEvents.length - 1] ?? null;
  const updateInFlight =
    working === '下载更新中' ||
    (latestProgress !== null && ['checking', 'downloading', 'preparing', 'applying'].includes(latestProgress.stage));
  const healthPreview = health.checks.slice(0, 8).map((check) => `${check.ok ? '已通过' : '需处理'} · ${check.label} · ${check.detail}`);
  const releasePreview = releaseBodyLines(update?.releaseBody ?? latestRelease?.body).slice(0, 8);
  const selectedCustomTalent =
    customTalentPack.talents.find((talent) => talent.id === selectedCustomTalentId) ?? customTalentPack.talents[0] ?? null;
  const customTalentValidationErrors = validateCustomTalentPack(customTalentPack);
  const settingsDirty = JSON.stringify(settings) !== savedSettingsText;
  const customTalentDirty = JSON.stringify(customTalentPack) !== savedCustomTalentPackText;
  const customTalentWriteBlocked = !customTalentsReady && !customTalentLoadError;
  const configurationStatus = deriveConfigurationStatus({
    gameRoot,
    customTalentsReady,
    customTalentLoadError,
    settingsDirty,
    customTalentDirty
  });
  const launchFacts = {
    gameRoot,
    working,
    launchBusy,
    launchReady,
    launchNote: snapshot?.launchNote,
    customTalentsReady,
    customTalentLoadError,
    customTalentValidationErrors,
    settingsDirty,
    customTalentDirty
  };
  const saveAndLaunchAvailability = deriveLaunchAvailability({ ...launchFacts, mode: 'save-and-launch' });
  const launchSavedAvailability = deriveLaunchAvailability({ ...launchFacts, mode: 'launch-saved' });
  const saveAvailability = {
    enabled: working === null && Boolean(gameRoot),
    disabledReason: working ? `${working}，请稍候。` : gameRoot ? null : '请先选择游戏目录。',
    warning: null
  };

  const save = async () => {
    const submittedSettingsText = JSON.stringify(settings);
    setWorking('保存中');
    clearError();
    try {
      const nextSnapshot = await window.longyin.saveSettings(settings);
      setSnapshot(nextSnapshot);
      acceptVisibleSettingsIfUnchanged(nextSnapshot.visibleSettings, submittedSettingsText);
      setUpdate(nextSnapshot.update);
      setMessage('设置已保存。');
    }
    catch (err) {
      showError(err instanceof Error ? err.message : String(err));
    }
    finally {
      setWorking(null);
    }
  };

  const saveCustomTalents = async () => {
    const submittedCustomTalentText = JSON.stringify(customTalentPack);
    setWorking('应用自定义天赋');
    clearError();
    try {
      const result = await window.longyin.saveCustomTalents(customTalentPack);
      acceptCustomTalentPackIfUnchanged(result.pack, submittedCustomTalentText);
      setCustomTalentLoadError(null);
      setCustomTalentsReady(true);
      setMessage(result.message);
    }
    catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      showError(message);
      setMessage('无法保存自定义天赋。');
    }
    finally {
      setWorking(null);
    }
  };

  const createTalent = () => {
    const nextTalent = createCustomTalent(`新天赋 ${customTalentPack.talents.length + 1}`);
    setCustomTalentPack((current) => ({
      version: current.version,
      talents: [...current.talents, nextTalent]
    }));
    setSelectedCustomTalentId(nextTalent.id);
  };

  const duplicateSelectedTalent = () => {
    if (!selectedCustomTalent) {
      return;
    }

    const duplicated = duplicateCustomTalent(selectedCustomTalent);
    setCustomTalentPack((current) => {
      const currentIndex = current.talents.findIndex((talent) => talent.id === selectedCustomTalent.id);
      const nextTalents = [...current.talents];
      nextTalents.splice(currentIndex + 1, 0, duplicated);
      return {
        version: current.version,
        talents: nextTalents
      };
    });
    setSelectedCustomTalentId(duplicated.id);
  };

  const deleteSelectedTalent = () => {
    if (!selectedCustomTalent) {
      return;
    }
    const talent = selectedCustomTalent;
    setConfirmRequest({
      title: '删除自定义天赋？',
      body: `“${talent.name || '未命名天赋'}”将从当前编辑列表中移除；保存前仍可取消本次修改。`,
      confirmLabel: '删除天赋',
      tone: 'danger',
      onConfirm: () => setCustomTalentPack((current) => ({
        version: current.version,
        talents: current.talents.filter((item) => item.id !== talent.id)
      }))
    });
  };

  const moveSelectedTalent = (direction: -1 | 1) => {
    if (!selectedCustomTalent) {
      return;
    }

    setCustomTalentPack((current) => {
      const currentIndex = current.talents.findIndex((talent) => talent.id === selectedCustomTalent.id);
      const targetIndex = currentIndex + direction;
      if (currentIndex < 0 || targetIndex < 0 || targetIndex >= current.talents.length) {
        return current;
      }

      const nextTalents = [...current.talents];
      const [moved] = nextTalents.splice(currentIndex, 1);
      nextTalents.splice(targetIndex, 0, moved);
      return {
        version: current.version,
        talents: nextTalents
      };
    });
  };

  const toggleSelectedTalentEnabled = () => {
    if (!selectedCustomTalent) {
      return;
    }

    updateSelectedTalent((talent) => ({
      ...talent,
      enabled: !talent.enabled
    }));
  };

  const saveAndLaunch = async () => {
    const submittedCustomTalentText = JSON.stringify(customTalentPack);
    const result = await run(
      '保存并启动',
      () => window.longyin.saveAndLaunch({ settings, customTalents: customTalentPack }),
      true
    );
    if (result?.customTalents) {
      acceptCustomTalentPackIfUnchanged(result.customTalents, submittedCustomTalentText);
      setCustomTalentLoadError(null);
      setCustomTalentsReady(true);
    }
  };

  const setLaunchOverlayWithGame = async (value: boolean) => {
    setWorking('保存 Overlay 设置');
    clearError();
    try {
      const next = await window.longyin.setLauncherPreferences({ launchOverlayWithGame: value });
      setSnapshot(next);
      setMessage(value ? '已启用随游戏启动 Overlay。' : '已关闭随游戏启动 Overlay。');
    }
    catch (err) {
      showError(err instanceof Error ? err.message : String(err));
    }
    finally {
      setWorking(null);
    }
  };

  const startOverlay = async () => {
    await run('启动 Overlay', () => window.longyin.startOverlay(), false);
  };

  const stopOverlay = async () => {
    await run('关闭 Overlay', () => window.longyin.stopOverlay(), false);
  };

  const install = async () => {
    await run('安装模组', () => window.longyin.install(), false);
  };

  const uninstall = async () => {
    await run('卸载模组', () => window.longyin.uninstall(), false);
  };

  const requestUninstall = () => {
    setConfirmRequest({
      title: '卸载当前模组？',
      body: '将移除由启动器安装的模组文件；你的游戏存档和未由启动器接管的文件不会删除。',
      confirmLabel: '确认卸载',
      tone: 'danger',
      onConfirm: () => void uninstall()
    });
  };

  const launch = async () => {
    await run('启动游戏', () => window.longyin.launch(), false);
  };

  const requestLaunchSaved = () => {
    if (!settingsDirty && !customTalentDirty) {
      void launch();
      return;
    }

    setConfirmRequest({
      title: '使用已保存配置启动？',
      body: '当前界面仍有未保存修改。本次游戏只会读取上次保存的配置，界面中的修改会继续保留。',
      confirmLabel: '启动已保存配置',
      onConfirm: () => void launch()
    });
  };

  const pickGameRoot = async () => {
    setWorking('选择目录');
    clearError();
    try {
      const next = await window.longyin.pickGameRoot();
      setSnapshot(next);
      acceptVisibleSettings(next.visibleSettings);
      setUpdate(next.update);
      setMessage('游戏目录已选择。');
    }
    catch (err) {
      showError(err instanceof Error ? err.message : String(err));
    }
    finally {
      setWorking(null);
    }
  };

  const checkUpdates = async () => {
    setWorking('检查更新');
    clearError();
    try {
      const next = await window.longyin.checkUpdates();
      setUpdate(next);
      void refreshReleaseHistory(true).catch(() => undefined);
      setMessage(next.status ?? '更新检查完成。');
    }
    catch (err) {
      showError(err instanceof Error ? err.message : String(err));
    }
    finally {
      setWorking(null);
    }
  };

  const applyUpdate = async () => {
    setWorking('下载更新中');
    clearError();
    setUpdateProgressEvents([]);
    setMessage('正在检查更新并准备下载。应用会显示当前步骤，请不要关闭窗口。');
    try {
      const result = await window.longyin.applyUpdate();
      if (result?.updatedSnapshot) {
        setSnapshot(result.updatedSnapshot);
        setUpdate(result.updatedSnapshot.update);
        setMessage(result.message ?? '更新包已下载。请等待应用自动重启。');
      }
    }
    catch (err) {
      showError(err instanceof Error ? err.message : String(err));
      setMessage('应用更新失败。请打开日志查看详细原因。');
    }
    finally {
      setWorking(null);
    }
  };

  const openReleasePage = async (targetUrl?: string) => {
    if (targetUrl) {
      await window.longyin.openExternal(targetUrl);
    }
  };

  const openGameRoot = async () => {
    if (gameRoot) {
      await window.longyin.openPath(gameRoot);
    }
  };

  const openPayloadRoot = async () => {
    if (payloadRoot) {
      await window.longyin.openPath(payloadRoot);
    }
  };

  const openLogFolder = async () => {
    if (userDataRoot) {
      await window.longyin.openPath(userDataRoot);
    }
  };

  const openStartupLog = async () => {
    if (startupLogPath) {
      await window.longyin.openPath(startupLogPath);
    }
  };

  const openOtaLog = async () => {
    if (otaLogPath) {
      await window.longyin.openPath(otaLogPath);
    }
  };

  if (!snapshot) {
    return (
      <div className="shell shell--loading">
        <div className="loading-card">
          {initialLoadError ? (
            <div className="stack">
              <strong>启动器状态加载失败</strong>
              <p className="body-copy">{initialLoadError}</p>
              <button
                className="btn btn--primary"
                onClick={() => {
                  setInitialLoadError(null);
                  setMessage('正在重试加载...');
                  void refresh().catch((err: Error) => {
                    showError(err.message);
                    setInitialLoadError(err.message);
                  });
                }}
              >
                重试加载
              </button>
            </div>
          ) : (
            '正在加载 龙胤立志传 Pro Max...'
          )}
        </div>
      </div>
    );
  }

  return (
    <div className="shell">
      <ConfirmDialog request={confirmRequest} onCancel={() => setConfirmRequest(null)} />
      <div className="ambient ambient--one" />
      <div className="ambient ambient--two" />
      <div className="ambient ambient--three" />

      <div className="dashboard">
        <SidebarNav
          items={navItems}
          activeKey={activePage}
          onNavigate={navigateTo}
          statusRows={[
            { label: '应用版本', value: snapshot.appVersion },
            { label: '游戏目录', value: gameRoot ? '已连接' : '未选择' },
            { label: '模组状态', value: gameInstalled ? '已就绪' : gameRoot ? '需修复' : '未安装' },
            { label: '更新状态', value: update?.updateAvailable ? `可升级到 ${update.latestVersion}` : '已是最新' },
            { label: '配置状态', value: configurationStatus.label, tone: configurationStatus.key === 'saved' ? 'good' : 'warn' }
          ]}
        />

        <div className="workspace">
          <header className="workspace__hero card">
            <div className="workspace__hero-copy">
              <span className="eyebrow">{activeNav.eyebrow}</span>
              <h1 ref={pageTitleRef} tabIndex={-1} data-page-title>
                {activeNav.title}
              </h1>
              <p>{activeNav.description}</p>
            </div>

            <LaunchActions
              save={{ run: () => void save(), availability: saveAvailability }}
              saveAndLaunch={{ run: () => void saveAndLaunch(), availability: saveAndLaunchAvailability }}
              launchSaved={{ run: requestLaunchSaved, availability: launchSavedAvailability }}
              configurationDirty={settingsDirty || customTalentDirty}
              launchBusy={launchBusy}
            />
          </header>

          <section className="summary-grid">
            <StatusPill label="配置状态" value={configurationStatus.label} tone={configurationStatus.tone} />
            <StatusPill
              label="启动状态"
              value={snapshot.launchState === 'starting' ? '启动中' : snapshot.launchState === 'running' ? '运行中' : '待命'}
              tone={launchTone(snapshot.launchState)}
            />
            <StatusPill label="环境自检" value={health.summary} tone={healthTone(snapshot)} />
          </section>

          <StatusCenter
            message={message}
            working={working}
            configuration={configurationStatus}
            dirtyScopes={[
              ...(gameRoot && settingsDirty ? ['普通设置未保存'] : []),
              ...(gameRoot && customTalentsReady && customTalentDirty ? ['自定义天赋未应用'] : [])
            ]}
          />

          {copyNotice ? <div className="copy-banner" role="status" aria-live="polite">{copyNotice}</div> : null}

          {error ? (
            <div className="error-banner" role="alert" aria-live="assertive">
              <div className="error-banner__head">
                <div>
                  <strong>最近错误</strong>
                  <span>{errorTime ? formatProgressTimestamp(errorTime) : '刚刚'}</span>
                </div>
                <div className="inline-actions">
                  <button className="btn btn--small" onClick={() => void handleCopy('错误信息', error)}>
                    复制错误
                  </button>
                  <button className="btn btn--small" onClick={openLogFolder} disabled={!userDataRoot}>
                    打开日志目录
                  </button>
                  <button className="btn btn--small" onClick={clearError}>
                    清除提示
                  </button>
                </div>
              </div>
              <div className="error-banner__body">{error}</div>
            </div>
          ) : null}

          {updateInFlight ? (
            <section className="progress-card">
              <div className="progress-card__head">
                <div>
                  <strong>更新正在进行</strong>
                  <span>{latestProgress?.detail ?? '正在准备更新步骤...'}</span>
                </div>
                {typeof latestProgress?.percent === 'number' ? <strong>{latestProgress.percent}%</strong> : null}
              </div>
              <div className="progress-bar" aria-hidden="true">
                <div className="progress-bar__fill" style={{ width: `${Math.max(8, latestProgress?.percent ?? 12)}%` }} />
              </div>
              <div className="check-list">
                {updateProgressEvents.length > 0 ? (
                  updateProgressEvents.map((event, index) => (
                    <div key={`${event.timestamp}-${index}`} className="check-list__item">
                      [{formatProgressTimestamp(event.timestamp)}] {event.detail}
                    </div>
                  ))
                ) : (
                  <div className="check-list__item">正在向 GitHub 检查最新版本，请稍候。</div>
                )}
              </div>
            </section>
          ) : null}

          <main className="page-stack">
            {activePage === 'home' ? (
              <div className="page-grid">
                <section className="command-center card">
                  <div className="command-center__main">
                    <div className={`launch-banner launch-banner--${snapshot.launchState}`}>
                      <div className="launch-banner__title">
                        {snapshot.launchState === 'starting'
                          ? '游戏正在启动，请耐心等待'
                          : snapshot.launchState === 'running'
                            ? '检测到游戏进程正在运行'
                            : '可以启动游戏'}
                      </div>
                      <div className="launch-banner__body">{snapshot.launchNote}</div>
                    </div>

                    <div className="toolbar__cluster">
                      <button className="btn" onClick={pickGameRoot} disabled={working !== null || launchBusy}>
                        {gameRoot ? '更换目录' : '选择目录'}
                      </button>
                      <button className="btn" onClick={openGameRoot} disabled={!gameRoot}>
                        打开游戏目录
                      </button>
                      <button className="btn" onClick={openPayloadRoot} disabled={!payloadRoot}>
                        打开载荷目录
                      </button>
                      <button className="btn" onClick={openLogFolder} disabled={!userDataRoot}>
                        打开日志目录
                      </button>
                    </div>
                  </div>

                  <div className="command-center__side">
                    <button className="btn" onClick={install} disabled={working !== null || !gameRoot || launchBusy}>
                      安装模组
                    </button>
                    <button className="btn" onClick={requestUninstall} disabled={working !== null || !gameRoot || launchBusy}>
                      卸载模组
                    </button>
                    <button className="btn" onClick={checkUpdates} disabled={working !== null}>
                      检查更新
                    </button>
                    {update?.updateAvailable ? (
                      <button className="btn btn--accent" onClick={applyUpdate} disabled={working !== null || launchBusy}>
                        立即更新
                      </button>
                    ) : null}
                  </div>
                </section>

                <Card title="游戏目录与载荷" eyebrow="Environment">
                  <div className="stack">
                    <p className="body-copy">
                      {gameRoot
                        ? '启动器会在这个目录安装并管理模组文件。'
                        : '请选择包含 LongYinLiZhiZhuan.exe 的目录，或者让应用自动识别 Steam。'}
                    </p>
                    <div className="path-box">{gameRoot || '尚未选择游戏目录'}</div>
                    <div className="path-box path-box--soft">{payloadRoot || '未找到当前 Electron 载荷目录'}</div>
                  </div>
                </Card>

                <Card title="自检摘要" eyebrow="Health">
                  <div className="stack">
                    <p className="body-copy">{health.summary}</p>
                    <CheckList
                      items={healthPreview}
                      empty={gameRoot ? '还没有自检项可展示。' : '选择游戏目录后，这里会显示安装自检结果。'}
                    />
                  </div>
                </Card>

                <Card title="更新通道" eyebrow="Release">
                  <div className="stack">
                    <div className="stat-line">
                      <span>当前版本</span>
                      <strong>{snapshot.appVersion}</strong>
                    </div>
                    <div className="stat-line">
                      <span>最新版本</span>
                      <strong>{update?.latestVersion ?? snapshot.appVersion}</strong>
                    </div>
                    <div className="stat-line">
                      <span>状态</span>
                      <strong>{update?.updateAvailable ? '有新版本可下载' : '已是最新'}</strong>
                    </div>
                    <div className="release-note release-note--panel">
                      {releasePreview.map((line, index) => (
                        <div key={`home-release-${index}`} className="release-note__line">
                          {line}
                        </div>
                      ))}
                    </div>
                    <div className="inline-actions">
                      <button className="btn btn--small" onClick={() => void refreshReleaseHistory()} disabled={working !== null}>
                        刷新更新记录
                      </button>
                      {update?.releaseUrl ? (
                        <button className="btn btn--small" onClick={() => void openReleasePage(update.releaseUrl)}>
                          打开发布页
                        </button>
                      ) : null}
                    </div>
                  </div>
                </Card>
              </div>
            ) : null}

            {activePage === 'updates' ? (
              <div className="page-grid">
                <Card title="当前 OTA 状态" eyebrow="Current">
                  <div className="stack">
                    <div className="stat-line">
                      <span>当前版本</span>
                      <strong>{update?.currentVersion ?? snapshot.appVersion}</strong>
                    </div>
                    <div className="stat-line">
                      <span>最新版本</span>
                      <strong>{update?.latestVersion ?? snapshot.appVersion}</strong>
                    </div>
                    <div className="stat-line">
                      <span>发布时间</span>
                      <strong>{formatReleaseDate(update?.publishedAt ?? latestRelease?.publishedAt)}</strong>
                    </div>
                    <div className="stat-line">
                      <span>更新状态</span>
                      <strong>{update?.status ?? '更新检查尚未运行。'}</strong>
                    </div>
                    <div className="inline-actions">
                      <button className="btn btn--primary" onClick={checkUpdates} disabled={working !== null}>
                        检查更新
                      </button>
                      <button className="btn" onClick={() => void refreshReleaseHistory()} disabled={working !== null}>
                        刷新更新记录
                      </button>
                      <button className="btn" onClick={() => void refreshLogs()} disabled={working !== null || logsBusy}>
                        {logsBusy ? '刷新中...' : '刷新日志'}
                      </button>
                      {update?.updateAvailable ? (
                        <button className="btn btn--accent" onClick={applyUpdate} disabled={working !== null || launchBusy}>
                          立即更新
                        </button>
                      ) : null}
                    </div>
                  </div>
                </Card>

                <Card title="本次发布说明" eyebrow="Release Body">
                  <div className="stack">
                    <div className="release-note release-note--panel">
                      {releaseBodyLines(update?.releaseBody ?? latestRelease?.body).map((line, index) => (
                        <div key={`current-release-${index}`} className="release-note__line">
                          {line}
                        </div>
                      ))}
                    </div>
                    {update?.releaseUrl || latestRelease?.htmlUrl ? (
                      <div className="inline-actions">
                        <button
                          className="btn btn--small"
                          onClick={() => void openReleasePage(update?.releaseUrl ?? latestRelease?.htmlUrl)}
                        >
                          打开这个发布页
                        </button>
                      </div>
                    ) : null}
                  </div>
                </Card>

                <Card title="版本更新记录" eyebrow="History">
                  <div className="stack">
                    <p className="body-copy">这里直接展示 GitHub Releases 的每次发布说明，发布时写什么，用户这里就看到什么。</p>
                    <div className="release-history">
                      {releaseHistory.length > 0 ? (
                        releaseHistory.map((release) => (
                          <article key={release.tagName || release.version} className="release-history__item">
                            <div className="release-history__meta">
                              <div className="release-history__title">
                                <strong>{release.name}</strong>
                                {release.isLatest ? <span className="release-badge">最新</span> : null}
                              </div>
                              <div className="release-history__subline">
                                <span>{release.tagName || `v${release.version}`}</span>
                                <span>{formatReleaseDate(release.publishedAt)}</span>
                              </div>
                            </div>
                            <div className="release-note">
                              {releaseBodyLines(release.body).map((line, index) => (
                                <div key={`${release.tagName}-${index}`} className="release-note__line">
                                  {line}
                                </div>
                              ))}
                            </div>
                            {release.htmlUrl ? (
                              <div className="inline-actions">
                                <button className="btn btn--small" onClick={() => void openReleasePage(release.htmlUrl)}>
                                  打开这个发布页
                                </button>
                              </div>
                            ) : null}
                          </article>
                        ))
                      ) : (
                        <div className="empty-state">当前还没有从 GitHub 拉取到更新历史。你可以先点“刷新更新记录”。</div>
                      )}
                    </div>
                  </div>
                </Card>

                <Card title="运行日志" eyebrow="Logs">
                  <div className="stack">
                    <div className="inline-actions">
                      <button className="btn btn--small" onClick={openStartupLog} disabled={!startupLogPath}>
                        打开 startup.log
                      </button>
                      <button className="btn btn--small" onClick={openOtaLog} disabled={!otaLogPath}>
                        打开 ota-update.log
                      </button>
                      <button className="btn btn--small" onClick={openLogFolder} disabled={!userDataRoot}>
                        打开日志目录
                      </button>
                    </div>
                    <div className="log-preview-grid">
                      <LogPreview title="startup.log" body={startupLogText} />
                      <LogPreview title="ota-update.log" body={otaLogText} />
                    </div>
                  </div>
                </Card>
              </div>
            ) : null}

            {activePage === 'systems' ? (
              <div className="page-grid page-grid--systems page-grid--settings">
                <Card title="时间与运行控制" eyebrow="Systems">
                  <div className="field-grid">
                    <CheckboxField
                      label="启动时开启冻结日期"
                      value={settings.freezeDate}
                      onChange={(value) => updateSetting('freezeDate', value)}
                    />
                    <SelectField
                      label="冻结快捷键"
                      value={settings.freezeHotkey}
                      onChange={(value) => updateSetting('freezeHotkey', clampText(value))}
                      options={HOTKEY_OPTIONS}
                    />
                    <SelectField
                      label="战斗外加速快捷键"
                      value={settings.outsideBattleSpeedHotkey}
                      onChange={(value) => updateSetting('outsideBattleSpeedHotkey', clampText(value))}
                      options={HOTKEY_OPTIONS}
                      hint="用于切换战斗外的测试速度倍率。"
                    />
                  </div>
                </Card>

                <Card title="游戏内悬浮信息窗" eyebrow="Overlay">
                  <div className="stack">
                    <CheckboxField
                      label="随游戏启动 Overlay"
                      value={snapshot.launcherPreferences.launchOverlayWithGame}
                      onChange={(value) => void setLaunchOverlayWithGame(value)}
                    />
                    <p className="body-copy body-copy--muted">
                      这是显示在游戏旁的实时信息小窗，方便你无需切回启动器就能查看辅助信息。它不会重复启动；如果由启动器随游戏开启，退出游戏时也会自动关闭。
                    </p>
                    <div className="inline-actions">
                      <button className="btn" onClick={startOverlay} disabled={working !== null || snapshot.overlayRunning}>
                        {snapshot.overlayRunning ? 'Overlay 已运行' : '启动 Overlay'}
                      </button>
                      <button className="btn" onClick={stopOverlay} disabled={working !== null || !snapshot.overlayRunning}>
                        关闭 Overlay
                      </button>
                    </div>
                  </div>
                </Card>

                <div className="system-environment-card">
                <Card title="环境自检与目录" eyebrow="Environment">
                  <div className="stack">
                    <p className="body-copy">
                      这一页保留和环境稳定性最相关的入口。目录更换、载荷查看、自检结果和失败项都放在这里。
                    </p>
                    <div className="path-box">{gameRoot || '尚未选择游戏目录'}</div>
                    <div className="path-box path-box--soft">{payloadRoot || '未找到当前载荷目录'}</div>
                    <div className="inline-actions">
                      <button className="btn" onClick={pickGameRoot} disabled={working !== null || launchBusy}>
                        {gameRoot ? '更换目录' : '选择目录'}
                      </button>
                      <button className="btn" onClick={openGameRoot} disabled={!gameRoot}>
                        打开游戏目录
                      </button>
                      <button className="btn" onClick={openPayloadRoot} disabled={!payloadRoot}>
                        打开载荷目录
                      </button>
                    </div>
                    <details className="health-details">
                      <summary>
                        <span>健康检查详情</span>
                        <strong>{health.summary}</strong>
                      </summary>
                      <CheckList
                        items={health.checks.map((check) => `${check.ok ? '已通过' : '需处理'} · ${check.label} · ${check.detail}`)}
                        empty={gameRoot ? '没有可展示的环境检查。' : '选择游戏目录后，这里会出现完整自检信息。'}
                      />
                    </details>
                  </div>
                </Card>
                </div>
              </div>
            ) : null}

            {activePage === 'expTalent' ||
            activePage === 'worldExplore' ||
            activePage === 'tradeCraft' ||
            activePage === 'socialTeam' ||
            activePage === 'battle' ? (
              <SettingsWorkspace page={activePage} settings={settings} onSettingChange={updateSetting} />
            ) : null}

            {activePage === 'customTalent' ? (
              <div className="custom-talents-layout">
                <Card title="自定义天赋列表" eyebrow="Creator">
                  <div className="stack">
                    <div className="note-box">
                      保存后写入配置文件，下次启动游戏生效。
                    </div>
                    {!gameRoot ? (
                      <div className="empty-state">请先在“系统更改”里选择游戏目录，然后再创建自定义天赋。</div>
                    ) : null}
                    {customTalentLoadError ? (
                      <div className="validation-box validation-box--warn">
                        <strong>当前自定义天赋 JSON 读取失败</strong>
                        <div>{customTalentLoadError}</div>
                        <div>你仍然可以继续编辑并点击“应用到游戏配置”覆盖这个损坏文件。</div>
                      </div>
                    ) : null}
                    <div className="inline-actions">
                      <button className="btn btn--small" onClick={createTalent} disabled={working !== null || !gameRoot}>
                        新建
                      </button>
                      <button className="btn btn--small" onClick={duplicateSelectedTalent} disabled={working !== null || !selectedCustomTalent}>
                        复制
                      </button>
                      <button className="btn btn--small" onClick={deleteSelectedTalent} disabled={working !== null || !selectedCustomTalent}>
                        删除
                      </button>
                      <button className="btn btn--small" onClick={() => moveSelectedTalent(-1)} disabled={working !== null || !selectedCustomTalent}>
                        上移
                      </button>
                      <button className="btn btn--small" onClick={() => moveSelectedTalent(1)} disabled={working !== null || !selectedCustomTalent}>
                        下移
                      </button>
                      <button className="btn btn--small" onClick={toggleSelectedTalentEnabled} disabled={working !== null || !selectedCustomTalent}>
                        {selectedCustomTalent?.enabled ? '禁用' : '启用'}
                      </button>
                    </div>
                    <div className="custom-talent-list">
                      {customTalentPack.talents.length > 0 ? (
                        customTalentPack.talents.map((talent) => (
                          <button
                            key={talent.id}
                            className={`custom-talent-item ${selectedCustomTalent?.id === talent.id ? 'custom-talent-item--active' : ''}`}
                            onClick={() => setSelectedCustomTalentId(talent.id)}
                          >
                            <div className="custom-talent-item__head">
                              <strong>{talent.name.trim() || '未命名天赋'}</strong>
                              <span className={`release-badge ${talent.enabled ? '' : 'release-badge--muted'}`}>
                                {talent.enabled ? '启用' : '禁用'}
                              </span>
                            </div>
                            <div className="custom-talent-item__meta">{summarizeCustomTalent(talent)}</div>
                          </button>
                        ))
                      ) : (
                        <div className="empty-state">还没有自定义天赋。点“新建”先做第一个。</div>
                      )}
                    </div>
                  </div>
                </Card>

                <div className="stack">
                  <Card title="天赋编辑" eyebrow="Editor">
                    {selectedCustomTalent ? (
                      <div className="stack">
                        <div className="inline-actions">
                          <button
                            className="btn btn--primary"
                            onClick={saveCustomTalents}
                            disabled={working !== null || !gameRoot || customTalentWriteBlocked || customTalentValidationErrors.length > 0 || !customTalentDirty}
                          >
                            应用到游戏配置
                          </button>
                          <button
                            className="btn btn--ghost"
                            onClick={() => replaceCustomTalentPack(JSON.parse(savedCustomTalentPackText) as CustomTalentPack)}
                            disabled={working !== null || !customTalentDirty}
                          >
                            放弃未保存修改
                          </button>
                        </div>
                        <div className="field-grid">
                          <TextField
                            label="名称"
                            value={selectedCustomTalent.name}
                            onChange={(value) =>
                              updateSelectedTalent((talent) => ({
                                ...talent,
                                name: value
                              }))
                            }
                          />
                          <NumberField
                            label="持续天数"
                            value={selectedCustomTalent.durationDays}
                            onChange={(value) =>
                              updateSelectedTalent((talent) => ({
                                ...talent,
                                durationDays: Math.max(1, Math.round(value))
                              }))
                            }
                            min={1}
                            max={999999}
                            step={1}
                            hint="999 是推荐的长效测试值。"
                          />
                          <CheckboxField
                            label="启用这个天赋"
                            value={selectedCustomTalent.enabled}
                            onChange={(value) =>
                              updateSelectedTalent((talent) => ({
                                ...talent,
                                enabled: value
                              }))
                            }
                          />
                        </div>
                      </div>
                    ) : (
                      <div className="empty-state">左侧选中一个天赋后，这里会显示完整编辑表单。</div>
                    )}
                  </Card>

                  <Card title="条件列表" eyebrow="Conditions">
                    {selectedCustomTalent ? (
                      <div className="stack">
                        <div className="body-copy">每条条件都可以检查玩家当前属性，或者检查玩家加当前队伍成员的属性总和。全部条件满足后天赋才会生效。</div>
                        <div className="stack">
                          {selectedCustomTalent.conditions.map((condition, conditionIndex) => (
                            <div key={`${selectedCustomTalent.id}-condition-${conditionIndex}`} className="array-row">
                              <div className="array-row__title">条件 {conditionIndex + 1}</div>
                              <div className="array-row__grid array-row__grid--conditions">
                                <SelectField
                                  label="类型"
                                  value={condition.type}
                                  onChange={(value) =>
                                    updateSelectedTalent((talent) => ({
                                      ...talent,
                                      conditions: talent.conditions.map((entry, index) =>
                                        index === conditionIndex
                                          ? {
                                              ...entry,
                                              type: value as CustomTalentConditionType
                                            }
                                          : entry
                                      )
                                    }))
                                  }
                                  options={[...CUSTOM_TALENT_CONDITION_TYPES]}
                                  getOptionLabel={formatCustomTalentConditionType}
                                  hint={formatCustomTalentConditionType(condition.type)}
                                />
                                <SelectField
                                  label="属性"
                                  value={condition.stat}
                                  onChange={(value) =>
                                    updateSelectedTalent((talent) => ({
                                      ...talent,
                                      conditions: talent.conditions.map((entry, index) =>
                                        index === conditionIndex
                                          ? {
                                              ...entry,
                                              stat: value as BaseAttriTypeName
                                            }
                                          : entry
                                      )
                                    }))
                                  }
                                  options={[...BASE_ATTRI_TYPE_NAMES]}
                                  getOptionLabel={formatBaseAttriType}
                                  hint={formatBaseAttriType(condition.stat)}
                                />
                                <NumberField
                                  label="最低值"
                                  value={condition.min}
                                  onChange={(value) =>
                                    updateSelectedTalent((talent) => ({
                                      ...talent,
                                      conditions: talent.conditions.map((entry, index) =>
                                        index === conditionIndex
                                          ? {
                                              ...entry,
                                              min: value
                                            }
                                          : entry
                                      )
                                    }))
                                  }
                                  min={-999999}
                                  max={999999}
                                  step={1}
                                />
                              </div>
                              <div className="inline-actions">
                                <button
                                  className="btn btn--small"
                                  onClick={() =>
                                    updateSelectedTalent((talent) => ({
                                      ...talent,
                                      conditions: talent.conditions.filter((_, index) => index !== conditionIndex)
                                    }))
                                  }
                                  disabled={selectedCustomTalent.conditions.length <= 1}
                                >
                                  删除条件
                                </button>
                              </div>
                            </div>
                          ))}
                        </div>
                        <div className="inline-actions">
                          <button
                            className="btn btn--small"
                            onClick={() =>
                              updateSelectedTalent((talent) => ({
                                ...talent,
                                conditions: [...talent.conditions, createCustomTalentCondition()]
                              }))
                            }
                          >
                            添加条件
                          </button>
                        </div>
                      </div>
                    ) : (
                      <div className="empty-state">先选中一个天赋，再设置它的触发条件。</div>
                    )}
                  </Card>

                  <Card title="效果列表" eyebrow="Effects">
                    {selectedCustomTalent ? (
                      <div className="stack">
                        <div className="body-copy">每个自定义天赋可以叠加多条效果，保存后会合并成一个游戏内天赋定义。</div>
                        <div className="stack">
                          {selectedCustomTalent.effects.map((effect, effectIndex) => (
                            <div key={`${selectedCustomTalent.id}-effect-${effectIndex}`} className="array-row">
                              <div className="array-row__title">效果 {effectIndex + 1}</div>
                              <div className="array-row__grid array-row__grid--effects">
                                <SelectField
                                  label="效果类型"
                                  value={effect.effectType}
                                  onChange={(value) =>
                                    updateSelectedTalent((talent) => ({
                                      ...talent,
                                      effects: talent.effects.map((entry, index) =>
                                        index === effectIndex
                                          ? {
                                              ...entry,
                                              effectType: value as HeroSpeAddDataTypeName
                                            }
                                          : entry
                                      )
                                    }))
                                  }
                                  options={[...HERO_SPE_ADD_DATA_TYPE_NAMES]}
                                  getOptionLabel={formatHeroSpeAddDataType}
                                  hint={formatHeroSpeAddDataType(effect.effectType)}
                                />
                                <NumberField
                                  label="数值"
                                  value={effect.value}
                                  onChange={(value) =>
                                    updateSelectedTalent((talent) => ({
                                      ...talent,
                                      effects: talent.effects.map((entry, index) =>
                                        index === effectIndex
                                          ? {
                                              ...entry,
                                              value
                                            }
                                          : entry
                                      )
                                    }))
                                  }
                                  min={-999999}
                                  max={999999}
                                  step={1}
                                />
                              </div>
                              <div className="inline-actions">
                                <button
                                  className="btn btn--small"
                                  onClick={() =>
                                    updateSelectedTalent((talent) => ({
                                      ...talent,
                                      effects: talent.effects.filter((_, index) => index !== effectIndex)
                                    }))
                                  }
                                  disabled={selectedCustomTalent.effects.length <= 1}
                                >
                                  删除效果
                                </button>
                              </div>
                            </div>
                          ))}
                        </div>
                        <div className="inline-actions">
                          <button
                            className="btn btn--small"
                            onClick={() =>
                              updateSelectedTalent((talent) => ({
                                ...talent,
                                effects: [...talent.effects, createCustomTalentEffect()]
                              }))
                            }
                          >
                            添加效果
                          </button>
                        </div>
                      </div>
                    ) : (
                      <div className="empty-state">先选中一个天赋，再设置它的数值效果。</div>
                    )}
                  </Card>

                  <Card title="保存检查" eyebrow="Validation">
                    <div className="stack">
                      <div className="note-box note-box--soft">
                        这里的每一项都会写入 `BepInEx/config/codex.longyin.custom-talents.json`。当前版本只在下次启动游戏时读取。
                      </div>
                      {customTalentValidationErrors.length > 0 ? (
                        <div className="validation-box">
                          {customTalentValidationErrors.map((item) => (
                            <div key={item}>{item}</div>
                          ))}
                        </div>
                      ) : (
                        <div className="empty-state">当前草稿通过校验，可以安全应用。</div>
                      )}
                      <div className="inline-actions">
                        <button
                          className="btn btn--primary"
                          onClick={saveCustomTalents}
                          disabled={working !== null || !gameRoot || customTalentWriteBlocked || customTalentValidationErrors.length > 0 || !customTalentDirty}
                        >
                          应用到游戏配置
                        </button>
                      </div>
                    </div>
                  </Card>
                </div>
              </div>
            ) : null}




          </main>
        </div>
      </div>
    </div>
  );
}
