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
    heroSummaryGap: 16,
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
    }
  };

  assert.doesNotThrow(() => assertRendererUiContracts(healthyUi));
  assert.throws(
    () => assertRendererUiContracts({ ...healthyUi, heroSummaryGap: 12 }),
    /hero.*summary.*16/i
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
