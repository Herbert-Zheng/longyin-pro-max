import type { LaunchAvailability } from '../../shared/launcher-state';

export type LauncherAction = {
  run: () => void;
  availability: LaunchAvailability;
};

export function LaunchActions(props: {
  save: LauncherAction;
  saveAndLaunch: LauncherAction;
  launchSaved: LauncherAction;
  configurationDirty: boolean;
  launchBusy: boolean;
}) {
  const unsavedPersistenceNote = '当前未保存修改仍会保留在界面中。';
  const saveTitle = props.save.availability.disabledReason ?? '保存当前普通设置。';
  const saveAndLaunchTitle =
    props.saveAndLaunch.availability.disabledReason ?? '保存普通设置和当前自定义天赋后启动游戏。';
  const launchSavedTitle =
    props.launchSaved.availability.disabledReason ??
    (props.launchSaved.availability.warning
      ? `${props.launchSaved.availability.warning}${unsavedPersistenceNote}`
      : null) ??
    '使用当前已保存的配置启动游戏。';

  return (
    <div className="workspace__hero-actions" aria-label="保存与启动">
      <button
        className="btn btn--primary"
        onClick={props.saveAndLaunch.run}
        disabled={!props.saveAndLaunch.availability.enabled}
        title={saveAndLaunchTitle}
      >
        {props.launchBusy ? '启动中，请等待' : '保存并启动'}
      </button>
      <button
        className="btn"
        onClick={props.save.run}
        disabled={!props.save.availability.enabled}
        title={saveTitle}
      >
        {props.configurationDirty ? '保存设置 · 未保存' : '保存设置'}
      </button>
      <button
        className="btn btn--ghost"
        onClick={props.launchSaved.run}
        disabled={!props.launchSaved.availability.enabled}
        title={launchSavedTitle}
      >
        {props.launchBusy ? '启动中，请等待' : props.configurationDirty ? '启动已保存配置' : '直接启动'}
      </button>
      {props.launchSaved.availability.warning ? (
        <span className="launch-actions__warning" role="note">
          {props.launchSaved.availability.warning} {unsavedPersistenceNote}
        </span>
      ) : null}
    </div>
  );
}
