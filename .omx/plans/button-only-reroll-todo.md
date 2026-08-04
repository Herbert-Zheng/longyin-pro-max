# 游戏内按钮化辅助与词条刷新 TODO

状态：待实施

## 需求摘要

- 拍卖会免费刷新、鉴宝自动选最高括号估价、刷新打造词条、刷新突破词条均只由 Electron 中的布尔开关启用或禁用。
- Electron 是唯一受支持的控制界面；插件仍以 BepInEx 布尔配置作为 Electron → 游戏插件的传递桥梁。
- 四项功能启用后，只在对应游戏 UI 中显示按钮；禁用时按钮不显示。
- 四项功能只能由玩家左键点击对应按钮触发，不提供快捷键，也不在进入界面时自动执行。
- 鉴宝只负责选中最高括号估价物品，最终确认保持手动。
- 拍卖会功能关闭后恢复原版有费用、有次数限制的刷新流程。
- 刷新打造词条覆盖普通装备打造、炼药、烹饪和特殊锻造。

## 默认值假设

- 既有 `Auction.PreviewRefreshEnabled` 和 `TreasureIdentify.BestValueAssistEnabled` 保持当前默认开启。
- 新增 `Breakthrough.RerollEnabled` 并默认开启；`Craft.RerollEnabled` 默认关闭，完成实机兼容验证后再决定是否改为默认开启。
- 不改动冻结日期、游戏速度、对话快进等其他功能的快捷键。

## 完成标准

- [ ] 四个功能关闭时，对应模组按钮均不存在或保持隐藏，原版 UI 与流程仍可用。
- [ ] 四个功能开启时，按钮只出现在各自对应 UI，关闭或切换界面后不残留。
- [ ] `Alt+W`、`Alt+F`、单独 `W`、单独 `F` 均不再触发拍卖、鉴宝、打造或突破的模组动作。
- [ ] 除按钮左键点击外，没有进入界面、定时器、热键或其他隐式触发路径。
- [ ] 连续点击每个刷新按钮 10 次，候选数量恒定，按钮和候选 UI 均不重复增长。
- [ ] 刷新前后金钱、材料、日期、突破用品和境界不发生变化。
- [ ] 刷新后可以正常选择一次并完成原版打造、鉴宝、拍卖或突破流程。
- [ ] 关闭并重进界面、切换材料、读档后没有旧候选或旧会话残留。
- [ ] Electron typecheck、自动测试、构建、ZIP 内容和 DLL 哈希验证全部通过。

## 每个功能阶段的固定交付顺序

阶段 1、2、3 均必须按以下顺序完成，不能把实机部署推迟到最终打包阶段：

- [ ] 先完成该阶段源码和对应回归测试。
- [ ] 运行该阶段静态语义检查与相关既有测试。
- [ ] 构建 DLL 到 `_codex_staged_updates/BepInEx/plugins` 并确认匹配的 `.pending` marker 存在。
- [ ] 确认游戏进程已关闭。
- [ ] 只通过 `mod-prototype/LongYinModControl/LongYinModControl.ps1` promote，并确认 live DLL 备份已生成。
- [ ] 运行该阶段实机验收，读取日志并核对资源/UI 状态。
- [ ] 将已验证 live DLL 同步到受跟踪 `dist`，核对源码 build metadata 与 DLL SHA256。
- [ ] 只有静态与实机验收都通过后，才提交该阶段；失败则继续修复，不提交未验证功能。

## 阶段 0：锁定按钮唯一触发契约

- [ ] 新增静态语义检查 `scripts/check-button-only-assists.ps1`，先建立失败测试。
- [ ] 断言拍卖与鉴宝不再 `Config.Bind` 快捷键键值，不再调用 `Input.GetKeyDown` 或 `IsConfiguredHotkeyPressed`。
- [ ] 断言四项动作入口都同时检查 `Enabled`、正确 UI 上下文和 `busy` 状态。
- [ ] 断言按钮文案不包含 `Alt+W`、`Alt+F` 或其他快捷键提示。
- [ ] 断言刷新/选择动作只从 `OverlayButtonOnPointerClickPrefix` 的精确按钮名路由进入。
- [ ] 四项功能要求 `eventData != null && eventData.button == Left`；不接受空事件、右键或程序化快捷触发作为成功点击。

主要落点：

- `mod-src/LongYinStaminaLock/LongYinStaminaLock.cs:1878` — 当前按钮点击总路由。
- `mod-src/LongYinStaminaLock/LongYinStaminaLock.cs:2015` — 拍卖按钮生命周期与现有热键分支。
- `mod-src/LongYinStaminaLock/LongYinStaminaLock.cs:2056` — 鉴宝按钮生命周期与现有热键分支。

## 阶段 1：拍卖刷新与鉴宝辅助改为纯按钮

### 插件运行时

- [ ] 删除 `_auctionPreviewRefreshHotkey`、`_auctionPreviewRefreshRequireAlt`、`_treasureIdentifyBestValueHotkey`、`_treasureIdentifyBestValueRequireAlt` 四个字段。
- [ ] 删除 `[Auction] PreviewRefreshHotkey`、`PreviewRefreshRequireAlt`、`[TreasureIdentify] BestValueHotkey`、`BestValueRequireAlt` 四个 `Config.Bind`。
- [ ] 删除拍卖和鉴宝更新循环中的快捷键触发分支。
- [ ] 删除启动日志中的快捷键说明。
- [ ] 将按钮文案改成纯动作文字：`免费刷新展品`、`自动选择最高估价`。
- [ ] 若已无其他引用，删除 `IsConfiguredHotkeyPressed` 和 `FormatConfiguredHotkey`。
- [ ] 保留点击路由和动作函数内部的双重 `Enabled` 检查。
- [ ] 验证关闭拍卖刷新开关时 `FreshAuctionItemPrefix` 恢复原版刷新，不移除原版按钮。
- [ ] 验证关闭鉴宝辅助时仅隐藏模组按钮，原版选择和确认不受影响。

主要落点：

- `mod-src/LongYinStaminaLock/LongYinStaminaLock.cs:109`
- `mod-src/LongYinStaminaLock/LongYinStaminaLock.cs:544`
- `mod-src/LongYinStaminaLock/LongYinStaminaLock.cs:1956`
- `mod-src/LongYinStaminaLock/LongYinStaminaLock.cs:2188`
- `mod-src/LongYinStaminaLock/LongYinStaminaLock.cs:2262`

### Electron 与配置迁移

- [ ] 从 `VisibleSettings` 删除四个快捷键字段。
- [ ] 从 `main.ts`、`shared/config.ts`、`renderer/components.tsx` 三套默认值删除四个字段。
- [ ] 从配置模板、normalize、read、save 和 renderer 表单中删除四个字段。
- [ ] 保存配置时，用 `removeIniSectionValue` 清理正确 section 中的四个旧键。
- [ ] 增加测试：正确 section 的旧键被删除，`[WrongSection]` 中同名 decoy 保持不变。
- [ ] 更新 `dist/BepInEx/config/codex.longyin.staminalock.cfg`，不再生成旧快捷键条目。
- [ ] 更新 README 当前功能说明；保留旧 release notes 的历史描述。
- [ ] 更新 `backend-safety.test.cjs` 和 `renderer-overlay.test.cjs`，明确快捷键控件及字段不存在。

主要落点：

- `electron-app/src/shared/types.ts:279`
- `electron-app/src/shared/config.ts:579` — 已有精确 section 键删除工具。
- `electron-app/src/shared/config.ts:652`
- `electron-app/src/shared/config.ts:879`
- `electron-app/src/shared/config.ts:1000`
- `electron-app/src/shared/config.ts:1462`
- `electron-app/src/renderer/App.tsx:1865`

### 阶段验收与提交

- [ ] 运行新的按钮唯一触发语义检查。
- [ ] 运行 Electron typecheck 和全部 45 项现有测试的更新版本。
- [ ] 按“每个功能阶段的固定交付顺序”构建、promote 和同步 DLL。
- [ ] 实机验证拍卖/鉴宝开关 on/off、按钮点击、快捷键无效和原版流程。
- [ ] 提交：`refactor: make auction and appraisal assists button-only`

## 阶段 2：刷新突破词条按钮

### 运行时状态与 Hook

- [ ] 新增 `[Breakthrough] RerollEnabled`，不新增任何快捷键配置。
- [ ] 为 `BreakThroughController.StartShowBreakChoice()` 注册 postfix，候选完整生成后标记 ready。
- [ ] 为 `BreakThroughChoiceController.OnClick()` 注册 prefix，选择前清除 ready。
- [ ] 为 `BreakBookChoose()`、`BreakFoodChoose()`、`BreakMedChoose()` 注册 prefix，进入用品选择时清除 ready。
- [ ] 面板关闭、控制器失效或读档时清除 ready、busy、待执行帧和按钮 root。
- [ ] Hook 缺失时记录 degraded 状态并安全禁用该功能，不阻止插件其他功能加载。

当前版本已只读确认以下接口存在于 `dist/BepInEx/interop/Assembly-CSharp.dll`：

- `BreakThroughController.breakThroughPanel`
- `BreakThroughController.breakThroughPos`
- `BreakThroughController.StartShowBreakChoice()`
- `BreakThroughChoiceController.OnClick()`
- `BreakBookChoose()`、`BreakFoodChoose()`、`BreakMedChoose()`

### 刷新动作与按钮

- [ ] 新增唯一按钮名和按钮 root，只在候选 ready、未消费、开关开启时显示。
- [ ] 将新按钮加入 `OverlayButtonOnPointerClickPrefix` 精确路由、模板查找排除集合和 overlay root 判断。
- [ ] 点击后立即进入 busy、禁用按钮并再次检查 enabled/context。
- [ ] 先将旧选择对象隐藏并与布局解绑，再销毁旧 `BreakThroughChoiceController`，避免 Unity 延迟销毁造成一帧重复。
- [ ] 下一帧调用 `StartShowBreakChoice()`；不得调用真实突破、扣费或用品消费方法。
- [ ] 验证新候选已生成后退出 busy；异常时安全隐藏按钮并给出状态提示。
- [ ] 选择词条后按钮立即隐藏，不能在已消费状态继续刷新。

### 自动与实机验证

- [ ] 新增 `scripts/check-breakthrough-reroll-semantics.ps1`。
- [ ] 在 `VisibleSettings`、三套默认值、配置模板、normalize、read、save 中加入 `breakthroughRerollEnabled`，且不增加任何快捷键字段。
- [ ] 在 Electron“成长与天赋”增加“刷新突破词条按钮”checkbox，默认开启，补齐 backend/renderer round-trip 测试。
- [ ] Electron 文案明确：启用只显示按钮，不自动刷新，保存后需重新启动游戏生效。
- [ ] 静态拒绝真实突破、日期推进和用品消费调用。
- [ ] 实机连续刷新 10 次，选项数恒定、无 UI 叠加。
- [ ] 比较刷新前后金钱、日期、境界、书籍、食物和药物数量。
- [ ] 刷新后选择一个词条并完成一次突破，确认只消费一次。
- [ ] 更新 README 的突破刷新按钮与 Electron 开关说明。
- [ ] 按“每个功能阶段的固定交付顺序”构建、promote 和同步 DLL。
- [ ] 提交：`feat: add breakthrough reroll button and launcher toggle`

## 阶段 3：刷新打造词条按钮

### 特殊锻造路径

- [ ] 新增 `[Craft] RerollEnabled`，不新增任何快捷键配置。
- [ ] 仅在 `SpeEnhanceEquipController.speEnhanceEquipUI` 可见且候选完整生成时显示按钮。
- [ ] 点击后执行原版 `ClearAllChoice()` → `GenerateChoice()` → `RefreshEnhanceButtonState()`。
- [ ] 不调用 `EnhanceButtonClicked()`、`FinishSpeEnhance()` 或任何确认/扣费入口。
- [ ] 关闭界面或完成选择时清除 busy 和按钮状态。

### 普通装备、炼药、烹饪路径

- [ ] 仅在 `CraftUIController.creaftUIPanel` 可见且 `craftResultList` 已生成时显示按钮。
- [ ] 第一次出现结果时按 `craftResultList` 的每个索引分别快照 seed 列表：`craftType`、物品类型、value、subType、littleType、attriType、目标武器/食物类型、目标英雄与实际建筑等级。
- [ ] seed 列表必须保留原候选数量与顺序；null 或单项生成失败时，在相同索引回退到原候选，不得跳过或压缩列表。
- [ ] 重复刷新始终基于本次材料会话的原始种子，不以刚生成结果继续漂移。
- [ ] 使用当前已编译成功的七参数 `GameController.GenerateRandomItemValue(...)` 重建全新的结果列表。
- [ ] 使用实际 `targetBuilding.lv` 作为 `bossLv`，不照搬参考实现的固定 `1f`。
- [ ] 只有整份新列表构建完成、数量/顺序/类型兼容性验证通过后，才原子替换 `craftResultList`；随后清理旧预览并调用 `ShowCraftResultChoosePanel()`，禁止向旧列表追加。
- [ ] 若生成异常，在替换前保留旧列表并安全回滚或保持 no-op。
- [ ] 不调用 `CraftButtonClicked()`、`CraftResultChoosen()`、奖励发放或材料扣除入口。
- [ ] 材料组合、craftType、目标子类型发生变化，或界面关闭/结果已选择时，重置整个刷新会话。
- [ ] 与现有制造增产兼容：只有最终手动选择后，现有 `CraftResultChoosen` 与奖励逻辑才工作。

主要落点：

- `mod-src/LongYinStaminaLock/LongYinStaminaLock.cs:677` — 已有 Craft UI 生命周期 hook。
- `mod-src/LongYinStaminaLock/LongYinStaminaLock.cs:1151` — 现有最终选择观察点。
- `mod-src/LongYinStaminaLock/LongYinStaminaLock.cs:9927` — 当前七参数随机装备生成逻辑。

### 自动与实机验证

- [ ] 新增 `scripts/check-craft-reroll-semantics.ps1`。
- [ ] 在 `VisibleSettings`、三套默认值、配置模板、normalize、read、save 中加入 `craftRerollEnabled`，且不增加任何快捷键字段。
- [ ] 在 Electron“交易与制造”增加“刷新打造词条按钮”checkbox，默认关闭，补齐 backend/renderer round-trip 测试。
- [ ] Electron 文案明确：启用只显示按钮，不自动刷新，保存后需重新启动游戏生效。
- [ ] 静态要求全列表替换、session reset、busy gate、enabled gate 和按钮唯一触发。
- [ ] 静态拒绝确认、扣费、发奖与时间推进方法。
- [ ] 普通装备、炼药、烹饪、特殊锻造分别连续刷新 10 次。
- [ ] 每次验证候选数量恒定，结果类型、装备族、材料上下文与打造目标保持一致。
- [ ] 比较刷新前后金钱、材料、时间和背包物品数量。
- [ ] 切换材料后确认不会沿用旧会话；关闭重进和读档后无旧候选。
- [ ] 刷新后正常完成一次打造，并验证制造增产只在最终确认时触发。
- [ ] 更新 README 的打造刷新按钮、覆盖范围与 Electron 开关说明。
- [ ] 按“每个功能阶段的固定交付顺序”构建、promote 和同步 DLL。
- [ ] 提交：`feat: add crafting reroll buttons and launcher toggle`

## 阶段 4：跨功能核对（不产生新的功能 diff）

- [ ] 核对 `VisibleSettings` 只保留四个功能的布尔开关，不存在对应 hotkey/RequireAlt 字段。
- [ ] 核对 `main.ts`、`shared/config.ts`、`renderer/components.tsx` 三套默认值完全一致。
- [ ] 核对四个设置卡片只有 checkbox，不出现快捷键选择控件。
- [ ] 统一文案：启用只会显示按钮，不会自动执行；保存后需重新启动游戏生效。
- [ ] 开关关闭时，运行时即使已创建按钮 root 也必须立即隐藏；下次启动不得重建。
- [ ] 更新 renderer 测试，明确四项功能均为 button-only。
- [ ] 核对阶段 1–3 已分别完成 README、Electron 与测试修改；本阶段只做交叉检查，不新增独立功能改动。
- [ ] 若核对发现问题，修复并归入对应阶段提交后重新跑该阶段验收，而不是留下边界不清的收尾 diff。

## 阶段 5：全量验证、暂存部署与打包

- [ ] 运行三个语义检查：按钮唯一触发、突破刷新、打造刷新。
- [ ] 运行现有拍卖、鉴宝、制造增产和运行时兼容检查，防止回归。
- [ ] 运行 Electron `typecheck`、backend/renderer 全测试和 build。
- [ ] 按 staged DLL 工作流构建到 `_codex_staged_updates/BepInEx/plugins` 并生成 `.pending`。
- [ ] 确认游戏关闭，只通过 `mod-prototype/LongYinModControl/LongYinModControl.ps1` promote，并保留 live DLL 备份。
- [ ] 执行四功能 on/off 实机矩阵，确认唯一触发入口是对应按钮左键点击。
- [ ] 显式验证右键、中键和 `eventData == null` 均不能触发四项模组动作。
- [ ] 在 1920×1080、2560×1440 和窗口模式检查按钮位置、缩放、遮挡与重复创建。
- [ ] 确认日志没有 `source=hotkey`、Harmony target failure、重复按钮或列表增长告警。
- [ ] 如需发布，更新 Electron 版本并重新生成 ZIP 与 `update-manifest.json`。
- [ ] 验证 ZIP SHA256 与 manifest 一致，ZIP 内 DLL 与 `dist`/live DLL 哈希一致。
- [ ] 提交打包版本元数据；release 目录若保持 ignored，则不提交本地产物。

## 风险与缓解

- Unity `Destroy` 延迟导致选项叠加：旧对象先隐藏/解绑，下一帧再生成，并以固定候选数验证。
- 原版生成方法存在隐藏副作用：实机记录刷新前后资源、日期、境界和背包差异；发现副作用即停用对应路径。
- 普通打造随机生成改变装备族或品质上下文：保存完整材料/目标上下文，固定实际建筑等级，并拒绝不兼容候选。
- 连续点击导致重入：按钮与动作双重 `busy` gate，完成或异常时统一释放。
- 旧快捷键键值残留：Electron 保存时精确删除正确 section 的四个旧键；插件完全不再绑定或读取它们。
- 功能关闭后仍残留按钮：每帧生命周期检查 enabled/context，关闭时隐藏，面板销毁时清 root。

## 推荐提交顺序

1. `refactor: make auction and appraisal assists button-only`
2. `feat: add breakthrough reroll button and launcher toggle`
3. `feat: add crafting reroll buttons and launcher toggle`
4. `chore: package launcher <version>`（仅提交版本与受跟踪元数据）

每个提交必须同时包含对应测试，并在提交前完成该阶段的静态检查和实机验收。
