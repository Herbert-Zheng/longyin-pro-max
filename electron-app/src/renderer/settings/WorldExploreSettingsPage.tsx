import { Card, CheckboxField, NumberField, TextField } from '../components';
import type { SettingsPageProps } from './types';

export function WorldExploreSettingsPage({ settings, onSettingChange }: SettingsPageProps) {
  return (
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
              onChange={(value) => onSettingChange('lockStamina', value)}
              hint="避免探索行动消耗体力。"
            />
            <CheckboxField
              label="首次移动后揭开全部探索迷雾"
              value={settings.revealAllOnStepTile}
              onChange={(value) => onSettingChange('revealAllOnStepTile', value)}
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
            onChange={(value) => onSettingChange('lockHorseTurboStamina', value)}
            hint="避免体力耗尽时加速提前结束。"
          />
          <NumberField
            label="坐骑体力倍率"
            value={settings.horseStaminaMultiplier}
            onChange={(value) => onSettingChange('horseStaminaMultiplier', value)}
            min={0.01}
            max={999}
            step={0.25}
            hint="大于 1 的数值会让坐骑持续更久。"
          />
          <NumberField
            label="基础速度倍率"
            value={settings.horseBaseSpeedMultiplier}
            onChange={(value) => onSettingChange('horseBaseSpeedMultiplier', value)}
            min={0.01}
            max={999}
            step={0.25}
          />
          <NumberField
            label="加速速度倍率"
            value={settings.horseTurboSpeedMultiplier}
            onChange={(value) => onSettingChange('horseTurboSpeedMultiplier', value)}
            min={0.01}
            max={999}
            step={0.25}
          />
          <NumberField
            label="加速持续倍率"
            value={settings.horseTurboDurationMultiplier}
            onChange={(value) => onSettingChange('horseTurboDurationMultiplier', value)}
            min={0.01}
            max={999}
            step={0.25}
          />
          <NumberField
            label="加速冷却倍率"
            value={settings.horseTurboCooldownMultiplier}
            onChange={(value) => onSettingChange('horseTurboCooldownMultiplier', value)}
            min={0.01}
            max={999}
            step={0.25}
          />
        </div>
      </Card>

      <Card title="城内事务刷新" eyebrow="City Affairs">
        <div className="stack">
          <p className="body-copy">
            这些开关控制对应界面的刷新功能；快捷键只在对应界面打开时生效。关闭后恢复原版刷新规则。
          </p>
          <div className="field-grid">
            <CheckboxField
              label="黄鹤楼候选人刷新"
              value={settings.yellowCraneCandidateRefreshEnabled}
              onChange={(value) => onSettingChange('yellowCraneCandidateRefreshEnabled', value)}
              hint="在黄鹤楼招募候选人界面显示刷新按钮，可重新生成本次候选人。"
            />
            <TextField
              label="黄鹤楼刷新快捷键"
              value={settings.yellowCraneCandidateRefreshHotkey}
              onChange={(value) => onSettingChange('yellowCraneCandidateRefreshHotkey', value)}
              disabled={!settings.yellowCraneCandidateRefreshEnabled}
              hint="默认 R；只在黄鹤楼候选人界面打开时生效。填写 Unity KeyCode 名称，例如 R 或 F8。"
            />
            <CheckboxField
              label="门派委托刷新"
              value={settings.forceBountyRefreshEnabled}
              onChange={(value) => onSettingChange('forceBountyRefreshEnabled', value)}
              hint="允许在门派委托界面重复使用原版刷新按钮。"
            />
            <CheckboxField
              label="看板委托刷新"
              value={settings.commonBountyRefreshEnabled}
              onChange={(value) => onSettingChange('commonBountyRefreshEnabled', value)}
              hint="允许在城市看板委托界面重复使用原版刷新按钮。"
            />
            <CheckboxField
              label="官府委托刷新"
              value={settings.governBountyRefreshEnabled}
              onChange={(value) => onSettingChange('governBountyRefreshEnabled', value)}
              hint="允许在官府委托界面重复使用原版刷新按钮。"
            />
            <TextField
              label="委托刷新快捷键"
              value={settings.bountyRefreshHotkey}
              onChange={(value) => onSettingChange('bountyRefreshHotkey', value)}
              disabled={!settings.forceBountyRefreshEnabled && !settings.commonBountyRefreshEnabled && !settings.governBountyRefreshEnabled}
              hint="默认 R；只在已启用的门派、看板或官府委托界面打开时生效。填写 Unity KeyCode 名称，例如 R 或 F8。"
            />
          </div>
        </div>
      </Card>
    </div>
  );
}
