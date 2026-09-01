# 龙胤立志传 Pro Max

适用于《龙胤立志传》`V1.1.0f5` 的便携模组与图形启动器。

普通用户无需额外安装运行环境。下载正式版本，运行启动器即可安装、配置、启动和更新模组。

## 下载

[下载最新稳定版](https://github.com/Herbert-Zheng/longyin-pro-max/releases/latest)

请选择 `LongYinProMaxApp-<版本>-win-x64.zip`，不要单独下载 `update-manifest.json`。

## 安装与启动

1. 完全关闭游戏。
2. 把下载的 ZIP 解压到游戏目录以外的任意文件夹。
3. 运行解压后的 `LongYinProMax.exe`。
4. 让启动器自动识别游戏，或选择包含 `LongYinLiZhiZhuan.exe` 的目录。
5. 按需调整功能，点击“保存并启动”。

启动器会把随包模组文件安装到游戏目录。以后继续使用同一个 `LongYinProMax.exe` 配置和启动游戏。

详细步骤与故障排查见 [INSTALL.md](./INSTALL.md)。

## 更新

启动器可以检查并安装 GitHub Releases 中的最新稳定版本。下载完成后会校验文件完整性，并保留启动器设置和模组配置。

也可以重新下载最新 ZIP，解压到新的文件夹后运行。

## 卸载

先完全关闭游戏，再使用启动器内的卸载功能。已安装载荷中也提供 `Uninstall.cmd`。

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

**Windows 显示安全提示**

本项目当前没有代码签名。请确认文件来自本仓库的正式 Release，再按系统提示决定是否运行。

## 版本记录与开发

- 用户可读的版本变化：[CHANGELOG.md](./CHANGELOG.md)
- 开发、CI、Release 与 OTA：[OTA-WORKFLOW.md](./OTA-WORKFLOW.md)
- 贡献者和自动化约束：[AGENTS.md](./AGENTS.md)

本仓库不包含游戏本体或 Steam 管理的游戏文件。
