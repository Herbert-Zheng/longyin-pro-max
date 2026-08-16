# 龙胤立志传 Pro Max 模组仓库

这是 `LongYinLiZhiZhuan` 的便携式模组仓库，便于通过 GitHub 管理模组与 Electron 启动器，而不上传游戏本体。

当前支持游戏版本：`V1.1.0f5`

## 仓库内容

- `dist/`
  Electron 应用复制到游戏目录中的模组载荷。
- `electron-app/`
  便携式 Electron 启动器与更新器源码，是唯一受支持的启动与配置入口。
- `archive/`
  存放已经退役的原型、旧脚本和历史备份；这些内容不属于当前受支持的安装与启动流程。
- `MODDING-NOTES-1.071F.md`
  `1.071F` 时期的历史开发记录，仅供旧版本逆向与实现参考。
- `PROJECT-NOTES.md`
  本地保留的项目说明与仓库处理备注。

## 仓库中不包含

- 游戏本体文件
- `LongYinLiZhiZhuan.exe`
- `LongYinLiZhiZhuan_Data/`
- `GameAssembly.dll`
- Steam 管理的安装内容

这个仓库只保存模组项目和便携式模组覆盖层。

## 快速安装

1. 安装一份干净的游戏。
2. 下载或克隆本仓库。
3. 运行 `electron-app/` 里的 `LongYinProMax.exe`。
4. 如果能自动识别到游戏目录，应用会把 `dist/` 复制到游戏根目录。
5. 如果自动识别失败，请手动选择包含 `LongYinLiZhiZhuan.exe` 的文件夹。
6. 安装完成后，继续通过 Electron 应用保存配置与启动游戏。
7. 如果之后需要卸载模组，请使用应用内卸载，或运行 `Uninstall.cmd`。

## 下载

稳定版会发布在 GitHub Releases：

- [最新稳定版下载](https://github.com/Herbert-Zheng/longyin_plus/releases/latest)

下载 Release ZIP 后，解压到任意位置，然后运行 `LongYinProMax.exe`。
同一个包里也包含 `Uninstall.cmd`，方便后续干净卸载。

## 标准 OTA 发布

仓库根目录提供了统一入口：

- [git-push-ota.cmd](G:\Steam\steamapps\common\longyin_plus_repo\git-push-ota.cmd)
- [publish-update.cmd](G:\Steam\steamapps\common\longyin_plus_repo\publish-update.cmd)

这两个命令是同义入口，都会执行同一套 OTA 发布流程：

1. 检查当前 Git 状态和最近变更
2. 读取 `electron-app/package.json` 版本号
3. 运行 `npm run typecheck`
4. 运行 `npm run build`
5. 校验 `release/LongYinProMaxApp-<version>-win-x64.zip`
6. 校验 `release/update-manifest.json`
7. 推送当前分支和对应 tag
8. 创建或更新 GitHub Release
9. 上传 ZIP 和 `update-manifest.json`

默认脚本要求工作树干净，否则会拒绝发布。

如果只想做预检查，不真正发布，可以运行：

```powershell
.\git-push-ota.ps1 -DryRun
```

如果已经手动 build，只想校验和发布，可以运行：

```powershell
.\git-push-ota.ps1 -SkipBuild
```

## 开发工具

当前仓库的模组开发工具链默认使用仓库内置的便携式 .NET：

- `.codex-tools/dotnet/dotnet.exe`
- 已在本机验证的 SDK 版本：`6.0.428`
- C# 脚本工具固定为 `dotnet-script 1.5.0`

之所以固定到 `1.5.0`，是因为 `dotnet-script 1.6.0+` 已改为 `net8.0/net9.0`，不能直接跑在当前这套便携式 .NET 6 工具链上。

第一次使用或更新本地工具时，运行：

```powershell
.\scripts\restore-tools.ps1
```

运行任意 `.csx` 脚本时，使用：

```powershell
.\scripts\run-csharp-script.ps1 `
  -ScriptPath .\scripts\csharp\inspect-interop-type.csx `
  -ScriptArguments '.\dist\BepInEx\interop\Assembly-CSharp.dll', 'PlotController', 'false', 'skip', 'auto', 'choice', 'plot'
```

检查互操作程序集中的某个类型时，优先使用封装好的命令：

```powershell
.\scripts\inspect-interop-type.ps1 -TypeName PlotController
```

使用约定：

- `mod-src/build-il2cpp-plugin.ps1` 仍然是唯一受支持的插件编译入口。
- PowerShell 负责文件编排、构建、日志、部署和仓库自动化。
- `dotnet-script` 只用于 C# 反射、互操作程序集探查、Harmony 目标发现、枚举转储这类分析型工作。

后续如果需要继续扩展，可以在同样的 repo-pinned 模式下补充：

- `ilspycmd` 用于命令行反编译/导出
- `gh` 用于 OTA Release 检查与发布辅助
- BepInEx 日志 tail 脚本
- 带“游戏已关闭检查 + DLL 备份”的安全部署脚本

## 手动安装

如果你不想通过 Electron 应用安装，也可以手动把 `dist/` 里的内容复制到游戏根目录。

注意：
不要把整个 `dist` 文件夹原样复制进去。
只复制 `dist/` 里面的文件和文件夹。

## 当前 dist 内容

当前便携载荷包含：

- BepInEx 加载器和运行时文件
- `dotnet/`
- 插件 DLL
- 插件配置文件
- `Uninstall.cmd`
- `Uninstall.ps1`
- `steam_appid.txt`
- 安装说明

## 包含的插件

- `LongYinBattleTurbo`
- `LongYinHorseStaminaMultiplier`
- `LongYinQuestSnapshot`
- `LongYinSkillTalentGrant`
- `LongYinSkipIntro`
- `LongYinProMax`

`LongYinProMax` 是当前综合玩法插件，提供以下拍卖、鉴宝、交易、制造、关系与功法辅助：

- 在珍宝铺（藏宝阁）交易界面顶部显示珍宝购物车汇总；鉴后卖价会把玩家看到的括号估价临时代入原版卖价公式重算，不额外收取不存在的鉴定费。
- 进入珍宝铺时，只把鉴定学识要求不高于玩家当前鉴定学识、且按原版买卖价重算后确有利润的未鉴定珍宝加入购物车；该功能只负责加购，结账仍由玩家手动确认。
- 在 Electron 启动器开启“拍卖刷新”后，可使用拍卖会“查看展品”窗口中的“免费刷新展品”按钮或快捷键；默认快捷键为 `R`，只在展品预览窗口生效，不消耗银钱且不受原版刷新次数限制。
- 可将新生成的“拍卖大会”固定为红色最高等级（难度 10）；事件难度及按等级生成的拍品会相应提高，关闭开关后恢复原版随机等级。
- 在 Electron 启动器开启“鉴宝辅助”后，使用鉴宝窗口中的“自动选择最高估价”按钮；按玩家学识决定的悬浮括号价选中最高价宝物，但仍由玩家手动确认。
- 在 Electron 启动器“成长与天赋”页面开启“刷新突破词条按钮”后，突破候选界面只显示同名按钮，不会自动刷新，也没有快捷键；保存配置后需重新启动游戏生效。
- 在 Electron 启动器“交易与制造”页面开启“刷新打造词条按钮”后，按钮只出现在普通打造或特殊强化的候选界面，不会自动打造、消耗材料，也没有快捷键；保存配置后需重新启动游戏生效。
- 在商店交易窗口上方显示“材料扫货”按钮、品级/等级下拉菜单和独立的“词条”筛选窗口。词条窗口最多保存 4 条文字条件，可选择“全部满足”或“任一满足”，并为每条条件选择“包含”或“完全匹配”；词条条件会和最低品级、最低等级同时生效。扫货只加入购物车，成交仍由玩家手动确认。
- 在官府仓库右侧物品列表的正下方居中显示“刷新”按钮；也可使用 Electron 中配置的快捷键（默认 `R`）。按钮和快捷键只在官府仓库页面生效，刷新会重建交易列表与购物车，不由模组扣除功绩。
- 在功法悬浮详情的“已习得/未习得”正下方用独立一行显示功法书拥有状态；背包、个人仓库或当前门派藏书中存在对应功法书时显示绿色“已拥有”，否则显示红色“未拥有”。
- Electron“经验与天赋”页面可开关莫高窟掌门代弟子遗忘功能；启用后，玩家担任掌门时选择“遗忘武学”或“遗忘天赋”会先选择本门弟子（也可选择自己），随后完整复用原版零重武学、永久/后置天赋、银两和闭关天数条件。关闭功能或玩家不是掌门时不会出现弟子选择，保持原版只能为自己遗忘。
- 黄鹤楼完成一次原版“物色人选”后，候选窗口会显示“刷新候选人”按钮；按钮沿用本次物色的类型、人数和等级重新生成候选，并清理被丢弃的临时候选，不重复消耗物色所需时间。候选窗口就绪时也可按默认快捷键 `R` 刷新。
- 门派、看板和官府委托各有独立开关；开启后复用原版委托刷新按钮和原版清空重建流程，但不会耗尽当月刷新次数。对应委托窗口中也可按默认快捷键 `R` 刷新；未知委托与 NPC 委托保持原版行为。
- Electron 启动器的“交易，制造类”页面提供倒宝估价、自动加购、材料扫货、店铺买断、拍卖刷新、拍卖刷新快捷键、官府仓库刷新及快捷键、拍卖会固定红色等级和鉴宝辅助的独立开关、筛选参数及使用提示；鉴宝辅助仍只通过对应的游戏内按钮触发。

## 启动日志与白屏防护

- BepInEx 控制台默认禁用。这样可避免 Windows 控制台进入“选择模式”后阻塞游戏进程并造成白屏。
- 禁用的是弹出的控制台窗口，不是日志记录；运行日志仍写入 `BepInEx/LogOutput.log`。
- Electron 启动器会在启动游戏前再次确保 `BepInEx/config/BepInEx.cfg` 中的 `[Logging.Console] Enabled` 为 `false`。

## Staged DLL 更新流程

开发构建的插件 DLL 必须先进入 `_codex_staged_updates/BepInEx/plugins`，不要直接覆盖游戏目录中的 live DLL。

- 只有同时存在匹配的 `<插件名>.dll.pending` 标记时，暂存 DLL 才会被视为待提升版本。
- 通过 `mod-prototype/LongYinModControl/LongYinModControl.ps1` 启动游戏；脚本会在启动前校验暂存文件、备份现有 live DLL，再把待更新 DLL 提升到 `BepInEx/plugins`。
- 如果检测到游戏正在运行，脚本会停止提升。禁止在游戏运行中热替换或编辑 live 插件 DLL。

## 重新安装流程

1. 先把这个仓库或它的 ZIP 备份到游戏目录外。
2. 确认备份安全后，再删除已修改过的游戏目录。
3. 重新安装一份干净的游戏。
4. 从发布包或已安装的游戏目录中运行 `Uninstall.cmd`，或使用应用内卸载。
5. 下载最新 Release ZIP，再运行一次 `LongYinProMax.exe`。
6. 后续配置与启动都通过 Electron 应用完成。

## 备注

- 这个便携包目标游戏版本为 `V1.1.0f5`。
- 安装器还会写入 `steam_appid.txt`，游戏 ID 为 `3202030`，这样在新电脑上直接启动也能正常识别 Steam。
- `mod-prototype/` 里的部分源码脚本是针对本地真实安装环境写的；如果你在另一台机器上重新编译源码，可能需要调整本地路径。
