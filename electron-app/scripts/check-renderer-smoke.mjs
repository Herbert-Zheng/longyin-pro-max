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
  if (snapshot.navigationPages?.length !== 9) {
    throw new Error(`All 9 navigation pages must be exercised (received ${snapshot.navigationPages?.length ?? 'missing'}).`);
  }
  for (const page of snapshot.navigationPages ?? []) {
    if (page.currentCount !== 1 || page.currentLabel !== page.label) {
      throw new Error(`${page.label} must be the only navigation item marked as the current page.`);
    }
    if (page.heading !== page.title) {
      throw new Error(`${page.label} must render the expected main heading ${page.title} (received ${page.heading || 'missing'}).`);
    }
  }
  if (!snapshot.responsive?.hasExpectedViewport) {
    throw new Error('Responsive smoke contract must run at 1120×760.');
  }
  if (snapshot.responsive.horizontalOverflow > 1) {
    throw new Error(`The 1120×760 layout must not overflow horizontally (${snapshot.responsive.horizontalOverflow}px overflow).`);
  }
  if (!snapshot.responsive.primaryActionVisible || !snapshot.responsive.saveActionVisible) {
    throw new Error('The primary save-and-launch action and the save action must remain visible at 1120×760.');
  }
  if (!snapshot.pageTransition?.scrolledToTop || !snapshot.pageTransition?.headingFocused) {
    throw new Error('Changing pages must scroll to the top and move keyboard focus to the page heading.');
  }
  if (!snapshot.materialAutoBuy?.disabledWhenOff) {
    throw new Error('Material purchase threshold controls must be disabled while material auto-buy is off.');
  }
  if (!snapshot.materialAutoBuy?.enabledWhenOn) {
    throw new Error('Material purchase threshold controls must be enabled when material auto-buy is on.');
  }
  if (!snapshot.materialAutoBuy?.valuesPreserved) {
    throw new Error('Material purchase threshold values must survive disabling and re-enabling material auto-buy.');
  }
  if (!snapshot.settingsSearch?.filteredToGovernmentStorage || !snapshot.settingsSearch?.restoredAllCards) {
    throw new Error('Settings search must isolate 官府仓库 controls and restore all 7 trade cards when cleared.');
  }
  if (!snapshot.confirmDialog?.dangerInitiallyFocusesCancel) {
    throw new Error('Danger confirmation dialogs must initially focus the cancel action.');
  }
  if ((snapshot.accessibility?.unnamedControls ?? []).length > 0) {
    throw new Error(`Every visible common control needs an accessible name: ${snapshot.accessibility.unnamedControls.join(', ')}`);
  }
  if (!snapshot.accessibility?.liveStatusPresent) {
    throw new Error('The current launcher status must be exposed through a polite live region.');
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

const NAVIGATION_PAGES = [
  { label: '主页', title: '主页' },
  { label: '更新记录', title: '更新记录' },
  { label: '系统更改', title: '系统更改' },
  { label: '成长与天赋', title: '成长与天赋' },
  { label: '自定义天赋', title: '自定义天赋' },
  { label: '探索与大地图', title: '探索与大地图' },
  { label: '交易与制造', title: '交易与制造' },
  { label: '社交与组队', title: '社交与组队' },
  { label: '战斗相关', title: '战斗相关' }
];

async function waitForRendererPaint(cdp) {
  await cdp.send('Runtime.evaluate', {
    expression: `new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)))`,
    awaitPromise: true
  });
}

async function readNavigationContracts(cdp) {
  const pages = [];
  for (const page of NAVIGATION_PAGES) {
    await clickNavigationItem(cdp, page.label);
    await waitForRendererPaint(cdp);
    const evaluation = await cdp.send('Runtime.evaluate', {
      expression: `(() => {
        const currentItems = [...document.querySelectorAll('[aria-current="page"]')];
        const heading = document.querySelector('main h1, main [data-page-title], .workspace__hero-copy h1, .workspace__hero-copy h2');
        return {
          label: ${JSON.stringify(page.label)},
          title: ${JSON.stringify(page.title)},
          currentCount: currentItems.length,
          currentLabel: currentItems[0]?.getAttribute('aria-label')?.trim() ??
            currentItems[0]?.querySelector('[data-nav-label], strong')?.textContent?.trim() ??
            currentItems[0]?.textContent?.trim().replace(/\\s+/g, ' ') ?? '',
          heading: heading?.textContent?.trim() ?? ''
        };
      })()`,
      returnByValue: true
    });
    pages.push(evaluation.result?.value);
  }
  return pages;
}

async function readResponsiveContract(cdp) {
  await cdp.send('Emulation.setDeviceMetricsOverride', {
    width: 1120,
    height: 760,
    deviceScaleFactor: 1,
    mobile: false
  });
  await waitForRendererPaint(cdp);
  const evaluation = await cdp.send('Runtime.evaluate', {
    expression: `(() => {
      const visibleButton = (label) => {
        const button = [...document.querySelectorAll('button')].find((node) => node.textContent?.trim().includes(label));
        if (!button) return false;
        const rect = button.getBoundingClientRect();
        const style = getComputedStyle(button);
        return style.visibility !== 'hidden' && style.display !== 'none' && rect.width > 0 && rect.height > 0 &&
          rect.top >= 0 && rect.left >= 0 && rect.bottom <= innerHeight && rect.right <= innerWidth;
      };
      const root = document.documentElement;
      return {
        hasExpectedViewport: innerWidth === 1120 && innerHeight === 760,
        horizontalOverflow: Math.max(0, root.scrollWidth - root.clientWidth),
        primaryActionVisible: visibleButton('保存并启动'),
        saveActionVisible: visibleButton('保存设置')
      };
    })()`,
    returnByValue: true
  });
  await cdp.send('Emulation.clearDeviceMetricsOverride');
  await waitForRendererPaint(cdp);
  return evaluation.result?.value;
}

async function readPageTransitionContract(cdp) {
  await clickNavigationItem(cdp, '交易与制造');
  await cdp.send('Runtime.evaluate', {
    expression: `window.scrollTo(0, document.documentElement.scrollHeight)`
  });
  await waitForRendererPaint(cdp);
  await clickNavigationItem(cdp, '战斗相关');
  await waitForRendererPaint(cdp);
  const evaluation = await cdp.send('Runtime.evaluate', {
    expression: `(() => {
      const heading = document.querySelector('main h1, main [data-page-title], .workspace__hero-copy h1, .workspace__hero-copy h2');
      return {
        scrolledToTop: window.scrollY <= 1,
        headingFocused: Boolean(heading && document.activeElement === heading)
      };
    })()`,
    returnByValue: true
  });
  return evaluation.result?.value;
}

async function readMaterialAutoBuyContract(cdp) {
  await clickNavigationItem(cdp, '交易与制造');
  const evaluation = await cdp.send('Runtime.evaluate', {
    expression: `(async () => {
      const inputByLabel = (label) => [...document.querySelectorAll('label')]
        .find((node) => node.querySelector('.field__label, .toggle__label')?.textContent?.trim() === label)
        ?.querySelector('input');
      const toggle = inputByLabel('启用材料一键扫货');
      const rare = inputByLabel('扫货最低品级');
      const level = inputByLabel('扫货最低等级');
      if (!toggle || !rare || !level) throw new Error('Material auto-buy controls are missing.');
      const setValue = (input, value) => {
        Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set.call(input, String(value));
        input.dispatchEvent(new Event('input', { bubbles: true }));
        input.dispatchEvent(new Event('change', { bubbles: true }));
      };
      if (!toggle.checked) toggle.click();
      setValue(rare, 4);
      setValue(level, 3);
      await new Promise((resolve) => requestAnimationFrame(resolve));
      toggle.click();
      await new Promise((resolve) => requestAnimationFrame(resolve));
      const disabledWhenOff = rare.disabled && level.disabled;
      const valuesWhileOff = [rare.value, level.value];
      toggle.click();
      await new Promise((resolve) => requestAnimationFrame(resolve));
      return {
        disabledWhenOff,
        enabledWhenOn: !rare.disabled && !level.disabled,
        valuesPreserved: rare.value === '4' && level.value === '3' && valuesWhileOff[0] === '4' && valuesWhileOff[1] === '3'
      };
    })()`,
    awaitPromise: true,
    returnByValue: true
  });
  if (evaluation.exceptionDetails) {
    throw new Error('Could not exercise material auto-buy dependent controls.');
  }
  return evaluation.result?.value;
}

async function readSettingsSearchContract(cdp) {
  await clickNavigationItem(cdp, '交易与制造');
  const evaluation = await cdp.send('Runtime.evaluate', {
    expression: `(async () => {
      const input = document.querySelector('[role="search"] input');
      if (!input) throw new Error('Settings search input is missing.');
      const setQuery = async (value) => {
        Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set.call(input, value);
        input.dispatchEvent(new Event('input', { bubbles: true }));
        input.dispatchEvent(new Event('change', { bubbles: true }));
        await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
      };
      const visibleCards = () => [...document.querySelectorAll('[data-searchable-card]')]
        .filter((card) => !card.hidden && getComputedStyle(card).display !== 'none');
      await setQuery('官府仓库');
      const filtered = visibleCards();
      const filteredToGovernmentStorage = filtered.length === 1 &&
        filtered[0].textContent.includes('官府仓库刷新') &&
        filtered[0].textContent.includes('启用官府仓库刷新');
      await setQuery('');
      return {
        filteredToGovernmentStorage,
        restoredAllCards: visibleCards().length === 7
      };
    })()`,
    awaitPromise: true,
    returnByValue: true
  });
  if (evaluation.exceptionDetails) {
    throw new Error('Could not exercise settings search filtering.');
  }
  return evaluation.result?.value;
}

async function readConfirmDialogContract(cdp) {
  await clickNavigationItem(cdp, '主页');
  const dangerEvaluation = await cdp.send('Runtime.evaluate', {
    expression: `(async () => {
      const uninstall = [...document.querySelectorAll('button')].find((button) => button.textContent?.trim() === '卸载模组');
      if (!uninstall || uninstall.disabled) throw new Error('Enabled uninstall action is missing.');
      uninstall.click();
      await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
      const dialog = document.querySelector('dialog.confirm-dialog[open]');
      const cancel = [...(dialog?.querySelectorAll('button') ?? [])].find((button) => button.textContent?.trim() === '取消');
      const dangerInitiallyFocusesCancel = Boolean(cancel && document.activeElement === cancel);
      cancel?.click();
      return dangerInitiallyFocusesCancel;
    })()`,
    awaitPromise: true,
    returnByValue: true
  });
  if (dangerEvaluation.exceptionDetails) {
    throw new Error('Could not exercise the danger confirmation dialog.');
  }
  return {
    dangerInitiallyFocusesCancel: dangerEvaluation.result?.value === true
  };
}
async function readAccessibilityContract(cdp) {
  const unnamedControls = [];
  for (const page of NAVIGATION_PAGES) {
    await clickNavigationItem(cdp, page.label);
    await waitForRendererPaint(cdp);
    const evaluation = await cdp.send('Runtime.evaluate', {
      expression: `(() => {
        const text = (node) => node?.textContent?.trim().replace(/\\s+/g, ' ') ?? '';
        const accessibleName = (control) => {
          const ariaLabel = control.getAttribute('aria-label')?.trim();
          if (ariaLabel) return ariaLabel;
          const labelledBy = control.getAttribute('aria-labelledby')?.trim();
          if (labelledBy) {
            const label = labelledBy.split(/\\s+/).map((id) => text(document.getElementById(id))).filter(Boolean).join(' ');
            if (label) return label;
          }
          const labels = [...(control.labels ?? [])].map(text).filter(Boolean).join(' ');
          if (labels) return labels;
          if (control.tagName === 'BUTTON' && text(control)) return text(control);
          return control.getAttribute('title')?.trim() ?? '';
        };
        return [...document.querySelectorAll('button, input, select, textarea')]
          .filter((control) => {
            const rect = control.getBoundingClientRect();
            const style = getComputedStyle(control);
            return style.display !== 'none' && style.visibility !== 'hidden' && rect.width > 0 && rect.height > 0;
          })
          .filter((control) => !accessibleName(control))
          .map((control) => control.outerHTML.slice(0, 160));
      })()`,
      returnByValue: true
    });
    unnamedControls.push(...(evaluation.result?.value ?? []).map((control) => `${page.label}: ${control}`));
  }
  const statusEvaluation = await cdp.send('Runtime.evaluate', {
    expression: `(() => {
      const status = document.querySelector('.status-strip, [data-status-region]');
      return Boolean(status && (status.getAttribute('role') === 'status' || status.getAttribute('aria-live') === 'polite'));
    })()`,
    returnByValue: true
  });
  return {
    unnamedControls,
    liveStatusPresent: statusEvaluation.result?.value === true
  };
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
  const navigationPages = await readNavigationContracts(cdp);
  const responsive = await readResponsiveContract(cdp);
  const pageTransition = await readPageTransitionContract(cdp);
  const materialAutoBuy = await readMaterialAutoBuyContract(cdp);
  const settingsSearch = await readSettingsSearchContract(cdp);
  const confirmDialog = await readConfirmDialogContract(cdp);
  const accessibility = await readAccessibilityContract(cdp);
  return {
    ...baseEvaluation.result?.value,
    systems: systemsEvaluation.result?.value,
    settingsPages,
    customTalents,
    navigationPages,
    responsive,
    pageTransition,
    materialAutoBuy,
    settingsSearch,
    confirmDialog,
    accessibility
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
