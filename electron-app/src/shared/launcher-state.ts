export type ConfigurationStatusKey = 'disconnected' | 'loading' | 'load-error' | 'dirty' | 'saved';

export type ConfigurationStatus = {
  key: ConfigurationStatusKey;
  label: string;
  detail: string;
  tone: 'good' | 'warn' | 'neutral';
};

export type ConfigurationFacts = {
  gameRoot?: string | null;
  customTalentsReady: boolean;
  customTalentLoadError?: string | null;
  settingsDirty: boolean;
  customTalentDirty: boolean;
};

export function deriveConfigurationStatus(facts: ConfigurationFacts): ConfigurationStatus {
  if (!facts.gameRoot) {
    return { key: 'disconnected', label: '未连接', detail: '未连接游戏目录', tone: 'neutral' };
  }

  if (facts.customTalentLoadError) {
    return { key: 'load-error', label: '读取失败', detail: '自定义天赋读取失败', tone: 'warn' };
  }

  if (!facts.customTalentsReady) {
    return { key: 'loading', label: '正在读取', detail: '正在读取游戏配置', tone: 'warn' };
  }

  if (facts.settingsDirty || facts.customTalentDirty) {
    return { key: 'dirty', label: '有未保存更改', detail: '配置有未保存更改', tone: 'warn' };
  }

  return { key: 'saved', label: '已保存', detail: '配置已保存', tone: 'good' };
}

export const getConfigurationStatus = deriveConfigurationStatus;

export type LaunchMode = 'save-and-launch' | 'launch-saved';

export type LaunchFacts = {
  mode: LaunchMode;
  gameRoot?: string | null;
  working?: string | null;
  launchBusy: boolean;
  launchReady: boolean;
  launchNote?: string | null;
  customTalentsReady: boolean;
  customTalentLoadError?: string | null;
  customTalentValidationErrors?: readonly string[];
  settingsDirty: boolean;
  customTalentDirty: boolean;
};

export type LaunchAvailability = {
  enabled: boolean;
  disabledReason: string | null;
  warning: string | null;
};

/**
 * Converts launcher facts into the complete action state used by both buttons and tooltips.
 * "launch-saved" deliberately ignores unsaved editor validation because it starts the last
 * persisted configuration; callers receive a warning instead of having to duplicate that rule.
 */
export function deriveLaunchAvailability(facts: LaunchFacts): LaunchAvailability {
  let disabledReason: string | null = null;

  if (facts.working) {
    disabledReason = `${facts.working}，请稍候。`;
  }
  else if (!facts.gameRoot) {
    disabledReason = '请先选择游戏目录。';
  }
  else if (facts.launchBusy) {
    disabledReason = '游戏正在启动或运行中。';
  }
  else if (facts.mode === 'save-and-launch' && facts.customTalentLoadError) {
    disabledReason = `自定义天赋读取失败：${facts.customTalentLoadError}`;
  }
  else if (facts.mode === 'save-and-launch' && !facts.customTalentsReady) {
    disabledReason = '正在读取自定义天赋，请稍候。';
  }
  else if (facts.mode === 'save-and-launch' && (facts.customTalentValidationErrors?.length ?? 0) > 0) {
    disabledReason = `自定义天赋尚未通过校验：${facts.customTalentValidationErrors?.[0]}`;
  }
  else if (!facts.launchReady) {
    disabledReason = facts.launchNote?.trim() || '当前环境尚未达到启动条件。';
  }

  const hasUnsavedChanges = facts.settingsDirty || facts.customTalentDirty;
  const warning =
    facts.mode === 'launch-saved' && hasUnsavedChanges
      ? '当前修改尚未保存；本次将使用上次保存的配置启动。'
      : null;

  return {
    enabled: disabledReason === null,
    disabledReason,
    warning
  };
}

export const getSaveAndLaunchDisabledReason = (facts: Omit<LaunchFacts, 'mode'>): string | null =>
  deriveLaunchAvailability({ ...facts, mode: 'save-and-launch' }).disabledReason;
