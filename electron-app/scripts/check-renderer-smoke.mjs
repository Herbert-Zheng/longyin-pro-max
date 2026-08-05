import { spawn, spawnSync } from 'node:child_process';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
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

export function assertRendererUiContracts(snapshot) {
  if (Math.abs((snapshot?.heroSummaryGap ?? 0) - 12) > 1) {
    throw new Error(`Hero to summary spacing must remain 12px (received ${snapshot?.heroSummaryGap ?? 'missing'}px).`);
  }
  if (Math.abs((snapshot?.summaryStatusGap ?? 0) - 12) > 1) {
    throw new Error(`Summary to status spacing must remain 12px (received ${snapshot?.summaryStatusGap ?? 'missing'}px).`);
  }
  if (!snapshot?.systems?.environmentFullWidth) {
    throw new Error(`Systems environment card must span the full grid width (${snapshot?.systems?.gridWidth ?? 'missing'}px grid, ${snapshot?.systems?.environmentWidth ?? 'missing'}px card).`);
  }
  if (!snapshot.systems.healthCollapsed) {
    throw new Error('Systems health details must be collapsed by default.');
  }
  if (!snapshot.systems.healthSummaryText?.includes('健康检查详情')) {
    throw new Error('Systems health summary must clearly identify the collapsed details.');
  }
  if (!snapshot.systems.overlayExplained) {
    throw new Error('Overlay card must explain the feature in player-facing Chinese.');
  }
  if (snapshot.systems.controlHeightSpread > 1) {
    throw new Error(`Systems control tiles must have aligned heights (${snapshot.systems.controlHeights?.join(', ') ?? 'missing'}px).`);
  }
  if (snapshot.systems.controlCount !== 3) {
    throw new Error(`Systems time-control card must expose all 3 setting tiles (received ${snapshot.systems.controlCount ?? 'missing'}).`);
  }
  for (const page of snapshot.settingsPages ?? []) {
    if (!page.gridPresent || page.cardCount < 1 || page.tileCount < 1) {
      throw new Error(`${page.label} settings contract cannot be measured because its grid, cards, or tiles are missing.`);
    }
    if (!page.cardsSelfAligned) {
      throw new Error(`${page.label} cards must opt out of grid stretching.`);
    }
    if (page.tileHeightSpread > 1) {
      throw new Error(`${page.label} field and toggle tiles must align within each row.`);
    }
  }
  if (snapshot.customTalents?.conditionOptionCount !== 2) {
    throw new Error(`Custom talent condition options must expose both supported Chinese choices (received ${snapshot.customTalents?.conditionOptionCount ?? 'missing'}).`);
  }
  if (!snapshot.customTalents?.intelligenceUsesRawValue || snapshot.customTalents?.intelligenceLabel !== '智力') {
    throw new Error('Custom talent attributes must display 智力 while preserving Inte as the saved value.');
  }
  if (snapshot.customTalents?.effectOptionCount !== 215) {
    throw new Error(`Custom talent effects must expose all 215 supported choices (received ${snapshot.customTalents?.effectOptionCount ?? 'missing'}).`);
  }
  if (snapshot.customTalents?.uniqueEffectLabelCount !== snapshot.customTalents?.effectOptionCount) {
    throw new Error('Every custom talent effect option must have a distinct visible Chinese label.');
  }
  if (!snapshot.customTalents?.allEffectLabelsChinese) {
    throw new Error('Every custom talent effect option must have a visible Chinese label.');
  }
}

async function clickNavigationItem(cdp, label) {
  const evaluation = await cdp.send('Runtime.evaluate', {
    expression: `(() => {
      const item = [...document.querySelectorAll('.nav-item')].find((node) => node.textContent?.includes(${JSON.stringify(label)}));
      if (!item) throw new Error('Navigation item not found: ' + ${JSON.stringify(label)});
      item.click();
    })()`
  });
  if (evaluation.exceptionDetails) {
    throw new Error(`Could not activate renderer navigation item: ${label}.`);
  }
  const deadline = Date.now() + 2_000;
  while (Date.now() < deadline) {
    const activeEvaluation = await cdp.send('Runtime.evaluate', {
      expression: `(() => [...document.querySelectorAll('.nav-item')].some((node) =>
        node.getAttribute('aria-current') === 'page' && node.textContent?.includes(${JSON.stringify(label)})))()`,
      returnByValue: true
    });
    if (activeEvaluation.result?.value === true) {
      return;
    }
    await wait(25);
  }
  throw new Error(`Renderer did not commit the requested navigation page: ${label}.`);
}

async function readSettingsPageContract(cdp, label) {
  await clickNavigationItem(cdp, label);
  const evaluation = await cdp.send('Runtime.evaluate', {
    expression: `(() => {
      const grid = document.querySelector('.page-grid--settings');
      const cards = [...(grid?.querySelectorAll(':scope > .card') ?? [])];
      const tiles = [...(grid?.querySelectorAll('.field, .toggle') ?? [])];
      const spreads = [];
      for (const fieldGrid of grid?.querySelectorAll('.field-grid') ?? []) {
        const rows = new Map();
        for (const tile of fieldGrid.querySelectorAll('.field, .toggle')) {
          const rect = tile.getBoundingClientRect();
          const rowKey = Math.round(rect.top);
          const heights = rows.get(rowKey) ?? [];
          heights.push(rect.height);
          rows.set(rowKey, heights);
        }
        spreads.push(...[...rows.values()].map((heights) => Math.max(...heights) - Math.min(...heights)));
      }
      return {
        label: ${JSON.stringify(label)},
        gridPresent: Boolean(grid),
        cardCount: cards.length,
        tileCount: tiles.length,
        cardsSelfAligned: cards.length > 0 && cards.every((card) => getComputedStyle(card).alignSelf === 'start'),
        tileHeightSpread: spreads.length ? Math.max(...spreads) : 0
      };
    })()`,
    returnByValue: true
  });
  return evaluation.result?.value;
}

async function readCustomTalentContract(cdp) {
  await clickNavigationItem(cdp, '自定义天赋');
  const createEvaluation = await cdp.send('Runtime.evaluate', {
    expression: `(() => {
      if (document.querySelector('.array-row select')) return false;
      const button = [...document.querySelectorAll('button')].find((node) => node.textContent?.trim() === '新建');
      if (!button || button.disabled) throw new Error('Custom talent editor could not create a temporary in-memory talent.');
      button.click();
      return true;
    })()`,
    returnByValue: true
  });
  if (createEvaluation.exceptionDetails) {
    throw new Error('Could not prepare the custom talent editor for option-label verification.');
  }
  const editorDeadline = Date.now() + 2_000;
  while (Date.now() < editorDeadline) {
    const readyEvaluation = await cdp.send('Runtime.evaluate', {
      expression: `document.querySelectorAll('.array-row select').length >= 3`,
      returnByValue: true
    });
    if (readyEvaluation.result?.value === true) {
      break;
    }
    await wait(25);
  }

  const evaluation = await cdp.send('Runtime.evaluate', {
    expression: `(() => {
      const findSelect = (label) => [...document.querySelectorAll('label.field')]
        .find((field) => field.querySelector('.field__label')?.textContent?.trim() === label)
        ?.querySelector('select');
      const conditionSelect = findSelect('类型');
      const attributeSelect = findSelect('属性');
      const effectSelect = findSelect('效果类型');
      const intelligence = [...(attributeSelect?.options ?? [])].find((option) => option.value === 'Inte');
      const effectLabels = [...(effectSelect?.options ?? [])].map((option) => option.textContent?.trim() ?? '');
      return {
        conditionOptionCount: conditionSelect?.options.length ?? -1,
        intelligenceUsesRawValue: intelligence?.value === 'Inte',
        intelligenceLabel: intelligence?.textContent?.trim() ?? '',
        effectOptionCount: effectSelect?.options.length ?? -1,
        uniqueEffectLabelCount: new Set(effectLabels).size,
        allEffectLabelsChinese: effectLabels.every((label) => /[\\u3400-\\u9fff]/.test(label))
      };
    })()`,
    returnByValue: true
  });
  if (evaluation.exceptionDetails) {
    throw new Error('Could not read custom talent option labels from the renderer.');
  }
  return evaluation.result?.value;
}

async function readRendererUiContracts(cdp) {
  const baseEvaluation = await cdp.send('Runtime.evaluate', {
    expression: `(() => {
      const hero = document.querySelector('.workspace__hero');
      const summary = document.querySelector('.summary-grid');
      const status = document.querySelector('.status-strip');
      const heroRect = hero?.getBoundingClientRect();
      const summaryRect = summary?.getBoundingClientRect();
      const statusRect = status?.getBoundingClientRect();
      return {
        heroSummaryGap: heroRect && summaryRect
          ? Math.round(summaryRect.top - heroRect.bottom)
          : -1,
        summaryStatusGap: summaryRect && statusRect
          ? Math.round(statusRect.top - summaryRect.bottom)
          : -1
      };
    })()`,
    returnByValue: true
  });

  await clickNavigationItem(cdp, '系统更改');
  const systemsEvaluation = await cdp.send('Runtime.evaluate', {
    expression: `(() => {
      const grid = document.querySelector('.page-grid--systems');
      const environment = document.querySelector('.system-environment-card');
      const details = document.querySelector('.health-details');
      const controlTiles = [...(grid?.querySelector('.card .field-grid')?.querySelectorAll('.field, .toggle') ?? [])];
      const heights = controlTiles.map((tile) => tile.getBoundingClientRect().height);
      return {
        environmentFullWidth: Boolean(grid && environment && Math.abs(grid.getBoundingClientRect().width - environment.getBoundingClientRect().width) <= 1),
        gridWidth: grid?.getBoundingClientRect().width ?? -1,
        environmentWidth: environment?.getBoundingClientRect().width ?? -1,
        healthCollapsed: Boolean(details && !details.open),
        healthSummaryText: details?.querySelector('summary')?.textContent?.trim() ?? '',
        overlayExplained: document.body.innerText.includes('无需切回启动器'),
        controlCount: heights.length,
        controlHeights: heights,
        controlHeightSpread: heights.length ? Math.max(...heights) - Math.min(...heights) : 0
      };
    })()`,
    returnByValue: true
  });

  const settingsPages = [];
  for (const label of ['成长与天赋', '交易与制造', '社交与组队']) {
    settingsPages.push(await readSettingsPageContract(cdp, label));
  }
  const customTalents = await readCustomTalentContract(cdp);
  return {
    ...baseEvaluation.result?.value,
    systems: systemsEvaluation.result?.value,
    settingsPages,
    customTalents
  };
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
  const fakeGameRoot = useExistingProfile
    ? undefined
    : await mkdtemp(path.join(os.tmpdir(), 'longyin-renderer-game-'));
  if (fakeGameRoot) {
    await writeFile(path.join(fakeGameRoot, 'LongYinLiZhiZhuan.exe'), 'renderer smoke fixture', 'utf8');
  }
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
        ...(fakeGameRoot ? { LONGYIN_GAME_ROOT: fakeGameRoot } : {}),
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
    const uiContracts = await readRendererUiContracts(cdp);
    assertRendererUiContracts(uiContracts);

    const rendererErrors = cdp.events.filter(isRendererError).map((event) => event.params);
    console.log(
      JSON.stringify(
        {
          target: { title: target.title, url: target.url },
          snapshot,
          uiContracts,
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
    if (fakeGameRoot) {
      await rm(fakeGameRoot, { recursive: true, force: true, maxRetries: 8, retryDelay: 250 });
    }
  }

  console.log('Electron renderer smoke check passed.');
}

const isEntryPoint = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isEntryPoint) {
  await runSmoke();
}
