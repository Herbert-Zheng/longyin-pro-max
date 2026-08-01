[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [string]$GameRoot,

    [string]$RepoRoot = "",

    [string]$GameExecutable = "LongYinLiZhiZhuan.exe",

    [switch]$SkipLaunch
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

function Assert-File([string]$Path, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "未找到$Label：$Path"
    }
}

function Get-PropertyValue($Object, [string]$Name) {
    if ($null -eq $Object -or $Object.PSObject.Properties.Name -notcontains $Name) {
        return $null
    }

    return $Object.$Name
}

function Get-RunningGameProcess([string]$ExecutablePath) {
    $processName = [System.IO.Path]::GetFileNameWithoutExtension($ExecutablePath)
    $candidates = @(Get-Process -Name $processName -ErrorAction SilentlyContinue)
    foreach ($candidate in $candidates) {
        try {
            $candidatePath = $candidate.Path
            if (-not $candidatePath) {
                return $candidate
            }
            if ([System.IO.Path]::GetFullPath($candidatePath).Equals(
                    [System.IO.Path]::GetFullPath($ExecutablePath),
                    [System.StringComparison]::OrdinalIgnoreCase)) {
                return $candidate
            }
        }
        catch {
            # If Windows withholds the path, the matching process name is enough
            # to conservatively block a DLL replacement.
            return $candidate
        }
    }

    return $null
}

if (-not $RepoRoot) {
    $RepoRoot = Join-Path $PSScriptRoot "..\.."
}

$repoRootPath = (Resolve-Path -LiteralPath $RepoRoot).Path
$gameRootPath = (Resolve-Path -LiteralPath $GameRoot).Path
$stageRoot = Join-Path $repoRootPath "_codex_staged_updates\BepInEx\plugins"
$livePluginRoot = Join-Path $gameRootPath "BepInEx\plugins"
$liveInteropPath = Join-Path $gameRootPath "BepInEx\interop\Assembly-CSharp.dll"
$gameExePath = Join-Path $gameRootPath $GameExecutable
Assert-File -Path $gameExePath -Label "游戏可执行文件"

$runningGame = Get-RunningGameProcess -ExecutablePath $gameExePath
if ($null -ne $runningGame) {
    throw "游戏正在运行（PID $($runningGame.Id)）。为避免热替换 DLL，已停止提升和启动流程。"
}

$promotionItems = @()
if (Test-Path -LiteralPath $stageRoot -PathType Container) {
    $pendingMarkers = @(Get-ChildItem -LiteralPath $stageRoot -File -Filter "*.dll.pending" | Sort-Object Name)
    foreach ($pendingMarker in $pendingMarkers) {
        $stagedDllPath = $pendingMarker.FullName.Substring(0, $pendingMarker.FullName.Length - ".pending".Length)
        Assert-File -Path $stagedDllPath -Label "pending 标记对应的暂存 DLL"

        $stagedHash = Get-Sha256 $stagedDllPath
        $markerText = Get-Content -LiteralPath $pendingMarker.FullName -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace([string]$markerText)) {
            throw "pending 标记为空，拒绝提升：$($pendingMarker.FullName)"
        }
        try {
            $marker = $markerText | ConvertFrom-Json
        }
        catch {
            throw "pending 标记不是有效 JSON：$($pendingMarker.FullName)"
        }
        if ([int](Get-PropertyValue -Object $marker -Name "SchemaVersion") -ne 1) {
            throw "pending 标记 SchemaVersion 无效：$($pendingMarker.FullName)"
        }
        $fileName = Split-Path -Leaf $stagedDllPath
        $expectedPluginName = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
        if ([string](Get-PropertyValue -Object $marker -Name "PluginName") -ne $expectedPluginName) {
            throw "pending 标记插件名与 DLL 不一致：$($pendingMarker.FullName)"
        }
        $markerHash = [string](Get-PropertyValue -Object $marker -Name "ArtifactSha256")
        if ($markerHash -notmatch '^[0-9a-fA-F]{64}$' -or $markerHash.ToLowerInvariant() -ne $stagedHash) {
            throw "pending 标记哈希缺失或与暂存 DLL 不一致：$($pendingMarker.FullName)"
        }

        $metadataFileName = [string](Get-PropertyValue -Object $marker -Name "MetadataFile")
        if (-not $metadataFileName) {
            throw "pending 标记缺少 MetadataFile：$($pendingMarker.FullName)"
        }
        if ([System.IO.Path]::GetFileName($metadataFileName) -ne $metadataFileName) {
            throw "pending 标记中的 MetadataFile 必须是同目录文件名：$metadataFileName"
        }

        $metadataPath = Join-Path $stageRoot $metadataFileName
        Assert-File -Path $metadataPath -Label "构建元数据"
        try {
            $metadata = Get-Content -LiteralPath $metadataPath -Raw -Encoding UTF8 | ConvertFrom-Json
        }
        catch {
            throw "构建元数据不是有效 JSON：$metadataPath"
        }
        if ([int](Get-PropertyValue -Object $metadata -Name "SchemaVersion") -ne 1 -or
            [string](Get-PropertyValue -Object $metadata -Name "PluginName") -ne $expectedPluginName) {
            throw "构建元数据版本或插件名无效：$metadataPath"
        }
        $metadataArtifact = Get-PropertyValue -Object $metadata -Name "Artifact"
        $metadataHash = [string](Get-PropertyValue -Object $metadataArtifact -Name "Sha256")
        if ($metadataHash -notmatch '^[0-9a-fA-F]{64}$' -or $metadataHash.ToLowerInvariant() -ne $stagedHash) {
            throw "构建元数据哈希缺失或与暂存 DLL 不一致：$metadataPath"
        }
        $metadataInterop = Get-PropertyValue -Object $metadata -Name "Interop"
        $metadataInteropHash = [string](Get-PropertyValue -Object $metadataInterop -Name "AssemblyCSharpSha256")
        if ($metadataInteropHash -notmatch '^[0-9a-fA-F]{64}$') {
            throw "构建元数据缺少有效 interop SHA-256：$metadataPath"
        }
        Assert-File -Path $liveInteropPath -Label "目标游戏 interop Assembly-CSharp.dll"
        $liveInteropHash = Get-Sha256 $liveInteropPath
        if ($metadataInteropHash.ToLowerInvariant() -ne $liveInteropHash) {
            throw "构建元数据 interop SHA-256 与目标游戏不一致：metadata=$($metadataInteropHash.ToLowerInvariant()), live=$liveInteropHash, path=$liveInteropPath"
        }

        $metadataTargetGame = Get-PropertyValue -Object $metadata -Name "TargetGame"
        if ($null -ne $metadataTargetGame) {
            $metadataGameHash = [string](Get-PropertyValue -Object $metadataTargetGame -Name "Sha256")
            if ($metadataGameHash -notmatch '^[0-9a-fA-F]{64}$') {
                throw "构建元数据 TargetGame 缺少有效 SHA-256：$metadataPath"
            }
            $liveGameHash = Get-Sha256 $gameExePath
            if ($metadataGameHash.ToLowerInvariant() -ne $liveGameHash) {
                throw "构建元数据 TargetGame SHA-256 与目标游戏不一致：metadata=$($metadataGameHash.ToLowerInvariant()), live=$liveGameHash, path=$gameExePath"
            }

            $metadataGameVersion = [string](Get-PropertyValue -Object $metadataTargetGame -Name "ProductVersion")
            if ($metadataGameVersion) {
                $liveGameVersion = [string]([System.Diagnostics.FileVersionInfo]::GetVersionInfo($gameExePath).ProductVersion)
                if ($metadataGameVersion -ne $liveGameVersion) {
                    throw "构建元数据 TargetGame ProductVersion 与目标游戏不一致：metadata=$metadataGameVersion, live=$liveGameVersion, path=$gameExePath"
                }
            }
        }

        $promotionItems += [pscustomobject]@{
            Name        = $fileName
            StagedPath  = $stagedDllPath
            PendingPath = $pendingMarker.FullName
            MetadataPath = $metadataPath
            StagedHash  = $stagedHash
            InteropHash = $liveInteropHash
            LivePath    = Join-Path $livePluginRoot $fileName
        }
    }
}

Write-Host "RepoRoot: $repoRootPath"
Write-Host "GameRoot: $gameRootPath"
Write-Host "Pending DLL count: $($promotionItems.Count)"

$promotionBatchId = "{0}-{1}" -f ([DateTime]::UtcNow.ToString("yyyyMMddTHHmmssfffZ")), ([guid]::NewGuid().ToString("N").Substring(0, 8))
$backupRoot = Join-Path $gameRootPath "_codex_plugin_backups\$promotionBatchId\BepInEx\plugins"
$receipts = @()

try {
foreach ($item in $promotionItems) {
    # Close the process-start race immediately before touching the live plugin.
    $runningGame = Get-RunningGameProcess -ExecutablePath $gameExePath
    if ($null -ne $runningGame) {
        throw "游戏在提升过程中启动（PID $($runningGame.Id)）。未继续处理 $($item.Name)。"
    }

    Assert-File -Path $liveInteropPath -Label "目标游戏 interop Assembly-CSharp.dll"
    if ((Get-Sha256 $liveInteropPath) -ne $item.InteropHash) {
        throw "目标游戏 interop 在预检后发生变化，未覆盖 live DLL：$liveInteropPath"
    }

    if (-not $PSCmdlet.ShouldProcess($item.LivePath, "备份并提升暂存 DLL $($item.Name)")) {
        continue
    }

    if (-not (Test-Path -LiteralPath $livePluginRoot -PathType Container)) {
        New-Item -ItemType Directory -Path $livePluginRoot | Out-Null
    }
    if (-not (Test-Path -LiteralPath $backupRoot -PathType Container)) {
        New-Item -ItemType Directory -Path $backupRoot | Out-Null
    }

    $liveExisted = Test-Path -LiteralPath $item.LivePath -PathType Leaf
    $previousHash = $null
    $backupPath = Join-Path $backupRoot $item.Name
    if ($liveExisted) {
        $previousHash = Get-Sha256 $item.LivePath
        Copy-Item -LiteralPath $item.LivePath -Destination $backupPath -Force
        if ((Get-Sha256 $backupPath) -ne $previousHash) {
            throw "live DLL 备份校验失败，未覆盖：$($item.LivePath)"
        }
    }

    $incomingPath = Join-Path $livePluginRoot (".{0}.{1}.incoming" -f $item.Name, [guid]::NewGuid().ToString("N"))
    try {
        Copy-Item -LiteralPath $item.StagedPath -Destination $incomingPath -Force
        if ((Get-Sha256 $incomingPath) -ne $item.StagedHash) {
            throw "临时部署副本哈希校验失败：$incomingPath"
        }

        Move-Item -LiteralPath $incomingPath -Destination $item.LivePath -Force
        if ((Get-Sha256 $item.LivePath) -ne $item.StagedHash) {
            throw "提升后的 live DLL 哈希校验失败：$($item.LivePath)"
        }

    }
    catch {
        $promotionError = $_
        Remove-Item -LiteralPath $incomingPath -Force -ErrorAction SilentlyContinue
        if ($liveExisted -and (Test-Path -LiteralPath $backupPath -PathType Leaf)) {
            Copy-Item -LiteralPath $backupPath -Destination $item.LivePath -Force
        }
        elseif (-not $liveExisted) {
            Remove-Item -LiteralPath $item.LivePath -Force -ErrorAction SilentlyContinue
        }

        throw $promotionError
    }

    $receipts += [ordered]@{
        Plugin        = $item.Name
        PromotedAtUtc = [DateTime]::UtcNow.ToString("o")
        StagedPath    = $item.StagedPath
        LivePath      = $item.LivePath
        PreviousSha256 = $previousHash
        PromotedSha256 = $item.StagedHash
        BackupPath    = if ($liveExisted) { $backupPath } else { $null }
        MetadataPath  = if (Test-Path -LiteralPath $item.MetadataPath -PathType Leaf) { $item.MetadataPath } else { $null }
        PendingPath   = $item.PendingPath
    }
    Write-Host "Promoted: $($item.Name) ($($item.StagedHash))"
}
}
catch {
    $promotionError = $_
    $batchRollbackFailures = @()
    for ($rollbackIndex = $receipts.Count - 1; $rollbackIndex -ge 0; $rollbackIndex--) {
        $previousReceipt = $receipts[$rollbackIndex]
        try {
            if ($previousReceipt.PreviousSha256) {
                Assert-File -Path $previousReceipt.BackupPath -Label "批次回滚备份"
                Copy-Item -LiteralPath $previousReceipt.BackupPath -Destination $previousReceipt.LivePath -Force
                if ((Get-Sha256 $previousReceipt.LivePath) -ne $previousReceipt.PreviousSha256) {
                    throw "恢复后哈希不一致"
                }
            }
            else {
                Remove-Item -LiteralPath $previousReceipt.LivePath -Force -ErrorAction SilentlyContinue
            }
        }
        catch {
            $batchRollbackFailures += "$($previousReceipt.Plugin): $($_.Exception.Message)"
        }
    }
    $receipts = @()
    if ($batchRollbackFailures.Count -gt 0) {
        throw "DLL 提升失败且批次回滚不完整：$($batchRollbackFailures -join ' | ')；原始错误：$($promotionError.Exception.Message)"
    }
    throw $promotionError
}

if ($receipts.Count -gt 0) {
    # The full batch is live and verified. Pending markers are consumed only
    # after every selected DLL has promoted successfully.
    foreach ($receipt in $receipts) {
        Remove-Item -LiteralPath $receipt.PendingPath -Force
    }
    $receiptPath = Join-Path (Split-Path -Parent $backupRoot) "promotion-receipt.json"
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText(
        $receiptPath,
        ($receipts | ConvertTo-Json -Depth 6),
        $utf8NoBom)
    Write-Host "Promotion receipt: $receiptPath"
}

if ($SkipLaunch) {
    Write-Host "SkipLaunch: DLL 提升流程结束，未启动游戏。"
    return
}

if ($PSCmdlet.ShouldProcess($gameExePath, "启动游戏")) {
    Start-Process -FilePath $gameExePath -WorkingDirectory $gameRootPath
    Write-Host "Game started: $gameExePath"
}
