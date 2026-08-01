const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');

const { inspectGameHealth, readCustomTalentPack, readVisibleSettings } = require('../dist/main/shared/config.js');
const { installOwnedPayload, uninstallOwnedPayload } = require('../dist/main/shared/payload.js');

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

test('uninstall restores replaced files and leaves unrelated BepInEx files untouched', async (t) => {
  const { root, gameRoot, payloadRoot } = await createWorkspace();
  t.after(() => fs.rm(root, { recursive: true, force: true }));

  await writeFile(payloadRoot, 'winhttp.dll', 'longyin loader');
  await writeFile(payloadRoot, 'BepInEx/plugins/LongYinStaminaLock.dll', 'longyin plugin');
  await writeFile(payloadRoot, 'BepInEx/plugins/LongYinSkipIntro.dll', 'new plugin');
  await writeFile(payloadRoot, 'BepInEx/unity-libs/runtime.zip', 'nested runtime archive');
  await writeFile(gameRoot, 'winhttp.dll', 'original loader');
  await writeFile(gameRoot, 'BepInEx/plugins/LongYinStaminaLock.dll', 'original plugin');
  await writeFile(gameRoot, 'BepInEx/plugins/ThirdParty.dll', 'third party');

  await installOwnedPayload(gameRoot, payloadRoot);
  assert.equal(await fs.readFile(path.join(gameRoot, 'winhttp.dll'), 'utf8'), 'longyin loader');
  assert.equal(
    await fs.readFile(path.join(gameRoot, 'BepInEx/plugins/LongYinStaminaLock.dll'), 'utf8'),
    'longyin plugin'
  );
  assert.equal(
    await fs.readFile(path.join(gameRoot, 'BepInEx/unity-libs/runtime.zip'), 'utf8'),
    'nested runtime archive'
  );

  await uninstallOwnedPayload(gameRoot, payloadRoot);
  assert.equal(await fs.readFile(path.join(gameRoot, 'winhttp.dll'), 'utf8'), 'original loader');
  assert.equal(
    await fs.readFile(path.join(gameRoot, 'BepInEx/plugins/LongYinStaminaLock.dll'), 'utf8'),
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
  const relativePlugin = 'BepInEx/plugins/LongYinStaminaLock.dll';
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
  assert.deepEqual(after, before);
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
    'LongYinStaminaLock.dll'
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
    'LongYinStaminaLock.dll'
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
