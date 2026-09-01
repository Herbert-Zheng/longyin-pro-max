import { promises as fs } from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import crypto from 'node:crypto';
import { spawn } from 'node:child_process';
import AdmZip from 'adm-zip';
import { RELEASE_MANIFEST_NAME, ReleaseHistoryItem, UpdateCheckResult, UpdateManifest } from './types';

const GITHUB_OWNER = 'Herbert-Zheng';
const GITHUB_REPO = 'longyin-pro-max';
const DEFAULT_PRESERVE_PATHS = ['user-data/**', 'BepInEx/config/**'];
const JSON_DOWNLOAD_LIMIT_BYTES = 2 * 1024 * 1024;
const UPDATE_DOWNLOAD_LIMIT_BYTES = 512 * 1024 * 1024;
const UPDATE_EXPANDED_LIMIT_BYTES = 1024 * 1024 * 1024;
const JSON_DOWNLOAD_TIMEOUT_MS = 30_000;
const UPDATE_DOWNLOAD_TIMEOUT_MS = 5 * 60_000;

function compareVersionParts(left: string, right: string): number {
  const leftParts = left.split('.').map((value) => Number.parseInt(value, 10) || 0);
  const rightParts = right.split('.').map((value) => Number.parseInt(value, 10) || 0);
  const length = Math.max(leftParts.length, rightParts.length);

  for (let index = 0; index < length; index += 1) {
    const diff = (leftParts[index] ?? 0) - (rightParts[index] ?? 0);
    if (diff !== 0) {
      return diff;
    }
  }

  return 0;
}

function matchesPattern(value: string, pattern: string): boolean {
  const normalizedValue = value.replace(/\\/g, '/').toLowerCase();
  const normalizedPattern = pattern.replace(/\\/g, '/').toLowerCase();

  if (normalizedPattern === '**') {
    return true;
  }

  if (!normalizedPattern.includes('*')) {
    return normalizedValue === normalizedPattern;
  }

  const escaped = normalizedPattern
    .replace(/[.+^${}()|[\]\\]/g, '\\$&')
    .replace(/\*\*/g, '::DOUBLESTAR::')
    .replace(/\*/g, '[^/]*')
    .replace(/::DOUBLESTAR::/g, '.*');
  return new RegExp(`^${escaped}$`, 'i').test(normalizedValue);
}

async function fileExists(filePath: string): Promise<boolean> {
  try {
    const stat = await fs.stat(filePath);
    return stat.isFile();
  }
  catch {
    return false;
  }
}

async function directoryExists(dirPath: string): Promise<boolean> {
  try {
    const stat = await fs.stat(dirPath);
    return stat.isDirectory();
  }
  catch {
    return false;
  }
}

async function downloadJson(url: string): Promise<any> {
  const buffer = await downloadBuffer(
    url,
    undefined,
    JSON_DOWNLOAD_LIMIT_BYTES,
    JSON_DOWNLOAD_TIMEOUT_MS,
    'application/vnd.github+json'
  );
  return JSON.parse(buffer.toString('utf8'));
}

function formatBytes(bytes: number): string {
  if (!Number.isFinite(bytes) || bytes <= 0) {
    return '0 B';
  }

  const units = ['B', 'KB', 'MB', 'GB'];
  let value = bytes;
  let unitIndex = 0;

  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex += 1;
  }

  const digits = value >= 100 || unitIndex === 0 ? 0 : value >= 10 ? 1 : 2;
  return `${value.toFixed(digits)} ${units[unitIndex]}`;
}

function normalizeRelease(releaseJson: any, isLatest: boolean): ReleaseHistoryItem {
  const version = String(releaseJson.tag_name ?? releaseJson.name ?? '').replace(/^v/i, '').trim();

  return {
    tagName: String(releaseJson.tag_name ?? ''),
    version,
    name: String(releaseJson.name ?? releaseJson.tag_name ?? version ?? '未命名版本'),
    publishedAt: releaseJson.published_at ? String(releaseJson.published_at) : undefined,
    body: String(releaseJson.body ?? '').trim(),
    htmlUrl: releaseJson.html_url ? String(releaseJson.html_url) : undefined,
    isLatest
  };
}

export async function downloadBuffer(
  url: string,
  onProgress?: (detail: string, percent?: number) => void,
  maxBytes = UPDATE_DOWNLOAD_LIMIT_BYTES,
  timeoutMs = UPDATE_DOWNLOAD_TIMEOUT_MS,
  accept = 'application/octet-stream'
): Promise<Buffer> {
  const abortController = new AbortController();
  const timeout = setTimeout(() => abortController.abort(), timeoutMs);

  try {
    const response = await fetch(url, {
      headers: {
        Accept: accept,
        'X-GitHub-Api-Version': '2022-11-28',
        'User-Agent': 'LongYinProMax-Electron'
      },
      signal: abortController.signal
    });

    if (!response.ok) {
      throw new Error(`下载失败 ${url}：${response.status} ${response.statusText}`);
    }

    const contentLength = Number.parseInt(response.headers.get('content-length') ?? '', 10);
    const totalBytes = Number.isFinite(contentLength) && contentLength > 0 ? contentLength : undefined;
    if (totalBytes && totalBytes > maxBytes) {
      throw new Error(`下载资源超过允许大小：${formatBytes(totalBytes)} > ${formatBytes(maxBytes)}。`);
    }

    if (!response.body) {
      const bytes = new Uint8Array(await response.arrayBuffer());
      if (bytes.byteLength > maxBytes) {
        throw new Error(`下载资源超过允许大小：${formatBytes(bytes.byteLength)} > ${formatBytes(maxBytes)}。`);
      }

      onProgress?.(`更新包下载完成，大小 ${formatBytes(bytes.byteLength)}。`, 100);
      return Buffer.from(bytes);
    }

    const reader = response.body.getReader();
    const chunks: Buffer[] = [];
    let receivedBytes = 0;
    let lastPercent = -1;

    while (true) {
      const { done, value } = await reader.read();
      if (done) {
        break;
      }

      if (!value || value.byteLength === 0) {
        continue;
      }

      const chunk = Buffer.from(value);
      chunks.push(chunk);
      receivedBytes += chunk.length;
      if (receivedBytes > maxBytes) {
        await reader.cancel();
        throw new Error(`下载资源超过允许大小：${formatBytes(receivedBytes)} > ${formatBytes(maxBytes)}。`);
      }

      if (totalBytes) {
        const percent = Math.max(1, Math.min(99, Math.round((receivedBytes / totalBytes) * 100)));
        if (percent !== lastPercent) {
          lastPercent = percent;
          onProgress?.(
            `正在下载更新包：${formatBytes(receivedBytes)} / ${formatBytes(totalBytes)}`,
            percent
          );
        }
      }
      else {
        onProgress?.(`正在下载更新包：已接收 ${formatBytes(receivedBytes)}`);
      }
    }

    const buffer = Buffer.concat(chunks);
    onProgress?.(`更新包下载完成，大小 ${formatBytes(buffer.length)}。`, 100);
    return buffer;
  }
  catch (error) {
    if (error instanceof Error && error.name === 'AbortError') {
      throw new Error(`下载超时：${url}`);
    }
    throw error;
  }
  finally {
    clearTimeout(timeout);
  }
}

async function writeBuffer(filePath: string, buffer: Buffer): Promise<void> {
  await fs.mkdir(path.dirname(filePath), { recursive: true });
  await fs.writeFile(filePath, buffer);
}

function sha256(buffer: Buffer): string {
  return crypto.createHash('sha256').update(buffer).digest('hex');
}

export async function extractFilteredZip(
  zipPath: string,
  stageRoot: string,
  preservePaths: string[],
  maxExpandedBytes = UPDATE_EXPANDED_LIMIT_BYTES
): Promise<void> {
  await fs.mkdir(stageRoot, { recursive: true });
  const zip = new AdmZip(zipPath);
  const entries = zip.getEntries();
  const resolvedStageRoot = path.resolve(stageRoot);
  const stagePrefix = `${resolvedStageRoot}${path.sep}`;
  let expandedBytes = 0;

  for (const entry of entries) {
    const entryName = entry.entryName.replace(/\\/g, '/');
    if (preservePaths.some((pattern) => matchesPattern(entryName, pattern))) {
      continue;
    }

    const targetPath = path.resolve(resolvedStageRoot, entryName);
    if (targetPath !== resolvedStageRoot && !targetPath.startsWith(stagePrefix)) {
      throw new Error(`更新包包含越界路径：${entry.entryName}`);
    }

    if (entry.isDirectory) {
      await fs.mkdir(targetPath, { recursive: true });
      continue;
    }

    const declaredSize = Number(entry.header.size) || 0;
    if (expandedBytes + declaredSize > maxExpandedBytes) {
      throw new Error(`更新包声明的解压大小超过限制：${formatBytes(expandedBytes + declaredSize)}。`);
    }

    const entryData = entry.getData();
    expandedBytes += entryData.length;
    if (expandedBytes > maxExpandedBytes) {
      throw new Error(`更新包实际解压大小超过限制：${formatBytes(expandedBytes)}。`);
    }
    await fs.mkdir(path.dirname(targetPath), { recursive: true });
    await fs.writeFile(targetPath, entryData);
  }
}

export async function checkGitHubRelease(currentVersion: string): Promise<UpdateCheckResult> {
  const releaseJson = await downloadJson(`https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPO}/releases/latest`);
  const normalizedRelease = normalizeRelease(releaseJson, true);
  const latestVersion = String(releaseJson.tag_name ?? releaseJson.name ?? '').replace(/^v/i, '').trim();
  const updateAvailable = Boolean(latestVersion) && compareVersionParts(latestVersion, currentVersion) > 0;
  const assets = Array.isArray(releaseJson.assets) ? releaseJson.assets : [];
  const manifestAsset = assets.find((asset: any) => asset.name === RELEASE_MANIFEST_NAME);

  if (!manifestAsset) {
    return {
      currentVersion,
      latestVersion: latestVersion || currentVersion,
      updateAvailable: false,
      releaseName: normalizedRelease.name,
      publishedAt: normalizedRelease.publishedAt,
      releaseBody: normalizedRelease.body,
      releaseUrl: normalizedRelease.htmlUrl,
      status: `最新发布中未包含 ${RELEASE_MANIFEST_NAME} 资源。`
    };
  }

  const manifestResponse = await downloadBuffer(manifestAsset.browser_download_url);
  const manifest = JSON.parse(manifestResponse.toString('utf8')) as UpdateManifest;
  const zipAsset = assets.find((asset: any) => asset.name === manifest.zipAsset);
  const assetUrl = typeof zipAsset?.browser_download_url === 'string'
    ? zipAsset.browser_download_url.trim()
    : '';
  if (!zipAsset || !assetUrl) {
    throw new Error(`Release 清单引用了 ${manifest.zipAsset}，但该 Release 未提供有效下载资产。`);
  }

  return {
    currentVersion,
    latestVersion: manifest.version || latestVersion || currentVersion,
    updateAvailable: updateAvailable && compareVersionParts(manifest.version, currentVersion) > 0,
    releaseName: normalizedRelease.name,
    publishedAt: normalizedRelease.publishedAt,
    releaseBody: normalizedRelease.body,
    releaseUrl: normalizedRelease.htmlUrl,
    manifest,
    asset: zipAsset,
    assetUrl,
    status: updateAvailable ? '发现了新版本。' : '当前已经是最新版本。'
  };
}

export async function fetchReleaseHistory(limit = 8): Promise<ReleaseHistoryItem[]> {
  const releasesJson = await downloadJson(
    `https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPO}/releases?per_page=${Math.max(1, Math.min(limit, 20))}`
  );

  if (!Array.isArray(releasesJson)) {
    return [];
  }

  return releasesJson
    .filter((release: any) => !release.draft)
    .map((release: any, index: number) => normalizeRelease(release, index === 0));
}

export async function stageGitHubUpdate(
  manifest: UpdateManifest,
  assetUrl: string,
  onProgress?: (detail: string, percent?: number) => void
): Promise<{ stageRoot: string; manifest: UpdateManifest }> {
  const progress = onProgress;
  progress?.(`开始下载 ${manifest.zipAsset} ...`, 0);
  const downloadUrl = assetUrl.trim();
  if (!downloadUrl) {
    throw new Error(`Release 未提供 ${manifest.zipAsset} 的直接下载 URL。`);
  }
  const zipBuffer = await downloadBuffer(
    downloadUrl,
    progress
  );

  progress?.('下载完成，正在校验更新包完整性...', 100);
  if (sha256(zipBuffer) !== manifest.sha256) {
    throw new Error('下载的更新包未通过 SHA-256 校验。');
  }

  const stageBaseRoot = path.join(os.tmpdir(), 'longyin-plus-update');
  await fs.mkdir(stageBaseRoot, { recursive: true });
  const stageRoot = await fs.mkdtemp(path.join(stageBaseRoot, `${manifest.version}-`));
  const zipPath = path.join(stageRoot, manifest.zipAsset);
  progress?.('校验通过，正在准备暂存目录...', 100);
  try {
    await writeBuffer(zipPath, zipBuffer);
    progress?.('正在解压更新包并准备替换文件...', 100);
    await extractFilteredZip(zipPath, stageRoot, manifest.preservePaths ?? DEFAULT_PRESERVE_PATHS);
    await fs.rm(zipPath, { force: true });
  }
  catch (error) {
    await fs.rm(stageRoot, { recursive: true, force: true });
    throw error;
  }
  progress?.('更新文件已准备完成，正在启动后台替换程序...', 100);
  return { stageRoot, manifest };
}

export async function prepareUpdaterBinary(updaterBinaryPath: string): Promise<string> {
  if (!(await fileExists(updaterBinaryPath))) {
    throw new Error(`未找到 OTA 更新器：${updaterBinaryPath}`);
  }

  const helperRoot = path.join(os.tmpdir(), 'longyin-plus-update', 'helpers');
  await fs.mkdir(helperRoot, { recursive: true });
  const runRoot = await fs.mkdtemp(path.join(helperRoot, 'run-'));
  const helperPath = path.join(runRoot, path.basename(updaterBinaryPath));
  await fs.copyFile(updaterBinaryPath, helperPath);
  return helperPath;
}

export async function launchUpdaterApp(
  updaterBinaryPath: string,
  waitPid: number,
  stageRoot: string,
  targetRoot: string,
  appExecutableName: string,
  logPath: string,
  version: string
): Promise<void> {
  const helperBinaryPath = await prepareUpdaterBinary(updaterBinaryPath);

  const child = spawn(helperBinaryPath, [
    '--wait-pid',
    String(waitPid),
    '--source',
    stageRoot,
    '--target',
    targetRoot,
    '--exe',
    appExecutableName,
    '--log',
    logPath,
    '--version',
    version
  ], {
    detached: true,
    stdio: 'ignore',
    windowsHide: false
  });
  await new Promise<void>((resolve, reject) => {
    child.once('spawn', resolve);
    child.once('error', reject);
  });
  child.unref();
}

export async function releaseStageExists(stageRoot: string): Promise<boolean> {
  return directoryExists(stageRoot);
}
