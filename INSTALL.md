# 龙胤立志传 Pro Max 安装说明

适用游戏版本：`V1.1.0f5`

## 安装

1. **完全关闭游戏。**不要在游戏运行时安装、更新或替换 DLL。
2. 从 [GitHub Releases](https://github.com/Herbert-Zheng/longyin-pro-max/releases/latest) 下载 `LongYinProMaxApp-<版本>-win-x64.zip`。
3. 把 ZIP 解压到游戏目录以外的任意文件夹。
4. 确认解压目录中能看到 `LongYinProMax.exe`、`resources/` 等文件；不要只复制 EXE。
5. 运行 `LongYinProMax.exe`。
6. 让启动器自动识别游戏，或选择包含 `LongYinLiZhiZhuan.exe` 的游戏目录。
7. 调整需要的功能，点击“保存并启动”。

正式 ZIP 是完整的便携启动器，内置模组载荷位于 `resources/payload`。启动器会把载荷安装到所选游戏目录；不要把整个 Release ZIP 解压到游戏根目录。

## 后续使用

- 继续运行解压目录中的 `LongYinProMax.exe` 来修改配置或启动游戏。
- 启动器可检查并安装最新稳定版本。
- 更新会保留启动器设置和游戏目录中的模组配置。
- 移动启动器目录时，请移动整个解压目录，不要只移动 EXE。

## 卸载或重装

1. 完全关闭游戏。
2. 使用启动器中的卸载功能；也可运行已安装到游戏目录的 `Uninstall.cmd`。
3. 如需重装，重新运行启动器并选择同一游戏目录。

## 故障排查

### 启动器打不开

- 确认 ZIP 已完整解压，不要直接在压缩软件中运行。
- 确认 `LongYinProMax.exe` 和 `resources/` 仍在同一解压目录。
- 本项目当前没有代码签名；请先确认文件来自本仓库的正式 Release。

### 游戏能启动，但模组没有生效

- 在启动器中重新确认游戏目录，并查看“安装体检”。
- 游戏根目录应包含 `BepInEx/`、`winhttp.dll` 和 `doorstop_config.ini`。
- 日志位于 `BepInEx/LogOutput.log`。

### 没有 BepInEx 控制台窗口

这是正常设置。控制台默认关闭以避免阻塞游戏，磁盘日志不受影响。

## 高级：手动安装载荷

仅在启动器安装不可用时，完全关闭游戏，再把 `resources/payload/` **里面的内容**复制到游戏根目录。不要复制 `payload` 文件夹本身，也不要在游戏运行时替换 DLL。
