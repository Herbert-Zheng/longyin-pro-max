# 游戏内按钮化辅助与词条刷新 Checklist

状态：已实现、已完成可达路径实机验收并已打包。

## 最终范围

- 突破入口按实际游戏流程定位在武馆。
- 装备打造与打造材料按实际游戏流程定位在兵器铺（铁匠铺）。
- 拍卖刷新、鉴宝最高估价、突破词条刷新、打造词条刷新均由 Electron 布尔开关控制，默认开启。
- 四项功能只在对应游戏 UI 显示按钮；不提供对应快捷键，也不在进入界面时自动执行。
- 鉴宝只选中玩家当前学识可见的括号估价最高物品，最终确认仍由玩家手动完成。
- 拍卖刷新绕过原版费用和次数限制，但关闭开关后恢复原版流程。
- 装备打造刷新只重建候选预览；不重复消耗材料、银钱或日期，不自动确认。

## 阶段 0：按钮是唯一触发入口

- [x] 新增并通过 `scripts/check-button-only-assists.ps1`。
- [x] 删除拍卖与鉴宝的专用快捷键字段、`Config.Bind`、轮询和提示文案。
- [x] 四项动作均要求开关开启、正确 UI 上下文、非 busy 状态和鼠标左键事件。
- [x] 四项动作只由 `OverlayButtonOnPointerClickPrefix` 的精确按钮名路由。
- [x] 右键、中键、空事件和程序化快捷键不能通过点击路由。

## 阶段 1：拍卖刷新与鉴宝辅助纯按钮化

- [x] 拍卖按钮文案为“免费刷新展品”，鉴宝按钮文案为“自动选择最高估价”。
- [x] 拍卖开关关闭后保留原版付费/次数限制刷新流程。
- [x] 鉴宝开关关闭后只隐藏模组按钮，不影响原版选择与确认。
- [x] Electron 删除四个旧快捷键字段、控件和默认值。
- [x] 保存配置时只删除所属 section 的旧键，不删除其他 section 的同名 decoy。
- [x] README、默认配置、后端测试和 renderer 测试已同步。
- [x] 阶段提交：`8bdf210 refactor: make auction and appraisal assists button-only`。

## 阶段 2：突破词条刷新按钮

- [x] 新增 `[Breakthrough] RerollEnabled = true`，未新增快捷键。
- [x] 候选生成、选择、用品选择、面板关闭和读档生命周期均有状态清理。
- [x] Hook 缺失时安全降级，不阻止插件其他功能加载。
- [x] 刷新先隐藏并解绑旧候选，下一帧调用原版候选生成，不调用真实突破或消耗入口。
- [x] Electron“成长与天赋”提供默认开启的按钮开关，并明确保存后重启游戏生效。
- [x] 新增并通过 `scripts/check-breakthrough-reroll-semantics.ps1`。
- [x] 已按用户说明复核武馆入口；当前三号存档武学未到突破节点，未强行训练或推进日期。
- [x] 阶段提交：`0a0515b feat: add safe breakthrough reroll button`。

## 阶段 3：打造词条刷新按钮

- [x] 新增 `[Craft] RerollEnabled = true`，未新增快捷键。
- [x] 普通打造仅在 `CraftUIController` 结果面板和完整候选列表存在时显示按钮。
- [x] 每个材料会话快照原始 seed；刷新始终基于原始 seed，不使用上一轮结果继续漂移。
- [x] 候选按原数量、顺序和类型生成；单项失败回退原候选，不压缩列表。
- [x] 完整新列表验证通过后才原子替换，旧预览先隐藏/解绑再销毁，避免列表持续增长。
- [x] 使用实际建筑等级生成候选，不调用确认、扣费、发奖、材料消费或时间推进方法。
- [x] 切换材料、关闭面板、选中结果或读档时重置会话与 busy 状态。
- [x] 特殊强化路径只调用 `ClearAllChoice()`、`GenerateChoice()`、`RefreshEnhanceButtonState()`；不调用确认入口。
- [x] Electron“交易与制造”提供默认开启的按钮开关，配置读写和 UI 文案已同步。
- [x] 新增并通过 `scripts/check-craft-reroll-semantics.ps1`。
- [x] 兵器铺实机连续刷新 10 次，候选数始终为 3，候选内容发生变化且 UI 不增长。
- [x] 10 次刷新前后银钱保持 16138、日期保持 2 年 4 月 23 日，未重复消耗材料。
- [x] 刷新后使用原版“制造”完成一次打造，只消耗一份劣质木材并获得一件劣质指环。
- [x] Electron 实际关闭该开关后，兵器铺结果面板无模组按钮、原版打造仍可用；随后已恢复开启。
- [x] 炼药入口已在医馆复核，但当前三号存档没有可用炼药材料；不把该不可达材料状态冒充实机通过。
- [x] 特殊强化为隐藏铁匠/剧情解锁路径；当前存档没有入口，改用 interop、生命周期日志和语义测试验证其安全降级。

## 阶段 4：跨功能与回归核对

- [x] `VisibleSettings` 只保留四个布尔开关，不存在对应 hotkey/RequireAlt 字段。
- [x] `main.ts`、`shared/config.ts`、renderer 默认值一致，四项均默认开启。
- [x] 四张设置卡只有 checkbox，文案统一为“只显示按钮，不自动执行，保存后重启游戏生效”。
- [x] 四项按钮均有 enabled/context/busy 双重保护，关闭或切换 UI 后隐藏。
- [x] 既有拍卖、鉴宝、材料扫货、探索迷雾和运行时兼容语义检查全部通过。
- [x] BepInEx 日志显示 163 个方法补丁启用、0 个安全跳过；突破、普通打造和特殊强化兼容性均为 ENABLED。

## 阶段 5：构建、部署与打包

- [x] 9 个语义/兼容检查全部通过。
- [x] Electron `typecheck` 通过。
- [x] Electron backend 测试 51/51 通过。
- [x] Electron renderer smoke 通过。
- [x] C# 通过唯一受支持脚本构建到 `_codex_staged_updates/BepInEx/plugins`，并生成匹配 `.pending`。
- [x] 确认游戏进程关闭后，仅通过 `LongYinModControl.ps1` promote，并生成备份回执。
- [x] staged、live、`dist` DLL SHA256 均为 `d20a9188205974fffdd762888bf0faa4eee654f025236b4dcc37d54cd9fa34f6`。
- [x] 插件版本为 `1.33.0`，Electron 版本为 `0.1.32`。
- [x] 已生成 `electron-app/release/LongYinProMaxApp-0.1.32-win-x64.zip`。
- [x] 已生成 `electron-app/release/update-manifest.json`，版本和 ZIP 文件名正确。
- [x] ZIP SHA256 与 manifest 一致：`938d0de7d6ae3e98bc675a264c6c0d24c11d473121ce64d0033152f694a2ee8f`。
- [x] ZIP 内 `resources/payload/BepInEx/plugins/LongYinStaminaLock.dll` 与 staged/live/dist DLL 哈希一致。

## 非阻塞的条件性补测

- 特殊强化只有在隐藏铁匠/剧情入口已解锁的存档中才能完成实际 10 次刷新；当前实现会在 Hook 或 UI 不存在时安全隐藏。
- 突破候选只有在武馆训练到真实突破节点时出现；当前存档不满足条件，本轮没有修改存档或消耗时间来制造测试节点。
- 这两项不影响默认开启、按钮唯一触发、配置读写、普通打造实机行为或本地安装包完整性。

## 提交记录

1. `8bdf210 refactor: make auction and appraisal assists button-only`
2. `0a0515b feat: add safe breakthrough reroll button`
3. `e91b59c feat: add crafting reroll buttons and launcher toggle`
4. `chore: package launcher 0.1.32`（本轮提交）
