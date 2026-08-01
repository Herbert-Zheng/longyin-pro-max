[CmdletBinding()]
param(
    [string]$RepoRoot = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-Sha256([string]$Path) {
    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try {
            return ([System.BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '').ToLowerInvariant()
        }
        finally {
            $sha.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }
}

function Assert-Equal($Expected, $Actual, [string]$Label) {
    if ($Expected -ne $Actual) {
        throw "$Label 断言失败：expected=$Expected, actual=$Actual"
    }
}

if (-not $RepoRoot) {
    $RepoRoot = Join-Path $PSScriptRoot ".."
}
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$controlScript = Join-Path $RepoRoot "mod-prototype\LongYinModControl\LongYinModControl.ps1"
if (-not (Test-Path -LiteralPath $controlScript -PathType Leaf)) {
    throw "未找到 DLL 提升脚本：$controlScript"
}

$tempRoot = Join-Path $RepoRoot ".codex-temp"
$testRoot = Join-Path $tempRoot ("staged-workflow-test-" + [guid]::NewGuid().ToString("N"))
$fakeRepo = Join-Path $testRoot "repo"
$fakeGame = Join-Path $testRoot "game"
$stageRoot = Join-Path $fakeRepo "_codex_staged_updates\BepInEx\plugins"
$liveRoot = Join-Path $fakeGame "BepInEx\plugins"
$interopRoot = Join-Path $fakeGame "BepInEx\interop"
$liveInterop = Join-Path $interopRoot "Assembly-CSharp.dll"
$stagedDll = Join-Path $stageRoot "WorkflowProbe.dll"
$pendingMarker = "$stagedDll.pending"
$metadataPath = "$stagedDll.build.json"
$liveDll = Join-Path $liveRoot "WorkflowProbe.dll"
$fakeGameExe = Join-Path $fakeGame "WorkflowProbeGame.exe"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$fakeGameProcess = $null

try {
    New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $liveRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $interopRoot -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $PSHOME "powershell.exe") -Destination $fakeGameExe -Force

    [System.IO.File]::WriteAllText($liveDll, "old-live-payload", $utf8NoBom)
    [System.IO.File]::WriteAllText($liveInterop, "matching-interop-payload", $utf8NoBom)
    [System.IO.File]::WriteAllText($stagedDll, "new-staged-payload", $utf8NoBom)
    $oldHash = Get-Sha256 $liveDll
    $interopHash = Get-Sha256 $liveInterop
    $gameHash = Get-Sha256 $fakeGameExe
    $gameVersion = [string]([System.Diagnostics.FileVersionInfo]::GetVersionInfo($fakeGameExe).ProductVersion)
    $newHash = Get-Sha256 $stagedDll
    $marker = [ordered]@{
        SchemaVersion  = 1
        PluginName     = "WorkflowProbe"
        ArtifactSha256 = $newHash
        MetadataFile   = [System.IO.Path]::GetFileName($metadataPath)
        CreatedAtUtc   = [DateTime]::UtcNow.ToString("o")
    } | ConvertTo-Json
    $metadata = [ordered]@{
        SchemaVersion = 1
        PluginName = "WorkflowProbe"
        Artifact = [ordered]@{ Sha256 = $newHash }
        Interop = [ordered]@{ AssemblyCSharpSha256 = $interopHash }
        TargetGame = [ordered]@{ Sha256 = $gameHash; ProductVersion = $gameVersion }
    } | ConvertTo-Json -Depth 4
    [System.IO.File]::WriteAllText($metadataPath, $metadata, $utf8NoBom)
    [System.IO.File]::WriteAllText($pendingMarker, $marker, $utf8NoBom)

    & $controlScript `
        -RepoRoot $fakeRepo `
        -GameRoot $fakeGame `
        -GameExecutable "WorkflowProbeGame.exe" `
        -SkipLaunch

    Assert-Equal -Expected $newHash -Actual (Get-Sha256 $liveDll) -Label "提升后的 live DLL"
    Assert-Equal -Expected $false -Actual (Test-Path -LiteralPath $pendingMarker) -Label "成功后 pending 标记"
    Assert-Equal -Expected $true -Actual (Test-Path -LiteralPath $stagedDll -PathType Leaf) -Label "可追溯的暂存 DLL"

    $backupDll = Get-ChildItem -LiteralPath (Join-Path $fakeGame "_codex_plugin_backups") -File -Filter "WorkflowProbe.dll" -Recurse | Select-Object -First 1
    if ($null -eq $backupDll) {
        throw "未生成 live DLL 备份。"
    }
    Assert-Equal -Expected $oldHash -Actual (Get-Sha256 $backupDll.FullName) -Label "备份 DLL"

    # A second queued payload under -WhatIf must not modify live state or consume
    # the marker. This is the non-destructive operator validation path.
    [System.IO.File]::WriteAllText($stagedDll, "whatif-staged-payload", $utf8NoBom)
    $whatIfHash = Get-Sha256 $stagedDll
    $whatIfMarker = [ordered]@{
        SchemaVersion  = 1
        PluginName     = "WorkflowProbe"
        ArtifactSha256 = $whatIfHash
        MetadataFile   = [System.IO.Path]::GetFileName($metadataPath)
        CreatedAtUtc   = [DateTime]::UtcNow.ToString("o")
    } | ConvertTo-Json
    $whatIfMetadata = [ordered]@{
        SchemaVersion = 1
        PluginName = "WorkflowProbe"
        Artifact = [ordered]@{ Sha256 = $whatIfHash }
        Interop = [ordered]@{ AssemblyCSharpSha256 = $interopHash }
        TargetGame = [ordered]@{ Sha256 = $gameHash; ProductVersion = $gameVersion }
    } | ConvertTo-Json -Depth 4
    [System.IO.File]::WriteAllText($metadataPath, $whatIfMetadata, $utf8NoBom)
    [System.IO.File]::WriteAllText($pendingMarker, $whatIfMarker, $utf8NoBom)

    & $controlScript `
        -RepoRoot $fakeRepo `
        -GameRoot $fakeGame `
        -GameExecutable "WorkflowProbeGame.exe" `
        -SkipLaunch `
        -WhatIf

    Assert-Equal -Expected $newHash -Actual (Get-Sha256 $liveDll) -Label "WhatIf live DLL"
    Assert-Equal -Expected $true -Actual (Test-Path -LiteralPath $pendingMarker -PathType Leaf) -Label "WhatIf pending 标记"

    # A truncated marker must never authorize promotion.
    [System.IO.File]::WriteAllText($pendingMarker, "", $utf8NoBom)
    $emptyMarkerBlocked = $false
    try {
        & $controlScript `
            -RepoRoot $fakeRepo `
            -GameRoot $fakeGame `
            -GameExecutable "WorkflowProbeGame.exe" `
            -SkipLaunch
    }
    catch {
        if ($_.Exception.Message -like '*pending 标记为空*') {
            $emptyMarkerBlocked = $true
        }
        else {
            throw
        }
    }
    Assert-Equal -Expected $true -Actual $emptyMarkerBlocked -Label "空 pending 标记拒绝"
    Assert-Equal -Expected $newHash -Actual (Get-Sha256 $liveDll) -Label "空 marker 后 live DLL"
    [System.IO.File]::WriteAllText($pendingMarker, $whatIfMarker, $utf8NoBom)

    # A wrong target root is rejected before any DLL is touched, including in
    # -SkipLaunch mode.
    $invalidGame = Join-Path $testRoot 'invalid-game'
    $invalidLiveRoot = Join-Path $invalidGame 'BepInEx\plugins'
    $invalidLiveDll = Join-Path $invalidLiveRoot 'WorkflowProbe.dll'
    New-Item -ItemType Directory -Path $invalidLiveRoot -Force | Out-Null
    [System.IO.File]::WriteAllText($invalidLiveDll, 'invalid-root-old', $utf8NoBom)
    $invalidRootHash = Get-Sha256 $invalidLiveDll
    $invalidRootBlocked = $false
    try {
        & $controlScript `
            -RepoRoot $fakeRepo `
            -GameRoot $invalidGame `
            -GameExecutable 'MissingGame.exe' `
            -SkipLaunch
    }
    catch {
        if ($_.Exception.Message -like '*游戏可执行文件*') {
            $invalidRootBlocked = $true
        }
        else {
            throw
        }
    }
    Assert-Equal -Expected $true -Actual $invalidRootBlocked -Label "错误 GameRoot 拒绝"
    Assert-Equal -Expected $invalidRootHash -Actual (Get-Sha256 $invalidLiveDll) -Label "错误 GameRoot 未改写 live DLL"

    # Promotion metadata is bound to the target GameRoot's live interop. A
    # missing interop must fail closed before touching the live plugin.
    Remove-Item -LiteralPath $liveInterop -Force
    $missingInteropBlocked = $false
    try {
        & $controlScript `
            -RepoRoot $fakeRepo `
            -GameRoot $fakeGame `
            -GameExecutable "WorkflowProbeGame.exe" `
            -SkipLaunch
    }
    catch {
        if ($_.Exception.Message -like '*目标游戏 interop Assembly-CSharp.dll*') {
            $missingInteropBlocked = $true
        }
        else {
            throw
        }
    }
    Assert-Equal -Expected $true -Actual $missingInteropBlocked -Label "缺失 interop 拒绝"
    Assert-Equal -Expected $newHash -Actual (Get-Sha256 $liveDll) -Label "缺失 interop 后 live DLL"
    Assert-Equal -Expected $true -Actual (Test-Path -LiteralPath $pendingMarker -PathType Leaf) -Label "缺失 interop pending 标记"

    # A well-formed but different interop hash must also fail closed.
    [System.IO.File]::WriteAllText($liveInterop, "mismatched-interop-payload", $utf8NoBom)
    $mismatchedInteropBlocked = $false
    try {
        & $controlScript `
            -RepoRoot $fakeRepo `
            -GameRoot $fakeGame `
            -GameExecutable "WorkflowProbeGame.exe" `
            -SkipLaunch
    }
    catch {
        if ($_.Exception.Message -like '*interop SHA-256 与目标游戏不一致*') {
            $mismatchedInteropBlocked = $true
        }
        else {
            throw
        }
    }
    Assert-Equal -Expected $true -Actual $mismatchedInteropBlocked -Label "interop hash mismatch 拒绝"
    Assert-Equal -Expected $newHash -Actual (Get-Sha256 $liveDll) -Label "interop mismatch 后 live DLL"
    Assert-Equal -Expected $true -Actual (Test-Path -LiteralPath $pendingMarker -PathType Leaf) -Label "interop mismatch pending 标记"
    [System.IO.File]::WriteAllText($liveInterop, "matching-interop-payload", $utf8NoBom)
    Assert-Equal -Expected $interopHash -Actual (Get-Sha256 $liveInterop) -Label "恢复匹配 interop"

    # A process whose executable is the configured game path must block even a
    # -SkipLaunch promotion. The test uses a temporary PowerShell host copy, not
    # the real game.
    $fakeGameProcess = Start-Process `
        -FilePath $fakeGameExe `
        -ArgumentList @('-NoProfile', '-Command', 'Start-Sleep -Seconds 30') `
        -WindowStyle Hidden `
        -PassThru
    Start-Sleep -Milliseconds 250

    $blocked = $false
    try {
        & $controlScript `
            -RepoRoot $fakeRepo `
            -GameRoot $fakeGame `
            -GameExecutable "WorkflowProbeGame.exe" `
            -SkipLaunch
    }
    catch {
        if ($_.Exception.Message -like '*游戏正在运行*') {
            $blocked = $true
        }
        else {
            throw
        }
    }
    Assert-Equal -Expected $true -Actual $blocked -Label "运行中禁止热替换"
    Assert-Equal -Expected $newHash -Actual (Get-Sha256 $liveDll) -Label "运行中 live DLL"
    Assert-Equal -Expected $true -Actual (Test-Path -LiteralPath $pendingMarker -PathType Leaf) -Label "运行中 pending 标记"

    Write-Host "PASS: staged promotion, backup, hashes, interop binding, pending semantics, WhatIf isolation, and running-game guard."
}
finally {
    if ($null -ne $fakeGameProcess) {
        Stop-Process -Id $fakeGameProcess.Id -Force -ErrorAction SilentlyContinue
        Wait-Process -Id $fakeGameProcess.Id -Timeout 5 -ErrorAction SilentlyContinue
    }
    $resolvedTempRoot = [System.IO.Path]::GetFullPath($tempRoot).TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    $resolvedTestRoot = [System.IO.Path]::GetFullPath($testRoot)
    if ($resolvedTestRoot.StartsWith($resolvedTempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
