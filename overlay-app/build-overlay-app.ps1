param(
    [string]$Configuration = "Release",
    [string]$OutputRoot = "",
    [string]$LiveOutput = ""
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$dotnet = Join-Path $repoRoot ".codex-tools\dotnet\dotnet.exe"
$project = Join-Path $PSScriptRoot "LongYinOverlay\LongYinOverlay.csproj"

if (-not (Test-Path $dotnet)) {
    throw "Expected local dotnet host at $dotnet."
}

if ($OutputRoot -eq "") {
    $OutputRoot = Join-Path $repoRoot "dist\LongYinOverlay"
}

& $dotnet publish $project `
    -c $Configuration `
    -o $OutputRoot `
    --nologo

if ($LASTEXITCODE -ne 0) {
    throw "Overlay publish failed with exit code $LASTEXITCODE."
}

if ($LiveOutput -ne "") {
    New-Item -ItemType Directory -Force -Path $LiveOutput | Out-Null
    Copy-Item -Recurse -Force (Join-Path $OutputRoot "*") $LiveOutput
}

Write-Host "Published overlay app to $OutputRoot"

if ($LiveOutput -ne "") {
    Write-Host "Copied overlay app to $LiveOutput"
}
