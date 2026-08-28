#Requires -Version 7.0

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$target = Join-Path $PSScriptRoot 'Rebuild-DisposableWslDevVm.ps1'
$expectedSha256 = 'a66161b738d0c0a5364470773326c4af69aaf9e77cfb3e2d3c2b12150f9c8dce'

if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
    throw "Approved r8 artifact is missing: $target"
}
$actualSha256 = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualSha256 -ne $expectedSha256) {
    throw "Approved r8 artifact hash mismatch: expected $expectedSha256, found $actualSha256."
}

& $target -Execute
if (-not $?) { throw 'Approved r8 artifact failed.' }
if ($LASTEXITCODE -is [int] -and $LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
