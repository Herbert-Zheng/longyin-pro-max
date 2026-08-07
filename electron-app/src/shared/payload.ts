import { promises as fs } from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

const INSTALL_STATE_DIRECTORY = '.longyin-plus';
const INSTALL_MANIFEST_NAME = 'install-manifest.json';
const INSTALL_MANIFEST_VERSION = 1 as const;
const PRIMARY_PLUGIN_RELATIVE_PATH = 'BepInEx/plugins/LongYinProMax.dll';
const LEGACY_PRIMARY_PLUGIN_RELATIVE_PATH = 'BepInEx/plugins/LongYinStaminaLock.dll';

type ManifestAction = 'created' | 'replaced' | 'preserved';

interface InstallManifestEntry {
  relativePath: string;
  action: ManifestAction;
}

interface InstallManifest {
  version: typeof INSTALL_MANIFEST_VERSION;
  entries: InstallManifestEntry[];
}

async function fileExists(filePath: string): Promise<boolean> {
  try {
    return (await fs.stat(filePath)).isFile();
  }
  catch {
    return false;
  }
}

function normalizeRelativePath(relativePath: string): string {
  const normalized = relativePath.replace(/\\/g, '/').replace(/^\.\//, '');
  if (
    !normalized ||
    path.posix.isAbsolute(normalized) ||
    normalized.split('/').some((part) => part === '..' || part.length === 0)
  ) {
    throw new Error(`载荷包含不安全路径：${relativePath}`);
  }

  return normalized;
}

function resolveInside(root: string, relativePath: string): string {
  const normalized = normalizeRelativePath(relativePath);
  const resolvedRoot = path.resolve(root);
  const resolved = path.resolve(resolvedRoot, ...normalized.split('/'));
  if (resolved !== resolvedRoot && !resolved.startsWith(`${resolvedRoot}${path.sep}`)) {
    throw new Error(`载荷路径超出目标目录：${relativePath}`);
  }
  return resolved;
}

async function listFiles(root: string): Promise<string[]> {
  const rootExists = await fs.stat(root).then((stat) => stat.isDirectory()).catch(() => false);
  if (!rootExists) {
    return [];
  }

  const files: string[] = [];
  async function visit(relativeDirectory: string): Promise<void> {
    const directoryPath = relativeDirectory ? resolveInside(root, relativeDirectory) : root;
    const entries = await fs.readdir(directoryPath, { withFileTypes: true });
    for (const entry of entries) {
      const relativePath = normalizeRelativePath(
        relativeDirectory ? `${relativeDirectory}/${entry.name}` : entry.name
      );
      if (entry.isSymbolicLink()) {
        throw new Error(`载荷不支持符号链接：${relativePath}`);
      }
      if (entry.isDirectory()) {
        await visit(relativePath);
      }
      else if (
        entry.isFile() &&
        (relativeDirectory.length > 0 || !entry.name.toLowerCase().endsWith('.zip'))
      ) {
        files.push(relativePath);
      }
    }
  }

  await visit('');
  return files.sort((left, right) => left.localeCompare(right));
}

async function sha256File(filePath: string): Promise<string | undefined> {
  try {
    const buffer = await fs.readFile(filePath);
    return crypto.createHash('sha256').update(buffer).digest('hex');
  }
  catch {
    return undefined;
  }
}

function manifestPaths(gameRoot: string) {
  const stateRoot = path.join(gameRoot, INSTALL_STATE_DIRECTORY);
  return {
    stateRoot,
    manifestPath: path.join(stateRoot, INSTALL_MANIFEST_NAME),
    backupRoot: path.join(stateRoot, 'backups'),
    updateBackupRoot: path.join(stateRoot, 'update-backups'),
    transactionRoot: path.join(stateRoot, 'transactions')
  };
}

function parseManifest(input: unknown): InstallManifest {
  if (!input || typeof input !== 'object') {
    throw new Error('安装清单不是合法对象。');
  }

  const candidate = input as Record<string, unknown>;
  if (candidate.version !== INSTALL_MANIFEST_VERSION || !Array.isArray(candidate.entries)) {
    throw new Error('安装清单版本或 entries 无效。');
  }

  const seen = new Set<string>();
  const entries = candidate.entries.map((inputEntry) => {
    if (!inputEntry || typeof inputEntry !== 'object') {
      throw new Error('安装清单包含无效条目。');
    }
    const entry = inputEntry as Record<string, unknown>;
    if (typeof entry.relativePath !== 'string') {
      throw new Error('安装清单条目缺少 relativePath。');
    }
    const relativePath = normalizeRelativePath(entry.relativePath);
    if (entry.action !== 'created' && entry.action !== 'replaced' && entry.action !== 'preserved') {
      throw new Error(`安装清单条目 action 无效：${relativePath}`);
    }
    if (seen.has(relativePath.toLowerCase())) {
      throw new Error(`安装清单包含重复路径：${relativePath}`);
    }
    seen.add(relativePath.toLowerCase());
    return { relativePath, action: entry.action } as InstallManifestEntry;
  });

  return { version: INSTALL_MANIFEST_VERSION, entries };
}

async function readManifest(gameRoot: string): Promise<InstallManifest | undefined> {
  const { manifestPath } = manifestPaths(gameRoot);
  if (!(await fileExists(manifestPath))) {
    return undefined;
  }

  try {
    return parseManifest(JSON.parse(await fs.readFile(manifestPath, 'utf8')));
  }
  catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    throw new Error(`无法读取安全安装清单：${message}`);
  }
}

async function writeManifest(gameRoot: string, manifest: InstallManifest): Promise<void> {
  const { manifestPath } = manifestPaths(gameRoot);
  await fs.mkdir(path.dirname(manifestPath), { recursive: true });
  const temporaryPath = `${manifestPath}.${process.pid}.${Date.now()}.tmp`;
  try {
    await fs.writeFile(temporaryPath, `${JSON.stringify(manifest, null, 2)}\n`, 'utf8');
    await fs.rename(temporaryPath, manifestPath);
  }
  catch (error) {
    await fs.rm(temporaryPath, { force: true }).catch(() => undefined);
    throw error;
  }
}

function isMutableConfig(relativePath: string): boolean {
  return relativePath.toLowerCase().startsWith('bepinex/config/');
}

function isLegacyProjectOwnedPath(relativePath: string): boolean {
  const normalized = relativePath.toLowerCase();
  return (
    /^bepinex\/plugins\/longyin[^/]*\.dll$/.test(normalized) ||
    /^bepinex\/config\/codex\.longyin\.[^/]+$/.test(normalized) ||
    normalized.startsWith('longyinoverlay/') ||
    normalized === 'launch-longyinpromax.cmd' ||
    normalized === 'uninstall.cmd' ||
    normalized === 'uninstall.ps1'
  );
}

async function removeEmptyParents(filePath: string, gameRoot: string): Promise<void> {
  const resolvedRoot = path.resolve(gameRoot);
  let current = path.dirname(filePath);
  while (current !== resolvedRoot && current.startsWith(`${resolvedRoot}${path.sep}`)) {
    try {
      await fs.rmdir(current);
    }
    catch {
      break;
    }
    current = path.dirname(current);
  }
}

interface TransactionSnapshot {
  originalPath: string;
  backupPath: string;
  kind: 'absent' | 'file' | 'directory';
}

async function getPathKind(filePath: string): Promise<TransactionSnapshot['kind']> {
  return fs.stat(filePath).then((stat) => {
    if (stat.isFile()) {
      return 'file' as const;
    }
    if (stat.isDirectory()) {
      return 'directory' as const;
    }
    throw new Error(`事务不支持此文件类型：${filePath}`);
  }).catch((error: NodeJS.ErrnoException) => {
    if (error.code === 'ENOENT' || error.code === 'ENOTDIR') {
      return 'absent' as const;
    }
    throw error;
  });
}

async function removeMissingPath(filePath: string): Promise<void> {
  await fs.rm(filePath, { recursive: true, force: true }).catch((error: NodeJS.ErrnoException) => {
    if (error.code !== 'ENOENT' && error.code !== 'ENOTDIR') {
      throw error;
    }
  });
}

async function createInstallTransaction(
  gameRoot: string,
  pathsToProtect: string[]
): Promise<{
  directory: string;
  commit: () => Promise<void>;
  rollback: () => Promise<void>;
}> {
  const { transactionRoot } = manifestPaths(gameRoot);
  await fs.mkdir(transactionRoot, { recursive: true });
  const directory = await fs.mkdtemp(path.join(transactionRoot, 'install-'));
  const uniquePaths = [...new Set(pathsToProtect.map((filePath) => path.resolve(filePath)))];
  const snapshots: TransactionSnapshot[] = [];

  for (const [index, originalPath] of uniquePaths.entries()) {
    const kind = await getPathKind(originalPath);
    const backupPath = path.join(directory, 'files', String(index));
    if (kind !== 'absent') {
      await fs.mkdir(path.dirname(backupPath), { recursive: true });
      if (kind === 'file') {
        await fs.copyFile(originalPath, backupPath);
      }
      else {
        await fs.cp(originalPath, backupPath, { recursive: true });
      }
    }
    snapshots.push({ originalPath, backupPath, kind });
  }

  await fs.writeFile(
    path.join(directory, 'transaction.json'),
    `${JSON.stringify({ createdAt: new Date().toISOString(), snapshots }, null, 2)}\n`,
    'utf8'
  );

  return {
    directory,
    commit: async () => {
      await fs.rm(directory, { recursive: true, force: true }).catch(() => undefined);
    },
    rollback: async () => {
      const failures: string[] = [];
      for (const snapshot of [...snapshots].reverse()) {
        try {
          if (snapshot.kind !== 'absent') {
            await removeMissingPath(snapshot.originalPath);
            await fs.mkdir(path.dirname(snapshot.originalPath), { recursive: true });
            if (snapshot.kind === 'file') {
              await fs.copyFile(snapshot.backupPath, snapshot.originalPath);
            }
            else {
              await fs.cp(snapshot.backupPath, snapshot.originalPath, { recursive: true });
            }
          }
          else {
            await removeMissingPath(snapshot.originalPath);
          }
        }
        catch (error) {
          failures.push(`${snapshot.originalPath}: ${error instanceof Error ? error.message : String(error)}`);
        }
      }
      if (failures.length > 0) {
        throw new Error(`事务回滚未完全成功；可恢复备份保留在 ${directory}。${failures.join('；')}`);
      }
    }
  };
}

export async function installOwnedPayload(gameRoot: string, payloadRoot: string): Promise<void> {
  const relativeFiles = await listFiles(payloadRoot);
  if (relativeFiles.length === 0) {
    throw new Error(`未找到可安装的模组载荷：${payloadRoot}`);
  }

  const existingManifest = await readManifest(gameRoot);
  const manifest: InstallManifest = existingManifest
    ? { version: INSTALL_MANIFEST_VERSION, entries: existingManifest.entries.map((entry) => ({ ...entry })) }
    : { version: INSTALL_MANIFEST_VERSION, entries: [] };
  const entriesByPath = new Map(
    manifest.entries.map((entry) => [entry.relativePath.toLowerCase(), entry] as const)
  );
  const { backupRoot, updateBackupRoot } = manifestPaths(gameRoot);
  const payloadPaths = new Set(relativeFiles.map((relativePath) => relativePath.toLowerCase()));
  const installsRenamedPrimaryPlugin = payloadPaths.has(PRIMARY_PLUGIN_RELATIVE_PATH.toLowerCase());
  const legacyPrimaryPluginKey = LEGACY_PRIMARY_PLUGIN_RELATIVE_PATH.toLowerCase();
  const legacyTargetPath = resolveInside(gameRoot, LEGACY_PRIMARY_PLUGIN_RELATIVE_PATH);
  const legacyTargetExists = await fileExists(legacyTargetPath);
  const legacyManifestEntry = entriesByPath.get(legacyPrimaryPluginKey);
  const legacyNeedsFreshBackup = installsRenamedPrimaryPlugin && legacyTargetExists &&
    (!legacyManifestEntry || legacyManifestEntry.action === 'preserved');
  if (legacyNeedsFreshBackup) {
    // Older installations may predate the manifest. Keep a persistent backup so
    // uninstall can restore the original legacy plugin after the rename migration.
    // A preserved entry also represents a pre-existing file that the old installer
    // deliberately left untouched, so removing it now changes the action to replaced.
    entriesByPath.set(legacyPrimaryPluginKey, {
      relativePath: LEGACY_PRIMARY_PLUGIN_RELATIVE_PATH,
      action: 'replaced'
    });
  }
  for (const entry of manifest.entries) {
    if (
      entry.action === 'replaced' &&
      !(legacyNeedsFreshBackup && entry.relativePath.toLowerCase() === legacyPrimaryPluginKey) &&
      !(await fileExists(resolveInside(backupRoot, entry.relativePath)))
    ) {
      throw new Error(`无法安全覆盖载荷：缺少原文件备份 ${entry.relativePath}`);
    }
  }

  const filesToCopy: string[] = [];
  const obsoleteEntries = manifest.entries.filter(
    (entry) =>
      !payloadPaths.has(entry.relativePath.toLowerCase()) &&
      !(installsRenamedPrimaryPlugin && entry.relativePath.toLowerCase() === legacyPrimaryPluginKey)
  );

  for (const relativePath of relativeFiles) {
    if (
      relativePath.toLowerCase() === INSTALL_STATE_DIRECTORY ||
      relativePath.toLowerCase().startsWith(`${INSTALL_STATE_DIRECTORY}/`)
    ) {
      throw new Error(`载荷不得占用安装状态目录：${relativePath}`);
    }
    const sourcePath = resolveInside(payloadRoot, relativePath);
    const targetPath = resolveInside(gameRoot, relativePath);
    let manifestEntry = entriesByPath.get(relativePath.toLowerCase());
    const targetExists = await fileExists(targetPath);

    if (manifestEntry && isMutableConfig(relativePath) && targetExists) {
      continue;
    }

    if (!targetExists) {
      if (!manifestEntry || manifestEntry.action === 'preserved') {
        manifestEntry = { relativePath, action: 'created' };
        entriesByPath.set(relativePath.toLowerCase(), manifestEntry);
      }
      filesToCopy.push(relativePath);
      continue;
    }

    const [sourceHash, targetHash] = await Promise.all([sha256File(sourcePath), sha256File(targetPath)]);
    if (sourceHash && sourceHash === targetHash) {
      if (!manifestEntry) {
        manifestEntry = { relativePath, action: 'preserved' };
        entriesByPath.set(relativePath.toLowerCase(), manifestEntry);
      }
      continue;
    }

    if (!manifestEntry || manifestEntry.action === 'preserved') {
      manifestEntry = { relativePath, action: 'replaced' };
      entriesByPath.set(relativePath.toLowerCase(), manifestEntry);
    }
    filesToCopy.push(relativePath);
  }

  const { manifestPath } = manifestPaths(gameRoot);
  const protectedPaths = [manifestPath];
  for (const relativePath of new Set([
    ...manifest.entries.map((entry) => entry.relativePath),
    ...relativeFiles,
    ...(installsRenamedPrimaryPlugin ? [LEGACY_PRIMARY_PLUGIN_RELATIVE_PATH] : [])
  ])) {
    protectedPaths.push(
      resolveInside(gameRoot, relativePath),
      resolveInside(backupRoot, relativePath),
      resolveInside(updateBackupRoot, relativePath)
    );
  }

  const transaction = await createInstallTransaction(gameRoot, protectedPaths);
  try {
    if (installsRenamedPrimaryPlugin) {
      const legacyBackupPath = resolveInside(backupRoot, LEGACY_PRIMARY_PLUGIN_RELATIVE_PATH);
      const legacyEntry = entriesByPath.get(legacyPrimaryPluginKey);
      if (
        legacyEntry?.action === 'replaced' &&
        legacyTargetExists &&
        (legacyNeedsFreshBackup || !(await fileExists(legacyBackupPath)))
      ) {
        await fs.mkdir(path.dirname(legacyBackupPath), { recursive: true });
        await fs.copyFile(legacyTargetPath, legacyBackupPath);
      }
      await fs.rm(legacyTargetPath, { force: true });
      await removeEmptyParents(legacyTargetPath, gameRoot);
    }

    for (const entry of obsoleteEntries) {
      const entryKey = entry.relativePath.toLowerCase();
      const targetPath = resolveInside(gameRoot, entry.relativePath);
      if (entry.action === 'created') {
        await fs.rm(targetPath, { force: true });
        await removeEmptyParents(targetPath, gameRoot);
      }
      else if (entry.action === 'replaced') {
        const backupPath = resolveInside(backupRoot, entry.relativePath);
        await fs.mkdir(path.dirname(targetPath), { recursive: true });
        await fs.copyFile(backupPath, targetPath);
        await fs.rm(backupPath, { force: true });
        await removeEmptyParents(backupPath, backupRoot);
      }
      await fs.rm(resolveInside(updateBackupRoot, entry.relativePath), { force: true });
      entriesByPath.delete(entryKey);
    }

    for (const relativePath of filesToCopy) {
      const targetPath = resolveInside(gameRoot, relativePath);
      const existingEntry = existingManifest?.entries.find(
        (entry) => entry.relativePath.toLowerCase() === relativePath.toLowerCase()
      );
      if (!existingEntry || existingEntry.action === 'preserved') {
        const backupPath = resolveInside(backupRoot, relativePath);
        if (await fileExists(targetPath)) {
          await fs.mkdir(path.dirname(backupPath), { recursive: true });
          await fs.copyFile(targetPath, backupPath);
        }
      }
      else if (relativePath.toLowerCase().endsWith('.dll') && await fileExists(targetPath)) {
        const updateBackupPath = resolveInside(updateBackupRoot, relativePath);
        await fs.mkdir(path.dirname(updateBackupPath), { recursive: true });
        await fs.copyFile(targetPath, updateBackupPath);
      }

      const sourcePath = resolveInside(payloadRoot, relativePath);
      await fs.mkdir(path.dirname(targetPath), { recursive: true });
      await fs.copyFile(sourcePath, targetPath);
    }

    manifest.entries = [...entriesByPath.values()].sort((left, right) =>
      left.relativePath.localeCompare(right.relativePath)
    );
    await writeManifest(gameRoot, manifest);
    await transaction.commit();
  }
  catch (error) {
    try {
      await transaction.rollback();
    }
    catch (rollbackError) {
      const originalMessage = error instanceof Error ? error.message : String(error);
      const rollbackMessage = rollbackError instanceof Error ? rollbackError.message : String(rollbackError);
      throw new Error(`载荷安装失败：${originalMessage}；${rollbackMessage}`);
    }
    const message = error instanceof Error ? error.message : String(error);
    throw new Error(`载荷安装失败，已回滚至安装前状态；恢复备份保留在 ${transaction.directory}。${message}`);
  }
}

export interface PayloadUninstallResult {
  usedManifest: boolean;
}

export async function uninstallOwnedPayload(
  gameRoot: string,
  payloadRoot: string
): Promise<PayloadUninstallResult> {
  const manifest = await readManifest(gameRoot);
  if (!manifest) {
    const legacyOwnedFiles = (await listFiles(payloadRoot)).filter(isLegacyProjectOwnedPath);
    for (const relativePath of legacyOwnedFiles) {
      const targetPath = resolveInside(gameRoot, relativePath);
      await fs.rm(targetPath, { force: true });
      await removeEmptyParents(targetPath, gameRoot);
    }
    return { usedManifest: false };
  }

  const { stateRoot, backupRoot } = manifestPaths(gameRoot);
  for (const entry of manifest.entries) {
    if (entry.action !== 'replaced') {
      continue;
    }
    const backupPath = resolveInside(backupRoot, entry.relativePath);
    if (!(await fileExists(backupPath))) {
      throw new Error(`无法安全卸载：缺少原文件备份 ${entry.relativePath}`);
    }
  }

  for (const entry of [...manifest.entries].reverse()) {
    const targetPath = resolveInside(gameRoot, entry.relativePath);
    if (entry.action === 'created') {
      await fs.rm(targetPath, { force: true });
      await removeEmptyParents(targetPath, gameRoot);
    }
    else if (entry.action === 'replaced') {
      const backupPath = resolveInside(backupRoot, entry.relativePath);
      await fs.mkdir(path.dirname(targetPath), { recursive: true });
      await fs.copyFile(backupPath, targetPath);
    }
  }

  await fs.rm(stateRoot, { recursive: true, force: true });
  return { usedManifest: true };
}
