import { Card, CheckboxField, NumberField, TextField } from '../components';
import type { SettingsPageProps } from './types';

export function TradeCraftSettingsPage({ settings, onSettingChange }: SettingsPageProps) {
  return (
    <div className="page-grid page-grid--settings">
      <Card title="珍宝交易" eyebrow="Treasure">
        <div className="field-grid">
          <CheckboxField
            label="显示珍宝购物车汇总"
            value={settings.treasureTradeHelperEnabled}
            onChange={(value) => onSettingChange('treasureTradeHelperEnabled', value)}
            hint="在珍宝铺中汇总购物车内珍宝的数量、实际买入价、括号估价代入原版公式后的预计卖出价与预计利润。"
          />
          <CheckboxField
            label="珍宝自动加入购物车"
            value={settings.treasureAutoTradeEnabled}
            onChange={(value) => onSettingChange('treasureAutoTradeEnabled', value)}
            hint="只把鉴定学识要求不高于当前学识、且按原版买卖价重算后有利润的未鉴定珍宝加入购物车；不会替你结账。"
          />
        </div>
      </Card>

      <Card title="材料扫货" eyebrow="Materials">
        <div className="field-grid">
          <CheckboxField
            label="启用材料一键扫货"
            value={settings.materialAutoBuyEnabled}
            onChange={(value) => onSettingChange('materialAutoBuyEnabled', value)}
            hint="在商店内显示材料扫货按钮和筛选菜单；只批量加入购物车，仍需手动结账。"
          />
          <NumberField
            label="扫货最低品级"
            value={settings.materialPurchaseMinRareLv}
            onChange={(value) => onSettingChange('materialPurchaseMinRareLv', value)}
            min={0}
            max={5}
            step={1}
            disabled={!settings.materialAutoBuyEnabled}
            hint="0 表示不限；1–5 表示只加入达到该品级的材料。"
          />
          <NumberField
            label="扫货最低等级"
            value={settings.materialPurchaseMinItemLv}
            onChange={(value) => onSettingChange('materialPurchaseMinItemLv', value)}
            min={0}
            max={5}
            step={1}
            disabled={!settings.materialAutoBuyEnabled}
            hint="0 表示不限；1–5 表示只加入达到该等级的材料。"
          />
        </div>
      </Card>

      <Card title="店铺与背包" eyebrow="Shop">
        <div className="field-grid">
          <NumberField
            label="商人现金下限"
            value={settings.merchantCarryCash}
            onChange={(value) => onSettingChange('merchantCarryCash', value)}
            min={0}
            max={999999999}
            step={1000}
          />
          <CheckboxField
            label="启用店铺产业与买断"
            value={settings.shopOwnershipEnabled}
            onChange={(value) => onSettingChange('shopOwnershipEnabled', value)}
            hint="在商店界面显示产业信息与买断按钮；关闭后隐藏相关入口。"
          />
          <NumberField
            label="幸运返利命中概率"
            value={settings.luckyHitChancePercent}
            onChange={(value) => onSettingChange('luckyHitChancePercent', value)}
            min={0}
            max={100}
            step={1}
            suffix="%"
          />
          <CheckboxField
            label="忽略负重"
            value={settings.ignoreCarryWeight}
            onChange={(value) => onSettingChange('ignoreCarryWeight', value)}
          />
          <NumberField
            label="负重上限"
            value={settings.carryWeightCap}
            onChange={(value) => onSettingChange('carryWeightCap', value)}
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
            onChange={(value) => onSettingChange('auctionEventAlwaysRedEnabled', value)}
            hint="开启后新生成的拍卖大会固定为红色最高等级，事件难度及按等级生成的拍品会相应提高；关闭后恢复原版随机等级。"
          />
          <CheckboxField
            label="启用拍卖预览免费刷新"
            value={settings.auctionPreviewRefreshEnabled}
            onChange={(value) => onSettingChange('auctionPreviewRefreshEnabled', value)}
            hint="在拍卖展品预览窗口增加不限次数的免费刷新按钮。"
          />
          <TextField
            label="拍卖刷新快捷键"
            value={settings.auctionPreviewRefreshHotkey}
            onChange={(value) => onSettingChange('auctionPreviewRefreshHotkey', value)}
            disabled={!settings.auctionPreviewRefreshEnabled}
            hint="只在拍卖展品预览窗口生效；填写 Unity KeyCode 名称，例如 R 或 F8。"
          />
          <CheckboxField
            label="启用鉴宝最高鉴定价辅助"
            value={settings.treasureIdentifyBestValueAssistEnabled}
            onChange={(value) => onSettingChange('treasureIdentifyBestValueAssistEnabled', value)}
            hint="按鼠标悬浮括号内的玩家鉴定价选择最高项；最终确认仍需手动完成。"
          />
        </div>
      </Card>

      <Card title="官府仓库刷新" eyebrow="Government Storage">
        <div className="field-grid">
          <CheckboxField
            label="启用官府仓库刷新"
            value={settings.governmentStorageRefreshEnabled}
            onChange={(value) => onSettingChange('governmentStorageRefreshEnabled', value)}
            hint="启用后在官府仓库页面显示“刷新”按钮。"
          />
          <TextField
            label="官府仓库刷新快捷键"
            value={settings.governmentStorageRefreshHotkey}
            onChange={(value) => onSettingChange('governmentStorageRefreshHotkey', value)}
            disabled={!settings.governmentStorageRefreshEnabled}
            hint="快捷键只在官府仓库页面可见时生效；填写 Unity KeyCode 名称，例如 R 或 F8。"
          />
        </div>
      </Card>

      <Card title="制造增产" eyebrow="Craft">
        <div className="field-grid">
          <CheckboxField
            label="刷新打造词条按钮"
            value={settings.craftRerollEnabled}
            onChange={(value) => onSettingChange('craftRerollEnabled', value)}
            hint="启用后只在普通打造和特殊强化候选界面显示“刷新打造词条”按钮，不会自动打造或消耗材料；保存后需重新启动游戏生效。"
          />
          <CheckboxField
            label="追加材料按大阶增产"
            value={settings.craftRandomPickUpgrade}
            onChange={(value) => onSettingChange('craftRandomPickUpgrade', value)}
            hint="按追加材料的大阶给成品加数量。下面 5 个数值分别对应一阶到五阶。"
          />
          <NumberField
            label="一阶额外数量"
            value={settings.craftTier1ExtraItems}
            onChange={(value) => onSettingChange('craftTier1ExtraItems', value)}
            min={0}
            max={999}
            step={1}
            disabled={!settings.craftRandomPickUpgrade}
          />
          <NumberField
            label="二阶额外数量"
            value={settings.craftTier2ExtraItems}
            onChange={(value) => onSettingChange('craftTier2ExtraItems', value)}
            min={0}
            max={999}
            step={1}
            disabled={!settings.craftRandomPickUpgrade}
          />
          <NumberField
            label="三阶额外数量"
            value={settings.craftTier3ExtraItems}
            onChange={(value) => onSettingChange('craftTier3ExtraItems', value)}
            min={0}
            max={999}
            step={1}
            disabled={!settings.craftRandomPickUpgrade}
          />
          <NumberField
            label="四阶额外数量"
            value={settings.craftTier4ExtraItems}
            onChange={(value) => onSettingChange('craftTier4ExtraItems', value)}
            min={0}
            max={999}
            step={1}
            disabled={!settings.craftRandomPickUpgrade}
          />
          <NumberField
            label="五阶额外数量"
            value={settings.craftTier5ExtraItems}
            onChange={(value) => onSettingChange('craftTier5ExtraItems', value)}
            min={0}
            max={999}
            step={1}
            disabled={!settings.craftRandomPickUpgrade}
          />
        </div>
      </Card>
    </div>
  );
}
