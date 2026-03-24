龙胤立志传 Pro Max 0.1.17

- Electron 启动器重做为左侧导航控制台，按主页、更新记录、系统更改、经验值与天赋、大地图与探索、交易与制造、聊天关系组队、战斗相关分区展示，减少所有开关堆在一页的混乱感。
- 启动器已移除两个过时开关：`TreasureChestAutoPickMostValuable` 与 `TeamStayDurationMultiplier`，保存设置时也会主动清理旧 INI 残留，避免界面和实际插件配置继续漂移。
- `LongYin Stamina Lock` 新增阈值天赋原型，可按指定属性门槛给玩家自动挂载自定义天赋效果，后续继续扩展游戏数据改造时可直接复用这条运行时注入路径。
- 伴侣回家围攻事件现已被拦截，避免情缘相关战斗在 `BattleTeamPrepare()` 阶段空引用并卡死加载；同时补齐该事件的 PrepareBattleMap / BattleTeamPrepare 追踪日志，方便后续继续深挖原版流程。
- 新增 `ABOUT-MODDING-GAME-DATA.MD` 与补充后的 `MODDING-NOTES-1.071F.md`，整理运行时修改 `HeroTagData`、`KungfuSkillData`、`PlotData` 的可行性和现有代码落点。
- 随包插件更新到 `LongYin Stamina Lock v1.29.0`。

建议这版重点验证：
- 启动器左侧新导航切页正常，保存设置、检查更新、保存并启动、启动游戏都能按预期工作。
- 旧配置文件里的 `TreasureChestAutoPickMostValuable` 与 `TeamStayDurationMultiplier` 会在保存后被清掉，不再回写。
- `ThresholdTalent` 配置段存在且可被插件读取。
- 回家触发情缘围攻时不再进入卡死战斗加载，`BepInEx/LogOutput.log` 能看到 `Blocked lover home battle`。
