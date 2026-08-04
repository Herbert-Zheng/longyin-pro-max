# 龙胤立志传 Pro Max Electron

这个目录包含《龙胤立志传 Pro Max》模组包的便携式 Electron 启动器和更新器。

## 功能

- 自动检测 Steam 安装目录，也可以手动选择
- 将模组配置文件保存在选定的游戏根目录中
- 在“成长与天赋”中配置默认开启的“刷新突破词条按钮”；它只控制游戏内按钮显示，不会自动刷新且没有快捷键，保存后需重启游戏生效
- 安装和卸载随包提供的 `dist/` 载荷
- 在确保 `steam_appid.txt` 和加载器设置就绪后启动游戏
- 检查 GitHub Releases 上是否有新的便携 ZIP，并准备自更新

## 构建

```bash
npm install
npm run build
```

构建会在 `release/` 中生成便携 ZIP，并在其旁边写入 `release/update-manifest.json`。

## 运行时目录

- `dist/`
  编译后的 Electron 输出
- `release/`
  打包好的 ZIP 产物以及生成的更新清单
- `user-data/`
  便携式应用设置，包括记住的游戏目录

打包后的应用会把 `../dist` 中的模组载荷作为 `payload/` 资源带上，因此安装和卸载都不需要回到仓库目录中找文件。
