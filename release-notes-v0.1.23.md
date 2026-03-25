龙胤立志传 Pro Max 0.1.23

- Electron 启动器在启动前会自动把 `LongYinQuestSnapshot` 的配置强制关掉，避免外部 quest snapshot 采集在长时间游戏时持续增加负担。
- 这次修复只动启动器侧的配置同步，不会改动游戏玩法本身。
- 仍然保留 quest snapshot 的配置文件，但启动器会确保它保持 `Enabled = false` 和 `TraceMode = false`。

建议这版重点验证：
- 从 Electron 启动游戏后，`BepInEx/config/codex.longyin.questsnapshot.cfg` 里的 `Enabled` 应保持为 `false`。
- 游戏启动后不要再看到 quest snapshot 持续刷新带来的额外 I/O 压力。
