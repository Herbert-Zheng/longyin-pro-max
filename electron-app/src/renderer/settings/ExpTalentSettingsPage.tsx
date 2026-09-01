import { Card, CheckboxField, NumberField } from '../components';
import type { SettingsPageProps } from './types';

export function ExpTalentSettingsPage({ settings, onSettingChange }: SettingsPageProps) {
  return (
    <div className="page-grid page-grid--settings">
      <Card title="经验成长" eyebrow="EXP">
        <div className="field-grid">
          <NumberField
            label="书籍经验倍率"
            value={settings.expMultiplier}
            onChange={(value) => onSettingChange('expMultiplier', value)}
            min={1}
            max={999}
            step={1}
          />
          <NumberField
            label="战斗武学经验倍率"
            value={settings.battleSkillExpMultiplier}
            onChange={(value) => onSettingChange('battleSkillExpMultiplier', value)}
            min={1}
            max={999}
            step={1}
            hint="只影响战斗内通过出招获得的武学经验，敌我双方都会生效。"
          />
          <NumberField
            label="创作点倍率"
            value={settings.creationPointMultiplier}
            onChange={(value) => onSettingChange('creationPointMultiplier', value)}
            min={1}
            max={999}
            step={1}
          />
        </div>
        <p className="body-copy body-copy--muted">
          武学写书现在直接按角色属性结算消耗，不再提供独立倍率开关。
        </p>
      </Card>

      <Card title="功法悬浮信息" eyebrow="Skill Display">
        <div className="field-grid">
          <CheckboxField
            label="显示功法书拥有状态"
            value={settings.skillBookOwnershipIndicatorEnabled}
            onChange={(value) => onSettingChange('skillBookOwnershipIndicatorEnabled', value)}
            hint="悬浮功法时合并检查背包与仓库（个人仓库及门派藏书）；已拥有显示绿色，未拥有显示红色。保存后需重启游戏生效。"
          />
        </div>
      </Card>

      <Card title="莫高窟遗忘" eyebrow="Mogao">
        <div className="field-grid">
          <CheckboxField
            label="掌门可为本门弟子遗忘武学与天赋"
            value={settings.mogaoDiscipleForgettingEnabled}
            onChange={(value) => onSettingChange('mogaoDiscipleForgettingEnabled', value)}
            hint="启用后，玩家担任掌门时可在莫高窟先选择本门弟子或自己，再按原版条件遗忘武学或天赋；非掌门仍只能为自己操作。保存后需重启游戏生效。"
          />
        </div>
      </Card>

      <Card title="心悟机制" eyebrow="Insight">
        <div className="field-grid">
          <NumberField
            label="心悟触发几率"
            value={settings.dailySkillInsightChancePercent}
            onChange={(value) => onSettingChange('dailySkillInsightChancePercent', value)}
            min={0}
            max={100}
            step={1}
            suffix="%"
          />
          <NumberField
            label="心悟经验值比率"
            value={settings.dailySkillInsightExpPercent}
            onChange={(value) => onSettingChange('dailySkillInsightExpPercent', value)}
            min={0}
            max={999}
            step={0.5}
            suffix="%"
          />
          <CheckboxField
            label="心悟经验值按武学品级调整"
            value={settings.dailySkillInsightUseRarityScaling}
            onChange={(value) => onSettingChange('dailySkillInsightUseRarityScaling', value)}
          />
          <NumberField
            label="心悟触发频率"
            value={settings.dailySkillInsightRealtimeIntervalSeconds}
            onChange={(value) => onSettingChange('dailySkillInsightRealtimeIntervalSeconds', value)}
            min={0}
            max={999}
            step={0.5}
            suffix="秒"
          />
        </div>
      </Card>

      <Card title="突破词条刷新" eyebrow="Breakthrough">
        <div className="field-grid">
          <CheckboxField
            label="刷新突破词条按钮"
            value={settings.breakthroughRerollEnabled}
            onChange={(value) => onSettingChange('breakthroughRerollEnabled', value)}
            hint="启用后只在突破候选界面显示“刷新突破词条”按钮，不会自动刷新；保存后需重新启动游戏生效。"
          />
        </div>
      </Card>

      <Card title="突破成功额外天赋" eyebrow="Talent">
        <div className="field-grid">
          <CheckboxField
            label="启用突破成功额外天赋"
            value={settings.skillTalentEnabled}
            onChange={(value) => onSettingChange('skillTalentEnabled', value)}
          />
          <CheckboxField
            label="仅玩家角色"
            value={settings.skillTalentPlayerOnly}
            onChange={(value) => onSettingChange('skillTalentPlayerOnly', value)}
            disabled={!settings.skillTalentEnabled}
          />
          <NumberField
            label="武学等级触发"
            value={settings.skillTalentLevelThreshold}
            onChange={(value) => onSettingChange('skillTalentLevelThreshold', value)}
            min={1}
            max={999}
            step={1}
            hint="如果设为 5，武学修炼到 5 级时触发天赋奖励。"
            disabled={!settings.skillTalentEnabled}
          />
          <NumberField
            label="品级天赋倍率"
            value={settings.skillTalentTierPointMultiplier}
            onChange={(value) => onSettingChange('skillTalentTierPointMultiplier', value)}
            min={0.1}
            max={999}
            step={0.25}
            hint="如果倍率 = 1，灰级 = 1 点、青级 = 2 点天赋。"
            disabled={!settings.skillTalentEnabled}
          />
        </div>
      </Card>
    </div>
  );
}
