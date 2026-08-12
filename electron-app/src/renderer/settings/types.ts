import type { VisibleSettings } from '../../shared/types';

export type SettingsPage = 'expTalent' | 'worldExplore' | 'tradeCraft' | 'socialTeam' | 'battle';

export type SettingChangeHandler = <K extends keyof VisibleSettings>(key: K, value: VisibleSettings[K]) => void;

export type SettingsPageProps = {
  settings: VisibleSettings;
  onSettingChange: SettingChangeHandler;
};
