龙胤立志传 Pro Max 0.1.14

- 新增 `战斗武学经验倍率`，可统一放大战斗内通过出招获得的武学经验，敌我双方都会生效。
- 启动器设置页已同步新增 `战斗武学经验倍率`，保存后会写入 `Battle -> SkillExpMultiplier`。
- 新增战斗武学经验追踪日志，开启 `TracerEnabled` 与 `TraceBattleSkillExp` 后，可在 BepInEx 日志中看到 `baseExp`、`finalExp` 与倍率。
- 延续本版的伴侣上限调整，启动器仍可配置 `伴侣上限`。
- 随包插件更新到 `LongYin Stamina Lock v1.27.18`。

建议这版重点验证：
- 启动器设置页能看到并保存 `战斗武学经验倍率`
- `BepInEx/config/codex.longyin.staminalock.cfg` 中存在 `SkillExpMultiplier = ...`
- 把倍率设为大于 `1` 后，战斗日志中的 `finalExp` 明显大于 `baseExp`
- `伴侣上限` 设置仍可正常保存和生效
