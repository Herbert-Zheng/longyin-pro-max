const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const { pathToFileURL } = require('node:url');

const smokeModuleUrl = pathToFileURL(
  path.resolve(__dirname, '..', 'scripts', 'check-renderer-smoke.mjs')
).href;

async function loadHarness() {
  return import(smokeModuleUrl);
}

test('static boot splash is not accepted as a ready React application', async () => {
  const { assertRendererHealthy } = await loadHarness();

  assert.throws(
    () =>
      assertRendererHealthy(
        {
          readyState: 'complete',
          bodyText: '龙胤立志传 Pro Max 正在读取游戏目录、模组与配置，请稍候…',
          rootChildCount: 1,
          rootHtml: '<div class="boot-splash" role="status">...</div>',
          appShellPresent: false,
          bootSplashPresent: true
        },
        []
      ),
    /boot splash|React application/i
  );
});

test('renderer runtime exceptions and error-level console messages fail the smoke check', async () => {
  const { assertRendererHealthy } = await loadHarness();
  const readySnapshot = {
    readyState: 'complete',
    bodyText: '龙胤立志传 Pro Max 控制台游戏路径模组设置更新与日志',
    rootChildCount: 1,
    rootHtml: '<div class="shell"><div class="dashboard"></div></div>',
    appShellPresent: true,
    bootSplashPresent: false
  };

  assert.throws(
    () =>
      assertRendererHealthy(readySnapshot, [
        {
          method: 'Runtime.exceptionThrown',
          params: { exceptionDetails: { text: 'Uncaught TypeError' } }
        }
      ]),
    /renderer.*error/i
  );

  assert.throws(
    () =>
      assertRendererHealthy(readySnapshot, [
        {
          method: 'Runtime.consoleAPICalled',
          params: { type: 'error', args: [{ type: 'string', value: 'render failed' }] }
        }
      ]),
    /renderer.*error/i
  );
});

test('renderer UI contract rejects collapsed-panel and tile-alignment regressions', async () => {
  const { assertRendererUiContracts } = await loadHarness();
  const healthyUi = {
    heroSummaryGap: 12,
    summaryStatusGap: 12,
    systems: {
      environmentFullWidth: true,
      healthCollapsed: true,
      healthSummaryText: '健康检查详情 全部通过',
      overlayExplained: true,
      controlCount: 3,
      controlHeightSpread: 0
    },
    settingsPages: [
      { label: '成长与天赋', gridPresent: true, cardCount: 2, tileCount: 2, cardsSelfAligned: true, tileHeightSpread: 0 },
      { label: '交易与制造', gridPresent: true, cardCount: 2, tileCount: 2, cardsSelfAligned: true, tileHeightSpread: 0 },
      { label: '社交与组队', gridPresent: true, cardCount: 2, tileCount: 2, cardsSelfAligned: true, tileHeightSpread: 0 }
    ],
    customTalents: {
      conditionOptionCount: 2,
      intelligenceUsesRawValue: true,
      intelligenceLabel: '智力',
      effectOptionCount: 215,
      uniqueEffectLabelCount: 215,
      allEffectLabelsChinese: true
    },
    navigationPages: [
      ['主页', '主页'],
      ['更新记录', '更新记录'],
      ['系统更改', '系统更改'],
      ['成长与天赋', '成长与天赋'],
      ['自定义天赋', '自定义天赋'],
      ['探索与大地图', '探索与大地图'],
      ['交易与制造', '交易与制造'],
      ['社交与组队', '社交与组队'],
      ['战斗相关', '战斗相关']
    ].map(([label, title]) => ({ label, title, currentCount: 1, currentLabel: label, heading: title })),
    responsive: {
      hasExpectedViewport: true,
      horizontalOverflow: 0,
      primaryActionVisible: true,
      saveActionVisible: true
    },
    pageTransition: { scrolledToTop: true, headingFocused: true },
    materialAutoBuy: { disabledWhenOff: true, enabledWhenOn: true, valuesPreserved: true },
    settingsSearch: { filteredToGovernmentStorage: true, restoredAllCards: true },
    confirmDialog: { dangerInitiallyFocusesCancel: true },
    accessibility: { unnamedControls: [], liveStatusPresent: true }
  };

  assert.doesNotThrow(() => assertRendererUiContracts(healthyUi));
  assert.throws(
    () => assertRendererUiContracts({ ...healthyUi, heroSummaryGap: 16 }),
    /hero.*summary.*12/i
  );
  assert.throws(
    () => assertRendererUiContracts({ ...healthyUi, summaryStatusGap: 16 }),
    /summary.*status.*12/i
  );
  assert.throws(
    () => assertRendererUiContracts({ ...healthyUi, systems: { ...healthyUi.systems, healthCollapsed: false } }),
    /health.*collapsed/i
  );
  assert.throws(
    () => assertRendererUiContracts({ ...healthyUi, customTalents: { ...healthyUi.customTalents, intelligenceLabel: 'Intelligence' } }),
    /attributes.*智力/i
  );
  assert.throws(
    () => assertRendererUiContracts({ ...healthyUi, settingsPages: [{ ...healthyUi.settingsPages[0], gridPresent: false, cardCount: 0, tileCount: 0 }] }),
    /cannot be measured/i
  );
});

function interactiveHealthyUi() {
  const page = (label) => ({ label, title: label, currentCount: 1, currentLabel: label, heading: label });
  return {
    heroSummaryGap: 12,
    summaryStatusGap: 12,
    systems: {
      environmentFullWidth: true,
      healthCollapsed: true,
      healthSummaryText: '健康检查详情 全部通过',
      overlayExplained: true,
      controlCount: 3,
      controlHeightSpread: 0
    },
    settingsPages: [{ label: '成长与天赋', gridPresent: true, cardCount: 1, tileCount: 1, cardsSelfAligned: true, tileHeightSpread: 0 }],
    customTalents: {
      conditionOptionCount: 2,
      intelligenceUsesRawValue: true,
      intelligenceLabel: '智力',
      effectOptionCount: 215,
      uniqueEffectLabelCount: 215,
      allEffectLabelsChinese: true
    },
    navigationPages: ['主页', '更新记录', '系统更改', '成长与天赋', '自定义天赋', '探索与大地图', '交易与制造', '社交与组队', '战斗相关'].map(page),
    responsive: { hasExpectedViewport: true, horizontalOverflow: 0, primaryActionVisible: true, saveActionVisible: true },
    pageTransition: { scrolledToTop: true, headingFocused: true },
    materialAutoBuy: { disabledWhenOff: true, enabledWhenOn: true, valuesPreserved: true },
    settingsSearch: { filteredToGovernmentStorage: true, restoredAllCards: true },
    confirmDialog: { dangerInitiallyFocusesCancel: true },
    accessibility: { unnamedControls: [], liveStatusPresent: true }
  };
}

test('renderer UI contract rejects an incomplete navigation pass', async () => {
  const { assertRendererUiContracts } = await loadHarness();
  const healthyUi = interactiveHealthyUi();
  assert.throws(
    () => assertRendererUiContracts({ ...healthyUi, navigationPages: healthyUi.navigationPages.slice(0, 8) }),
    /9 navigation pages/i
  );
});

test('renderer UI contract rejects horizontal overflow at the supported compact viewport', async () => {
  const { assertRendererUiContracts } = await loadHarness();
  const healthyUi = interactiveHealthyUi();
  assert.throws(
    () => assertRendererUiContracts({ ...healthyUi, responsive: { ...healthyUi.responsive, horizontalOverflow: 24 } }),
    /overflow horizontally/i
  );
});

test('renderer UI contract rejects page changes that lose heading focus', async () => {
  const { assertRendererUiContracts } = await loadHarness();
  const healthyUi = interactiveHealthyUi();
  assert.throws(
    () => assertRendererUiContracts({ ...healthyUi, pageTransition: { scrolledToTop: true, headingFocused: false } }),
    /keyboard focus/i
  );
});

test('renderer UI contract rejects visible controls without accessible names', async () => {
  const { assertRendererUiContracts } = await loadHarness();
  const healthyUi = interactiveHealthyUi();
  assert.throws(
    () => assertRendererUiContracts({ ...healthyUi, accessibility: { unnamedControls: ['button'], liveStatusPresent: true } }),
    /accessible name/i
  );
});

test('renderer UI contract rejects danger confirmation that initially focuses the destructive action', async () => {
  const { assertRendererUiContracts } = await loadHarness();
  const healthyUi = interactiveHealthyUi();
  assert.throws(
    () => assertRendererUiContracts({ ...healthyUi, confirmDialog: { ...healthyUi.confirmDialog, dangerInitiallyFocusesCancel: false } }),
    /danger confirmation.*cancel/i
  );
});
