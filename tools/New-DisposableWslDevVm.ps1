[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$WindowsMedia,

    [string]$VmName = 'ultra-minimal-wsl-dev',
    [string]$VmRoot = 'C:\Hyper-V\ultra-minimal-wsl',
    [string]$SwitchName = 'Default Switch',
    [ValidateRange(2GB, 8GB)]
    [long]$StartupMemory = 6GB,
    [ValidateRange(2, 16)]
    [int]$ProcessorCount = 4,
    [ValidateRange(40GB, 512GB)]
    [long]$DiskSize = 100GB,
    [string]$CheckpointName = 'clean-shell',
    [string]$StatePath = "$env:LOCALAPPDATA\ultra-minimal-wsl\hyper-v-vm.json",
    [switch]$Execute
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

$media = Get-Item -LiteralPath $WindowsMedia
$extension = $media.Extension.ToLowerInvariant()
if ($extension -notin @('.iso', '.vhdx')) {
    throw 'WindowsMedia must be a Windows installation ISO or a generalized Windows VHDX.'
}

$plan = [ordered]@{
    schema = 1
    action = if ($Execute) { 'create' } else { 'plan' }
    vmName = $VmName
    vmRoot = $VmRoot
    media = $media.FullName
    mediaType = $extension.TrimStart('.')
    mediaSha256 = (Get-FileHash -LiteralPath $media.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    switchName = $SwitchName
    startupMemoryBytes = $StartupMemory
    processorCount = $ProcessorCount
    diskSizeBytes = $DiskSize
    nestedVirtualization = $true
    secureBootTemplate = 'MicrosoftWindows'
    virtualTpm = $true
    automaticCheckpoints = $false
    checkpoint = $CheckpointName
    startsVm = $false
    statePath = $StatePath
    requiresElevation = $true
}

if (-not $Execute) {
    [pscustomobject]$plan | ConvertTo-Json -Depth 4
    exit 0
}

if (-not (Test-IsAdministrator)) {
    throw 'VM creation requires an elevated PowerShell process and an explicit -Execute invocation.'
}

Import-Module Hyper-V -ErrorAction Stop
if (Get-VM -Name $VmName -ErrorAction SilentlyContinue) {
    throw "A VM named '$VmName' already exists; refusing to modify it."
}
if (Test-Path -LiteralPath (Join-Path $VmRoot $VmName)) {
    throw "The VM directory already exists; refusing to overwrite it: $(Join-Path $VmRoot $VmName)"
}
$switch = Get-VMSwitch -Name $SwitchName -ErrorAction Stop

$vmDirectory = Join-Path $VmRoot $VmName
$diskDirectory = Join-Path $vmDirectory 'Virtual Hard Disks'
New-Item -ItemType Directory -Path $diskDirectory -Force | Out-Null
$vmDisk = Join-Path $diskDirectory "$VmName.vhdx"

$vmCreated = $false
try {
    if ($extension -eq '.vhdx') {
        Copy-Item -LiteralPath $media.FullName -Destination $vmDisk
    }
    else {
        New-VHD -Path $vmDisk -Dynamic -SizeBytes $DiskSize | Out-Null
    }

    $vm = New-VM -Name $VmName -Generation 2 -Path $VmRoot -MemoryStartupBytes $StartupMemory -VHDPath $vmDisk -SwitchName $switch.Name
    $vmCreated = $true
    Set-VM -VM $vm -AutomaticCheckpointsEnabled $false -CheckpointType Standard -AutomaticStartAction Nothing -AutomaticStopAction ShutDown
    Set-VMMemory -VM $vm -DynamicMemoryEnabled $true -MinimumBytes 2GB -StartupBytes $StartupMemory -MaximumBytes 8GB
    Set-VMProcessor -VM $vm -Count $ProcessorCount -ExposeVirtualizationExtensions $true
    Set-VMFirmware -VM $vm -EnableSecureBoot On -SecureBootTemplate MicrosoftWindows
    Set-VMKeyProtector -VM $vm -NewLocalKeyProtector
    Enable-VMTPM -VM $vm

    if ($extension -eq '.iso') {
        Add-VMDvdDrive -VM $vm -Path $media.FullName | Out-Null
        $dvd = Get-VMDvdDrive -VM $vm
        Set-VMFirmware -VM $vm -FirstBootDevice $dvd
    }

    Checkpoint-VM -VM $vm -SnapshotName $CheckpointName | Out-Null
    $snapshot = Get-VMSnapshot -VM $vm -Name $CheckpointName
    $created = Get-VM -Name $VmName

    $result = [ordered]@{}
    foreach ($entry in $plan.GetEnumerator()) { $result[$entry.Key] = $entry.Value }
    $result.action = 'created'
    $result.vmId = $created.Id.Guid
    $result.vmPath = $created.Path
    $result.diskPath = $vmDisk
    $result.checkpointId = $snapshot.Id.Guid
    $result.checkpointCreationTimeUtc = $snapshot.CreationTime.ToUniversalTime().ToString('o')
    $result.createdUtc = [DateTime]::UtcNow.ToString('o')

    $stateDirectory = Split-Path -Parent $StatePath
    New-Item -ItemType Directory -Path $stateDirectory -Force | Out-Null
    $temporaryState = "$StatePath.tmp"
    [pscustomobject]$result | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $temporaryState -Encoding utf8
    Move-Item -LiteralPath $temporaryState -Destination $StatePath -Force
    [pscustomobject]$result | ConvertTo-Json -Depth 4
}
catch {
    if ($vmCreated) {
        $existingVm = Get-VM -Name $VmName -ErrorAction SilentlyContinue
        if ($existingVm) {
            Remove-VM -VM $existingVm -Force -ErrorAction SilentlyContinue
        }
    }
    if (Test-Path -LiteralPath $vmDirectory) {
        Remove-Item -LiteralPath $vmDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
    throw
}
