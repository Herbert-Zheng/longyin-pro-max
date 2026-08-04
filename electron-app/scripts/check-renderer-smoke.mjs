import { spawn, spawnSync } from 'node:child_process';
import { mkdtemp, rm } from 'node:fs/promises';
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptsDir = path.dirname(fileURLToPath(import.meta.url));
const appRoot = path.resolve(scriptsDir, '..');
const electronExe = path.join(appRoot, 'node_modules', 'electron', 'dist', 'electron.exe');

function reservePort() {
  return new Promise((resolve, reject) => {
    const server = net.createServer();
    server.once('error', reject);
    server.listen(0, '127.0.0.1', () => {
      const address = server.address();
      const port = typeof address === 'object' && address ? address.port : undefined;
      server.close((error) => (error ? reject(error) : resolve(port)));
    });
  });
}

function wait(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

async function waitForRendererTarget(port, timeoutMs = 10_000) {
  const deadline = Date.now() + timeoutMs;
  let lastError;
  while (Date.now() < deadline) {
    try {
      const response = await fetch(`http://127.0.0.1:${port}/json`);
      const targets = await response.json();
      const renderer = targets.find(
        (target) =>
          target.type === 'page' &&
          typeof target.url === 'string' &&
          target.url.includes('/dist/renderer/index.html')
      );
      if (renderer?.webSocketDebuggerUrl) {
        return renderer;
      }
    } catch (error) {
      lastError = error;
    }
    await wait(100);
  }
  throw new Error(`Renderer CDP target was not available within ${timeoutMs} ms.`, {
    cause: lastError
  });
}

function connectCdp(webSocketUrl) {
  return new Promise((resolve, reject) => {
    const socket = new WebSocket(webSocketUrl);
    const pending = new Map();
    const events = [];
    let nextId = 1;

    socket.addEventListener('open', () => {
      resolve({
        events,
        async send(method, params = {}) {
          const id = nextId++;
          const result = new Promise((resolveResult, rejectResult) => {
            pending.set(id, { resolve: resolveResult, reject: rejectResult });
          });
          socket.send(JSON.stringify({ id, method, params }));
          return result;
        },
        close() {
          socket.close();
        }
      });
    });
    socket.addEventListener('error', reject);
    socket.addEventListener('message', (message) => {
      const payload = JSON.parse(String(message.data));
      if (payload.id) {
        const callback = pending.get(payload.id);
        pending.delete(payload.id);
        if (payload.error) {
          callback?.reject(new Error(`${payload.error.message} (${payload.error.code})`));
        } else {
          callback?.resolve(payload.result);
        }
        return;
      }
      events.push(payload);
    });
  });
}

function isRendererError(event) {
  return (
    event.method === 'Runtime.exceptionThrown' ||
    (event.method === 'Runtime.consoleAPICalled' && event.params?.type === 'error') ||
    (event.method === 'Log.entryAdded' && event.params?.entry?.level === 'error')
  );
}

export function assertRendererHealthy(snapshot, events) {
  const rendererErrors = events.filter(isRendererError);
  if (rendererErrors.length > 0) {
    throw new Error(`Electron renderer reported ${rendererErrors.length} runtime error(s).`);
  }
  if (!snapshot?.appShellPresent || snapshot.bootSplashPresent) {
    throw new Error('Electron renderer did not replace the boot splash with the ready React application.');
  }
}

async function readRendererSnapshot(cdp) {
  const evaluation = await cdp.send('Runtime.evaluate', {
    expression: `({
      readyState: document.readyState,
      title: document.title,
      bodyText: document.body?.innerText?.trim() ?? '',
      rootChildCount: document.getElementById('root')?.childElementCount ?? -1,
      rootHtml: document.getElementById('root')?.innerHTML?.slice(0, 500) ?? '',
      appShellPresent: document.querySelector('.app-shell, .shell:not(.shell--loading)') !== null,
      bootSplashPresent: document.querySelector('.boot-splash') !== null
    })`,
    returnByValue: true
  });
  return evaluation.result?.value;
}

async function waitForReactApplication(cdp, timeoutMs = 15_000) {
  const deadline = Date.now() + timeoutMs;
  let snapshot;
  while (Date.now() < deadline) {
    snapshot = await readRendererSnapshot(cdp);
    const rendererErrors = cdp.events.filter(isRendererError);
    if (rendererErrors.length > 0 || (snapshot?.appShellPresent && !snapshot.bootSplashPresent)) {
      assertRendererHealthy(snapshot, cdp.events);
      return snapshot;
    }
    await wait(100);
  }
  assertRendererHealthy(snapshot, cdp.events);
}

async function runSmoke() {
  const useExistingProfile = process.argv.includes('--existing-profile');
  const userDataDir = useExistingProfile
    ? undefined
    : await mkdtemp(path.join(os.tmpdir(), 'longyin-renderer-smoke-'));
  const port = await reservePort();
  const child = spawn(
    electronExe,
    [
      `--remote-debugging-port=${port}`,
      ...(userDataDir ? [`--user-data-dir=${userDataDir}`] : []),
      appRoot
    ],
    {
      cwd: appRoot,
      env: {
        ...process.env,
        ...(userDataDir ? { LONGYIN_USER_DATA_ROOT: userDataDir } : {}),
        ELECTRON_DISABLE_SECURITY_WARNINGS: 'true'
      },
      stdio: ['ignore', 'pipe', 'pipe'],
      windowsHide: true
    }
  );

  let stdout = '';
  let stderr = '';
  child.stdout.setEncoding('utf8');
  child.stderr.setEncoding('utf8');
  child.stdout.on('data', (chunk) => {
    stdout += chunk;
  });
  child.stderr.on('data', (chunk) => {
    stderr += chunk;
  });

  let cdp;
  try {
    const target = await waitForRendererTarget(port);
    cdp = await connectCdp(target.webSocketDebuggerUrl);
    await cdp.send('Runtime.enable');
    await cdp.send('Log.enable');
    const snapshot = await waitForReactApplication(cdp);
    await wait(250);
    assertRendererHealthy(snapshot, cdp.events);

    const rendererErrors = cdp.events.filter(isRendererError).map((event) => event.params);
    console.log(
      JSON.stringify(
        {
          target: { title: target.title, url: target.url },
          snapshot,
          rendererErrors,
          stdout: stdout.trim(),
          stderr: stderr.trim(),
          isolatedUserData: Boolean(userDataDir)
        },
        null,
        2
      )
    );
  } finally {
    cdp?.close();
    if (child.pid) {
      spawnSync('taskkill.exe', ['/PID', String(child.pid), '/T', '/F'], {
        stdio: 'ignore',
        windowsHide: true
      });
    }
    if (userDataDir) {
      await rm(userDataDir, { recursive: true, force: true, maxRetries: 8, retryDelay: 250 });
    }
  }

  console.log('Electron renderer smoke check passed.');
}

const isEntryPoint = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isEntryPoint) {
  await runSmoke();
}
