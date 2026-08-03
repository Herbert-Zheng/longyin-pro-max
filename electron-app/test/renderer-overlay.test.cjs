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

test('renderer exposes controls and shortcut hints for the new commerce and assist settings', () => {
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
    'auctionPreviewRefreshRequireAlt',
    'treasureIdentifyBestValueAssistEnabled',
    'treasureIdentifyBestValueHotkey',
    'treasureIdentifyBestValueRequireAlt'
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
    '显示珍宝交易估价',
    '启用材料一键扫货',
    '扫货最低品级',
    '扫货最低等级',
    '启用店铺产业与买断',
    '拍卖会固定红色等级',
    '启用拍卖预览免费刷新',
    '拍卖刷新主键',
    '拍卖刷新需要按住 Alt',
    '启用鉴宝最高鉴定价辅助',
    '最高估值选择主键',
    '最高估值选择需要按住 Alt'
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

  assert.match(renderer, /hint="在出售珍宝的商店中显示当前转售估价与技能影响。"/);
  assert.match(renderer, /hint="在商店内显示材料扫货按钮和筛选菜单；只批量加入购物车，仍需手动结账。"/);
  assert.match(renderer, /hint="0 表示不限；1–5 表示只加入达到该品级的材料。"/);
  assert.match(renderer, /hint="0 表示不限；1–5 表示只加入达到该等级的材料。"/);
  assert.match(renderer, /hint="在商店界面显示产业信息与买断按钮；关闭后隐藏相关入口。"/);
  assert.match(renderer, /hint="在拍卖展品预览窗口增加不限次数的免费刷新按钮。"/);
  assert.match(renderer, /hint="按鼠标悬浮括号内的玩家鉴定价选择最高项；最终确认仍需手动完成。"/);
  assert.equal((renderer.match(/hint="开启时快捷键为 Alt \+ 主键。"/g) ?? []).length >= 2, true);
});
