# 龙胤立志传 Pro Max

适用于《龙胤立志传》`V1.1.0f5` 的模组与图形启动器。

普通用户无需额外安装运行环境。下载正式版本，运行启动器即可安装、配置、启动和更新模组。

## 下载

[下载最新稳定版](https://github.com/Herbert-Zheng/longyin-pro-max/releases/latest)

普通用户请选择 `LongYinProMaxSetup-<版本>-win-x64.exe`。ZIP 和 `update-manifest.json` 是启动器自动更新使用的资产，无需手动下载。

## 安装与启动

1. 完全关闭游戏。
2. 运行下载的安装器，并完成安装。
3. 从桌面或开始菜单打开“龙胤立志传 Pro Max”。
4. 让启动器自动识别游戏，或选择包含 `LongYinLiZhiZhuan.exe` 的目录。
5. 按需调整功能，点击“保存并启动”。

启动器会把随包模组文件安装到游戏目录。以后继续从桌面或开始菜单打开启动器即可。

详细步骤与故障排查见 [INSTALL.md](./INSTALL.md)。

## 更新

启动器可以检查并安装 GitHub Releases 中的最新稳定版本。下载完成后会校验文件完整性，并保留启动器设置和模组配置。

也可以重新下载最新版安装器并覆盖安装。

## 卸载

先完全关闭游戏。启动器内的卸载功能或游戏目录中的 `Uninstall.cmd` 用于移除模组；如需移除启动器本身，请在 Windows“已安装的应用”中卸载。

## 主要功能

- 战斗速度、体力和武学成长辅助
- 交易、藏宝阁、拍卖、鉴宝与材料筛选辅助
- 城市、门派建筑和道路批量升级
- 委托、关系、队伍与探索辅助
- 功法书持有状态、秘籍合成与弟子培养辅助
- 图形化配置、安装体检、日志查看和自动更新

完整功能与使用边界见 [docs/FEATURES.md](./docs/FEATURES.md)。

## 常见问题

**游戏启动了，但模组没有生效**

先在启动器中检查游戏路径和安装体检。运行日志位于游戏目录的 `BepInEx/LogOutput.log`。

**为什么没有 BepInEx 控制台窗口**

控制台默认关闭，以避免 Windows 控制台选择模式阻塞游戏。日志仍会正常写入磁盘。

**如何确认下载文件可信**

只从本仓库的正式 Release 下载安装器。当前安装器没有代码签名，Windows 可能显示“未知发布者”或 SmartScreen 提示；请核对 Release 页面和 `update-manifest.json` 中的文件名与 SHA-256，不要从第三方转载地址下载。

## 版本记录与开发

- 用户可读的版本变化：[CHANGELOG.md](./CHANGELOG.md)
- 开发、CI、Release 与 OTA：[OTA-WORKFLOW.md](./OTA-WORKFLOW.md)
- 贡献者和自动化约束：[AGENTS.md](./AGENTS.md)

本仓库不包含游戏本体或 Steam 管理的游戏文件。
