[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-PortableDotnetRoot {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot
  )

  return Join-Path $RepoRoot '.codex-tools\dotnet'
}

function Get-PortableDotnetPath {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot
  )

  return Join-Path (Get-PortableDotnetRoot -RepoRoot $RepoRoot) 'dotnet.exe'
}

function Initialize-PortableDotnetEnvironment {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot
  )

  $dotnetRoot = Get-PortableDotnetRoot -RepoRoot $RepoRoot
  $dotnetPath = Get-PortableDotnetPath -RepoRoot $RepoRoot
  $usingPortableSdk = Test-Path -LiteralPath $dotnetPath -PathType Leaf

  if (-not $usingPortableSdk) {
    $systemDotnet = Get-Command dotnet -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $systemDotnet) {
      throw "未找到可用的 .NET SDK。请安装 .NET 6 SDK，或准备仓库便携 SDK：$dotnetPath"
    }

    $dotnetPath = $systemDotnet.Source
  }

  $cliHome = Join-Path $RepoRoot '.codex-temp\dotnet-cli'
  New-Item -ItemType Directory -Force -Path $cliHome | Out-Null

  if ($usingPortableSdk) {
    $env:DOTNET_ROOT = $dotnetRoot
    $env:DOTNET_MULTILEVEL_LOOKUP = '0'
  }
  else {
    $env:DOTNET_MULTILEVEL_LOOKUP = '1'
  }

  $installedSdks = @(& $dotnetPath --list-sdks 2>$null)
  if ($LASTEXITCODE -ne 0 -or $installedSdks.Count -eq 0) {
    throw "找到 dotnet 主机但没有可用的 .NET SDK：$dotnetPath。请安装 .NET 6 SDK，或准备仓库便携 SDK：$(Get-PortableDotnetPath -RepoRoot $RepoRoot)"
  }

  $env:DOTNET_SKIP_FIRST_TIME_EXPERIENCE = '1'
  $env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
  $env:DOTNET_CLI_HOME = $cliHome

  return $dotnetPath
}

function Restore-RepoDotnetTools {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot,
    [Parameter(Mandatory = $true)]
    [string]$DotnetPath
  )

  Push-Location $RepoRoot
  try {
    & $DotnetPath tool restore
    if ($LASTEXITCODE -ne 0) {
      throw "dotnet tool restore 失败。"
    }
  }
  finally {
    Pop-Location
  }
}

function Invoke-PortableDotnet {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot,
    [Parameter(Mandatory = $true)]
    [string[]]$Arguments
  )

  $dotnetPath = Initialize-PortableDotnetEnvironment -RepoRoot $RepoRoot

  Push-Location $RepoRoot
  try {
    & $dotnetPath @Arguments
    if ($LASTEXITCODE -ne 0) {
      throw "dotnet $($Arguments -join ' ') 失败。"
    }
  }
  finally {
    Pop-Location
  }
}
