# Project Instructions

## Repository Baseline

- `origin/main` is the only integration trunk and must remain buildable and releasable.
- A release source is a commit on `origin/main` referenced by an annotated `vX.Y.Z` tag.
- The latest commit on `main` may be newer than the latest published version; the latest stable tag identifies what users receive.
- Existing historical branches are not rewritten solely to satisfy new naming rules. The rules below apply to new branches.
- Do not introduce a long-lived `develop` branch or a permanent `release` branch.

## Short-Lived Branch Workflow

- Create short-lived branches using `<type>/<short-topic>` names such as:
  - `feature/github-release`
  - `fix/ota-manifest-selection`
  - `chore/release-0.1.51`
  - `docs/release-workflow`
- Branch names must describe the work. Do not prefix them with an agent, model, author, username, machine, or tool name.
- Merge short-lived branches into `main` through a pull request after required CI checks pass.
- Prefer squash merge for ordinary feature, fix, documentation, and maintenance pull requests.
- Delete short-lived branches after they are fully merged.
- Use a dedicated `sync/<topic>` branch when importing upstream changes; never merge upstream changes directly into `main` without CI and review.

## Source and Artifact Boundary

- The canonical GitHub repository slug is `longyin-pro-max`; repository URLs and OTA API endpoints must use that slug.
- Preserve legacy runtime compatibility identifiers such as `com.zhihong.longyinplus`, `.longyin-plus`, `longyin-plus-update`, and `LongYinPlus-InstallBundle-*` unless a dedicated migration supports existing installations and rollback data.
- `dist/` is intentionally tracked as the current portable payload baseline and build input. Do not remove it as part of unrelated release work.
- Rebuild first-party plugin DLLs from source and verify that the staged DLL, tracked payload DLL, and DLL inside the final ZIP have the same SHA-256.
- Do not commit generated Electron outputs from `electron-app/release/`, `electron-app/updater-dist/`, or `electron-app/dist/`.
- GitHub Actions artifacts are short-lived CI outputs. GitHub Release assets are the stable user download and OTA source.

## CI and Release Workflow

- Repository automation requires PowerShell 7 and must invoke scripts with `pwsh`; do not run UTF-8 automation through Windows PowerShell 5.1.
- Pull requests targeting `main` and pushes to `main` run `.github/workflows/ci.yml`.
- Only a pushed stable tag matching `vX.Y.Z` triggers `.github/workflows/release.yml`.
- The release workflow must reject a tag when:
  - its commit is not part of `origin/main`
  - the tag, `package.json`, or `package-lock.json` versions differ
  - the expected ZIP or `update-manifest.json` is missing
  - the manifest asset name or SHA-256 differs from the ZIP
  - a maintained plugin or interop DLL does not match the verified build provenance
- GitHub Actions is the only writer for Release creation and Release assets. Local scripts must not create, delete, replace, or upload Release assets.
- Never replace assets on a published version. Fixes require a higher version and a new tag.
- Use `scripts/build-and-verify-release.ps1` for the shared local/CI build gate.
- Use `scripts/prepare-release.ps1` only from a clean, synchronized `main` to prepare or push a release tag.
- Before preparing a release, inspect `git status`, recent `git log`, `git diff --stat`, and the diff from the previous stable tag when one exists.
- GitHub Release body is the canonical OTA update history shown by the Electron app.
- Keep `README.md` concise and written for ordinary Release users. Installation, download, update, uninstall, and common troubleshooting come first; move exhaustive feature and contributor detail to linked documents.
- `CHANGELOG.md` is the only repository authoring source for Release notes. Maintain one exact `## vX.Y.Z` section per published version and an optional `## Unreleased` section for pending user-visible changes.
- A GitHub Release body contains only the user-visible changes for that version, extracted from the matching `CHANGELOG.md` section. Do not append download instructions, CI evidence, internal implementation notes, or the full project history.
- Do not create root-level `release-notes-v*.md` files. Historical release-note files have been consolidated into `CHANGELOG.md`.
- A published tag and its binary assets are immutable. A body-only correction may edit an existing GitHub Release description only when the user explicitly requests it, the corrected body matches that version's `CHANGELOG.md` section, and it only fixes wording or removes unrelated text without claiming new code. Code or asset changes always require a higher version and a new tag.

## Staged DLL Workflow

- Queue rebuilt plugin DLLs under `_codex_staged_updates\BepInEx\plugins`.
- Treat a DLL as pending only when a matching `*.pending` marker exists.
- Promote staged DLLs only from `mod-prototype\LongYinModControl\LongYinModControl.ps1` before launching the game.
- Back up live plugin DLLs before overwriting them.
- Never hot-swap or edit live plugin DLLs while the game is running.
- `_codex_staged_updates` is an established runtime protocol name; the no-agent-name branch rule does not rename this directory.

## Local Game Folder

- Treat a detected game installation as a local test target only, never as the source for commits, tags, builds, or OTA assets.
- Do not require a specific drive letter, user profile, absolute checkout path, or local game path.
- Local game verification may supplement CI, but it does not replace the tag build and Release asset verification performed by GitHub Actions.
