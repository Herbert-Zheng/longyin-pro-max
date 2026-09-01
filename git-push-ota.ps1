$scriptPath = Join-Path $PSScriptRoot 'scripts\prepare-release.ps1'
& $scriptPath -PushTag @args
exit $LASTEXITCODE
