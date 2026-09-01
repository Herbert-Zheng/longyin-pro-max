# 龙胤立志传 Pro Max：GitHub Flow、Release 与 OTA

本文档是仓库开发、CI、正式 Release 和 OTA 的可执行流程。长期约束同时记录在 `AGENTS.md`，后续维护者和 Agent 必须遵守。

## 术语

- **主干 `main`**：唯一集成分支，始终保持可构建、可发布。
- **短期分支**：承载一个明确功能、修复或维护任务，完成后通过 PR 合入 `main` 并删除。
- **发布源**：`origin/main` 上由 `vX.Y.Z` tag 指向的 commit。
- **已验证构建产物**：tag workflow 的 build job 构建并通过所有门禁的 ZIP 和 manifest。
- **Actions artifact**：job 之间传递以及短期人工下载的 CI 载体。
- **Release asset**：用户长期下载和 OTA 使用的正式资产。
- **staged DLL**：本地游戏部署队列中的 DLL，不是 Actions artifact。

## 分支策略

新分支使用内容型名称：

```text
feature/<short-topic>
fix/<short-topic>
chore/<short-topic>
docs/<short-topic>
sync/<short-topic>
```

示例：

```text
feature/github-release
fix/ota-manifest-selection
chore/release-0.1.51
docs/release-workflow
```

分支名不得包含 Agent、模型、作者、用户名、机器名或工具名。已有历史分支不为满足新规则而重写；规则从新分支开始生效。

日常变更流程：

```text
main
  -> 短期分支
  -> push / Pull Request
  -> CI
  -> squash merge
  -> main
  -> 删除短期分支
```

本仓库不使用长期 `develop` 或永久 `release` 分支。最新稳定 tag 表示用户实际收到的版本，因此 `main` 可以包含尚未发布、但已经通过 CI 且随时可发布的后续改动。

## 源码和二进制边界

当前 `dist/` 同时包含便携 payload、BepInEx/interop 构建输入和部分第一方 DLL，因此本阶段继续跟踪 `dist/`。

“代码与 Release 产物分离”在当前基线中的含义是：

- 不提交 `electron-app/release/` 中的 ZIP 和 manifest。
- 不提交 `electron-app/updater-dist/` 和 `electron-app/dist/`。
- GitHub Actions 从 tag 对应源码重建第一方 DLL和 Electron 包。
- 构建门禁验证 staged DLL、tracked `dist` DLL 和 ZIP 内 DLL 的 SHA-256。
- 第三方 runtime 和 interop 从 Git 移出的工作必须单独设计可重复下载、版本锁定和哈希验证，不能夹带在普通 Release 改造中。

## 日常 CI

`.github/workflows/ci.yml` 在以下事件运行：

```text
pull_request -> main
push -> main
```

CI 使用干净的 Windows runner，并执行：

1. checkout 仓库。
2. 安装 Node `22.12.0`。
3. 安装 .NET SDK `6.0.428`。
4. 在 `electron-app` 执行 `npm ci`。
5. 执行 TypeScript typecheck。
6. 执行 backend tests 和 renderer smoke harness。
7. 执行 staged DLL 和 updater rollback tests。
8. 调用 `scripts/build-and-verify-release.ps1` 完成真实打包和 OTA 校验。

PR 会完成完整构建和校验，但不保存大型 ZIP。`main` push 成功后会保存 7 天的 ZIP + manifest Actions artifact，供维护者下载检查。

## 本地构建门禁

本地使用与 CI 相同的入口：

```powershell
pwsh ./scripts/build-and-verify-release.ps1
```

该脚本会：

- 清理本次 Electron Release 输出目录。
- 重建维护中的插件 DLL 到 staged 队列。
- 同步并校验 tracked `dist` payload。
- 运行现有静态语义检查。
- 构建 Electron updater、main、renderer 和 Windows x64 ZIP。
- 按 `package.json.version` 精确生成 `update-manifest.json`。
- 验证 manifest、ZIP、SHA-256、第一方 DLL 和 interop provenance。

它不会 push、创建 tag 或修改 GitHub Release。

本地优先使用 `.codex-tools/dotnet/dotnet.exe`。该 SDK 不存在时，构建脚本允许使用 PATH 中的 .NET SDK；CI 因此不依赖未提交的本机工具目录。

## 准备正式版本

正式版本只能从干净且与 `origin/main` 完全同步的 `main` 准备。

版本准备通常通过短期分支完成：

```text
main
  -> chore/release-<version>
  -> 更新 electron-app/package.json 与 package-lock.json
  -> PR + CI
  -> squash merge 回 main
```

合入后先运行本地预检并创建本地 tag：

```powershell
pwsh ./scripts/prepare-release.ps1
```

确认 tag 后推送并触发 GitHub Release workflow：

```powershell
pwsh ./scripts/prepare-release.ps1 -SkipBuild -PushTag
```

`prepare-release.ps1` 不具备 GitHub Release 写权限。正式 ZIP 始终由 GitHub tag workflow 构建。

## 正式 Release

`.github/workflows/release.yml` 只响应 pushed `v*` tag，并进一步严格验证 `vX.Y.Z`。

build job：

1. checkout tag，完整获取 Git 历史。
2. 验证 tag commit 属于 `origin/main`。
3. 验证 tag、`package.json` 和 `package-lock.json` 版本一致。
4. 安装与 CI 相同的 Node 和 .NET。
5. 执行与 CI 相同的测试和 `build-and-verify`。
6. 上传仅包含版本 ZIP 和 `update-manifest.json` 的 Actions artifact。

publish job：

1. 下载 build job 的同一份 artifact，不重新构建。
2. 只有该 job 获得 `contents: write`。
3. 创建 draft GitHub Release。
4. 上传缺失的 ZIP 和 manifest，不使用覆盖上传。
5. 从 GitHub 重新下载资产并比较 SHA-256。
6. 资产完全匹配后发布为 latest stable Release。

Release body 使用 GitHub 自动生成的 notes 作为初稿，并继续作为 Electron OTA 显示的唯一更新历史来源。

## OTA 读取流程

Electron 应用读取：

```text
https://api.github.com/repos/Herbert-Zheng/longyin_plus/releases/latest
```

客户端随后：

1. 查找 `update-manifest.json`。
2. 比较本地版本与 manifest 版本。
3. 下载 manifest 指定的版本 ZIP。
4. 校验 ZIP SHA-256。
5. 暂存更新。
6. 重启后由 updater 完成替换和回滚保护。

draft 和 prerelease 不进入当前 stable OTA channel。

## 失败和重试

- tag/version/main ancestry 不一致：build job 失败，不创建 Release。
- 测试、构建、manifest、SHA-256 或 DLL provenance 失败：不创建 Release。
- draft 缺少资产：同一 workflow 重跑可以补上传缺失资产。
- draft 已有同名资产：必须先下载并验证与本次 build artifact 完全一致。
- 已发布 Release 资产一致：重跑只验证，不覆盖。
- 已发布 Release 缺少资产或哈希不同：失败；不得原地修补。
- 发布后发现问题：修复代码并增加版本号，创建新 tag。

禁止删除旧资产后以相同文件名重传，也禁止让本地脚本成为第二个 Release 写入者。

## 首次启用顺序

1. 将本工作流通过 PR 合入 `main`。
2. 等待新 CI 在 `main` 成功一次。
3. 在 GitHub 为 `main` 启用：禁止 force push、禁止删除、PR 合并、required CI check。
4. 准备第一个稳定版本 PR。
5. 从同步后的 `main` 创建并推送第一个 `vX.Y.Z` tag。
6. 检查 Actions build、Release 页面、ZIP、manifest 和 SHA-256。
7. 使用现有客户端验证 `releases/latest`、下载、暂存和重启替换。

远程 branch protection 必须在 CI check 首次成功后启用，避免先引用一个尚不存在的 required check 而锁死 `main`。
