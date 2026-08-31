Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-BrokerId {
    param([Parameter(Mandatory)][string] $Value, [string] $Name = 'id')
    if ($Value -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$') {
        throw "Invalid $Name."
    }
    $Value
}

function Assert-Sequence {
    param([Parameter(Mandatory)][object] $Value)
    $number = 0L
    if (-not [long]::TryParse([string]$Value, [ref]$number) -or $number -lt 1 -or $number -gt 999999999) {
        throw 'Invalid sequence.'
    }
    $number
}

function Assert-Sha256 {
    param([Parameter(Mandatory)][string] $Value)
    if ($Value -notmatch '^[a-f0-9]{64}$') { throw 'Invalid SHA-256.' }
    $Value
}

function Get-CanonicalPath {
    param([Parameter(Mandatory)][string] $Path)
    [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Path)).TrimEnd('\')
}

function Assert-PathUnderRoots {
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string[]] $Roots,
        [switch] $MustExist,
        [switch] $Leaf
    )
    $candidate = Get-CanonicalPath $Path
    $allowed = $false
    foreach ($rootValue in $Roots) {
        $root = Get-CanonicalPath $rootValue
        if ($candidate.Equals($root, [StringComparison]::OrdinalIgnoreCase) -or
            $candidate.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) {
            $allowed = $true
            break
        }
    }
    if (-not $allowed) { throw 'Path is outside the configured roots.' }
    if ($MustExist) {
        $kind = if ($Leaf) { 'Leaf' } else { 'Any' }
        if (-not (Test-Path -LiteralPath $candidate -PathType $kind)) { throw 'Required path does not exist.' }
    }
    $candidate
}

function Assert-NoReparsePoint {
    param([Parameter(Mandatory)][string] $Path)
    $current = Get-CanonicalPath $Path
    while ($current) {
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw 'Reparse points are not permitted in trusted paths.'
            }
        }
        $parent = Split-Path -Parent $current
        if (-not $parent -or $parent -eq $current) { break }
        $current = $parent
    }
}

function Assert-RelativeOutputPath {
    param([Parameter(Mandatory)][string] $Path)
    if ([IO.Path]::IsPathRooted($Path) -or $Path -match '(^|[\\/])\.\.([\\/]|$)' -or $Path -match '[:*?"<>|]') {
        throw 'Invalid relative output path.'
    }
    $normalized = $Path.Replace('/', '\').Trim('\')
    if (-not $normalized -or $normalized.Length -gt 240) { throw 'Invalid relative output path.' }
    $normalized
}

function Assert-GuestPath {
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string[]] $Roots
    )
    if ($Path -match '(^|[\\/])\.\.([\\/]|$)') { throw 'Guest path traversal is not permitted.' }
    $candidate = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    if (-not $candidate.StartsWith('C:\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Only guest C: paths are permitted.'
    }
    foreach ($rootValue in $Roots) {
        $root = [IO.Path]::GetFullPath($rootValue).TrimEnd('\')
        if ($candidate.Equals($root, [StringComparison]::OrdinalIgnoreCase) -or
            $candidate.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) {
            return $candidate
        }
    }
    throw 'Guest path is outside the configured roots.'
}

function Get-StreamSha256 {
    param([Parameter(Mandatory)][IO.Stream] $Stream)
    $position = $Stream.Position
    try {
        $Stream.Position = 0
        $hash = [Security.Cryptography.SHA256]::Create()
        try { ([Convert]::ToHexString($hash.ComputeHash($Stream))).ToLowerInvariant() }
        finally { $hash.Dispose() }
    }
    finally { $Stream.Position = $position }
}

function Assert-ExpectedHash {
    param([Parameter(Mandatory)][string] $Actual, [Parameter(Mandatory)][string] $Expected)
    Assert-Sha256 $Actual | Out-Null
    Assert-Sha256 $Expected | Out-Null
    if ($Actual -ne $Expected) { throw 'Protected workload hash mismatch.' }
    $true
}

function Assert-ExpectedSequence {
    param([Parameter(Mandatory)][object] $Actual, [Parameter(Mandatory)][object] $Expected)
    $actualNumber = Assert-Sequence $Actual
    $expectedNumber = Assert-Sequence $Expected
    if ($actualNumber -ne $expectedNumber) { throw 'Job sequence is not the next expected value.' }
    $true
}

function Select-AllowlistedWorkload {
    param([Parameter(Mandatory)][object[]] $Workloads, [Parameter(Mandatory)][string] $Id)
    Assert-BrokerId $Id 'workloadId' | Out-Null
    $workloadMatches = @($Workloads | Where-Object { $_.id -eq $Id })
    if ($workloadMatches.Count -ne 1) { throw 'Workload is not in the protected allowlist.' }
    $workloadMatches[0]
}

function Assert-ProtectedAcl {
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $UserSid
    )
    $canonical = Get-CanonicalPath $Path
    Assert-NoReparsePoint $canonical
    $acl = Get-Acl -LiteralPath $canonical
    if (-not $acl.AreAccessRulesProtected) { throw 'Trusted path inherits permissions.' }
    $dangerous = [Security.AccessControl.FileSystemRights]::WriteData -bor
        [Security.AccessControl.FileSystemRights]::CreateFiles -bor
        [Security.AccessControl.FileSystemRights]::AppendData -bor
        [Security.AccessControl.FileSystemRights]::WriteAttributes -bor
        [Security.AccessControl.FileSystemRights]::WriteExtendedAttributes -bor
        [Security.AccessControl.FileSystemRights]::Delete -bor
        [Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles -bor
        [Security.AccessControl.FileSystemRights]::ChangePermissions -bor
        [Security.AccessControl.FileSystemRights]::TakeOwnership
    foreach ($rule in $acl.Access) {
        if ($rule.AccessControlType -ne [Security.AccessControl.AccessControlType]::Allow) { continue }
        $sid = $rule.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value
        if ($sid -in @('S-1-5-18', 'S-1-5-32-544')) { continue }
        if (($rule.FileSystemRights -band $dangerous) -ne 0) {
            throw "Untrusted principal has write access to protected path: $sid"
        }
    }
    $readRule = $acl.Access | Where-Object {
        $_.AccessControlType -eq [Security.AccessControl.AccessControlType]::Allow -and
        $_.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value -eq $UserSid
    }
    if (-not $readRule) { throw 'Launching user lacks protected broker read access.' }
    $true
}

function Read-StrictJob {
    param([Parameter(Mandatory)][string] $Path)
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -gt 65536) { throw 'Job manifest exceeds 64 KiB.' }
    $text = [Text.UTF8Encoding]::new($false, $true).GetString($bytes)
    $job = $text | ConvertFrom-Json
    $allowedTop = @('schema','id','sequence','operation','workloadId')
    foreach ($property in $job.PSObject.Properties.Name) {
        if ($property -notin $allowedTop) { throw "Unknown job field: $property" }
    }
    if ($job.schema -ne 1) { throw 'Unsupported job schema.' }
    Assert-BrokerId ([string]$job.id) | Out-Null
    Assert-Sequence $job.sequence | Out-Null
    if ($job.operation -notin @('status','execute','finish')) {
        throw 'Unsupported broker operation.'
    }
    if ($job.operation -eq 'execute') {
        if (-not ($job.PSObject.Properties.Name -contains 'workloadId')) { throw 'Execute job requires workloadId.' }
        Assert-BrokerId ([string]$job.workloadId) 'workloadId' | Out-Null
    }
    elseif ($job.PSObject.Properties.Name -contains 'workloadId') {
        throw 'workloadId is valid only for execute jobs.'
    }
    $job
}

Export-ModuleMember -Function Assert-BrokerId,Assert-Sequence,Assert-Sha256,Get-CanonicalPath,Assert-PathUnderRoots,Assert-NoReparsePoint,Assert-RelativeOutputPath,Assert-GuestPath,Get-StreamSha256,Assert-ExpectedHash,Assert-ExpectedSequence,Select-AllowlistedWorkload,Assert-ProtectedAcl,Read-StrictJob
