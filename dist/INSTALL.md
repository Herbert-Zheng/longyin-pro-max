# 龙胤立志传 Pro Max 安装说明

适用游戏版本：`V1.1.0f5`

## 安装

1. **完全关闭游戏。**不要在游戏运行时安装、更新或替换 DLL。
2. 从 [GitHub Releases](https://github.com/Herbert-Zheng/longyin-pro-max/releases/latest) 下载 `LongYinProMaxSetup-<版本>-win-x64.exe`。
3. 运行安装器，并按提示完成安装。
4. 从桌面或开始菜单打开“龙胤立志传 Pro Max”。
5. 让启动器自动识别游戏，或选择包含 `LongYinLiZhiZhuan.exe` 的游戏目录。
6. 调整需要的功能，点击“保存并启动”。

普通用户无需下载 Release 中的 ZIP 或 `update-manifest.json`；它们是启动器 OTA 更新使用的资产。启动器会把内置模组载荷安装到所选游戏目录。

## 后续使用

- 继续从桌面或开始菜单打开启动器来修改配置或启动游戏。
- 启动器可检查并安装最新稳定版本。
- 更新会保留启动器设置和游戏目录中的模组配置。
- 如需更改安装位置，请重新运行安装器并选择目标目录。

## 卸载或重装

1. 完全关闭游戏。
2. 使用启动器中的卸载功能移除游戏模组；也可运行游戏目录中的 `Uninstall.cmd`。
3. 如需移除启动器本身，请在 Windows“已安装的应用”中卸载“龙胤立志传 Pro Max”。
4. 如需重装模组，重新运行启动器并选择同一游戏目录。

## 故障排查

### 启动器打不开

- 确认下载的是正式 Release 中的 `LongYinProMaxSetup-<版本>-win-x64.exe`，而不是 OTA ZIP 或 manifest。
- 在安装器文件属性的“数字签名”页检查签名是否有效；新的正式发布流程会拒绝未签名安装器，旧版本不具备这一保证。
- 如 Windows Defender 明确报告了威胁名称或隔离记录，请不要绕过提示，保留告警详情并向项目反馈。

### 游戏能启动，但模组没有生效

- 在启动器中重新确认游戏目录，并查看“安装体检”。
- 游戏根目录应包含 `BepInEx/`、`winhttp.dll` 和 `doorstop_config.ini`。
- 日志位于 `BepInEx/LogOutput.log`。

### 没有 BepInEx 控制台窗口

这是正常设置。控制台默认关闭以避免阻塞游戏，磁盘日志不受影响。

## 高级：手动安装载荷

仅在启动器安装不可用时，完全关闭游戏，再把 `resources/payload/` **里面的内容**复制到游戏根目录。不要复制 `payload` 文件夹本身，也不要在游戏运行时替换 DLL。
