[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$project = Join-Path $repoRoot 'updater-app\LongYinUpdater.RollbackTest\LongYinUpdater.RollbackTest.csproj'
. (Join-Path $PSScriptRoot 'portable-dotnet.ps1')
$dotnetPath = Initialize-PortableDotnetEnvironment -RepoRoot $repoRoot

& $dotnetPath run --project $project --configuration Release
if ($LASTEXITCODE -ne 0) {
    throw "Updater rollback test failed with exit code $LASTEXITCODE."
}
