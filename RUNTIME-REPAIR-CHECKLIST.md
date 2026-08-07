# 龙胤立志传 Pro Max 运行时修复 Checklist

目标分支：`codex/fix-runtime-compatibility`

目标运行基线：当前本机游戏 `V1.1.0f5`。旧版 `1.071F` 只能作为独立兼容目标，不能与当前 interop、DLL 或发布产物混用。

## 调试反馈回路

- [x] 建立快速兼容性检查：`scripts/check-runtime-compatibility.ps1`。
- [x] 在修复前连续两次复现红灯：静态 `heroTagDataBase` accessor 引用可稳定触发检查失败。
- [x] 插件修改后运行 `scripts/check-runtime-compatibility.ps1 -SkipRuntimeLog` 变绿。
- [x] staged DLL 实机启动后，用最新 `BepInEx/LogOutput.log` 运行完整检查变绿。

## P0 — 版本、构建与部署一致性

- [x] 构建时显式指定目标 BepInEx/interop 根目录，不再静默使用硬编码旧环境。
- [x] 构建前记录目标 `Assembly-CSharp.dll`、插件源码和产物 SHA-256。
- [x] 为插件构建写入可追踪的版本、Git 提交和 interop 指纹。
- [x] 提升前将 staged metadata 的 interop 指纹绑定到目标 `GameRoot` 的 live `Assembly-CSharp.dll`，并在每次覆盖前复检；缺失或不一致时 fail-closed。
- [x] 插件构建只能写入 `_codex_staged_updates\BepInEx\plugins`，并创建匹配的 `*.pending` 标记。
- [x] 禁止构建脚本直接热替换正在运行游戏中的 DLL。
- [x] 启动游戏前备份 live DLL，再提升已带 pending 标记的 staged DLL。
- [x] 校验仓库产物、`dist`、OTA ZIP 和 live DLL 的哈希一致性。

## P0 — Mod 运行时兼容

- [x] 移除对可能不存在的 `GameDataController.heroTagDataBase` 的静态调用依赖。
- [x] 为自定义天赋和阈值天赋增加运行时能力检测与安全降级。
- [x] 重新定位或兼容 `BattleController.HeroEnterBattleFieldCoroutine` 的当前签名。
- [x] 重新定位或兼容 `HeroData.RefreshHorseState` 的当前签名。
- [x] 检查 `MaxLoverNum`、`correctTreasure`、`MailData` 等 IL2CPP 特殊目标并避免无效补丁。
- [x] 启动日志输出每个可选子功能的启用、降级或不兼容状态。
- [x] 恢复或定位其余五个二进制插件的源码；已恢复 BattleTurbo、HorseStaminaMultiplier、SkipIntro，`LongYinQuestSnapshot.dll` 与 `LongYinSkillTalentGrant.dll` 明确列为仅有二进制、当前不可维护。

## P1 — Electron 安装、卸载与健康检查安全

- [x] 安装、卸载、修复和载荷覆盖统一拒绝在游戏运行时执行。
- [x] 卸载改为删除本项目拥有的文件，不再递归删除整个 `BepInEx`。
- [x] 为被覆盖文件建立安装清单和可恢复备份。
- [x] payload 安装/升级使用整批快照事务与原子 manifest 替换；复制、清理或 manifest 写入失败时恢复安装前状态。
- [x] 将只读状态检查与 `ensure/repair` 写操作分离。
- [x] 快照和设置读取不得删除文件、改写 Doorstop 或重建 Steam AppId。
- [x] 健康检查报告 payload/live DLL 哈希漂移。
- [x] 健康检查识别 BepInEx 日志中的插件异常和 Harmony 目标缺失。
- [x] 初始快照失败时前端显示可操作的错误状态。
- [x] 有未保存普通设置或自定义天赋时，启动前通过原子“保存并启动”统一写入；写入前再次确认游戏停止，任一配置保存失败时回滚两者。

## P1 — OTA 与更新器稳健性

- [x] OTA 下载直接使用 GitHub Release 返回的资产 URL。
- [x] 网络下载增加超时和最大下载大小。
- [x] ZIP 解压执行规范化后的目标路径包含性检查和展开大小限制。
- [x] 更新替换前创建回滚备份；失败时恢复原文件并验证恢复哈希。
- [x] 更新器等待旧进程时 fail-closed：仅 PID 明确不存在或已退出才继续，并校验 PID 对应目标可执行文件。
- [x] Electron 等待 updater 的 `spawn/error` 握手成功后才退出，不再把启动失败误报为已交接。
- [x] 更新完成后验证下载 ZIP 与被替换文件的哈希。
- [x] 更新状态覆盖 `complete`，重启后的完成哨兵避免退出时序吞掉 Renderer 最终状态。
- [x] 发布脚本拒绝 interop、dist、ZIP 或版本元数据不一致的产物。

## P2 — Overlay 与操作体验

- [x] Electron 提供 Overlay 启动/关闭入口，并可在游戏启动时按设置托管其生命周期。
- [x] 防止 Overlay 多实例；即使先关闭启动器窗口，主进程仍会监视游戏退出、关闭自启 Overlay 后再退出。
- [x] “保存并启动”同时处理普通设置与自定义天赋。
- [x] 不兼容的玩法选项不作为可操作控件暴露，并在健康页说明原因；当前不可补丁的寻宝高亮未出现在 Electron 设置中且插件默认关闭。

## 验证门槛

- [x] Electron `npm run typecheck` 通过。
- [x] Electron `npm run build` 通过，ZIP 与 manifest 校验通过。
- [x] .NET Updater 和 Overlay 构建通过。
- [x] `LongYinProMax` 使用目标 interop 构建通过。
- [x] staged DLL 提升流程验证：pending、备份、提升、哈希检查全部通过。
- [x] staged DLL 负向验证：目标 interop 缺失或哈希不一致时 live DLL 不变且 pending 保留。
- [x] 游戏启动到主菜单，BepInEx 完成加载且没有未处理异常。
- [x] 日志中没有目标方法缺失警告；有意降级的功能输出了明确兼容状态。
- [ ] 至少验证：跳过开场、探索体力、坐骑、战斗 Turbo、自定义/阈值天赋安全降级。已实测跳过开场和 BattleTurbo 开关；探索/坐骑补丁注册与自定义/阈值安全降级已由日志确认，但未执行会改动存档的完整探索和骑乘场景。
- [x] 游戏关闭后工作树、live DLL 和 staged 状态均已核对；四个维护插件的 live/staged/dist SHA-256 一致且无 pending 标记。
- [x] 打包启动器真实 E2E：原子“保存并启动”成功，先关闭 launcher 窗口后后台继续监视，游戏退出后 Overlay 与 launcher 均自动退出。

## 当前剩余项

- `LongYinQuestSnapshot.dll`、`LongYinSkillTalentGrant.dll` 尚无可维护源码。
- 若未来把更多动态兼容功能暴露为控件，需要同步增加逐项能力状态，而不是仅依赖健康页摘要。
- 为避免污染个人存档，本轮没有执行探索消耗、骑乘耐力等会改变游戏状态的完整场景测试。
- updater 已验证启动失败的 `error` 握手；尚未实现“子进程已触发 `spawn` 但立即崩溃”的独立 readiness ACK，属于低风险后续加固项。
