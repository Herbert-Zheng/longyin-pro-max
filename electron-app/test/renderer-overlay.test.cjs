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
