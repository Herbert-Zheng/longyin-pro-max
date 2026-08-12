import { BATTLE_TURBO_HOTKEYS, Card, CheckboxField, NumberField, SelectField, clampText } from '../components';
import type { SettingsPageProps } from './types';

export function BattleSettingsPage({ settings, onSettingChange }: SettingsPageProps) {
  return (
    <div className="page-grid">
      <Card title="战斗数值" eyebrow="Combat">
        <div className="field-grid">
          <NumberField
            label="辩论我方伤害倍率"
            value={settings.debatePlayerDamageTakenMultiplier}
            onChange={(value) => onSettingChange('debatePlayerDamageTakenMultiplier', value)}
            min={0}
            max={999}
            step={0.25}
          />
          <NumberField
            label="辩论敌方伤害倍率"
            value={settings.debateEnemyDamageTakenMultiplier}
            onChange={(value) => onSettingChange('debateEnemyDamageTakenMultiplier', value)}
            min={0}
            max={999}
            step={0.25}
          />
          <NumberField
            label="对酒我方伤害倍率"
            value={settings.drinkPlayerPowerCostMultiplier}
            onChange={(value) => onSettingChange('drinkPlayerPowerCostMultiplier', value)}
            min={0}
            max={999}
            step={0.25}
          />
          <NumberField
            label="对酒敌方伤害倍率"
            value={settings.drinkEnemyPowerCostMultiplier}
            onChange={(value) => onSettingChange('drinkEnemyPowerCostMultiplier', value)}
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
            onChange={(value) => onSettingChange('battleTurboEnabled', value)}
          />
          <SelectField
            label="战斗加速快捷键"
            value={settings.battleTurboHotkey}
            onChange={(value) => onSettingChange('battleTurboHotkey', clampText(value))}
            options={BATTLE_TURBO_HOTKEYS}
            hint="在战斗中按下可切换加速开关。20x 速度，取消技能视觉特效。"
          />
          <p className="body-copy body-copy--muted">保存时会自动保留原始模组配置中的高级计时与视觉标记。</p>
        </div>
      </Card>
    </div>
  );
}
