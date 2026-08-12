import { Card, CheckboxField, NumberField } from '../components';
import type { SettingsPageProps } from './types';

export function SocialTeamSettingsPage({ settings, onSettingChange }: SettingsPageProps) {
  return (
    <div className="page-grid page-grid--settings">
      <Card title="聊天与互动" eyebrow="Dialog">
        <div className="field-grid">
          <NumberField
            label="每月对话次数倍率"
            value={settings.dialogMonthlyLimitMultiplier}
            onChange={(value) => onSettingChange('dialogMonthlyLimitMultiplier', value)}
            min={0}
            max={999}
            step={1}
            hint="影响交谈、请教等每月互动次数。"
          />
          <CheckboxField
            label="启用剧情快进辅助"
            value={settings.dialogFastForwardAssistEnabled}
            onChange={(value) => onSettingChange('dialogFastForwardAssistEnabled', value)}
            hint="在剧情出现快进按钮时自动开启快进，游戏内热键仍然是 P。"
          />
          <NumberField
            label="好感翻倍触发几率"
            value={settings.extraRelationshipGainChancePercent}
            onChange={(value) => onSettingChange('extraRelationshipGainChancePercent', value)}
            min={0}
            max={100}
            step={1}
            suffix="%"
            hint="需同时开启“人物关系增强总开关”；命中后，本次正向好感增加量变为 2 倍，0% 表示关闭。"
          />
        </div>
      </Card>

      <Card title="关系与组队" eyebrow="Relationship">
        <div className="stack">
          <p className="body-copy">总开关关闭时，下列人物关系增强不会修改游戏人物数据；伴侣上限是独立设置，不受总开关影响。</p>
          <div className="field-grid">
            <CheckboxField
              label="人物关系增强总开关"
              value={settings.relationshipFeaturesEnabled}
              onChange={(value) => onSettingChange('relationshipFeaturesEnabled', value)}
              hint="默认关闭。关闭后，好感加成、队友好感与声望共享、回家战斗阻断、同门传授和人物数据测试均不生效。"
            />
            <CheckboxField
              label="队友每日自动加好感"
              value={settings.teamAutoFavorEnabled}
              onChange={(value) => onSettingChange('teamAutoFavorEnabled', value)}
              disabled={!settings.relationshipFeaturesEnabled}
              hint="当前队伍中的已招募 NPC 会在每个游戏日自动获得好感。"
            />
            <NumberField
              label="队友每日自动加好感点数"
              value={settings.teamAutoFavorPerDay}
              onChange={(value) => onSettingChange('teamAutoFavorPerDay', value)}
              min={0}
              max={999}
              step={1}
              disabled={!settings.relationshipFeaturesEnabled || !settings.teamAutoFavorEnabled}
            />
            <CheckboxField
              label="队友声望共享"
              value={settings.teamFameShareEnabled}
              onChange={(value) => onSettingChange('teamFameShareEnabled', value)}
              disabled={!settings.relationshipFeaturesEnabled}
              hint="玩家获得正声望时，按下方比例同步给当前队友；需开启人物关系增强总开关。"
            />
            <NumberField
              label="队友声望共享比例"
              value={settings.teamFameSharePercent}
              onChange={(value) => onSettingChange('teamFameSharePercent', value)}
              min={0}
              max={100}
              step={1}
              suffix="%"
              disabled={!settings.relationshipFeaturesEnabled || !settings.teamFameShareEnabled}
            />
            <CheckboxField
              label="阻断超额伴侣回家战斗"
              value={settings.blockOverflowLoverHomeBattle}
              onChange={(value) => onSettingChange('blockOverflowLoverHomeBattle', value)}
              disabled={!settings.relationshipFeaturesEnabled}
              hint="单独控制回家时的超额伴侣战斗阻断；需开启人物关系增强总开关。"
            />
            <CheckboxField
              label="同门传授范围共享"
              value={settings.sameSectAreaShareEnabled}
              onChange={(value) => onSettingChange('sameSectAreaShareEnabled', value)}
              disabled={!settings.relationshipFeaturesEnabled}
              hint="同门传授成功时，向同区域同门共享收益；需开启人物关系增强总开关。"
            />
            <CheckboxField
              label="人物数据测试（K）"
              value={settings.characterDataTestHotkeyEnabled}
              onChange={(value) => onSettingChange('characterDataTestHotkeyEnabled', value)}
              disabled={!settings.relationshipFeaturesEnabled}
              hint="调试功能，默认关闭；开启总开关和本项后，游戏内按 K 执行人物数据测试。"
            />
            <NumberField
              label="伴侣上限"
              value={settings.maxLoverCount}
              onChange={(value) => onSettingChange('maxLoverCount', value)}
              min={1}
              max={999}
              step={1}
              hint="提高玩家可同时拥有的伴侣/夫妻数量。此项独立生效，不受人物关系增强总开关影响；默认 8。"
            />
          </div>
        </div>
      </Card>
    </div>
  );
}
