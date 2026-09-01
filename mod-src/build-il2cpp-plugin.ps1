[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [string]$Source,

    [Parameter(Mandatory = $true)]
    [string]$LoaderRoot,

    # Compatibility output for callers that still keep an artifacts directory.
    # Compilation always lands in the staged queue first; this copy is optional.
    [string]$Output = "",

    [string]$StagedPluginOutput = "",

    [ValidateRange(6, 9)]
    [int]$RuntimeMajor = 6,

    # Kept only to fail old unsafe invocations with an actionable error.
    [string]$LivePluginOutput = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-FullPath([string]$Path, [string]$BasePath) {
    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $BasePath $Path))
}

function Assert-PathWithin([string]$Path, [string]$Parent, [string]$Label) {
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $fullParent = [System.IO.Path]::GetFullPath($Parent).TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    if (-not $fullPath.StartsWith($fullParent, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "$Label 必须位于 $fullParent 内，实际为 $fullPath。"
    }
}

function Assert-File([string]$Path, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "未找到$Label：$Path"
    }
}

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

function Find-DotnetToolchain([string]$RepositoryRoot, [string]$ResolvedLoaderRoot, [int]$RequiredRuntimeMajor) {
    $localDotnetRoot = Join-Path $RepositoryRoot ".codex-tools\dotnet"
    $dotnetCandidates = @(
        (Join-Path $localDotnetRoot "dotnet.exe")
    )

    $pathDotnet = Get-Command dotnet -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $pathDotnet) {
        $dotnetCandidates += $pathDotnet.Source
    }

    $dotnetHost = $dotnetCandidates |
        Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } |
        Select-Object -First 1
    if (-not $dotnetHost) {
        throw "未找到 dotnet 主机。请运行 scripts\restore-tools.ps1，或安装 .NET SDK。"
    }

    $compilerCandidates = @(
        (Join-Path $ResolvedLoaderRoot ".codex-temp\compilers\tasks\netcore\bincore\csc.dll")
    )

    $localSdkRoot = Join-Path $localDotnetRoot "sdk"
    if (Test-Path -LiteralPath $localSdkRoot -PathType Container) {
        $compilerCandidates += Get-ChildItem -LiteralPath $localSdkRoot -Directory |
            Sort-Object { try { [version]$_.Name } catch { [version]'0.0' } } -Descending |
            ForEach-Object { Join-Path $_.FullName "Roslyn\bincore\csc.dll" }
    }

    $sdkLines = & $dotnetHost --list-sdks 2>$null
    if ($LASTEXITCODE -eq 0) {
        foreach ($line in @($sdkLines)) {
            if ($line -match '^\s*(?<version>\S+)\s+\[(?<root>.+)\]\s*$') {
                $compilerCandidates += Join-Path (Join-Path $Matches.root $Matches.version) "Roslyn\bincore\csc.dll"
            }
        }
    }

    $compiler = $compilerCandidates |
        Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } |
        Select-Object -First 1
    if (-not $compiler) {
        throw "未找到 Roslyn csc.dll。请运行 scripts\restore-tools.ps1，或安装 .NET SDK。"
    }

    $runtimeCandidates = @()
    $localRuntimeRoot = Join-Path $localDotnetRoot "shared\Microsoft.NETCore.App"
    if (Test-Path -LiteralPath $localRuntimeRoot -PathType Container) {
        $runtimeCandidates += Get-ChildItem -LiteralPath $localRuntimeRoot -Directory
    }

    $runtimeLines = & $dotnetHost --list-runtimes 2>$null
    if ($LASTEXITCODE -eq 0) {
        foreach ($line in @($runtimeLines)) {
            if ($line -match '^Microsoft\.NETCore\.App\s+(?<version>\S+)\s+\[(?<root>.+)\]\s*$') {
                $candidate = Join-Path $Matches.root $Matches.version
                if (Test-Path -LiteralPath $candidate -PathType Container) {
                    $runtimeCandidates += Get-Item -LiteralPath $candidate
                }
            }
        }
    }

    $runtimeDir = $runtimeCandidates |
        Where-Object {
            try { ([version]$_.Name).Major -eq $RequiredRuntimeMajor }
            catch { $false }
        } |
        Sort-Object { try { [version]$_.Name } catch { [version]'0.0' } } -Descending |
        Select-Object -ExpandProperty FullName -First 1
    if (-not $runtimeDir) {
        throw "未找到 Microsoft.NETCore.App $RequiredRuntimeMajor.x 运行时引用目录。"
    }

    return [pscustomobject]@{
        DotnetHost = [System.IO.Path]::GetFullPath($dotnetHost)
        Compiler   = [System.IO.Path]::GetFullPath($compiler)
        RuntimeDir = [System.IO.Path]::GetFullPath($runtimeDir)
    }
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$sourcePath = (Resolve-Path -LiteralPath $Source).Path
$loaderRootPath = (Resolve-Path -LiteralPath $LoaderRoot).Path
$bepInExRoot = Join-Path $loaderRootPath "BepInEx"
$interopDir = Join-Path $bepInExRoot "interop"
$coreDir = Join-Path $bepInExRoot "core"

if ($LivePluginOutput) {
    throw "-LivePluginOutput 已被禁用：构建脚本绝不直接写入游戏目录。请使用 mod-prototype\LongYinModControl\LongYinModControl.ps1 在游戏关闭时提升暂存 DLL。"
}

if (-not (Test-Path -LiteralPath $interopDir -PathType Container) -or
    -not (Test-Path -LiteralPath $coreDir -PathType Container)) {
    throw "LoaderRoot 必须明确指向包含 BepInEx\interop 和 BepInEx\core 的根目录：$loaderRootPath"
}

$pluginName = [System.IO.Path]::GetFileNameWithoutExtension($sourcePath)
$stagedRoot = Join-Path $repoRoot "_codex_staged_updates\BepInEx\plugins"
if (-not $StagedPluginOutput) {
    $StagedPluginOutput = Join-Path $stagedRoot "$pluginName.dll"
}
else {
    $StagedPluginOutput = Get-FullPath -Path $StagedPluginOutput -BasePath $repoRoot
}

Assert-PathWithin -Path $StagedPluginOutput -Parent $stagedRoot -Label "StagedPluginOutput"
if ([System.IO.Path]::GetExtension($StagedPluginOutput) -ne ".dll") {
    throw "StagedPluginOutput 必须是 DLL：$StagedPluginOutput"
}

if ($Output) {
    $Output = Get-FullPath -Path $Output -BasePath $repoRoot
    Assert-PathWithin -Path $Output -Parent $repoRoot -Label "兼容 Output"
    if ($Output -match '(?i)[\\/]BepInEx[\\/]plugins[\\/]') {
        throw "-Output 不能指向 BepInEx\plugins。构建产物只能通过暂存提升流程部署。"
    }
}

$toolchain = Find-DotnetToolchain `
    -RepositoryRoot $repoRoot `
    -ResolvedLoaderRoot $loaderRootPath `
    -RequiredRuntimeMajor $RuntimeMajor
$references = @(
    (Join-Path $coreDir "0Harmony.dll")
    (Join-Path $coreDir "BepInEx.Core.dll")
    (Join-Path $coreDir "BepInEx.Unity.IL2CPP.dll")
    (Join-Path $coreDir "Il2CppInterop.Common.dll")
    (Join-Path $coreDir "Il2CppInterop.Runtime.dll")
    (Join-Path $interopDir "Assembly-CSharp.dll")
    (Join-Path $interopDir "Il2Cppmscorlib.dll")
    (Join-Path $interopDir "UnityEngine.CoreModule.dll")
    (Join-Path $interopDir "UnityEngine.TextRenderingModule.dll")
    (Join-Path $interopDir "UnityEngine.UIModule.dll")
    (Join-Path $interopDir "UnityEngine.UI.dll")
    (Join-Path $interopDir "UnityEngine.IMGUIModule.dll")
    (Join-Path $interopDir "UnityEngine.InputLegacyModule.dll")
    (Join-Path $interopDir "UnityEngine.VideoModule.dll")
    (Join-Path $interopDir "Unity.TextMeshPro.dll")
    (Join-Path $toolchain.RuntimeDir "netstandard.dll")
    (Join-Path $toolchain.RuntimeDir "System.Console.dll")
    (Join-Path $toolchain.RuntimeDir "System.Collections.dll")
    (Join-Path $toolchain.RuntimeDir "System.IO.FileSystem.dll")
    (Join-Path $toolchain.RuntimeDir "System.Linq.dll")
    (Join-Path $toolchain.RuntimeDir "System.Memory.dll")
    (Join-Path $toolchain.RuntimeDir "System.Private.CoreLib.dll")
    (Join-Path $toolchain.RuntimeDir "System.Runtime.dll")
    (Join-Path $toolchain.RuntimeDir "System.Text.Json.dll")
)

foreach ($reference in $references) {
    Assert-File -Path $reference -Label "编译引用"
}

$assemblyCSharpPath = Join-Path $interopDir "Assembly-CSharp.dll"
$stageDir = Split-Path -Parent $StagedPluginOutput
$metadataPath = "$StagedPluginOutput.build.json"
$pendingPath = "$StagedPluginOutput.pending"

Write-Host "Source: $sourcePath"
Write-Host "LoaderRoot: $loaderRootPath"
Write-Host "Interop: $assemblyCSharpPath ($(Get-Sha256 $assemblyCSharpPath))"
Write-Host "Staged DLL: $StagedPluginOutput"
Write-Host "Pending marker: $pendingPath"
if ($Output) {
    Write-Host "Compatibility artifact copy: $Output"
}

if ($WhatIfPreference) {
    Write-Host "WhatIf: 已验证工具链和全部引用；未编译、未写入暂存区。"
    return
}

if (-not (Test-Path -LiteralPath $stageDir -PathType Container)) {
    New-Item -ItemType Directory -Path $stageDir | Out-Null
}

# A failed rebuild must never leave the previous payload marked as pending.
Remove-Item -LiteralPath $pendingPath -Force -ErrorAction SilentlyContinue

$tempCompileDir = Join-Path $stageDir (".build-{0}" -f [guid]::NewGuid().ToString('N'))
$tempCompilePath = Join-Path $tempCompileDir ([System.IO.Path]::GetFileName($StagedPluginOutput))
try {
    New-Item -ItemType Directory -Path $tempCompileDir | Out-Null
    $referenceArgs = $references | ForEach-Object { "-r:$_" }
    & $toolchain.DotnetHost $toolchain.Compiler `
        /nologo `
        /target:library `
        /langversion:latest `
        /nullable:enable `
        /optimize+ `
        /deterministic+ `
        /debug- `
        "/out:$tempCompilePath" `
        $referenceArgs `
        $sourcePath

    if ($LASTEXITCODE -ne 0) {
        throw "编译失败，退出代码 $LASTEXITCODE。"
    }

    Assert-File -Path $tempCompilePath -Label "编译产物"
    Move-Item -LiteralPath $tempCompilePath -Destination $StagedPluginOutput -Force
}
finally {
    Remove-Item -LiteralPath $tempCompileDir -Recurse -Force -ErrorAction SilentlyContinue
}

$artifactHash = Get-Sha256 $StagedPluginOutput
$sourceHash = Get-Sha256 $sourcePath
$interopHash = Get-Sha256 $assemblyCSharpPath
$compilerHash = Get-Sha256 $toolchain.Compiler
$gitCommit = (& git -C $repoRoot rev-parse --short=12 HEAD 2>$null | Select-Object -First 1)
$gitDirty = [bool](& git -C $repoRoot status --porcelain 2>$null)

$gameExe = Join-Path $loaderRootPath "LongYinLiZhiZhuan.exe"
$targetGame = $null
if (Test-Path -LiteralPath $gameExe -PathType Leaf) {
    $gameVersion = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($gameExe).ProductVersion
    $targetGame = [ordered]@{
        Path           = $gameExe
        ProductVersion = $gameVersion
        Sha256         = Get-Sha256 $gameExe
    }
}

$metadata = [ordered]@{
    SchemaVersion = 1
    BuiltAtUtc    = [DateTime]::UtcNow.ToString("o")
    PluginName    = $pluginName
    GitCommit     = [string]$gitCommit
    GitDirty      = $gitDirty
    Source        = [ordered]@{
        Path   = $sourcePath
        Sha256 = $sourceHash
    }
    LoaderRoot    = $loaderRootPath
    Interop       = [ordered]@{
        AssemblyCSharpPath   = $assemblyCSharpPath
        AssemblyCSharpSha256 = $interopHash
    }
    Compiler      = [ordered]@{
        DotnetHost = $toolchain.DotnetHost
        Path       = $toolchain.Compiler
        Sha256     = $compilerHash
        RuntimeDir = $toolchain.RuntimeDir
        RuntimeMajor = $RuntimeMajor
    }
    TargetGame    = $targetGame
    Artifact      = [ordered]@{
        Path   = $StagedPluginOutput
        Sha256 = $artifactHash
    }
}

if ($Output) {
    $outputDir = Split-Path -Parent $Output
    if (-not (Test-Path -LiteralPath $outputDir -PathType Container)) {
        New-Item -ItemType Directory -Path $outputDir | Out-Null
    }
    Copy-Item -LiteralPath $StagedPluginOutput -Destination $Output -Force
    if ((Get-Sha256 $Output) -ne $artifactHash) {
        throw "兼容 Output 副本哈希校验失败：$Output"
    }
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$metadataJson = $metadata | ConvertTo-Json -Depth 8
[System.IO.File]::WriteAllText($metadataPath, $metadataJson, $utf8NoBom)

# The marker is written last. Its presence is the sole definition of a pending DLL.
$pendingMarker = [ordered]@{
    SchemaVersion  = 1
    PluginName     = $pluginName
    ArtifactSha256 = $artifactHash
    MetadataFile   = [System.IO.Path]::GetFileName($metadataPath)
    CreatedAtUtc   = [DateTime]::UtcNow.ToString("o")
} | ConvertTo-Json -Depth 4
[System.IO.File]::WriteAllText($pendingPath, $pendingMarker, $utf8NoBom)

Write-Host "Built and staged: $StagedPluginOutput"
Write-Host "SHA256: $artifactHash"
Write-Host "Metadata: $metadataPath"
Write-Host "Pending: $pendingPath"

[pscustomobject]@{
    StagedPluginOutput = $StagedPluginOutput
    PendingPath        = $pendingPath
    MetadataPath       = $metadataPath
    ArtifactSha256     = $artifactHash
    SourceSha256       = $sourceHash
    InteropSha256      = $interopHash
}
