const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');

const {
  ensureBepInExConsoleDisabled,
  inspectGameHealth,
  readCustomTalentPack,
  readVisibleSettings,
  saveVisibleSettings
} = require('../dist/main/shared/config.js');
const { installOwnedPayload, uninstallOwnedPayload } = require('../dist/main/shared/payload.js');
const { reconcilePersistedValue } = require('../dist/main/shared/persisted-state.js');

test('ordinary settings save response preserves edits made while the request is pending', () => {
  const submitted = { enabled: true, multiplier: 2 };
  const persisted = { enabled: true, multiplier: 2 };
  const editedWhileSaving = { enabled: true, multiplier: 3 };

  assert.deepEqual(reconcilePersistedValue(submitted, JSON.stringify(submitted), persisted), persisted);
  assert.deepEqual(reconcilePersistedValue(editedWhileSaving, JSON.stringify(submitted), persisted), editedWhileSaving);
});

test('custom talent save response preserves talent edits made while the request is pending', () => {
  const submitted = { version: 1, talents: [{ id: 'talent-a', name: '旧名称' }] };
  const persisted = { version: 1, talents: [{ id: 'talent-a', name: '旧名称' }] };
  const editedWhileSaving = { version: 1, talents: [{ id: 'talent-a', name: '新名称' }] };

  assert.deepEqual(reconcilePersistedValue(submitted, JSON.stringify(submitted), persisted), persisted);
  assert.deepEqual(reconcilePersistedValue(editedWhileSaving, JSON.stringify(submitted), persisted), editedWhileSaving);
});

async function createWorkspace() {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'longyin-electron-test-'));
  const gameRoot = path.join(root, 'game');
  const payloadRoot = path.join(root, 'payload');
  await fs.mkdir(gameRoot, { recursive: true });
  await fs.mkdir(payloadRoot, { recursive: true });
  return { root, gameRoot, payloadRoot };
}

async function writeFile(root, relativePath, content) {
  const filePath = path.join(root, relativePath);
  await fs.mkdir(path.dirname(filePath), { recursive: true });
  await fs.writeFile(filePath, content);
  return filePath;
}

async function exists(filePath) {
  return fs.stat(filePath).then(() => true).catch(() => false);
}

const realisticBepInExConfig = [
  '## BepInEx configuration',
  '# User comments and custom values must survive launcher repairs.',
  '',
  '[Logging.Console]',
  '## Enables showing a console for log output.',
  '# Setting type: Boolean',
  '# Default value: false',
  'Enabled = true',
  'PreventClose = true',
  '',
  '[Logging.Disk]',
  'Enabled = true',
  'AppendLog = false',
  '',
  '[Chainloader]',
  'Enabled = custom-value',
  'HideManagerGameObject = false',
  ''
].join('\r\n');

test('console enforcement changes only Logging.Console Enabled to false', async (t) => {
  const { root, gameRoot } = await createWorkspace();
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  const configPath = await writeFile(gameRoot, 'BepInEx/config/BepInEx.cfg', realisticBepInExConfig);
  const expected = realisticBepInExConfig.replace(
    '[Logging.Console]\r\n## Enables showing a console for log output.\r\n# Setting type: Boolean\r\n# Default value: false\r\nEnabled = true',
    '[Logging.Console]\r\n## Enables showing a console for log output.\r\n# Setting type: Boolean\r\n# Default value: false\r\nEnabled = false'
  );

  await ensureBepInExConsoleDisabled(gameRoot);

  assert.equal(await fs.readFile(configPath, 'utf8'), expected);
});

test('console enforcement is byte-idempotent after the console is disabled', async (t) => {
  const { root, gameRoot } = await createWorkspace();
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  const configPath = await writeFile(gameRoot, 'BepInEx/config/BepInEx.cfg', realisticBepInExConfig);

  await ensureBepInExConsoleDisabled(gameRoot);
  const afterFirstCall = await fs.readFile(configPath);
  await ensureBepInExConsoleDisabled(gameRoot);
  const afterSecondCall = await fs.readFile(configPath);

  assert.deepEqual(afterSecondCall, afterFirstCall);
});

test('console enforcement rejects a missing BepInEx.cfg with an actionable repair message', async (t) => {
  const { root, gameRoot } = await createWorkspace();
  t.after(() => fs.rm(root, { recursive: true, force: true }));

  await assert.rejects(
    ensureBepInExConsoleDisabled(gameRoot),
    /BepInEx\.cfg[\s\S]*(?:修复|重新安装)/
  );
});

test('console enforcement adds a disabled Logging.Console section when the section is absent', async (t) => {
  const { root, gameRoot } = await createWorkspace();
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  const before = [
    '## Existing BepInEx configuration',
    '[Logging.Disk]',
    'Enabled = true',
    'LogLevels = Fatal, Error, Warning, Message, Info',
    ''
  ].join('\r\n');
  const expected = `${before}\r\n[Logging.Console]\r\nEnabled = false\r\n`;
  const configPath = await writeFile(gameRoot, 'BepInEx/config/BepInEx.cfg', before);

  await ensureBepInExConsoleDisabled(gameRoot);

  assert.equal(await fs.readFile(configPath, 'utf8'), expected);
});

test('console enforcement adds Enabled false when Logging.Console has no Enabled key', async (t) => {
  const { root, gameRoot } = await createWorkspace();
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  const before = [
    '[Logging.Console]',
    '## Keep this user comment.',
    'PreventClose = true',
    '',
    '[Logging.Disk]',
    'Enabled = true',
    ''
  ].join('\r\n');
  const expected = [
    '[Logging.Console]',
    '## Keep this user comment.',
    'PreventClose = true',
    'Enabled = false',
    '',
    '[Logging.Disk]',
    'Enabled = true',
    ''
  ].join('\r\n');
  const configPath = await writeFile(gameRoot, 'BepInEx/config/BepInEx.cfg', before);

  await ensureBepInExConsoleDisabled(gameRoot);

  assert.equal(await fs.readFile(configPath, 'utf8'), expected);
});

test('console enforcement separates an EOF-only Logging.Console header from the inserted key', async (t) => {
  const { root, gameRoot } = await createWorkspace();
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  const configPath = await writeFile(gameRoot, 'BepInEx/config/BepInEx.cfg', '[Logging.Console]');

  await ensureBepInExConsoleDisabled(gameRoot);

  assert.equal(
    await fs.readFile(configPath, 'utf8'),
    '[Logging.Console]\r\nEnabled = false\r\n'
  );
});

for (const invalidValueCase of [
  {
    name: 'yes',
    before: 'Enabled = yes # keep yes comment',
    expected: 'Enabled = false # keep yes comment'
  },
  {
    name: 'empty',
    before: 'Enabled =    # keep empty comment',
    expected: 'Enabled = false   # keep empty comment'
  },
  {
    name: 'custom text',
    before: 'Enabled = sometimes ; keep custom comment',
    expected: 'Enabled = false ; keep custom comment'
  }
]) {
  test(`console enforcement repairs ${invalidValueCase.name} Enabled value and preserves its comment`, async (t) => {
    const { root, gameRoot } = await createWorkspace();
    t.after(() => fs.rm(root, { recursive: true, force: true }));
    const before = [
      '[Logging.Console]',
      invalidValueCase.before,
      'PreventClose = true',
      '',
      '[Logging.Disk]',
      'Enabled = true',
      ''
    ].join('\r\n');
    const expected = before.replace(invalidValueCase.before, invalidValueCase.expected);
    const configPath = await writeFile(gameRoot, 'BepInEx/config/BepInEx.cfg', before);

    await ensureBepInExConsoleDisabled(gameRoot);

    assert.equal(await fs.readFile(configPath, 'utf8'), expected);
  });
}

test('console enforcement converges every duplicate Logging.Console Enabled key to false', async (t) => {
  const { root, gameRoot } = await createWorkspace();
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  const before = [
    '# Preserve every byte outside console values.',
    '[Logging.Console]',
    'Enabled = false # already safe',
    'Enabled = true # unsafe duplicate',
    'Enabled = yes # invalid duplicate',
    'PreventClose = true',
    '',
    '[Logging.Disk]',
    'Enabled = true # disk logging remains enabled',
    ''
  ].join('\r\n');
  const expected = before
    .replace('Enabled = true # unsafe duplicate', 'Enabled = false # unsafe duplicate')
    .replace('Enabled = yes # invalid duplicate', 'Enabled = false # invalid duplicate');
  const configPath = await writeFile(gameRoot, 'BepInEx/config/BepInEx.cfg', before);

  await ensureBepInExConsoleDisabled(gameRoot);

  assert.equal(await fs.readFile(configPath, 'utf8'), expected);
});

test('launch enforces disabled BepInEx console after guards and before overlay or game spawn', async () => {
  const mainSource = await fs.readFile(path.join(__dirname, '../src/main.ts'), 'utf8');
  const launchStart = mainSource.indexOf('async function launchGame(gameRoot: string): Promise<void>');
  const launchEnd = mainSource.indexOf('\nasync function buildSnapshot', launchStart);
  const launchSource = mainSource.slice(launchStart, launchEnd);
  const repairNeededGuard = launchSource.indexOf('if (repairResult.health.needsRepair)');
  const repairGuard = launchSource.indexOf('if (repairResult.health.launchBlocked)');
  const runningGuard = launchSource.indexOf("if (launchState.launchState !== 'idle')");
  const enforcement = launchSource.indexOf('await ensureBepInExConsoleDisabled(gameRoot)');
  const overlay = launchSource.indexOf('await startOverlay(gameRoot, true)');
  const gameSpawn = launchSource.indexOf('spawn(paths.gameExePath');

  assert.notEqual(repairNeededGuard, -1, 'launchGame must retain the repair-needed guard');
  assert.notEqual(repairGuard, -1, 'launchGame must retain the launch-blocked guard');
  assert.notEqual(runningGuard, -1, 'launchGame must retain the game-running guard');
  assert.notEqual(enforcement, -1, 'launchGame must enforce the BepInEx console setting');
  assert.notEqual(overlay, -1, 'launchGame must retain overlay startup');
  assert.notEqual(gameSpawn, -1, 'launchGame must retain game spawn');
  assert.equal(repairNeededGuard < enforcement, true, 'repair-needed guard must run before console enforcement');
  assert.equal(repairGuard < enforcement, true, 'repair/health guards must run before console enforcement');
  assert.equal(runningGuard < enforcement, true, 'game-running guard must run before console enforcement');
  assert.equal(enforcement < overlay, true, 'console enforcement must run before overlay startup');
  assert.equal(enforcement < gameSpawn, true, 'console enforcement must run before spawning the game');
});

test('uninstall restores replaced files and leaves unrelated BepInEx files untouched', async (t) => {
  const { root, gameRoot, payloadRoot } = await createWorkspace();
  t.after(() => fs.rm(root, { recursive: true, force: true }));

  await writeFile(payloadRoot, 'winhttp.dll', 'longyin loader');
  await writeFile(payloadRoot, 'BepInEx/plugins/LongYinProMax.dll', 'longyin plugin');
  await writeFile(payloadRoot, 'BepInEx/plugins/LongYinSkipIntro.dll', 'new plugin');
  await writeFile(payloadRoot, 'BepInEx/unity-libs/runtime.zip', 'nested runtime archive');
  await writeFile(gameRoot, 'winhttp.dll', 'original loader');
  await writeFile(gameRoot, 'BepInEx/plugins/LongYinProMax.dll', 'original plugin');
  await writeFile(gameRoot, 'BepInEx/plugins/ThirdParty.dll', 'third party');

  await installOwnedPayload(gameRoot, payloadRoot);
  assert.equal(await fs.readFile(path.join(gameRoot, 'winhttp.dll'), 'utf8'), 'longyin loader');
  assert.equal(
    await fs.readFile(path.join(gameRoot, 'BepInEx/plugins/LongYinProMax.dll'), 'utf8'),
    'longyin plugin'
  );
  assert.equal(
    await fs.readFile(path.join(gameRoot, 'BepInEx/unity-libs/runtime.zip'), 'utf8'),
    'nested runtime archive'
  );

  await uninstallOwnedPayload(gameRoot, payloadRoot);
  assert.equal(await fs.readFile(path.join(gameRoot, 'winhttp.dll'), 'utf8'), 'original loader');
  assert.equal(
    await fs.readFile(path.join(gameRoot, 'BepInEx/plugins/LongYinProMax.dll'), 'utf8'),
    'original plugin'
  );
  assert.equal(await fs.readFile(path.join(gameRoot, 'BepInEx/plugins/ThirdParty.dll'), 'utf8'), 'third party');
  assert.equal(await exists(path.join(gameRoot, 'BepInEx/plugins/LongYinSkipIntro.dll')), false);
  assert.equal(await exists(path.join(gameRoot, 'BepInEx/unity-libs/runtime.zip')), false);
});

test('reinstall preserves an existing user configuration file', async (t) => {
  const { root, gameRoot, payloadRoot } = await createWorkspace();
  t.after(() => fs.rm(root, { recursive: true, force: true }));

  const relativeConfig = 'BepInEx/config/codex.longyin.staminalock.cfg';
  await writeFile(payloadRoot, relativeConfig, 'LockStamina = true');
  await installOwnedPayload(gameRoot, payloadRoot);
  await writeFile(gameRoot, relativeConfig, 'LockStamina = false');

  await installOwnedPayload(gameRoot, payloadRoot);
  assert.equal(await fs.readFile(path.join(gameRoot, relativeConfig), 'utf8'), 'LockStamina = false');
});

test('reinstall backs up a live plugin DLL before overwriting drift', async (t) => {
  const { root, gameRoot, payloadRoot } = await createWorkspace();
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  const relativePlugin = 'BepInEx/plugins/LongYinProMax.dll';
  await writeFile(payloadRoot, relativePlugin, 'payload v1');
  await installOwnedPayload(gameRoot, payloadRoot);
  await writeFile(gameRoot, relativePlugin, 'live drift');
  await writeFile(payloadRoot, relativePlugin, 'payload v2');

  await installOwnedPayload(gameRoot, payloadRoot);

  assert.equal(
    await fs.readFile(path.join(gameRoot, '.longyin-plus/update-backups', relativePlugin), 'utf8'),
    'live drift'
  );
  assert.equal(await fs.readFile(path.join(gameRoot, relativePlugin), 'utf8'), 'payload v2');
});

test('payload upgrade removes obsolete created files and restores obsolete replaced files', async (t) => {
  const { root, gameRoot, payloadRoot } = await createWorkspace();
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  const createdPlugin = 'BepInEx/plugins/LongYinOldCreated.dll';
  const replacedPlugin = 'BepInEx/plugins/LongYinOldReplaced.dll';
  const retainedPlugin = 'BepInEx/plugins/LongYinCurrent.dll';

  await writeFile(gameRoot, replacedPlugin, 'third-party original');
  await writeFile(payloadRoot, createdPlugin, 'payload-created v1');
  await writeFile(payloadRoot, replacedPlugin, 'payload-replaced v1');
  await installOwnedPayload(gameRoot, payloadRoot);

  await fs.rm(path.join(payloadRoot, createdPlugin), { force: true });
  await fs.rm(path.join(payloadRoot, replacedPlugin), { force: true });
  await writeFile(payloadRoot, retainedPlugin, 'payload-current v2');
  await installOwnedPayload(gameRoot, payloadRoot);

  assert.equal(await exists(path.join(gameRoot, createdPlugin)), false);
  assert.equal(await fs.readFile(path.join(gameRoot, replacedPlugin), 'utf8'), 'third-party original');
  assert.equal(await fs.readFile(path.join(gameRoot, retainedPlugin), 'utf8'), 'payload-current v2');

  await uninstallOwnedPayload(gameRoot, payloadRoot);
  assert.equal(await fs.readFile(path.join(gameRoot, replacedPlugin), 'utf8'), 'third-party original');
  assert.equal(await exists(path.join(gameRoot, retainedPlugin)), false);
});

test('installing renamed primary plugin removes legacy DLL without an install manifest', async (t) => {
  const { root, gameRoot, payloadRoot } = await createWorkspace();
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  const currentPlugin = 'BepInEx/plugins/LongYinProMax.dll';
  const legacyPlugin = 'BepInEx/plugins/LongYinStaminaLock.dll';

  await writeFile(gameRoot, legacyPlugin, 'legacy plugin');
  await writeFile(payloadRoot, currentPlugin, 'renamed plugin');

  await installOwnedPayload(gameRoot, payloadRoot);

  assert.equal(await exists(path.join(gameRoot, legacyPlugin)), false);
  assert.equal(await fs.readFile(path.join(gameRoot, currentPlugin), 'utf8'), 'renamed plugin');
  assert.equal(
    await fs.readFile(path.join(gameRoot, '.longyin-plus/backups', legacyPlugin), 'utf8'),
    'legacy plugin'
  );

  await uninstallOwnedPayload(gameRoot, payloadRoot);
  assert.equal(await fs.readFile(path.join(gameRoot, legacyPlugin), 'utf8'), 'legacy plugin');
  assert.equal(await exists(path.join(gameRoot, currentPlugin)), false);
});

test('renamed primary plugin migration replaces a stale legacy backup with the current live DLL', async (t) => {
  const { root, gameRoot, payloadRoot } = await createWorkspace();
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  const currentPlugin = 'BepInEx/plugins/LongYinProMax.dll';
  const legacyPlugin = 'BepInEx/plugins/LongYinStaminaLock.dll';

  await writeFile(gameRoot, legacyPlugin, 'current live legacy plugin');
  await writeFile(gameRoot, `.longyin-plus/backups/${legacyPlugin}`, 'stale legacy backup');
  await writeFile(payloadRoot, currentPlugin, 'renamed plugin');

  await installOwnedPayload(gameRoot, payloadRoot);

  assert.equal(await exists(path.join(gameRoot, legacyPlugin)), false);
  assert.equal(
    await fs.readFile(path.join(gameRoot, '.longyin-plus/backups', legacyPlugin), 'utf8'),
    'current live legacy plugin'
  );

  await uninstallOwnedPayload(gameRoot, payloadRoot);
  assert.equal(
    await fs.readFile(path.join(gameRoot, legacyPlugin), 'utf8'),
    'current live legacy plugin'
  );
  assert.equal(await exists(path.join(gameRoot, currentPlugin)), false);
});

test('installing renamed primary plugin removes legacy DLL tracked by an older manifest', async (t) => {
  const { root, gameRoot, payloadRoot } = await createWorkspace();
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  const currentPlugin = 'BepInEx/plugins/LongYinProMax.dll';
  const legacyPlugin = 'BepInEx/plugins/LongYinStaminaLock.dll';

  await writeFile(gameRoot, legacyPlugin, 'legacy original');
  await writeFile(payloadRoot, legacyPlugin, 'legacy payload');
  await installOwnedPayload(gameRoot, payloadRoot);
  await fs.rm(path.join(payloadRoot, legacyPlugin), { force: true });
  await writeFile(payloadRoot, currentPlugin, 'renamed plugin');

  await installOwnedPayload(gameRoot, payloadRoot);

  assert.equal(await exists(path.join(gameRoot, legacyPlugin)), false);
  assert.equal(await fs.readFile(path.join(gameRoot, currentPlugin), 'utf8'), 'renamed plugin');
  const manifest = JSON.parse(
    await fs.readFile(path.join(gameRoot, '.longyin-plus/install-manifest.json'), 'utf8')
  );
  assert.equal(
    manifest.entries.some((entry) => entry.relativePath.toLowerCase() === legacyPlugin.toLowerCase()),
    true
  );
  assert.equal(
    await fs.readFile(path.join(gameRoot, '.longyin-plus/backups', legacyPlugin), 'utf8'),
    'legacy original'
  );

  await uninstallOwnedPayload(gameRoot, payloadRoot);
  assert.equal(await fs.readFile(path.join(gameRoot, legacyPlugin), 'utf8'), 'legacy original');
  assert.equal(await exists(path.join(gameRoot, currentPlugin)), false);
});

test('renamed primary plugin migration preserves a pre-existing legacy DLL recorded as preserved', async (t) => {
  const { root, gameRoot, payloadRoot } = await createWorkspace();
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  const currentPlugin = 'BepInEx/plugins/LongYinProMax.dll';
  const legacyPlugin = 'BepInEx/plugins/LongYinStaminaLock.dll';

  await writeFile(gameRoot, legacyPlugin, 'matching pre-existing plugin');
  await writeFile(payloadRoot, legacyPlugin, 'matching pre-existing plugin');
  await installOwnedPayload(gameRoot, payloadRoot);

  await fs.rm(path.join(payloadRoot, legacyPlugin), { force: true });
  await writeFile(payloadRoot, currentPlugin, 'renamed plugin');
  await installOwnedPayload(gameRoot, payloadRoot);

  assert.equal(await exists(path.join(gameRoot, legacyPlugin)), false);
  assert.equal(
    await fs.readFile(path.join(gameRoot, '.longyin-plus/backups', legacyPlugin), 'utf8'),
    'matching pre-existing plugin'
  );

  await uninstallOwnedPayload(gameRoot, payloadRoot);
  assert.equal(
    await fs.readFile(path.join(gameRoot, legacyPlugin), 'utf8'),
    'matching pre-existing plugin'
  );
  assert.equal(await exists(path.join(gameRoot, currentPlugin)), false);
});

test('renamed primary plugin migration refuses a replaced legacy entry whose original backup is missing', async (t) => {
  const { root, gameRoot, payloadRoot } = await createWorkspace();
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  const currentPlugin = 'BepInEx/plugins/LongYinProMax.dll';
  const legacyPlugin = 'BepInEx/plugins/LongYinStaminaLock.dll';

  await writeFile(gameRoot, legacyPlugin, 'legacy original');
  await writeFile(payloadRoot, legacyPlugin, 'legacy payload');
  await installOwnedPayload(gameRoot, payloadRoot);
  await fs.rm(path.join(gameRoot, '.longyin-plus/backups', legacyPlugin), { force: true });
  await fs.rm(path.join(payloadRoot, legacyPlugin), { force: true });
  await writeFile(payloadRoot, currentPlugin, 'renamed plugin');

  await assert.rejects(
    installOwnedPayload(gameRoot, payloadRoot),
    /缺少原文件备份/
  );
  assert.equal(await fs.readFile(path.join(gameRoot, legacyPlugin), 'utf8'), 'legacy payload');
  assert.equal(await exists(path.join(gameRoot, currentPlugin)), false);
});

test('renamed primary plugin install restores legacy DLL when a later copy fails', async (t) => {
  const { root, gameRoot, payloadRoot } = await createWorkspace();
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  const currentPlugin = 'BepInEx/plugins/LongYinProMax.dll';
  const legacyPlugin = 'BepInEx/plugins/LongYinStaminaLock.dll';

  await writeFile(gameRoot, legacyPlugin, 'legacy plugin');
  await writeFile(payloadRoot, currentPlugin, 'renamed plugin');
  await writeFile(payloadRoot, 'blocked/file.dll', 'cannot be copied');
  await writeFile(gameRoot, 'blocked', 'parent path is a file');

  await assert.rejects(
    installOwnedPayload(gameRoot, payloadRoot),
    /已回滚至安装前状态/
  );

  assert.equal(await fs.readFile(path.join(gameRoot, legacyPlugin), 'utf8'), 'legacy plugin');
  assert.equal(await exists(path.join(gameRoot, currentPlugin)), false);
});

test('payload upgrade rolls back earlier deletes and copies when a later copy fails', async (t) => {
  const { root, gameRoot, payloadRoot } = await createWorkspace();
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  const obsoletePlugin = 'BepInEx/plugins/LongYinObsolete.dll';
  const retainedPlugin = 'BepInEx/plugins/LongYinRetained.dll';

  await writeFile(payloadRoot, obsoletePlugin, 'obsolete v1');
  await writeFile(payloadRoot, retainedPlugin, 'retained v1');
  await installOwnedPayload(gameRoot, payloadRoot);
  const manifestBefore = await fs.readFile(path.join(gameRoot, '.longyin-plus/install-manifest.json'), 'utf8');

  await fs.rm(path.join(payloadRoot, obsoletePlugin), { force: true });
  await writeFile(payloadRoot, retainedPlugin, 'retained v2');
  await writeFile(payloadRoot, 'blocked/file.dll', 'cannot be copied');
  await writeFile(gameRoot, 'blocked', 'parent path is a file');

  await assert.rejects(
    installOwnedPayload(gameRoot, payloadRoot),
    /已回滚至安装前状态/
  );

  assert.equal(await fs.readFile(path.join(gameRoot, obsoletePlugin), 'utf8'), 'obsolete v1');
  assert.equal(await fs.readFile(path.join(gameRoot, retainedPlugin), 'utf8'), 'retained v1');
  assert.equal(
    await fs.readFile(path.join(gameRoot, '.longyin-plus/install-manifest.json'), 'utf8'),
    manifestBefore
  );
  const transactionNames = await fs.readdir(path.join(gameRoot, '.longyin-plus/transactions'));
  assert.equal(transactionNames.some((name) => name.startsWith('install-')), true);
});

test('payload upgrade rolls back copied files when the atomic manifest replacement fails', async (t) => {
  const { root, gameRoot, payloadRoot } = await createWorkspace();
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  const plugin = 'BepInEx/plugins/LongYinAtomic.dll';

  await writeFile(payloadRoot, plugin, 'payload v1');
  await installOwnedPayload(gameRoot, payloadRoot);
  const manifestPath = path.join(gameRoot, '.longyin-plus/install-manifest.json');
  const manifestBefore = await fs.readFile(manifestPath, 'utf8');
  await writeFile(payloadRoot, plugin, 'payload v2');

  const originalRename = fs.rename;
  fs.rename = async (sourcePath, targetPath) => {
    if (path.resolve(targetPath) === path.resolve(manifestPath)) {
      const error = new Error('injected manifest rename failure');
      error.code = 'EIO';
      throw error;
    }
    return originalRename(sourcePath, targetPath);
  };
  try {
    await assert.rejects(
      installOwnedPayload(gameRoot, payloadRoot),
      /injected manifest rename failure/
    );
  }
  finally {
    fs.rename = originalRename;
  }

  assert.equal(await fs.readFile(path.join(gameRoot, plugin), 'utf8'), 'payload v1');
  assert.equal(await fs.readFile(manifestPath, 'utf8'), manifestBefore);
});

test('reading visible settings does not create or modify game files', async (t) => {
  const { root, gameRoot } = await createWorkspace();
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  await writeFile(gameRoot, 'LongYinLiZhiZhuan.exe', 'game');

  const before = await fs.readdir(gameRoot);
  const settings = await readVisibleSettings(gameRoot);
  const after = await fs.readdir(gameRoot);

  assert.equal(settings.lockStamina, true);
  assert.equal(settings.revealAllOnStepTile, false);
  assert.deepEqual(after, before);
});

test('relationship memory features default safely off while independent settings keep their defaults', async (t) => {
  const { root, gameRoot } = await createWorkspace();
  t.after(() => fs.rm(root, { recursive: true, force: true }));

  const settings = await readVisibleSettings(gameRoot);

  assert.equal(settings.relationshipFeaturesEnabled, false);
  assert.equal(settings.teamFameShareEnabled, true);
  assert.equal(settings.teamFameSharePercent, 30);
  assert.equal(settings.blockOverflowLoverHomeBattle, true);
  assert.equal(settings.sameSectAreaShareEnabled, true);
  assert.equal(settings.characterDataTestHotkeyEnabled, false);
  assert.equal(settings.maxLoverCount, 8);
});

test('relationship, teaching, and character test settings are section-scoped and round-trip', async (t) => {
  const { root, gameRoot } = await createWorkspace();
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  const configPath = 'BepInEx/config/codex.longyin.staminalock.cfg';
  await writeFile(
    gameRoot,
    configPath,
    [
      '[WrongSection]',
      'FeaturesEnabled = false',
      'TeamFameShareEnabled = false',
      'TeamFameSharePercent = 1',
      'BlockOverflowLoverHomeBattle = false',
      'SameSectAreaShareEnabled = false',
      'CharacterDataTestHotkeyEnabled = false',
      '',
      '[Relationship]',
      'FeaturesEnabled = true',
      'ExtraRelationshipGainChancePercent = 25',
      'TeamAutoFavorEnabled = false',
      'TeamAutoFavorPerDay = 2.5',
      'TeamFameShareEnabled = true',
      'TeamFameSharePercent = 45.5',
      'BlockOverflowLoverHomeBattle = true',
      'MaxLoverCount = 12',
      'UnrelatedRelationshipSetting = keep-relationship',
      '',
      '[Teaching]',
      'SameSectAreaShareEnabled = true',
      'UnrelatedTeachingSetting = keep-teaching',
      '',
      '[Debug]',
      'CharacterDataTestHotkeyEnabled = true',
      'UnrelatedDebugSetting = keep-debug',
      ''
    ].join('\r\n')
  );

  const current = await readVisibleSettings(gameRoot);
  assert.equal(current.relationshipFeaturesEnabled, true);
  assert.equal(current.teamFameShareEnabled, true);
  assert.equal(current.teamFameSharePercent, 45.5);
  assert.equal(current.blockOverflowLoverHomeBattle, true);
  assert.equal(current.sameSectAreaShareEnabled, true);
  assert.equal(current.characterDataTestHotkeyEnabled, true);
  assert.equal(current.maxLoverCount, 12);

  const saved = await saveVisibleSettings(gameRoot, {
    ...current,
    relationshipFeaturesEnabled: false,
    teamFameShareEnabled: false,
    teamFameSharePercent: 37.5,
    blockOverflowLoverHomeBattle: false,
    sameSectAreaShareEnabled: false,
    characterDataTestHotkeyEnabled: false,
    maxLoverCount: 16
  });
  const text = await fs.readFile(path.join(gameRoot, configPath), 'utf8');

  assert.equal(saved.relationshipFeaturesEnabled, false);
  assert.equal(saved.teamFameShareEnabled, false);
  assert.equal(saved.teamFameSharePercent, 37.5);
  assert.equal(saved.blockOverflowLoverHomeBattle, false);
  assert.equal(saved.sameSectAreaShareEnabled, false);
  assert.equal(saved.characterDataTestHotkeyEnabled, false);
  assert.equal(saved.maxLoverCount, 16);
  assert.match(text, /\[Relationship\][\s\S]*?^FeaturesEnabled = false$/m);
  assert.match(text, /\[Relationship\][\s\S]*?^TeamFameShareEnabled = false$/m);
  assert.match(text, /\[Relationship\][\s\S]*?^TeamFameSharePercent = 37\.5$/m);
  assert.match(text, /\[Relationship\][\s\S]*?^BlockOverflowLoverHomeBattle = false$/m);
  assert.match(text, /\[Relationship\][\s\S]*?^MaxLoverCount = 16$/m);
  assert.match(text, /\[Teaching\][\s\S]*?^SameSectAreaShareEnabled = false$/m);
  assert.match(text, /\[Debug\][\s\S]*?^CharacterDataTestHotkeyEnabled = false$/m);
  assert.match(text, /^UnrelatedRelationshipSetting = keep-relationship$/m);
  assert.match(text, /^UnrelatedTeachingSetting = keep-teaching$/m);
  assert.match(text, /^UnrelatedDebugSetting = keep-debug$/m);
  assert.match(text, /\[WrongSection\]\r?\nFeaturesEnabled = false/);
});

test('saving missing relationship keys preserves CRLF line endings', async (t) => {
  const { root, gameRoot } = await createWorkspace();
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  const configPath = 'BepInEx/config/codex.longyin.staminalock.cfg';
  await writeFile(
    gameRoot,
    configPath,
    [
      '[Relationship]',
      'MaxLoverCount = 8',
      '',
      '[Teaching]',
      'SameSectAreaShareEnabled = true',
      '',
      '[Debug]',
      'TracerEnabled = false',
      ''
    ].join('\r\n')
  );

  const current = await readVisibleSettings(gameRoot);
  await saveVisibleSettings(gameRoot, current);
  const text = await fs.readFile(path.join(gameRoot, configPath), 'utf8');
  const withoutCrLf = text.replace(/\r\n/g, '');

  assert.equal(withoutCrLf.includes('\r'), false, 'must not introduce lone carriage returns');
  assert.equal(withoutCrLf.includes('\n'), false, 'must not introduce lone line feeds');
  assert.match(text, /MaxLoverCount = 8\r\nFeaturesEnabled = false\r\n/);
  assert.match(text, /CharacterDataTestHotkeyEnabled = false\r\n/);
  assert.doesNotMatch(text, /(?:\r\n){3,}/, 'must not expand section spacing');
  assert.match(text, /BlockOverflowLoverHomeBattle = true\r\n\r\n\[Teaching\]/);
});

test('exploration full-reveal setting reads only the Exploration section and round-trips', async (t) => {
  const { root, gameRoot } = await createWorkspace();
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  const configPath = 'BepInEx/config/codex.longyin.staminalock.cfg';
  await writeFile(
    gameRoot,
    configPath,
    [
      '[WrongSection]',
      'RevealAllOnStepTile = true',
      '',
      '[Exploration]',
      'LockStamina = true',
      'RevealAllOnStepTile = false',
      'UnrelatedExplorationSetting = keep-me',
      ''
    ].join('\r\n')
  );

  const current = await readVisibleSettings(gameRoot);
  assert.equal(current.revealAllOnStepTile, false);

  const enabled = await saveVisibleSettings(gameRoot, {
    ...current,
    revealAllOnStepTile: true
  });
  const text = await fs.readFile(path.join(gameRoot, configPath), 'utf8');

  assert.equal(enabled.revealAllOnStepTile, true);
  assert.match(text, /\[Exploration\][\s\S]*^RevealAllOnStepTile = true$/m);
  assert.match(text, /^UnrelatedExplorationSetting = keep-me$/m);
  assert.match(text, /\[WrongSection\]\r?\nRevealAllOnStepTile = true/);
});

test('breakthrough reroll defaults enabled without shortcut settings', async (t) => {
  const { root, gameRoot } = await createWorkspace();
  t.after(() => fs.rm(root, { recursive: true, force: true }));

  const settings = await readVisibleSettings(gameRoot);

  assert.equal(settings.breakthroughRerollEnabled, true);
  assert.equal(Object.hasOwn(settings, 'breakthroughRerollHotkey'), false);
  assert.equal(Object.hasOwn(settings, 'breakthroughRerollRequireAlt'), false);
});

test('breakthrough reroll reads only its owning section and round-trips', async (t) => {
  const { root, gameRoot } = await createWorkspace();
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  const configPath = 'BepInEx/config/codex.longyin.staminalock.cfg';
  await writeFile(
    gameRoot,
    configPath,
    [
      '[WrongSection]',
      'RerollEnabled = false',
      '',
      '[Breakthrough]',
      'RerollEnabled = true',
      'UnrelatedBreakthroughSetting = keep-me',
      ''
    ].join('\r\n')
  );

  const current = await readVisibleSettings(gameRoot);
  assert.equal(current.breakthroughRerollEnabled, true);

  const saved = await saveVisibleSettings(gameRoot, {
    ...current,
    breakthroughRerollEnabled: false
  });
  const text = await fs.readFile(path.join(gameRoot, configPath), 'utf8');

  assert.equal(saved.breakthroughRerollEnabled, false);
  assert.match(text, /\[Breakthrough\][\s\S]*?^RerollEnabled = false$/m);
  assert.match(text, /^UnrelatedBreakthroughSetting = keep-me$/m);
  assert.match(text, /\[WrongSection\]\r?\nRerollEnabled = false/);
  assert.doesNotMatch(text, /\[Breakthrough\][\s\S]*?^(?:RerollHotkey|RerollRequireAlt)\s*=/m);
});

test('craft reroll defaults enabled without shortcut settings', async (t) => {
  const { root, gameRoot } = await createWorkspace();
  t.after(() => fs.rm(root, { recursive: true, force: true }));

  const settings = await readVisibleSettings(gameRoot);

  assert.equal(settings.craftRerollEnabled, true);
  assert.equal(Object.hasOwn(settings, 'craftRerollHotkey'), false);
  assert.equal(Object.hasOwn(settings, 'craftRerollRequireAlt'), false);
});

test('craft reroll reads only the Craft section and round-trips', async (t) => {
  const { root, gameRoot } = await createWorkspace();
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  const configPath = 'BepInEx/config/codex.longyin.staminalock.cfg';
  await writeFile(
    gameRoot,
    configPath,
    [
      '[WrongSection]',
      'RerollEnabled = false',
      '',
      '[Breakthrough]',
      'RerollEnabled = false',
      '',
      '[Craft]',
      'RerollEnabled = true',
      'UnrelatedCraftSetting = keep-me',
      ''
    ].join('\r\n')
  );

  const current = await readVisibleSettings(gameRoot);
  assert.equal(current.craftRerollEnabled, true);

  const saved = await saveVisibleSettings(gameRoot, {
    ...current,
    craftRerollEnabled: false
  });
  const text = await fs.readFile(path.join(gameRoot, configPath), 'utf8');

  assert.equal(saved.craftRerollEnabled, false);
  assert.match(text, /\[Craft\][\s\S]*?^RerollEnabled = false$/m);
  assert.match(text, /^UnrelatedCraftSetting = keep-me$/m);
  assert.match(text, /\[WrongSection\]\r?\nRerollEnabled = false/);
  assert.match(text, /\[Breakthrough\]\r?\nRerollEnabled = false/);
  assert.doesNotMatch(text, /\[Craft\][\s\S]*?^(?:RerollHotkey|RerollRequireAlt)\s*=/m);
});

test('government storage refresh defaults enabled with the R shortcut', async (t) => {
  const { root, gameRoot } = await createWorkspace();
  t.after(() => fs.rm(root, { recursive: true, force: true }));

  const settings = await readVisibleSettings(gameRoot);

  assert.equal(settings.governmentStorageRefreshEnabled, true);
  assert.equal(settings.governmentStorageRefreshHotkey, 'R');
});

test('government storage refresh is section-scoped and round-trips without touching decoys', async (t) => {
  const { root, gameRoot } = await createWorkspace();
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  const configPath = 'BepInEx/config/codex.longyin.staminalock.cfg';
  await writeFile(
    gameRoot,
    configPath,
    [
      '[WrongSection]',
      'RefreshEnabled = decoy-enabled',
      'RefreshHotkey = DECOY_KEY',
      'UnrelatedDecoySetting = keep-decoy',
      '',
      '[GovernmentStorage]',
      'RefreshEnabled = false',
      'RefreshHotkey = T',
      'UnrelatedGovernmentStorageSetting = keep-owner',
      ''
    ].join('\r\n')
  );

  const current = await readVisibleSettings(gameRoot);
  assert.equal(current.governmentStorageRefreshEnabled, false);
  assert.equal(current.governmentStorageRefreshHotkey, 'T');

  const saved = await saveVisibleSettings(gameRoot, {
    ...current,
    governmentStorageRefreshEnabled: true,
    governmentStorageRefreshHotkey: 'Y'
  });
  const text = await fs.readFile(path.join(gameRoot, configPath), 'utf8');

  assert.equal(saved.governmentStorageRefreshEnabled, true);
  assert.equal(saved.governmentStorageRefreshHotkey, 'Y');
  assert.match(text, /\[GovernmentStorage\][\s\S]*?^RefreshEnabled = true$/m);
  assert.match(text, /\[GovernmentStorage\][\s\S]*?^RefreshHotkey = Y$/m);
  assert.match(text, /^UnrelatedGovernmentStorageSetting = keep-owner$/m);
  assert.match(
    text,
    /\[WrongSection\]\r?\nRefreshEnabled = decoy-enabled\r?\nRefreshHotkey = DECOY_KEY\r?\nUnrelatedDecoySetting = keep-decoy/
  );
});

test('city affair refresh controls default enabled with R shortcuts', async (t) => {
  const { root, gameRoot } = await createWorkspace();
  t.after(() => fs.rm(root, { recursive: true, force: true }));

  const settings = await readVisibleSettings(gameRoot);

  assert.equal(settings.yellowCraneCandidateRefreshEnabled, true);
  assert.equal(settings.yellowCraneCandidateRefreshHotkey, 'R');
  assert.equal(settings.forceBountyRefreshEnabled, true);
  assert.equal(settings.commonBountyRefreshEnabled, true);
  assert.equal(settings.governBountyRefreshEnabled, true);
  assert.equal(settings.bountyRefreshHotkey, 'R');
});

test('city affair refresh controls are section-scoped and preserve unknown keys on round-trip', async (t) => {
  const { root, gameRoot } = await createWorkspace();
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  const configPath = 'BepInEx/config/codex.longyin.staminalock.cfg';
  await writeFile(
    gameRoot,
    configPath,
    [
      '[WrongSection]',
      'CandidateRefreshEnabled = decoy-candidate',
      'ForceEnabled = decoy-force',
      'CommonEnabled = decoy-common',
      'GovernEnabled = decoy-govern',
      'CandidateRefreshHotkey = DECOY_CANDIDATE_KEY',
      'RefreshHotkey = DECOY_BOUNTY_KEY',
      'UnrelatedDecoySetting = keep-decoy',
      '',
      '[YellowCraneTower]',
      'CandidateRefreshEnabled = false',
      'CandidateRefreshHotkey = T',
      'UnrelatedYellowCraneSetting = keep-yellow-crane',
      '',
      '[BountyRefresh]',
      'ForceEnabled = false',
      'CommonEnabled = true',
      'GovernEnabled = false',
      'RefreshHotkey = F8',
      'UnrelatedBountySetting = keep-bounty',
      ''
    ].join('\r\n')
  );

  const current = await readVisibleSettings(gameRoot);
  assert.equal(current.yellowCraneCandidateRefreshEnabled, false);
  assert.equal(current.yellowCraneCandidateRefreshHotkey, 'T');
  assert.equal(current.forceBountyRefreshEnabled, false);
  assert.equal(current.commonBountyRefreshEnabled, true);
  assert.equal(current.governBountyRefreshEnabled, false);
  assert.equal(current.bountyRefreshHotkey, 'F8');

  const saved = await saveVisibleSettings(gameRoot, {
    ...current,
    yellowCraneCandidateRefreshEnabled: true,
    yellowCraneCandidateRefreshHotkey: 'Y',
    forceBountyRefreshEnabled: true,
    commonBountyRefreshEnabled: false,
    governBountyRefreshEnabled: true,
    bountyRefreshHotkey: 'F9'
  });
  const text = await fs.readFile(path.join(gameRoot, configPath), 'utf8');

  assert.equal(saved.yellowCraneCandidateRefreshEnabled, true);
  assert.equal(saved.yellowCraneCandidateRefreshHotkey, 'Y');
  assert.equal(saved.forceBountyRefreshEnabled, true);
  assert.equal(saved.commonBountyRefreshEnabled, false);
  assert.equal(saved.governBountyRefreshEnabled, true);
  assert.equal(saved.bountyRefreshHotkey, 'F9');
  assert.match(text, /\[YellowCraneTower\][\s\S]*?^CandidateRefreshEnabled = true$/m);
  assert.match(text, /\[YellowCraneTower\][\s\S]*?^CandidateRefreshHotkey = Y$/m);
  assert.match(text, /\[BountyRefresh\][\s\S]*?^ForceEnabled = true$/m);
  assert.match(text, /\[BountyRefresh\][\s\S]*?^CommonEnabled = false$/m);
  assert.match(text, /\[BountyRefresh\][\s\S]*?^GovernEnabled = true$/m);
  assert.match(text, /\[BountyRefresh\][\s\S]*?^RefreshHotkey = F9$/m);
  assert.match(text, /^UnrelatedYellowCraneSetting = keep-yellow-crane$/m);
  assert.match(text, /^UnrelatedBountySetting = keep-bounty$/m);
  assert.match(
    text,
    /\[WrongSection\]\r?\nCandidateRefreshEnabled = decoy-candidate\r?\nForceEnabled = decoy-force\r?\nCommonEnabled = decoy-common\r?\nGovernEnabled = decoy-govern\r?\nCandidateRefreshHotkey = DECOY_CANDIDATE_KEY\r?\nRefreshHotkey = DECOY_BOUNTY_KEY\r?\nUnrelatedDecoySetting = keep-decoy/
  );
});

test('skill book ownership indicator defaults enabled and round-trips only in SkillDisplay', async (t) => {
  const { root, gameRoot } = await createWorkspace();
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  const configPath = 'BepInEx/config/codex.longyin.staminalock.cfg';

  const defaults = await readVisibleSettings(gameRoot);
  assert.equal(defaults.skillBookOwnershipIndicatorEnabled, true);

  await writeFile(
    gameRoot,
    configPath,
    [
      '[WrongSection]',
      'BookOwnershipIndicatorEnabled = true',
      'UnrelatedDecoySetting = keep-decoy',
      '',
      '[SkillDisplay]',
      'BookOwnershipIndicatorEnabled = false',
      'UnrelatedSkillDisplaySetting = keep-owner',
      ''
    ].join('\r\n')
  );

  const current = await readVisibleSettings(gameRoot);
  assert.equal(current.skillBookOwnershipIndicatorEnabled, false);

  const saved = await saveVisibleSettings(gameRoot, {
    ...current,
    skillBookOwnershipIndicatorEnabled: true
  });
  const text = await fs.readFile(path.join(gameRoot, configPath), 'utf8');

  assert.equal(saved.skillBookOwnershipIndicatorEnabled, true);
  assert.match(text, /\[SkillDisplay\][\s\S]*?^BookOwnershipIndicatorEnabled = true$/m);
  assert.match(text, /^UnrelatedSkillDisplaySetting = keep-owner$/m);
  assert.match(
    text,
    /\[WrongSection\]\r?\nBookOwnershipIndicatorEnabled = true\r?\nUnrelatedDecoySetting = keep-decoy/
  );
});

test('commerce and assist settings have safe defaults with only the supported auction shortcut', async (t) => {
  const { root, gameRoot } = await createWorkspace();
  t.after(() => fs.rm(root, { recursive: true, force: true }));

  const settings = await readVisibleSettings(gameRoot);

  assert.deepEqual(
    {
      treasureTradeHelperEnabled: settings.treasureTradeHelperEnabled,
      materialAutoBuyEnabled: settings.materialAutoBuyEnabled,
      materialPurchaseMinRareLv: settings.materialPurchaseMinRareLv,
      materialPurchaseMinItemLv: settings.materialPurchaseMinItemLv,
      shopOwnershipEnabled: settings.shopOwnershipEnabled,
      auctionEventAlwaysRedEnabled: settings.auctionEventAlwaysRedEnabled,
      auctionPreviewRefreshEnabled: settings.auctionPreviewRefreshEnabled,
      auctionPreviewRefreshHotkey: settings.auctionPreviewRefreshHotkey,
      treasureIdentifyBestValueAssistEnabled: settings.treasureIdentifyBestValueAssistEnabled
    },
    {
      treasureTradeHelperEnabled: true,
      materialAutoBuyEnabled: true,
      materialPurchaseMinRareLv: 0,
      materialPurchaseMinItemLv: 0,
      shopOwnershipEnabled: true,
      auctionEventAlwaysRedEnabled: true,
      auctionPreviewRefreshEnabled: true,
      auctionPreviewRefreshHotkey: 'R',
      treasureIdentifyBestValueAssistEnabled: true
    }
  );
  for (const removedKey of [
    'auctionPreviewRefreshRequireAlt',
    'treasureIdentifyBestValueHotkey',
    'treasureIdentifyBestValueRequireAlt'
  ]) {
    assert.equal(Object.hasOwn(settings, removedKey), false, `legacy field remains: ${removedKey}`);
  }
});

test('commerce and assist settings read the supported auction shortcut only from its owning section', async (t) => {
  const { root, gameRoot } = await createWorkspace();
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  await writeFile(
    gameRoot,
    'BepInEx/config/codex.longyin.staminalock.cfg',
    [
      '[WrongSection]',
      'TreasureTradeHelperEnabled = true',
      'MaterialAutoBuyEnabled = true',
      'MaterialPurchaseMinRareLv = 1',
      'MaterialPurchaseMinItemLv = 1',
      'ShopOwnershipEnabled = true',
      'EventAlwaysRedEnabled = true',
      'PreviewRefreshEnabled = true',
      'PreviewRefreshHotkey = WRONG_AUCTION_KEY',
      'PreviewRefreshRequireAlt = true',
      'BestValueAssistEnabled = true',
      'BestValueHotkey = WRONG_IDENTIFY_KEY',
      'BestValueRequireAlt = true',
      '',
      '[Commerce]',
      'TreasureTradeHelperEnabled = false',
      'MaterialAutoBuyEnabled = false',
      'MaterialPurchaseMinRareLv = 4',
      'MaterialPurchaseMinItemLv = 3',
      'ShopOwnershipEnabled = false',
      '',
      '[Auction]',
      'EventAlwaysRedEnabled = false',
      'PreviewRefreshEnabled = false',
      'PreviewRefreshHotkey = T',
      'PreviewRefreshRequireAlt = false',
      '',
      '[TreasureIdentify]',
      'BestValueAssistEnabled = false',
      'BestValueHotkey = G',
      'BestValueRequireAlt = false',
      ''
    ].join('\r\n')
  );

  const settings = await readVisibleSettings(gameRoot);

  assert.deepEqual(
    {
      treasureTradeHelperEnabled: settings.treasureTradeHelperEnabled,
      materialAutoBuyEnabled: settings.materialAutoBuyEnabled,
      materialPurchaseMinRareLv: settings.materialPurchaseMinRareLv,
      materialPurchaseMinItemLv: settings.materialPurchaseMinItemLv,
      shopOwnershipEnabled: settings.shopOwnershipEnabled,
      auctionEventAlwaysRedEnabled: settings.auctionEventAlwaysRedEnabled,
      auctionPreviewRefreshEnabled: settings.auctionPreviewRefreshEnabled,
      auctionPreviewRefreshHotkey: settings.auctionPreviewRefreshHotkey,
      treasureIdentifyBestValueAssistEnabled: settings.treasureIdentifyBestValueAssistEnabled
    },
    {
      treasureTradeHelperEnabled: false,
      materialAutoBuyEnabled: false,
      materialPurchaseMinRareLv: 4,
      materialPurchaseMinItemLv: 3,
      shopOwnershipEnabled: false,
      auctionEventAlwaysRedEnabled: false,
      auctionPreviewRefreshEnabled: false,
      auctionPreviewRefreshHotkey: 'T',
      treasureIdentifyBestValueAssistEnabled: false
    }
  );
  for (const removedKey of [
    'auctionPreviewRefreshRequireAlt',
    'treasureIdentifyBestValueHotkey',
    'treasureIdentifyBestValueRequireAlt'
  ]) {
    assert.equal(Object.hasOwn(settings, removedKey), false, `legacy field was parsed: ${removedKey}`);
  }
});

test('saving commerce and assist settings round-trips the auction shortcut and removes obsolete shortcut fields without touching decoys', async (t) => {
  const { root, gameRoot } = await createWorkspace();
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  const configPath = 'BepInEx/config/codex.longyin.staminalock.cfg';
  await writeFile(
    gameRoot,
    configPath,
    [
      '[WrongSection]',
      'TreasureTradeHelperEnabled = decoy-trade',
      'MaterialAutoBuyEnabled = decoy-material',
      'MaterialPurchaseMinRareLv = 91',
      'MaterialPurchaseMinItemLv = 92',
      'ShopOwnershipEnabled = decoy-shop',
      'EventAlwaysRedEnabled = decoy-auction-event',
      'PreviewRefreshEnabled = decoy-auction',
      '## decoy auction shortcut comment must stay',
      'PreviewRefreshHotkey = DECOY_AUCTION_KEY',
      'PreviewRefreshRequireAlt = decoy-auction-alt',
      'BestValueAssistEnabled = decoy-identify',
      '## decoy appraisal shortcut comment must stay',
      'BestValueHotkey = DECOY_IDENTIFY_KEY',
      'BestValueRequireAlt = decoy-identify-alt',
      '',
      '[Commerce]',
      'MerchantCarryCash = 43210',
      'UnrelatedFutureSetting = keep-me',
      '',
      '[Auction]',
      '## unrelated user note: preserve me',
      '## Main key used to refresh while the auction exhibit preview is open.',
      '# Setting type: KeyCode',
      '# Default value: W',
      '# Acceptable values: A, B, C',
      'PreviewRefreshHotkey = T',
      '## When true, hold either Alt key while pressing PreviewRefreshHotkey. The default shortcut is Alt+W.',
      '# Setting type: Boolean',
      '# Default value: true',
      '',
      '[TreasureIdentify]',
      '# another custom comment that must survive migration',
      '## Main key used to select the highest parenthesized appraisal value while the appraisal window is open.',
      '# Setting type: KeyCode',
      '# Default value: F',
      '# Acceptable values: A, B, C',
      'BestValueHotkey = G',
      '## When true, hold either Alt key while pressing BestValueHotkey. The default shortcut is Alt+F.',
      '# Setting type: Boolean',
      '# Default value: true',
      ''
    ].join('\r\n')
  );
  const current = await readVisibleSettings(gameRoot);

  const saved = await saveVisibleSettings(gameRoot, {
    ...current,
    treasureTradeHelperEnabled: false,
    materialAutoBuyEnabled: false,
    materialPurchaseMinRareLv: 5,
    materialPurchaseMinItemLv: 2,
    shopOwnershipEnabled: false,
    auctionEventAlwaysRedEnabled: false,
    auctionPreviewRefreshEnabled: false,
    auctionPreviewRefreshHotkey: 'Y',
    treasureIdentifyBestValueAssistEnabled: false
  });
  const text = await fs.readFile(path.join(gameRoot, configPath), 'utf8');

  assert.equal(saved.treasureTradeHelperEnabled, false);
  assert.equal(saved.materialAutoBuyEnabled, false);
  assert.equal(saved.materialPurchaseMinRareLv, 5);
  assert.equal(saved.materialPurchaseMinItemLv, 2);
  assert.equal(saved.shopOwnershipEnabled, false);
  assert.equal(saved.auctionEventAlwaysRedEnabled, false);
  assert.equal(saved.auctionPreviewRefreshEnabled, false);
  assert.equal(saved.auctionPreviewRefreshHotkey, 'Y');
  assert.equal(saved.treasureIdentifyBestValueAssistEnabled, false);
  for (const removedKey of [
    'auctionPreviewRefreshRequireAlt',
    'treasureIdentifyBestValueHotkey',
    'treasureIdentifyBestValueRequireAlt'
  ]) {
    assert.equal(Object.hasOwn(saved, removedKey), false, `legacy field was returned: ${removedKey}`);
  }
  assert.match(text, /^UnrelatedFutureSetting = keep-me$/m);
  assert.match(text, /^MerchantCarryCash = 43210$/m);
  assert.match(text, /^TreasureTradeHelperEnabled = false$/m);
  assert.match(text, /^MaterialAutoBuyEnabled = false$/m);
  assert.match(text, /^MaterialPurchaseMinRareLv = 5$/m);
  assert.match(text, /^MaterialPurchaseMinItemLv = 2$/m);
  assert.match(text, /^ShopOwnershipEnabled = false$/m);
  assert.match(text, /^\[Auction\]$/m);
  assert.match(text, /^EventAlwaysRedEnabled = false$/m);
  assert.match(text, /^PreviewRefreshEnabled = false$/m);
  assert.match(text, /^PreviewRefreshHotkey = Y$/m);
  assert.match(text, /^\[TreasureIdentify\]$/m);
  assert.match(text, /^BestValueAssistEnabled = false$/m);
  assert.doesNotMatch(text, /\[Auction\][\s\S]*?^PreviewRefreshRequireAlt\s*=/m);
  assert.doesNotMatch(text, /\[TreasureIdentify\][\s\S]*?^BestValueHotkey\s*=/m);
  assert.doesNotMatch(text, /\[TreasureIdentify\][\s\S]*?^BestValueRequireAlt\s*=/m);
  assert.doesNotMatch(text, /Main key used to (?:refresh|select)/);
  assert.doesNotMatch(text, /default shortcut is Alt\+[WF]/);
  assert.match(text, /^## unrelated user note: preserve me$/m);
  assert.match(text, /^# another custom comment that must survive migration$/m);
  assert.match(text, /^## decoy auction shortcut comment must stay$/m);
  assert.match(text, /^## decoy appraisal shortcut comment must stay$/m);
  assert.match(
    text,
    /\[WrongSection\]\r?\nTreasureTradeHelperEnabled = decoy-trade\r?\nMaterialAutoBuyEnabled = decoy-material\r?\nMaterialPurchaseMinRareLv = 91\r?\nMaterialPurchaseMinItemLv = 92\r?\nShopOwnershipEnabled = decoy-shop\r?\nEventAlwaysRedEnabled = decoy-auction-event\r?\nPreviewRefreshEnabled = decoy-auction\r?\n## decoy auction shortcut comment must stay\r?\nPreviewRefreshHotkey = DECOY_AUCTION_KEY\r?\nPreviewRefreshRequireAlt = decoy-auction-alt\r?\nBestValueAssistEnabled = decoy-identify\r?\n## decoy appraisal shortcut comment must stay\r?\nBestValueHotkey = DECOY_IDENTIFY_KEY\r?\nBestValueRequireAlt = decoy-identify-alt/
  );
});

test('reading custom talents returns an empty pack without creating its JSON file', async (t) => {
  const { root, gameRoot } = await createWorkspace();
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  await writeFile(gameRoot, 'LongYinLiZhiZhuan.exe', 'game');

  const pack = await readCustomTalentPack(gameRoot);

  assert.deepEqual(pack, { version: 1, talents: [] });
  assert.equal(
    await exists(path.join(gameRoot, 'BepInEx/config/codex.longyin.custom-talents.json')),
    false
  );
});

test('health reports live plugin hash drift and MissingMethod or Harmony target failures', async (t) => {
  const { root, gameRoot, payloadRoot } = await createWorkspace();
  t.after(() => fs.rm(root, { recursive: true, force: true }));

  const pluginPath = 'BepInEx/plugins/LongYinFuturePlugin.dll';
  await writeFile(payloadRoot, pluginPath, 'payload dll');
  await writeFile(gameRoot, pluginPath, 'stale live dll');
  await writeFile(
    gameRoot,
    'BepInEx/LogOutput.log',
    '[Error :LongYin] System.MissingMethodException: Method not found\n' +
      '[Error : HarmonyX] HarmonyLib.HarmonyException: Patching exception in method null'
  );

  const health = await inspectGameHealth(gameRoot, payloadRoot);
  const runtimeCheck = health.checks.find((check) => check.key === 'bepinex-runtime-log');

  assert.equal(health.driftedFiles.includes(pluginPath), true);
  assert.equal(runtimeCheck?.ok, false);
  assert.equal(runtimeCheck?.blocking, false);
  assert.match(runtimeCheck?.detail ?? '', /MissingMethod/);
  assert.match(runtimeCheck?.detail ?? '', /Harmony/);
});

test('health reports missing managed configuration files without creating them', async (t) => {
  const { root, gameRoot } = await createWorkspace();
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  await writeFile(gameRoot, 'LongYinLiZhiZhuan.exe', 'game');

  const health = await inspectGameHealth(gameRoot);
  const configCheck = health.checks.find((check) => check.key === 'config-files');

  assert.equal(configCheck?.ok, false);
  assert.equal(await exists(path.join(gameRoot, 'BepInEx/config')), false);
});

test('stale runtime-log findings warn without forcing a payload repair loop', async (t) => {
  const { root, gameRoot, payloadRoot } = await createWorkspace();
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  const plugins = [
    'LongYinBattleTurbo.dll',
    'LongYinHorseStaminaMultiplier.dll',
    'LongYinQuestSnapshot.dll',
    'LongYinSkillTalentGrant.dll',
    'LongYinSkipIntro.dll',
    'LongYinProMax.dll'
  ];

  await writeFile(gameRoot, 'LongYinLiZhiZhuan.exe', 'game');
  await writeFile(gameRoot, 'steam_appid.txt', '3202030\n');
  await writeFile(gameRoot, 'BepInEx/LogOutput.log', 'System.MissingMethodException: old run');
  for (const relativePath of ['winhttp.dll', 'doorstop_config.ini']) {
    const content = relativePath === 'doorstop_config.ini'
      ? 'enabled = true\nignore_disable_switch = true\n'
      : 'loader';
    await writeFile(payloadRoot, relativePath, content);
    await writeFile(gameRoot, relativePath, content);
  }
  for (const plugin of plugins) {
    const relativePath = `BepInEx/plugins/${plugin}`;
    await writeFile(payloadRoot, relativePath, plugin);
    await writeFile(gameRoot, relativePath, plugin);
  }
  for (const configName of [
    'codex.longyin.staminalock.cfg',
    'codex.longyin.horsestamina.cfg',
    'codex.longyin.questsnapshot.cfg',
    'codex.longyin.skilltalentgrant.cfg',
    'codex.longyin.battleturbo.cfg',
    'codex.longyin.custom-talents.json'
  ]) {
    await writeFile(gameRoot, `BepInEx/config/${configName}`, configName.endsWith('.json') ? '{"version":1,"talents":[]}' : '');
  }
  const staleLogTime = new Date(Date.now() - 60_000);
  await fs.utimes(path.join(gameRoot, 'BepInEx/LogOutput.log'), staleLogTime, staleLogTime);

  const health = await inspectGameHealth(gameRoot, payloadRoot);
  const runtimeCheck = health.checks.find((check) => check.key === 'bepinex-runtime-log');

  assert.equal(health.healthy, false);
  assert.equal(health.needsRepair, false);
  assert.equal(health.launchBlocked, false);
  assert.equal(runtimeCheck?.ok, false);
  assert.equal(runtimeCheck?.blocking, false);
  assert.match(runtimeCheck?.detail ?? '', /日志早于当前插件部署/);
});

test('current hard runtime failures block launch while compatibility degradation remains a warning', async (t) => {
  const { root, gameRoot, payloadRoot } = await createWorkspace();
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  const plugins = [
    'LongYinBattleTurbo.dll',
    'LongYinHorseStaminaMultiplier.dll',
    'LongYinQuestSnapshot.dll',
    'LongYinSkillTalentGrant.dll',
    'LongYinSkipIntro.dll',
    'LongYinProMax.dll'
  ];

  await writeFile(gameRoot, 'LongYinLiZhiZhuan.exe', 'game');
  await writeFile(gameRoot, 'steam_appid.txt', '3202030\n');
  for (const relativePath of ['winhttp.dll', 'doorstop_config.ini']) {
    const content = relativePath === 'doorstop_config.ini'
      ? 'enabled = true\nignore_disable_switch = true\n'
      : 'loader';
    await writeFile(payloadRoot, relativePath, content);
    await writeFile(gameRoot, relativePath, content);
  }
  for (const plugin of plugins) {
    const relativePath = `BepInEx/plugins/${plugin}`;
    await writeFile(payloadRoot, relativePath, plugin);
    await writeFile(gameRoot, relativePath, plugin);
  }
  for (const configName of [
    'codex.longyin.staminalock.cfg',
    'codex.longyin.horsestamina.cfg',
    'codex.longyin.questsnapshot.cfg',
    'codex.longyin.skilltalentgrant.cfg',
    'codex.longyin.battleturbo.cfg',
    'codex.longyin.custom-talents.json'
  ]) {
    await writeFile(gameRoot, `BepInEx/config/${configName}`, configName.endsWith('.json') ? '{"version":1,"talents":[]}' : '');
  }
  await writeFile(
    gameRoot,
    'BepInEx/LogOutput.log',
    '[Error :LongYin] System.MissingMethodException: current failure\n' +
      '[Info :LongYin] [Compatibility] Treasure helper: DEGRADED'
  );

  const health = await inspectGameHealth(gameRoot, payloadRoot);
  const runtimeCheck = health.checks.find((check) => check.key === 'bepinex-runtime-log');

  assert.equal(health.healthy, false);
  assert.equal(health.needsRepair, false);
  assert.equal(health.launchBlocked, true);
  assert.equal(runtimeCheck?.blocking, false);
  assert.equal(runtimeCheck?.launchBlocking, true);
  assert.match(runtimeCheck?.detail ?? '', /MissingMethodException/);
  assert.match(runtimeCheck?.detail ?? '', /DEGRADED/);
});
