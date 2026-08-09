const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const projectRoot = path.resolve(__dirname, '..');
const readSource = (relativePath) => fs.readFileSync(path.join(projectRoot, relativePath), 'utf8');

test('initial snapshot failure renders an actionable retry path', () => {
  const renderer = readSource('src/renderer/App.tsx');
  assert.match(renderer, /setInitialLoadError\(err\.message\)/);
  assert.match(renderer, /启动器状态加载失败/);
  assert.match(renderer, /重试加载/);
  assert.match(renderer, /void refresh\(\)\.catch/);
});

test('save-and-launch transports settings and the current custom talent pack together', () => {
  const renderer = readSource('src/renderer/App.tsx');
  const preload = readSource('src/preload.ts');
  const main = readSource('src/main.ts');

  assert.match(renderer, /saveAndLaunch\(\{ settings, customTalents: customTalentPack \}\)/);
  assert.match(preload, /saveAndLaunch: \(request: SaveAndLaunchRequest\)/);
  assert.match(main, /ensureGameStopped\('保存设置并启动游戏'\)/);
  assert.match(main, /beginSettingsTransaction\(gameRoot\)/);
  assert.match(main, /saveVisibleSettings\(gameRoot, request\.settings\)/);
  assert.match(main, /saveCustomTalentPack\(gameRoot, request\.customTalents\)/);
  assert.match(main, /await transaction\.rollback\(\)/);
  assert.match(main, /await transaction\.commit\(\)/);
});

test('overlay has explicit IPC controls and game-owned lifecycle cleanup', () => {
  const preload = readSource('src/preload.ts');
  const main = readSource('src/main.ts');
  const renderer = readSource('src/renderer/App.tsx');

  assert.match(preload, /app:start-overlay/);
  assert.match(preload, /app:stop-overlay/);
  assert.match(main, /if \(launcherPreferences\.launchOverlayWithGame\)/);
  assert.match(main, /path\.join\(gameRoot, 'LongYinOverlay', OVERLAY_EXE_NAME\)/);
  assert.match(main, /startOverlay\(gameRoot, true\)/);
  assert.match(main, /monitorGameExitAndCleanup/);
  assert.match(main, /if \(gameLifecycleMonitor\)/);
  assert.match(main, /stopOverlay\(false\)/);
  assert.match(renderer, /随游戏启动 Overlay/);
  assert.match(renderer, /snapshot\.overlayRunning/);
});

test('updater launch waits for the child spawn handshake before the app can quit', () => {
  const main = readSource('src/main.ts');
  const updates = readSource('src/shared/updates.ts');
  const spawnHandshake = updates.indexOf("child.once('spawn', resolve)");
  const unref = updates.indexOf('child.unref()');

  assert.notEqual(spawnHandshake, -1);
  assert.notEqual(updates.indexOf("child.once('error', reject)"), -1);
  assert.equal(spawnHandshake < unref, true);
  assert.match(main, /await launchUpdaterApp\([\s\S]*?setTimeout\(\(\) => app\.quit\(\), 750\)/);
});

test('OTA completion is only emitted after the restarted app consumes the updater sentinel', () => {
  const main = readSource('src/main.ts');
  assert.match(main, /OTA_COMPLETION_PATH/);
  assert.match(main, /consumeUpdateCompletion/);
  assert.match(main, /emitUpdateProgress\('complete'/);
  assert.doesNotMatch(main, /更新包已准备完成[^\n]+emitUpdateProgress\('complete'/);
});

test('renderer exposes commerce and assist controls with only the supported auction shortcut', () => {
  const renderer = readSource('src/renderer/App.tsx');
  const controlBindings = [
    'treasureTradeHelperEnabled',
    'materialAutoBuyEnabled',
    'materialPurchaseMinRareLv',
    'materialPurchaseMinItemLv',
    'shopOwnershipEnabled',
    'auctionEventAlwaysRedEnabled',
    'auctionPreviewRefreshEnabled',
    'auctionPreviewRefreshHotkey',
    'treasureIdentifyBestValueAssistEnabled'
  ];

  for (const binding of controlBindings) {
    assert.match(
      renderer,
      new RegExp(
        `value=\\{settings\\.${binding}\\}[\\s\\S]{0,180}` +
        `onChange=\\{\\(value\\) => updateSetting\\('${binding}', value\\)\\}`
      ),
      `missing value/onChange wiring for ${binding}`
    );
  }

  assert.match(
    renderer,
    /label="扫货最低品级"[\s\S]{0,240}value=\{settings\.materialPurchaseMinRareLv\}[\s\S]{0,240}min=\{0\}[\s\S]{0,80}max=\{5\}/
  );
  assert.match(
    renderer,
    /label="扫货最低等级"[\s\S]{0,240}value=\{settings\.materialPurchaseMinItemLv\}[\s\S]{0,240}min=\{0\}[\s\S]{0,80}max=\{5\}/
  );

  for (const label of [
    '首次移动后揭开全部探索迷雾',
    '显示珍宝购物车汇总',
    '启用材料一键扫货',
    '扫货最低品级',
    '扫货最低等级',
    '启用店铺产业与买断',
    '拍卖会固定红色等级',
    '启用拍卖预览免费刷新',
    '拍卖刷新快捷键',
    '启用鉴宝最高鉴定价辅助'
  ]) {
    assert.match(renderer, new RegExp(`label="${label}"`), `missing independent label: ${label}`);
  }

  assert.match(
    renderer,
    /label="首次移动后揭开全部探索迷雾"[\s\S]{0,240}value=\{settings\.revealAllOnStepTile\}[\s\S]{0,240}updateSetting\('revealAllOnStepTile', value\)/
  );
  assert.match(renderer, /关闭时保持原版迷雾探索/);

  assert.match(renderer, /事件难度及按等级生成的拍品会相应提高/);
  assert.match(renderer, /关闭后恢复原版随机等级/);

  assert.match(renderer, /hint="在珍宝铺中汇总购物车内珍宝的数量、实际买入价、括号估价代入原版公式后的预计卖出价与预计利润。"/);
  assert.match(renderer, /hint="只把鉴定学识要求不高于当前学识、且按原版买卖价重算后有利润的未鉴定珍宝加入购物车；不会替你结账。"/);
  assert.doesNotMatch(renderer, /鉴定费/);
  assert.match(renderer, /hint="在商店内显示材料扫货按钮和筛选菜单；只批量加入购物车，仍需手动结账。"/);
  assert.match(renderer, /hint="0 表示不限；1–5 表示只加入达到该品级的材料。"/);
  assert.match(renderer, /hint="0 表示不限；1–5 表示只加入达到该等级的材料。"/);
  assert.match(renderer, /hint="在商店界面显示产业信息与买断按钮；关闭后隐藏相关入口。"/);
  assert.match(renderer, /hint="在拍卖展品预览窗口增加不限次数的免费刷新按钮。"/);
  assert.match(renderer, /hint="只在拍卖展品预览窗口生效；填写 Unity KeyCode 名称，例如 R 或 F8。"/);
  assert.match(renderer, /hint="按鼠标悬浮括号内的玩家鉴定价选择最高项；最终确认仍需手动完成。"/);

  for (const removedBinding of [
    'auctionPreviewRefreshRequireAlt',
    'treasureIdentifyBestValueHotkey',
    'treasureIdentifyBestValueRequireAlt'
  ]) {
    assert.doesNotMatch(renderer, new RegExp(removedBinding), `legacy renderer binding remains: ${removedBinding}`);
  }
});

test('growth settings expose breakthrough reroll as a button-only toggle', () => {
  const renderer = readSource('src/renderer/App.tsx');

  assert.match(
    renderer,
    /label="刷新突破词条按钮"[\s\S]{0,240}value=\{settings\.breakthroughRerollEnabled\}[\s\S]{0,240}updateSetting\('breakthroughRerollEnabled', value\)/
  );
  assert.match(renderer, /启用后只在突破候选界面显示“刷新突破词条”按钮，不会自动刷新；保存后需重新启动游戏生效。/);
  assert.doesNotMatch(renderer, /breakthroughReroll(?:Hotkey|RequireAlt)/);
});

test('trade and craft settings expose craft reroll as a button-only toggle', () => {
  const renderer = readSource('src/renderer/App.tsx');

  assert.match(
    renderer,
    /label="刷新打造词条按钮"[\s\S]{0,240}value=\{settings\.craftRerollEnabled\}[\s\S]{0,240}updateSetting\('craftRerollEnabled', value\)/
  );
  assert.match(renderer, /启用后只在普通打造和特殊强化候选界面显示“刷新打造词条”按钮，不会自动打造或消耗材料；保存后需重新启动游戏生效。/);
  assert.doesNotMatch(renderer, /craftReroll(?:Hotkey|RequireAlt)/);
});

test('trade and craft settings expose dedicated government storage refresh controls and scope copy', () => {
  const renderer = readSource('src/renderer/App.tsx');

  assert.match(renderer, /<Card title="官府仓库刷新" eyebrow="Government Storage">/);
  assert.match(
    renderer,
    /label="启用官府仓库刷新"[\s\S]{0,240}value=\{settings\.governmentStorageRefreshEnabled\}[\s\S]{0,240}updateSetting\('governmentStorageRefreshEnabled', value\)/
  );
  assert.match(
    renderer,
    /label="官府仓库刷新快捷键"[\s\S]{0,240}value=\{settings\.governmentStorageRefreshHotkey\}[\s\S]{0,240}updateSetting\('governmentStorageRefreshHotkey', value\)/
  );
  assert.match(renderer, /在官府仓库页面显示“刷新”按钮/);
  assert.match(renderer, /快捷键只在官府仓库页面可见时生效/);
});

test('world exploration exposes city affair refresh controls and shortcuts', () => {
  const renderer = readSource('src/renderer/App.tsx');

  assert.match(renderer, /<Card title="城内事务刷新" eyebrow="City Affairs">/);
  for (const [label, setting] of [
    ['黄鹤楼候选人刷新', 'yellowCraneCandidateRefreshEnabled'],
    ['门派委托刷新', 'forceBountyRefreshEnabled'],
    ['看板委托刷新', 'commonBountyRefreshEnabled'],
    ['官府委托刷新', 'governBountyRefreshEnabled']
  ]) {
    assert.match(
      renderer,
      new RegExp(`label="${label}"[\\s\\S]{0,240}value=\\{settings\\.${setting}\\}[\\s\\S]{0,240}updateSetting\\('${setting}', value\\)`)
    );
  }
  assert.match(renderer, /快捷键只在对应界面打开时生效/);
  assert.match(
    renderer,
    /label="黄鹤楼刷新快捷键"[\s\S]{0,240}value=\{settings\.yellowCraneCandidateRefreshHotkey\}[\s\S]{0,240}updateSetting\('yellowCraneCandidateRefreshHotkey', value\)/
  );
  assert.match(
    renderer,
    /label="委托刷新快捷键"[\s\S]{0,240}value=\{settings\.bountyRefreshHotkey\}[\s\S]{0,240}updateSetting\('bountyRefreshHotkey', value\)/
  );
  assert.match(renderer, /默认 R；只在黄鹤楼候选人界面打开时生效/);
  assert.match(renderer, /默认 R；只在已启用的门派、看板或官府委托界面打开时生效/);
});

test('growth settings expose the skill book ownership indicator and its inventory scope', () => {
  const renderer = readSource('src/renderer/App.tsx');

  assert.match(renderer, /<Card title="功法悬浮信息" eyebrow="Skill Display">/);
  assert.match(
    renderer,
    /label="显示功法书拥有状态"[\s\S]{0,240}value=\{settings\.skillBookOwnershipIndicatorEnabled\}[\s\S]{0,240}updateSetting\('skillBookOwnershipIndicatorEnabled', value\)/
  );
  assert.match(renderer, /背包与仓库（个人仓库及门派藏书）/);
  assert.match(renderer, /已拥有显示绿色，未拥有显示红色/);
});

test('launcher keeps primary actions visible and clearly marks unsaved settings', () => {
  const renderer = readSource('src/renderer/App.tsx');
  const styles = readSource('src/renderer/styles.css');
  const main = readSource('src/main.ts');
  const html = readSource('index.html');

  assert.match(renderer, /const settingsDirty = JSON\.stringify\(settings\) !== savedSettingsText/);
  assert.match(renderer, /普通设置未保存/);
  assert.match(renderer, /配置已保存/);
  assert.match(renderer, /run\('启动游戏',[\s\S]{0,100}, false\)/);
  assert.match(renderer, /当前未保存修改仍会保留在界面中/);
  assert.match(styles, /\.workspace__hero\s*\{[\s\S]*?position:\s*sticky;[\s\S]*?top:\s*16px;/);
  assert.match(styles, /\.nav-item__desc\s*\{\s*display:\s*none;/);
  assert.match(styles, /\.toggle__input:checked::after\s*\{[\s\S]*?translateX\(20px\)/);
  assert.match(main, /autoHideMenuBar:\s*true/);
  assert.match(html, /class="boot-splash"/);
  assert.match(html, /正在读取游戏目录、模组与配置/);
  assert.match(html, /启动界面加载超时/);
  assert.match(main, /webContents\.on\('did-fail-load'/);
  assert.match(main, /webContents\.on\('render-process-gone'/);
  assert.match(main, /webContents\.on\('console-message'/);
  assert.match(main, /renderer-ready/);
  assert.match(html, /renderer-error/);
  assert.match(html, /renderer-unhandledrejection/);
});

test('configuration status distinguishes disconnected, loading, failed, dirty and saved states', () => {
  const renderer = readSource('src/renderer/App.tsx');

  for (const state of ['disconnected', 'loading', 'load-error', 'dirty', 'saved']) {
    assert.match(renderer, new RegExp(`key: '${state}'`), `missing configuration state: ${state}`);
  }

  assert.match(renderer, /disabled=\{working !== null \|\| !gameRoot\}/);
  assert.match(renderer, /acceptVisibleSettingsIfUnchanged/);
  assert.match(renderer, /acceptCustomTalentPackIfUnchanged/);
  assert.match(renderer, /run\('安装模组',[\s\S]{0,100}, false\)/);
  assert.match(renderer, /run\('卸载模组',[\s\S]{0,100}, false\)/);
  assert.match(renderer, /setCustomTalentsReady\(true\)/);
});

test('commerce settings use readable groups without legacy shortcut controls', () => {
  const renderer = readSource('src/renderer/App.tsx');

  for (const title of ['珍宝交易', '材料扫货', '店铺与背包', '拍卖与珍宝鉴定']) {
    assert.match(renderer, new RegExp(`title="${title}"`));
  }

  assert.match(
    renderer,
    /label="扫货最低品级"[\s\S]{0,400}disabled=\{!settings\.materialAutoBuyEnabled\}/
  );
  assert.doesNotMatch(renderer, /拍卖刷新需要按住 Alt/);
  assert.doesNotMatch(renderer, /最高估值选择主键|最高估值选择需要按住 Alt/);
});

test('renderer settings pages use scoped, aligned tiles without stretching cards', () => {
  const renderer = readSource('src/renderer/App.tsx');
  const styles = readSource('src/renderer/styles.css');
  const smoke = readSource('scripts/check-renderer-smoke.mjs');

  assert.match(styles, /\.workspace\s*\{[\s\S]*?gap:\s*12px;/);
  assert.match(styles, /\.workspace__hero\s*\+\s*\.summary-grid\s*\{[\s\S]*?margin-top:\s*16px;/);
  assert.match(smoke, /summaryRect\.top\s*-\s*heroRect\.bottom/);
  assert.match(smoke, /statusRect\.top\s*-\s*summaryRect\.bottom/);
  assert.doesNotMatch(smoke, /rowGap\s*\+/);
  assert.match(renderer, /className="page-grid page-grid--systems page-grid--settings"/);
  assert.match(renderer, /className="page-grid page-grid--settings"/);
  assert.match(styles, /\.page-grid--settings\s*\{[\s\S]*?align-items:\s*start;/);
  assert.match(styles, /\.page-grid--settings\s*>\s*\.card\s*\{[\s\S]*?align-self:\s*start;/);
  assert.match(styles, /\.page-grid--settings\s+\.field,[\s\S]*?\.page-grid--settings\s+\.toggle\s*\{[\s\S]*?min-height:\s*112px;/);
});

test('relationship controls expose the safe master switch and independent lover limit', () => {
  const renderer = readSource('src/renderer/App.tsx');

  assert.match(renderer, /label="人物关系增强总开关"[\s\S]{0,220}settings\.relationshipFeaturesEnabled/);
  assert.match(renderer, /label="队友声望共享"[\s\S]{0,220}settings\.teamFameShareEnabled/);
  assert.match(renderer, /label="队友声望共享比例"[\s\S]{0,220}settings\.teamFameSharePercent/);
  assert.match(renderer, /label="阻断超额伴侣回家战斗"[\s\S]{0,220}settings\.blockOverflowLoverHomeBattle/);
  assert.match(renderer, /label="同门传授范围共享"[\s\S]{0,220}settings\.sameSectAreaShareEnabled/);
  assert.match(renderer, /label="人物数据测试（K）"[\s\S]{0,220}settings\.characterDataTestHotkeyEnabled/);
  assert.match(renderer, /伴侣上限是独立设置，不受总开关影响/);
  assert.match(renderer, /此项独立生效，不受人物关系增强总开关影响/);
  assert.doesNotMatch(renderer, /已确认无效的“队友离队天数倍率”/);
});

test('systems page makes environment full width and health details collapsible', () => {
  const renderer = readSource('src/renderer/App.tsx');
  const styles = readSource('src/renderer/styles.css');

  assert.match(renderer, /<div className="system-environment-card">[\s\S]*?<Card title="环境自检与目录"/);
  assert.match(styles, /\.system-environment-card\s*\{[\s\S]*?grid-column:\s*1\s*\/\s*-1;/);
  assert.match(renderer, /<details className="health-details">/);
  assert.match(renderer, /<summary>[\s\S]*?健康检查详情[\s\S]*?health\.summary/);
  assert.match(renderer, /游戏内悬浮信息窗/);
  assert.match(renderer, /无需切回启动器/);
});

test('custom talent selects show Chinese labels while preserving raw keys', () => {
  const renderer = readSource('src/renderer/App.tsx');
  const components = readSource('src/renderer/components.tsx');
  const customTalents = readSource('src/renderer/customTalents.ts');

  assert.match(components, /getOptionLabel\?:\s*\(option:\s*T\)\s*=>\s*string/);
  assert.match(components, /<option key=\{option\} value=\{option\}>[\s\S]*?props\.getOptionLabel\?\.\(option\)\s*\?\?\s*option/);
  assert.match(renderer, /getOptionLabel=\{formatCustomTalentConditionType\}/);
  assert.match(renderer, /getOptionLabel=\{formatBaseAttriType\}/);
  assert.match(renderer, /getOptionLabel=\{formatHeroSpeAddDataType\}/);
  assert.match(customTalents, /export const HERO_SPE_ADD_DATA_TYPE_LABELS:[\s\S]*?Record<HeroSpeAddDataTypeName, string>/);
  assert.match(customTalents, /HERO_SPE_ADD_DATA_TYPE_NAMES\.map/);
  assert.match(renderer, /条件 \{conditionIndex \+ 1\}/);
  assert.match(renderer, /效果 \{effectIndex \+ 1\}/);
  assert.match(renderer, /首个条件：\$\{formatCustomTalentConditionType/);
  assert.match(renderer, /首个效果：\$\{formatHeroSpeAddDataType/);
});
