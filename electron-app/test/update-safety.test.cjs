const assert = require('node:assert/strict');
const childProcess = require('node:child_process');
const crypto = require('node:crypto');
const { EventEmitter } = require('node:events');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');
const AdmZip = require('adm-zip');

const {
  checkGitHubRelease,
  downloadBuffer,
  extractFilteredZip,
  launchUpdaterApp,
  stageGitHubUpdate
} = require('../dist/main/shared/updates.js');

function sha256(buffer) {
  return crypto.createHash('sha256').update(buffer).digest('hex');
}

function replaceAllAscii(buffer, from, to) {
  assert.equal(Buffer.byteLength(from), Buffer.byteLength(to));
  let offset = 0;
  let replacements = 0;

  while ((offset = buffer.indexOf(from, offset, 'ascii')) >= 0) {
    buffer.write(to, offset, 'ascii');
    offset += Buffer.byteLength(to);
    replacements += 1;
  }

  assert.equal(replacements, 2, 'expected local and central ZIP entry names');
}

function makeTraversalZip(entryLeaf) {
  const safeName = `aa/${entryLeaf}`;
  const traversalName = `../${entryLeaf}`;
  const zip = new AdmZip();
  zip.addFile(safeName, Buffer.from('escape attempt'));
  const buffer = zip.toBuffer();
  replaceAllAscii(buffer, safeName, traversalName);
  return buffer;
}

function makeOversizedDeclaredZip() {
  const zip = new AdmZip();
  zip.addFile('payload.bin', Buffer.from('small payload'));
  const buffer = zip.toBuffer();
  const declaredSize = 1024 * 1024 * 1024 + 1;
  const localHeader = buffer.indexOf(Buffer.from([0x50, 0x4b, 0x03, 0x04]));
  const centralHeader = buffer.indexOf(Buffer.from([0x50, 0x4b, 0x01, 0x02]));
  assert.notEqual(localHeader, -1);
  assert.notEqual(centralHeader, -1);
  buffer.writeUInt32LE(declaredSize, localHeader + 22);
  buffer.writeUInt32LE(declaredSize, centralHeader + 24);
  return buffer;
}

async function stageDirectoryNames(prefix) {
  const stageBase = path.join(os.tmpdir(), 'longyin-plus-update');
  const names = await fs.readdir(stageBase).catch(() => []);
  return names.filter((name) => name.startsWith(prefix)).sort();
}

test('download rejects declared and streamed payloads above the byte limit', async (t) => {
  const originalFetch = global.fetch;
  t.after(() => { global.fetch = originalFetch; });

  global.fetch = async () => new Response(Buffer.from('12345'), {
    status: 200,
    headers: { 'content-length': '5' }
  });
  await assert.rejects(
    downloadBuffer('https://example.invalid/declared', undefined, 4, 1_000),
    /超过允许大小/
  );

  global.fetch = async () => new Response(new ReadableStream({
    start(controller) {
      controller.enqueue(Uint8Array.from([1, 2, 3]));
      controller.enqueue(Uint8Array.from([4, 5, 6]));
      controller.close();
    }
  }), { status: 200 });
  await assert.rejects(
    downloadBuffer('https://example.invalid/streamed', undefined, 4, 1_000),
    /超过允许大小/
  );
});

test('download timeout aborts the request with an actionable error', async (t) => {
  const originalFetch = global.fetch;
  t.after(() => { global.fetch = originalFetch; });

  global.fetch = async (_url, options) => new Promise((_resolve, reject) => {
    options.signal.addEventListener('abort', () => {
      const error = new Error('aborted');
      error.name = 'AbortError';
      reject(error);
    }, { once: true });
  });

  await assert.rejects(
    downloadBuffer('https://example.invalid/timeout', undefined, 1024, 10),
    /下载超时/
  );
});

test('release check rejects a manifest whose ZIP has no direct release asset URL', async (t) => {
  const originalFetch = global.fetch;
  t.after(() => { global.fetch = originalFetch; });
  const requestedUrls = [];
  const responses = [
    {
      tag_name: 'v9.9.9',
      name: 'v9.9.9',
      assets: [
        {
          name: 'update-manifest.json',
          browser_download_url: 'https://example.invalid/update-manifest.json'
        }
      ]
    },
    {
      version: '9.9.9',
      zipAsset: 'missing.zip',
      sha256: '0'.repeat(64)
    }
  ];
  global.fetch = async (url) => {
    requestedUrls.push(String(url));
    return new Response(JSON.stringify(responses.shift()), {
      status: 200,
      headers: { 'content-type': 'application/json' }
    });
  };

  await assert.rejects(checkGitHubRelease('0.1.0'), /未提供有效下载资产/);
  assert.equal(requestedUrls[0], 'https://api.github.com/repos/Herbert-Zheng/longyin-pro-max/releases/latest');
});

test('staging requires the direct URL returned by the Release asset', async () => {
  await assert.rejects(
    stageGitHubUpdate({
      version: '1.0.0',
      zipAsset: 'release.zip',
      sha256: '0'.repeat(64)
    }, ''),
    /直接下载 URL/
  );
});

test('ZIP traversal is rejected and the partially-created stage is removed', async (t) => {
  const originalFetch = global.fetch;
  t.after(() => { global.fetch = originalFetch; });

  const unique = `${Date.now()}-${crypto.randomUUID()}`;
  const entryLeaf = `escape-${unique}.exe`;
  const zipBuffer = makeTraversalZip(entryLeaf);
  const version = `traversal-${unique}`;
  const prefix = `${version}-`;
  const before = await stageDirectoryNames(prefix);
  global.fetch = async () => new Response(zipBuffer, {
    status: 200,
    headers: { 'content-length': String(zipBuffer.length) }
  });

  await assert.rejects(
    stageGitHubUpdate({
      version,
      zipAsset: 'malicious.zip',
      sha256: sha256(zipBuffer)
    }, 'https://example.invalid/malicious.zip'),
    /越界路径/
  );

  assert.deepEqual(await stageDirectoryNames(prefix), before);
  assert.equal(
    await fs.stat(path.join(os.tmpdir(), 'longyin-plus-update', entryLeaf)).then(() => true).catch(() => false),
    false
  );
});

test('declared or actual expanded ZIP size above the limit is rejected', async (t) => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'longyin-update-size-test-'));
  t.after(() => fs.rm(root, { recursive: true, force: true }));

  const ordinaryZip = new AdmZip();
  ordinaryZip.addFile('payload.bin', Buffer.from('12345'));
  const ordinaryZipPath = path.join(root, 'ordinary.zip');
  await fs.writeFile(ordinaryZipPath, ordinaryZip.toBuffer());
  await assert.rejects(
    extractFilteredZip(ordinaryZipPath, path.join(root, 'actual-stage'), [], 4),
    /解压大小超过限制/
  );

  const originalFetch = global.fetch;
  t.after(() => { global.fetch = originalFetch; });
  const oversizedZip = makeOversizedDeclaredZip();
  const version = `oversized-${Date.now()}-${crypto.randomUUID()}`;
  const prefix = `${version}-`;
  const before = await stageDirectoryNames(prefix);
  global.fetch = async () => new Response(oversizedZip, {
    status: 200,
    headers: { 'content-length': String(oversizedZip.length) }
  });

  await assert.rejects(
    stageGitHubUpdate({
      version,
      zipAsset: 'oversized.zip',
      sha256: sha256(oversizedZip)
    }, 'https://example.invalid/oversized.zip'),
    /声明的解压大小超过限制/
  );
  assert.deepEqual(await stageDirectoryNames(prefix), before);
});

test('updater launch rejects a child error instead of allowing the main app to exit', async (t) => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'longyin-updater-spawn-test-'));
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  const updaterPath = path.join(root, 'LongYinUpdater.exe');
  await fs.writeFile(updaterPath, 'fake updater');

  const originalSpawn = childProcess.spawn;
  childProcess.spawn = () => {
    const child = new EventEmitter();
    child.unref = () => undefined;
    process.nextTick(() => child.emit('error', new Error('injected updater spawn failure')));
    return child;
  };
  try {
    await assert.rejects(
      launchUpdaterApp(updaterPath, process.pid, root, root, 'LongYinProMax.exe', path.join(root, 'ota.log'), 'test'),
      /injected updater spawn failure/
    );
  }
  finally {
    childProcess.spawn = originalSpawn;
  }
});
