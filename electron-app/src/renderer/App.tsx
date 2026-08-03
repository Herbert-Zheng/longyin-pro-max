import { useEffect, useMemo, useState } from 'react';
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
import {
  BATTLE_TURBO_HOTKEYS,
  Card,
  CheckboxField,
  HOTKEY_OPTIONS,
  NumberField,
  SelectField,
  StatusPill,
  TextField,
  clampText,
  defaultSettings,
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
  return `${talent.conditions.length} 条条件 · ${talent.effects.length} 条效果 · ${talent.durationDays} 天`;
}

export function App() {
  const [snapshot, setSnapshot] = useState<GameSnapshot | null>(null);
  const [settings, setSettings] = useState<VisibleSettings>(defaultSettings());
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

  const navItems = useMemo<NavItem[]>(
    () => [
      { key: 'home', label: '主页', eyebrow: 'Launcher', title: '主页', description: '集中处理安装、自检、保存配置与安全启动。' },
      { key: 'updates', label: '更新记录', eyebrow: 'OTA', title: '更新记录', description: '查看当前版本、GitHub Release 说明与 OTA 运行日志。' },
      { key: 'systems', label: '系统更改', eyebrow: 'Runtime', title: '系统更改', description: '整理全局运行控制、时间冻结与环境自检。' },
      { key: 'expTalent', label: '经验值，天赋相关', eyebrow: 'Growth', title: '经验值，天赋相关', description: '把经验成长、心悟机制与突破天赋放在同一页。' },
      { key: 'customTalent', label: '自定义天赋', eyebrow: 'Creator', title: '自定义天赋', description: '创建、编辑和管理多个自定义天赋，保存后下次启动游戏生效。' },
      { key: 'worldExplore', label: '大地图，探索类', eyebrow: 'Explore', title: '大地图，探索类', description: '专注探索体力、世界地图坐骑与移动体验。' },
      { key: 'tradeCraft', label: '交易，制造类', eyebrow: 'Commerce', title: '交易，制造类', description: '交易、背包与制造增产统一归档。' },
      { key: 'socialTeam', label: '聊天，关系，组队', eyebrow: 'Social', title: '聊天，关系，组队', description: '把聊天配额、关系提升与组队辅助集中展示。' },
      { key: 'battle', label: '战斗相关', eyebrow: 'Battle', title: '战斗相关', description: '收纳战斗数值、战斗节奏与战斗加速。' }
    ],
    []
  );

  const activeNav = navItems.find((item) => item.key === activePage) ?? navItems[0];

  const updateSetting = <K extends keyof VisibleSettings>(key: K, value: VisibleSettings[K]) => {
    setSettings((current) => mergeSettings(current, { [key]: value } as Partial<VisibleSettings>));
  };

  const replaceCustomTalentPack = (nextPack: CustomTalentPack) => {
    setCustomTalentPack(cloneCustomTalentPack(nextPack));
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
      setSettings(next.visibleSettings);
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

  const run = async (label: string, action: () => Promise<any>) => {
    setWorking(label);
    clearError();
    try {
      const result = await action();
      if (result?.updatedSnapshot) {
        setSnapshot(result.updatedSnapshot);
        setSettings(result.updatedSnapshot.visibleSettings);
        setUpdate(result.updatedSnapshot.update);
        setMessage(result.message ?? label);
      }
      else {
        await refresh(label);
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
  const customTalentDirty = JSON.stringify(customTalentPack) !== savedCustomTalentPackText;
  const saveAndLaunchDisabledReason = !customTalentsReady
    ? customTalentLoadError
      ? `自定义天赋读取失败：${customTalentLoadError}`
      : '正在读取自定义天赋，请稍候。'
    : customTalentValidationErrors.length > 0
      ? `自定义天赋尚未通过校验：${customTalentValidationErrors[0]}`
      : !launchReady
        ? snapshot?.launchNote ?? '当前环境尚未达到启动条件。'
        : null;

  const save = async () => {
    setWorking('保存中');
    clearError();
    try {
      const nextSnapshot = await window.longyin.saveSettings(settings);
      setSnapshot(nextSnapshot);
      setSettings(nextSnapshot.visibleSettings);
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
    setWorking('应用自定义天赋');
    clearError();
    try {
      const result = await window.longyin.saveCustomTalents(customTalentPack);
      replaceCustomTalentPack(result.pack);
      setSavedCustomTalentPackText(JSON.stringify(result.pack));
      setCustomTalentLoadError(null);
      setMessage(result.message);
    }
    catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      setCustomTalentLoadError(message);
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

    setCustomTalentPack((current) => ({
      version: current.version,
      talents: current.talents.filter((talent) => talent.id !== selectedCustomTalent.id)
    }));
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
    const result = await run('保存并启动', () => window.longyin.saveAndLaunch({ settings, customTalents: customTalentPack }));
    if (result?.customTalents) {
      replaceCustomTalentPack(result.customTalents);
      setSavedCustomTalentPackText(JSON.stringify(result.customTalents));
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
    await run('启动 Overlay', () => window.longyin.startOverlay());
  };

  const stopOverlay = async () => {
    await run('关闭 Overlay', () => window.longyin.stopOverlay());
  };

  const install = async () => {
    await run('安装模组', () => window.longyin.install());
  };

  const uninstall = async () => {
    await run('卸载模组', () => window.longyin.uninstall());
  };

  const launch = async () => {
    await run('启动游戏', () => window.longyin.launch());
  };

  const pickGameRoot = async () => {
    setWorking('选择目录');
    clearError();
    try {
      const next = await window.longyin.pickGameRoot();
      setSnapshot(next);
      setSettings(next.visibleSettings);
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
        setSettings(result.updatedSnapshot.visibleSettings);
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
      <div className="ambient ambient--one" />
      <div className="ambient ambient--two" />
      <div className="ambient ambient--three" />

      <div className="dashboard">
        <aside className="sidebar">
          <div className="sidebar__brand">
            <span className="eyebrow">龙胤立志传 Pro Max</span>
            <h1>控制台</h1>
            <p>左侧按功能分区，右侧专注当前页面，不再把所有开关堆在一起。</p>
          </div>

          <nav className="sidebar__nav" aria-label="主导航">
            {navItems.map((item) => (
              <button
                key={item.key}
                className={`nav-item ${activePage === item.key ? 'nav-item--active' : ''}`}
                onClick={() => setActivePage(item.key)}
              >
                <span className="nav-item__eyebrow">{item.eyebrow}</span>
                <strong>{item.label}</strong>
                <span className="nav-item__desc">{item.description}</span>
              </button>
            ))}
          </nav>

          <div className="sidebar__panel">
            <div className="sidebar__panel-row">
              <span>应用版本</span>
              <strong>{snapshot.appVersion}</strong>
            </div>
            <div className="sidebar__panel-row">
              <span>游戏目录</span>
              <strong>{gameRoot ? '已连接' : '未选择'}</strong>
            </div>
            <div className="sidebar__panel-row">
              <span>模组状态</span>
              <strong>{gameInstalled ? '已就绪' : gameRoot ? '需修复' : '未安装'}</strong>
            </div>
            <div className="sidebar__panel-row">
              <span>更新状态</span>
              <strong>{update?.updateAvailable ? `可升级到 ${update.latestVersion}` : '已是最新'}</strong>
            </div>
          </div>
        </aside>

        <div className="workspace">
          <header className="workspace__hero card">
            <div className="workspace__hero-copy">
              <span className="eyebrow">{activeNav.eyebrow}</span>
              <h2>{activeNav.title}</h2>
              <p>{activeNav.description}</p>
            </div>

            <div className="workspace__hero-actions">
              <button className="btn btn--primary" onClick={save} disabled={working !== null}>
                保存设置
              </button>
              <button
                className="btn btn--ghost"
                onClick={saveAndLaunch}
                disabled={working !== null || saveAndLaunchDisabledReason !== null}
                title={saveAndLaunchDisabledReason ?? '保存普通设置和当前自定义天赋后启动游戏。'}
              >
                {launchBusy ? '启动中，请等待' : '保存并启动'}
              </button>
              <button
                className={`btn btn--launch ${launchBusy ? 'btn--launching' : ''}`}
                onClick={launch}
                disabled={working !== null || !launchReady}
              >
                <span className="btn--launch__glow" />
                <span className="btn--launch__label">{launchBusy ? '启动中，请等待' : '启动游戏'}</span>
              </button>
            </div>
          </header>

          <section className="summary-grid">
            <StatusPill label="应用版本" value={snapshot.appVersion} tone="good" />
            <StatusPill label="游戏目录" value={gameRoot ? '已连接' : '未选择'} tone={gameRoot ? 'good' : 'warn'} />
            <StatusPill label="模组状态" value={gameInstalled ? '已就绪' : gameRoot ? '需修复' : '未安装'} tone={gameInstalled ? 'good' : 'warn'} />
            <StatusPill
              label="启动状态"
              value={snapshot.launchState === 'starting' ? '启动中' : snapshot.launchState === 'running' ? '运行中' : '待命'}
              tone={launchTone(snapshot.launchState)}
            />
            <StatusPill label="环境自检" value={health.summary} tone={healthTone(snapshot)} />
            <StatusPill label="OTA 通道" value={update?.updateAvailable ? `发现 ${update.latestVersion}` : '已是最新'} tone={update?.updateAvailable ? 'warn' : 'good'} />
          </section>

          <section className="status-strip">
            <div className="status-strip__label">当前状态</div>
            <div className="status-strip__value">{working ?? message}</div>
          </section>

          {copyNotice ? <div className="copy-banner">{copyNotice}</div> : null}

          {error ? (
            <div className="error-banner">
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
                    <button className="btn" onClick={uninstall} disabled={working !== null || !gameRoot || launchBusy}>
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
              <div className="page-grid">
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

                <Card title="游戏 Overlay" eyebrow="Overlay">
                  <div className="stack">
                    <CheckboxField
                      label="随游戏启动 Overlay"
                      value={snapshot.launcherPreferences.launchOverlayWithGame}
                      onChange={(value) => void setLaunchOverlayWithGame(value)}
                    />
                    <p className="body-copy body-copy--muted">
                      Overlay 自带单实例保护。由启动器随游戏启动的实例会在游戏退出后自动关闭。
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
                    <CheckList
                      items={health.checks.map((check) => `${check.ok ? '已通过' : '需处理'} · ${check.label} · ${check.detail}`)}
                      empty={gameRoot ? '没有可展示的环境检查。' : '选择游戏目录后，这里会出现完整自检信息。'}
                    />
                  </div>
                </Card>
              </div>
            ) : null}

            {activePage === 'expTalent' ? (
              <div className="page-grid">
                <Card title="经验成长" eyebrow="EXP">
                  <div className="field-grid">
                    <NumberField
                      label="书籍经验倍率"
                      value={settings.expMultiplier}
                      onChange={(value) => updateSetting('expMultiplier', value)}
                      min={1}
                      max={999}
                      step={1}
                    />
                    <NumberField
                      label="战斗武学经验倍率"
                      value={settings.battleSkillExpMultiplier}
                      onChange={(value) => updateSetting('battleSkillExpMultiplier', value)}
                      min={1}
                      max={999}
                      step={1}
                      hint="只影响战斗内通过出招获得的武学经验，敌我双方都会生效。"
                    />
                    <NumberField
                      label="创作点倍率"
                      value={settings.creationPointMultiplier}
                      onChange={(value) => updateSetting('creationPointMultiplier', value)}
                      min={1}
                      max={999}
                      step={1}
                    />
                  </div>
                  <p className="body-copy body-copy--muted">
                    武学写书现在直接按角色属性结算消耗，不再提供独立倍率开关。
                  </p>
                </Card>

                <Card title="心悟机制" eyebrow="Insight">
                  <div className="field-grid">
                    <NumberField
                      label="心悟触发几率"
                      value={settings.dailySkillInsightChancePercent}
                      onChange={(value) => updateSetting('dailySkillInsightChancePercent', value)}
                      min={0}
                      max={100}
                      step={1}
                      suffix="%"
                    />
                    <NumberField
                      label="心悟经验值比率"
                      value={settings.dailySkillInsightExpPercent}
                      onChange={(value) => updateSetting('dailySkillInsightExpPercent', value)}
                      min={0}
                      max={999}
                      step={0.5}
                      suffix="%"
                    />
                    <CheckboxField
                      label="心悟经验值按武学品级调整"
                      value={settings.dailySkillInsightUseRarityScaling}
                      onChange={(value) => updateSetting('dailySkillInsightUseRarityScaling', value)}
                    />
                    <NumberField
                      label="心悟触发频率"
                      value={settings.dailySkillInsightRealtimeIntervalSeconds}
                      onChange={(value) => updateSetting('dailySkillInsightRealtimeIntervalSeconds', value)}
                      min={0}
                      max={999}
                      step={0.5}
                      suffix="秒"
                    />
                  </div>
                </Card>

                <Card title="突破成功额外天赋" eyebrow="Talent">
                  <div className="field-grid">
                    <CheckboxField
                      label="启用突破成功额外天赋"
                      value={settings.skillTalentEnabled}
                      onChange={(value) => updateSetting('skillTalentEnabled', value)}
                    />
                    <CheckboxField
                      label="仅玩家角色"
                      value={settings.skillTalentPlayerOnly}
                      onChange={(value) => updateSetting('skillTalentPlayerOnly', value)}
                    />
                    <NumberField
                      label="武学等级触发"
                      value={settings.skillTalentLevelThreshold}
                      onChange={(value) => updateSetting('skillTalentLevelThreshold', value)}
                      min={1}
                      max={999}
                      step={1}
                      hint="如果设为 5，武学修炼到 5 级时触发天赋奖励。"
                    />
                    <NumberField
                      label="品级天赋倍率"
                      value={settings.skillTalentTierPointMultiplier}
                      onChange={(value) => updateSetting('skillTalentTierPointMultiplier', value)}
                      min={0.1}
                      max={999}
                      step={0.25}
                      hint="如果倍率 = 1，灰级 = 1 点、青级 = 2 点天赋。"
                    />
                  </div>
                </Card>
              </div>
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
                            disabled={working !== null || !gameRoot || customTalentValidationErrors.length > 0 || !customTalentDirty}
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
                          disabled={working !== null || !gameRoot || customTalentValidationErrors.length > 0 || !customTalentDirty}
                        >
                          应用到游戏配置
                        </button>
                      </div>
                    </div>
                  </Card>
                </div>
              </div>
            ) : null}

            {activePage === 'worldExplore' ? (
              <div className="page-grid">
                <Card title="探索辅助" eyebrow="Explore">
                  <div className="stack">
                    <p className="body-copy">
                      这页只保留确认有效的探索与大地图项。已确认无效的“宝箱自动选最高价值”已从界面和脚本中移除。
                    </p>
                    <div className="field-grid field-grid--single">
                      <CheckboxField
                        label="锁定探索体力"
                        value={settings.lockStamina}
                        onChange={(value) => updateSetting('lockStamina', value)}
                        hint="避免探索行动消耗体力。"
                      />
                      <CheckboxField
                        label="首次移动后揭开全部探索迷雾"
                        value={settings.revealAllOnStepTile}
                        onChange={(value) => updateSetting('revealAllOnStepTile', value)}
                        hint="开启后，每次进入探索地图并完成第一次移动时揭开整张地图；关闭时保持原版迷雾探索。"
                      />
                    </div>
                  </div>
                </Card>

                <Card title="世界地图坐骑" eyebrow="World Map">
                  <div className="field-grid">
                    <CheckboxField
                      label="锁定加速体力"
                      value={settings.lockHorseTurboStamina}
                      onChange={(value) => updateSetting('lockHorseTurboStamina', value)}
                      hint="避免体力耗尽时加速提前结束。"
                    />
                    <NumberField
                      label="坐骑体力倍率"
                      value={settings.horseStaminaMultiplier}
                      onChange={(value) => updateSetting('horseStaminaMultiplier', value)}
                      min={0.01}
                      max={999}
                      step={0.25}
                      hint="大于 1 的数值会让坐骑持续更久。"
                    />
                    <NumberField
                      label="基础速度倍率"
                      value={settings.horseBaseSpeedMultiplier}
                      onChange={(value) => updateSetting('horseBaseSpeedMultiplier', value)}
                      min={0.01}
                      max={999}
                      step={0.25}
                    />
                    <NumberField
                      label="加速速度倍率"
                      value={settings.horseTurboSpeedMultiplier}
                      onChange={(value) => updateSetting('horseTurboSpeedMultiplier', value)}
                      min={0.01}
                      max={999}
                      step={0.25}
                    />
                    <NumberField
                      label="加速持续倍率"
                      value={settings.horseTurboDurationMultiplier}
                      onChange={(value) => updateSetting('horseTurboDurationMultiplier', value)}
                      min={0.01}
                      max={999}
                      step={0.25}
                    />
                    <NumberField
                      label="加速冷却倍率"
                      value={settings.horseTurboCooldownMultiplier}
                      onChange={(value) => updateSetting('horseTurboCooldownMultiplier', value)}
                      min={0.01}
                      max={999}
                      step={0.25}
                    />
                  </div>
                </Card>
              </div>
            ) : null}

            {activePage === 'tradeCraft' ? (
              <div className="page-grid">
                <Card title="交易与背包" eyebrow="Trade">
                  <div className="field-grid">
                    <NumberField
                      label="商人现金下限"
                      value={settings.merchantCarryCash}
                      onChange={(value) => updateSetting('merchantCarryCash', value)}
                      min={0}
                      max={999999999}
                      step={1000}
                    />
                    <CheckboxField
                      label="显示珍宝交易估价"
                      value={settings.treasureTradeHelperEnabled}
                      onChange={(value) => updateSetting('treasureTradeHelperEnabled', value)}
                      hint="在出售珍宝的商店中显示当前转售估价与技能影响。"
                    />
                    <CheckboxField
                      label="珍宝自动加入购物车"
                      value={settings.treasureAutoTradeEnabled}
                      onChange={(value) => updateSetting('treasureAutoTradeEnabled', value)}
                      hint="进入珍宝铺时，自动把预估有利润的未鉴定珍宝加入购物车；不会替你结账。"
                    />
                    <CheckboxField
                      label="启用材料一键扫货"
                      value={settings.materialAutoBuyEnabled}
                      onChange={(value) => updateSetting('materialAutoBuyEnabled', value)}
                      hint="在商店内显示材料扫货按钮和筛选菜单；只批量加入购物车，仍需手动结账。"
                    />
                    <NumberField
                      label="扫货最低品级"
                      value={settings.materialPurchaseMinRareLv}
                      onChange={(value) => updateSetting('materialPurchaseMinRareLv', value)}
                      min={0}
                      max={5}
                      step={1}
                      hint="0 表示不限；1–5 表示只加入达到该品级的材料。"
                    />
                    <NumberField
                      label="扫货最低等级"
                      value={settings.materialPurchaseMinItemLv}
                      onChange={(value) => updateSetting('materialPurchaseMinItemLv', value)}
                      min={0}
                      max={5}
                      step={1}
                      hint="0 表示不限；1–5 表示只加入达到该等级的材料。"
                    />
                    <CheckboxField
                      label="启用店铺产业与买断"
                      value={settings.shopOwnershipEnabled}
                      onChange={(value) => updateSetting('shopOwnershipEnabled', value)}
                      hint="在商店界面显示产业信息与买断按钮；关闭后隐藏相关入口。"
                    />
                    <NumberField
                      label="幸运返利命中概率"
                      value={settings.luckyHitChancePercent}
                      onChange={(value) => updateSetting('luckyHitChancePercent', value)}
                      min={0}
                      max={100}
                      step={1}
                      suffix="%"
                    />
                    <CheckboxField
                      label="忽略负重"
                      value={settings.ignoreCarryWeight}
                      onChange={(value) => updateSetting('ignoreCarryWeight', value)}
                    />
                    <NumberField
                      label="负重上限"
                      value={settings.carryWeightCap}
                      onChange={(value) => updateSetting('carryWeightCap', value)}
                      min={0}
                      max={999999999}
                      step={1000}
                    />
                  </div>
                </Card>

                <Card title="拍卖与珍宝鉴定" eyebrow="Auction">
                  <div className="field-grid">
                    <CheckboxField
                      label="拍卖会固定红色等级"
                      value={settings.auctionEventAlwaysRedEnabled}
                      onChange={(value) => updateSetting('auctionEventAlwaysRedEnabled', value)}
                      hint="开启后新生成的拍卖大会固定为红色最高等级，事件难度及按等级生成的拍品会相应提高；关闭后恢复原版随机等级。"
                    />
                    <CheckboxField
                      label="启用拍卖预览免费刷新"
                      value={settings.auctionPreviewRefreshEnabled}
                      onChange={(value) => updateSetting('auctionPreviewRefreshEnabled', value)}
                      hint="在拍卖展品预览窗口增加不限次数的免费刷新按钮。"
                    />
                    <TextField
                      label="拍卖刷新主键"
                      value={settings.auctionPreviewRefreshHotkey}
                      onChange={(value) => updateSetting('auctionPreviewRefreshHotkey', value)}
                      hint="填写 Unity KeyCode 名称，例如 R、F8 或 Mouse3。"
                    />
                    <CheckboxField
                      label="拍卖刷新需要按住 Alt"
                      value={settings.auctionPreviewRefreshRequireAlt}
                      onChange={(value) => updateSetting('auctionPreviewRefreshRequireAlt', value)}
                      hint="开启时快捷键为 Alt + 主键。"
                    />
                    <CheckboxField
                      label="启用鉴宝最高鉴定价辅助"
                      value={settings.treasureIdentifyBestValueAssistEnabled}
                      onChange={(value) => updateSetting('treasureIdentifyBestValueAssistEnabled', value)}
                      hint="按鼠标悬浮括号内的玩家鉴定价选择最高项；最终确认仍需手动完成。"
                    />
                    <TextField
                      label="最高估值选择主键"
                      value={settings.treasureIdentifyBestValueHotkey}
                      onChange={(value) => updateSetting('treasureIdentifyBestValueHotkey', value)}
                      hint="填写 Unity KeyCode 名称，例如 F、F8 或 Mouse3。"
                    />
                    <CheckboxField
                      label="最高估值选择需要按住 Alt"
                      value={settings.treasureIdentifyBestValueRequireAlt}
                      onChange={(value) => updateSetting('treasureIdentifyBestValueRequireAlt', value)}
                      hint="开启时快捷键为 Alt + 主键。"
                    />
                  </div>
                </Card>

                <Card title="制造增产" eyebrow="Craft">
                  <div className="field-grid">
                    <CheckboxField
                      label="追加材料按大阶增产"
                      value={settings.craftRandomPickUpgrade}
                      onChange={(value) => updateSetting('craftRandomPickUpgrade', value)}
                      hint="按追加材料的大阶给成品加数量。下面 5 个数值分别对应一阶到五阶。"
                    />
                    <NumberField
                      label="一阶额外数量"
                      value={settings.craftTier1ExtraItems}
                      onChange={(value) => updateSetting('craftTier1ExtraItems', value)}
                      min={0}
                      max={999}
                      step={1}
                    />
                    <NumberField
                      label="二阶额外数量"
                      value={settings.craftTier2ExtraItems}
                      onChange={(value) => updateSetting('craftTier2ExtraItems', value)}
                      min={0}
                      max={999}
                      step={1}
                    />
                    <NumberField
                      label="三阶额外数量"
                      value={settings.craftTier3ExtraItems}
                      onChange={(value) => updateSetting('craftTier3ExtraItems', value)}
                      min={0}
                      max={999}
                      step={1}
                    />
                    <NumberField
                      label="四阶额外数量"
                      value={settings.craftTier4ExtraItems}
                      onChange={(value) => updateSetting('craftTier4ExtraItems', value)}
                      min={0}
                      max={999}
                      step={1}
                    />
                    <NumberField
                      label="五阶额外数量"
                      value={settings.craftTier5ExtraItems}
                      onChange={(value) => updateSetting('craftTier5ExtraItems', value)}
                      min={0}
                      max={999}
                      step={1}
                    />
                  </div>
                </Card>
              </div>
            ) : null}

            {activePage === 'socialTeam' ? (
              <div className="page-grid">
                <Card title="聊天与互动" eyebrow="Dialog">
                  <div className="field-grid">
                    <NumberField
                      label="每月对话次数倍率"
                      value={settings.dialogMonthlyLimitMultiplier}
                      onChange={(value) => updateSetting('dialogMonthlyLimitMultiplier', value)}
                      min={0}
                      max={999}
                      step={1}
                      hint="影响交谈、请教等每月互动次数。"
                    />
                    <CheckboxField
                      label="启用剧情快进辅助"
                      value={settings.dialogFastForwardAssistEnabled}
                      onChange={(value) => updateSetting('dialogFastForwardAssistEnabled', value)}
                      hint="在剧情出现快进按钮时自动开启快进，游戏内热键仍然是 P。"
                    />
                    <NumberField
                      label="额外好感增长"
                      value={settings.extraRelationshipGainChancePercent}
                      onChange={(value) => updateSetting('extraRelationshipGainChancePercent', value)}
                      min={0}
                      max={100}
                      step={1}
                      suffix="%"
                    />
                  </div>
                </Card>

                <Card title="关系与组队" eyebrow="Relationship">
                  <div className="stack">
                    <p className="body-copy">已确认无效的“队友离队天数倍率”已移除，避免继续在界面里误导使用。</p>
                    <div className="field-grid">
                      <CheckboxField
                        label="队友每日自动加好感"
                        value={settings.teamAutoFavorEnabled}
                        onChange={(value) => updateSetting('teamAutoFavorEnabled', value)}
                        hint="当前队伍中的已招募 NPC 会在每个游戏日自动获得好感。"
                      />
                      <NumberField
                        label="队友每日自动加好感点数"
                        value={settings.teamAutoFavorPerDay}
                        onChange={(value) => updateSetting('teamAutoFavorPerDay', value)}
                        min={0}
                        max={999}
                        step={1}
                      />
                      <NumberField
                        label="伴侣上限"
                        value={settings.maxLoverCount}
                        onChange={(value) => updateSetting('maxLoverCount', value)}
                        min={1}
                        max={999}
                        step={1}
                        hint="提高玩家可同时拥有的伴侣/夫妻数量。默认改为 8。"
                      />
                    </div>
                  </div>
                </Card>
              </div>
            ) : null}

            {activePage === 'battle' ? (
              <div className="page-grid">
                <Card title="战斗数值" eyebrow="Combat">
                  <div className="field-grid">
                    <NumberField
                      label="辩论我方伤害倍率"
                      value={settings.debatePlayerDamageTakenMultiplier}
                      onChange={(value) => updateSetting('debatePlayerDamageTakenMultiplier', value)}
                      min={0}
                      max={999}
                      step={0.25}
                    />
                    <NumberField
                      label="辩论敌方伤害倍率"
                      value={settings.debateEnemyDamageTakenMultiplier}
                      onChange={(value) => updateSetting('debateEnemyDamageTakenMultiplier', value)}
                      min={0}
                      max={999}
                      step={0.25}
                    />
                    <NumberField
                      label="对酒我方伤害倍率"
                      value={settings.drinkPlayerPowerCostMultiplier}
                      onChange={(value) => updateSetting('drinkPlayerPowerCostMultiplier', value)}
                      min={0}
                      max={999}
                      step={0.25}
                    />
                    <NumberField
                      label="对酒敌方伤害倍率"
                      value={settings.drinkEnemyPowerCostMultiplier}
                      onChange={(value) => updateSetting('drinkEnemyPowerCostMultiplier', value)}
                      min={0}
                      max={999}
                      step={0.25}
                    />
                  </div>
                </Card>

                <Card title="战斗节奏" eyebrow="Turbo">
                  <div className="stack">
                    <CheckboxField
                      label="启动时开启战斗加速"
                      value={settings.battleTurboEnabled}
                      onChange={(value) => updateSetting('battleTurboEnabled', value)}
                    />
                    <SelectField
                      label="战斗加速快捷键"
                      value={settings.battleTurboHotkey}
                      onChange={(value) => updateSetting('battleTurboHotkey', clampText(value))}
                      options={BATTLE_TURBO_HOTKEYS}
                      hint="在战斗中按下可切换加速开关。20x 速度，取消技能视觉特效。"
                    />
                    <p className="body-copy body-copy--muted">保存时会自动保留原始模组配置中的高级计时与视觉标记。</p>
                  </div>
                </Card>
              </div>
            ) : null}
          </main>
        </div>
      </div>
    </div>
  );
}
