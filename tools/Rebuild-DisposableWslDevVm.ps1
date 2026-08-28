#Requires -Version 5.1

[CmdletBinding()]
param(
    [switch]$Execute
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$VmName = 'ultra-minimal-wsl-dev'
$StagingVmName = 'ultra-minimal-wsl-dev-rebuild-r7'
$RetiredVmName = 'ultra-minimal-wsl-dev-retired-r7'
$ExpectedOldVmId = 'dd4b6df9-4fab-4f1b-b565-ba4e481ad6a6'
$ExpectedOldVmRoot = 'C:\Hyper-V\ultra-minimal-wsl\ultra-minimal-wsl-dev'
$StagingRoot = 'C:\Hyper-V\ultra-minimal-wsl-rebuild-r7'
$StagingVmRoot = Join-Path $StagingRoot $StagingVmName
$StagingVhdPath = Join-Path $StagingVmRoot 'Virtual Hard Disks\ultra-minimal-wsl-dev.vhdx'
$WindowsMedia = "$env:LOCALAPPDATA\ultra-minimal-wsl\controlled-inputs\windows-media\Win11_25H2_English_x64_v2.iso"
$ExpectedMediaSha256 = '768984706b909479417b2368438909440f2967ff05c6a9195ed2667254e465e3'
$WindowsImageName = 'Windows 11 Pro'
$GuestUsername = 'WslLabAdmin'
$CredentialPath = "$env:LOCALAPPDATA\ultra-minimal-wsl\credentials\ultra-minimal-wsl-dev.credential.clixml"
$CredentialMetadataPath = "$env:LOCALAPPDATA\ultra-minimal-wsl\credentials\ultra-minimal-wsl-dev.credential.json"
$StatePath = "$env:LOCALAPPDATA\ultra-minimal-wsl\hyper-v-vm.json"
$EvidenceRoot = "$env:LOCALAPPDATA\ultra-minimal-wsl\approval-state\zero-touch-rebuild-r7"
$StockMsiPath = "$env:LOCALAPPDATA\ultra-minimal-wsl\controlled-inputs\stock-wsl\wsl.2.7.12.0.x64.msi"
$ExpectedStockMsiSha256 = 'a460d4560215f2efe003c136244b78ea3415d773824d7a688ea9ded36dbe9145'
$ExpectedStockMsiBytes = 258998272
$GuestStockMsiPath = 'C:\controlled-inputs\ultra-minimal-wsl\controlled-inputs\stock-wsl\wsl.2.7.12.0.x64.msi'
$CheckpointName = 'clean-shell'
$DiskSize = 100GB
$StartupMemory = 4GB
$RequiredHostFreeBytes = $StartupMemory + 1GB
$ProcessorCount = 4

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Save-Json([object]$Value, [string]$Path) {
    $directory = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $temporary = "$Path.$([Guid]::NewGuid().ToString('N')).tmp"
    $Value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $temporary -Encoding UTF8
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}

function Save-FailureEvidence([string]$Phase, [object]$Failure) {
    try {
        Save-Json ([ordered]@{
            failedUtc = [DateTime]::UtcNow.ToString('o')
            phase = $Phase
            exceptionType = $Failure.Exception.GetType().FullName
            hresult = $Failure.Exception.HResult
            scriptLine = $Failure.InvocationInfo.Line.Trim()
        }) (Join-Path $EvidenceRoot 'failure.json')
    }
    catch { }
}

function Set-CurrentUserOnlyAcl([string]$Path) {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $sid = $identity.User
    $acl = New-Object Security.AccessControl.FileSecurity
    $acl.SetOwner($sid)
    $acl.SetAccessRuleProtection($true, $false)
    $rule = New-Object Security.AccessControl.FileSystemAccessRule($sid, 'FullControl', 'Allow')
    [void]$acl.AddAccessRule($rule)
    Set-Acl -LiteralPath $Path -AclObject $acl -ErrorAction Stop
}

function Get-TargetVm([string]$Name) {
    Import-Module Hyper-V -ErrorAction Stop
    Hyper-V\Get-VM -Name $Name -ErrorAction Stop
}

function Assert-Off([object]$Vm) {
    if ($Vm.State -ne [Microsoft.HyperV.PowerShell.VMState]::Off) {
        throw "VM '$($Vm.Name)' must be Off; current state is $($Vm.State)."
    }
}

function Assert-NoHostAttachedVmDisk([string]$Name) {
    $drives = @(Get-VMHardDiskDrive -VMName $Name -ErrorAction Stop)
    $attached = @($drives | ForEach-Object { Get-DiskImage -ImagePath $_.Path -ErrorAction Stop } | Where-Object Attached)
    if ($attached.Count -ne 0) { throw "A disk belonging to VM '$Name' is host-mounted." }
}

function Wait-VmState([string]$Name, [Microsoft.HyperV.PowerShell.VMState]$State, [int]$Minutes) {
    $deadline = [DateTime]::UtcNow.AddMinutes($Minutes)
    do {
        Start-Sleep -Seconds 2
        $vm = Get-TargetVm $Name
    } while ($vm.State -ne $State -and [DateTime]::UtcNow -lt $deadline)
    if ($vm.State -ne $State) { throw "VM '$Name' did not reach $State within $Minutes minute(s)." }
    $vm
}

function Request-GracefulStop([string]$Name) {
    $vm = Get-TargetVm $Name
    if ($vm.State -ne [Microsoft.HyperV.PowerShell.VMState]::Off) {
        Stop-VM -Name $Name -Confirm:$false -ErrorAction Stop | Out-Null
        Wait-VmState $Name ([Microsoft.HyperV.PowerShell.VMState]::Off) 5 | Out-Null
    }
}

function New-RandomPassword {
    $bytes = New-Object byte[] 30
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    'Aa1!' + [Convert]::ToBase64String($bytes)
}

function New-UnattendXml([string]$Username, [string]$Password) {
    $escapedUser = [Security.SecurityElement]::Escape($Username)
    $escapedPassword = [Security.SecurityElement]::Escape($Password)
    @"
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
  <settings pass="specialize">
    <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
      <ComputerName>WSL-LAB</ComputerName>
      <RegisteredOwner>Disposable WSL Lab</RegisteredOwner>
      <TimeZone>GMT Standard Time</TimeZone>
      <ProductKey>W269N-WFGWX-YVC9B-4J6C9-T83GX</ProductKey>
    </component>
  </settings>
  <settings pass="oobeSystem">
    <component name="Microsoft-Windows-International-Core" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <InputLocale>en-GB</InputLocale><SystemLocale>en-GB</SystemLocale><UILanguage>en-US</UILanguage><UserLocale>en-GB</UserLocale>
    </component>
    <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
      <OOBE><HideEULAPage>true</HideEULAPage><HideLocalAccountScreen>true</HideLocalAccountScreen><HideOEMRegistrationScreen>true</HideOEMRegistrationScreen><HideOnlineAccountScreens>true</HideOnlineAccountScreens><HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE><ProtectYourPC>3</ProtectYourPC></OOBE>
      <UserAccounts><LocalAccounts><LocalAccount wcm:action="add"><Description>Disposable WSL automation account</Description><DisplayName>$escapedUser</DisplayName><Group>Administrators</Group><Name>$escapedUser</Name><Password><Value>$escapedPassword</Value><PlainText>true</PlainText></Password></LocalAccount></LocalAccounts></UserAccounts>
      <AutoLogon><Password><Value>$escapedPassword</Value><PlainText>true</PlainText></Password><Domain>WSL-LAB</Domain><Enabled>true</Enabled><LogonCount>1</LogonCount><Username>$escapedUser</Username></AutoLogon>
      <FirstLogonCommands><SynchronousCommand wcm:action="add"><Order>1</Order><Description>Disable autologon after the initial profile creation</Description><CommandLine>reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v AutoLogonCount /t REG_DWORD /d 0 /f</CommandLine><RequiresUserInput>false</RequiresUserInput></SynchronousCommand></FirstLogonCommands>
    </component>
  </settings>
</unattend>
"@
}

$plan = [ordered]@{
    schema = 1
    action = if ($Execute) { 'zero-touch-rebuild' } else { 'plan-zero-touch-rebuild' }
    executableNow = $false
    approvalCarriedForward = $false
    destructive = $true
    oldVm = [ordered]@{ name=$VmName; id=$ExpectedOldVmId; requiredState='Off'; requiredPath=$ExpectedOldVmRoot }
    replacementVm = [ordered]@{ stagingName=$StagingVmName; finalName=$VmName; root=$StagingRoot; generation=2; memoryBytes=$StartupMemory; requiredHostFreeBytes=$RequiredHostFreeBytes; processors=$ProcessorCount; diskBytes=$DiskSize; networkAdapter=$false }
    media = [ordered]@{ path=$WindowsMedia; sha256=$ExpectedMediaSha256; imageName=$WindowsImageName }
    credential = [ordered]@{ username=$GuestUsername; generated=$true; shownToHuman=$false; prompts=$false; storage=$CredentialPath; protection='DPAPI current-user encryption plus non-inherited current-user-only ACL'; lifetime='created before first boot, paired to VM ID, deleted with VM' }
    replacementPolicy = 'If automated PowerShell Direct validation fails, gracefully stop and discard the staging VM/credential pair; never request human guest credentials or use VMConnect repair.'
    preservedInput = [ordered]@{ stockMsi=$StockMsiPath; sha256=$ExpectedStockMsiSha256; bytes=$ExpectedStockMsiBytes; guestPath=$GuestStockMsiPath }
    expectedFinal = [ordered]@{ vmName=$VmName; state='Off'; checkpoints=@($CheckpointName); hostMountedVmDisks=0; credentialPaired=$true; stockMsiStaged=$true }
    exactCommand = '& .\tools\Rebuild-DisposableWslDevVm.ps1 -Execute'
}
if (-not $Execute) {
    [pscustomobject]$plan | ConvertTo-Json -Depth 8
    exit 0
}
if (-not (Test-IsAdministrator)) { throw 'Zero-touch VM rebuild requires an elevated PowerShell 5.1 process and explicit -Execute.' }
Import-Module Hyper-V -ErrorAction Stop
Import-Module Dism -ErrorAction Stop
if (Test-Path -LiteralPath $EvidenceRoot) { throw "Evidence path already exists; refusing replay: $EvidenceRoot" }
if ((Test-Path -LiteralPath $CredentialPath) -or (Test-Path -LiteralPath $CredentialMetadataPath)) { throw 'A lifecycle credential already exists; refusing to overwrite it.' }
if (Get-VM -Name $StagingVmName -ErrorAction SilentlyContinue) { throw "Staging VM '$StagingVmName' already exists." }
if (Get-VM -Name $RetiredVmName -ErrorAction SilentlyContinue) { throw "Retired VM name '$RetiredVmName' already exists." }
if (Test-Path -LiteralPath $StagingRoot) { throw "Staging root already exists: $StagingRoot" }
if (-not (Test-Path -LiteralPath $WindowsMedia -PathType Leaf)) { throw "Windows media is missing: $WindowsMedia" }
if ((Get-FileHash -LiteralPath $WindowsMedia -Algorithm SHA256).Hash.ToLowerInvariant() -ne $ExpectedMediaSha256) { throw 'Windows media hash mismatch.' }
$stockMsi = Get-Item -LiteralPath $StockMsiPath -ErrorAction Stop
if ($stockMsi.Length -ne $ExpectedStockMsiBytes -or (Get-FileHash -LiteralPath $stockMsi.FullName -Algorithm SHA256).Hash.ToLowerInvariant() -ne $ExpectedStockMsiSha256) { throw 'Pinned stock MSI size or hash mismatch.' }

$oldVm = Get-TargetVm $VmName
if ($oldVm.Id.Guid -ne $ExpectedOldVmId) { throw "Existing VM ID is not the approved disposable VM: $($oldVm.Id.Guid)" }
Assert-Off $oldVm
Assert-NoHostAttachedVmDisk $VmName
$oldCheckpoints = @((Get-VMSnapshot -VM $oldVm -ErrorAction Stop) | ForEach-Object Name | Sort-Object)
if ($oldCheckpoints.Count -ne 1 -or $oldCheckpoints[0] -ne $CheckpointName) { throw "Existing VM checkpoint set is not exactly '$CheckpointName'." }
$oldPath = $oldVm.Path
if ($oldPath.TrimEnd('\') -ne $ExpectedOldVmRoot.TrimEnd('\')) { throw "Existing VM path is not the approved disposable path: $oldPath" }
$wslUtilityVm = @(Get-Process -Name vmmemWSL -ErrorAction SilentlyContinue)
if ($wslUtilityVm.Count -ne 0) { throw 'WSL utility VM is running; shut WSL down before the disposable VM rebuild.' }
$hostFreeBytes = [uint64](Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).FreePhysicalMemory * 1KB
if ($hostFreeBytes -lt $RequiredHostFreeBytes) { throw "Host free memory ($hostFreeBytes bytes) is below the required $RequiredHostFreeBytes bytes." }

New-Item -ItemType Directory -Path $EvidenceRoot -Force | Out-Null
Save-Json ([ordered]@{ observedUtc=[DateTime]::UtcNow.ToString('o'); vmName=$oldVm.Name; vmId=$oldVm.Id.Guid; state=[string]$oldVm.State; path=$oldPath; checkpoints=$oldCheckpoints; hostMountedVmDisks=0 }) (Join-Path $EvidenceRoot 'old-vm-preflight.json')

$operationPhase = 'credential-export'
$passwordPlain = New-RandomPassword
$passwordSecure = ConvertTo-SecureString -String $passwordPlain -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential($GuestUsername, $passwordSecure)
$tempCredential = Join-Path $EvidenceRoot 'replacement.credential.clixml'
try {
    $credential | Export-Clixml -LiteralPath $tempCredential -Depth 3
    Set-CurrentUserOnlyAcl $tempCredential
}
catch {
    Save-FailureEvidence $operationPhase $_
    $passwordPlain = $null
    $passwordSecure = $null
    $credential = $null
    Remove-Item -LiteralPath $tempCredential -Force -ErrorAction SilentlyContinue
    throw
}

$isoMountAttempted = $false
$vhdMountAttempted = $false
$session = $null
$stagingCreated = $false
$stagingPromoted = $false
$oldRenamed = $false
$credentialCommitted = $false
$operationFailure = $null
try {
    $operationPhase = 'media-mount-and-image-selection'
    $iso = Get-DiskImage -ImagePath $WindowsMedia -ErrorAction Stop
    if ($iso.Attached) { throw 'Windows ISO is already mounted; refusing to reuse operator state.' }
    $isoMountAttempted = $true
    Mount-DiskImage -ImagePath $WindowsMedia -Access ReadOnly -ErrorAction Stop | Out-Null
    $isoVolume = Get-DiskImage -ImagePath $WindowsMedia | Get-Volume
    $installWim = Join-Path ($isoVolume.DriveLetter + ':\') 'sources\install.wim'
    $images = @(Get-WindowsImage -ImagePath $installWim -ErrorAction Stop)
    $selected = @($images | Where-Object ImageName -eq $WindowsImageName)
    if ($selected.Count -ne 1) { throw "Expected exactly one '$WindowsImageName' image in install.wim; found $($selected.Count)." }
    Save-Json ([ordered]@{ imageIndex=$selected[0].ImageIndex; imageName=$selected[0].ImageName }) (Join-Path $EvidenceRoot 'windows-image.json')

    $operationPhase = 'staging-vhd-preparation'
    New-Item -ItemType Directory -Path (Split-Path -Parent $StagingVhdPath) -Force | Out-Null
    New-VHD -Path $StagingVhdPath -Dynamic -SizeBytes $DiskSize -ErrorAction Stop | Out-Null
    $vhdMountAttempted = $true
    $disk = Mount-VHD -Path $StagingVhdPath -Passthru -ErrorAction Stop | Get-Disk
    Initialize-Disk -Number $disk.Number -PartitionStyle GPT -ErrorAction Stop | Out-Null
    $efi = New-Partition -DiskNumber $disk.Number -Size 100MB -GptType '{C12A7328-F81F-11D2-BA4B-00A0C93EC93B}' -AssignDriveLetter -ErrorAction Stop
    Format-Volume -Partition $efi -FileSystem FAT32 -NewFileSystemLabel 'System' -Confirm:$false -ErrorAction Stop | Out-Null
    New-Partition -DiskNumber $disk.Number -Size 16MB -GptType '{E3C9E316-0B5C-4DB8-817D-F92DF00215AE}' -ErrorAction Stop | Out-Null
    $windowsPartition = New-Partition -DiskNumber $disk.Number -UseMaximumSize -AssignDriveLetter -ErrorAction Stop
    Format-Volume -Partition $windowsPartition -FileSystem NTFS -NewFileSystemLabel 'Windows' -Confirm:$false -ErrorAction Stop | Out-Null
    $efiRoot = (($efi | Get-Volume).DriveLetter + ':')
    $windowsRoot = (($windowsPartition | Get-Volume).DriveLetter + ':')
    Expand-WindowsImage -ImagePath $installWim -Index $selected[0].ImageIndex -ApplyPath ($windowsRoot + '\') -ErrorAction Stop | Out-Null
    $bcd = Start-Process -FilePath "$env:SystemRoot\System32\bcdboot.exe" -ArgumentList @("$windowsRoot\Windows", '/s', $efiRoot, '/f', 'UEFI') -Wait -PassThru -NoNewWindow
    if ($bcd.ExitCode -ne 0) { throw "bcdboot failed with exit code $($bcd.ExitCode)." }
    $panther = Join-Path $windowsRoot 'Windows\Panther'
    New-Item -ItemType Directory -Path $panther -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $panther 'unattend.xml'), (New-UnattendXml $GuestUsername $passwordPlain), [Text.UTF8Encoding]::new($false))
    $passwordPlain = $null
    Dismount-VHD -Path $StagingVhdPath -ErrorAction Stop
    Dismount-DiskImage -ImagePath $WindowsMedia -ErrorAction Stop

    $operationPhase = 'staging-vm-create'
    $stagingVm = New-VM -Name $StagingVmName -Generation 2 -Path $StagingRoot -MemoryStartupBytes $StartupMemory -VHDPath $StagingVhdPath -ErrorAction Stop
    $stagingCreated = $true
    Set-VM -VM $stagingVm -AutomaticCheckpointsEnabled $false -CheckpointType Standard -AutomaticStartAction Nothing -AutomaticStopAction ShutDown
    Set-VMMemory -VM $stagingVm -DynamicMemoryEnabled $true -MinimumBytes 2GB -StartupBytes $StartupMemory -MaximumBytes 8GB
    Set-VMProcessor -VM $stagingVm -Count $ProcessorCount -ExposeVirtualizationExtensions $true
    Set-VMFirmware -VM $stagingVm -EnableSecureBoot On -SecureBootTemplate MicrosoftWindows
    Set-VMKeyProtector -VM $stagingVm -NewLocalKeyProtector
    Enable-VMTPM -VM $stagingVm
    @(Get-VMNetworkAdapter -VM $stagingVm -ErrorAction Stop) | Remove-VMNetworkAdapter -ErrorAction Stop
    if (@(Get-VMNetworkAdapter -VM $stagingVm -ErrorAction Stop).Count -ne 0) { throw 'Replacement VM network-adapter removal validation failed.' }

    $operationPhase = 'automatic-guest-control-validation'
    Start-VM -VM $stagingVm -ErrorAction Stop | Out-Null
    Wait-VmState $StagingVmName ([Microsoft.HyperV.PowerShell.VMState]::Running) 5 | Out-Null
    $sessionDeadline = [DateTime]::UtcNow.AddMinutes(20)
    $lastSessionError = $null
    do {
        try { $session = New-PSSession -VMName $StagingVmName -Credential $credential -ErrorAction Stop }
        catch { $session = $null; $lastSessionError = $_; if ([DateTime]::UtcNow -lt $sessionDeadline) { Start-Sleep -Seconds 5 } }
    } while ($null -eq $session -and [DateTime]::UtcNow -lt $sessionDeadline)
    if ($null -eq $session) { throw "Fresh replacement PowerShell Direct was unavailable after 20 minutes: $($lastSessionError.Exception.Message)" }

    $guestPreflight = Invoke-Command -Session $session -ErrorAction Stop -ScriptBlock {
        param($ExpectedUser)
        $service = Get-Service -Name vmicvmsession -ErrorAction Stop
        $account = Get-LocalUser -Name $ExpectedUser -ErrorAction Stop
        $isAdministrator = [bool](Get-LocalGroupMember -Group 'Administrators' -ErrorAction Stop | Where-Object Name -Match ('\\' + [regex]::Escape($ExpectedUser) + '$'))
        $sensitive = @('C:\unattend.xml','C:\Windows\Panther\unattend.xml','C:\Windows\Panther\Unattend\unattend.xml','C:\Windows\System32\Sysprep\unattend.xml')
        foreach ($path in $sensitive) { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
        [pscustomobject]@{ serviceName=$service.Name; serviceStatus=[string]$service.Status; serviceStartType=[string]$service.StartType; accountEnabled=$account.Enabled; administrator=$isAdministrator; sensitiveUnattendRemaining=@($sensitive | Where-Object { Test-Path -LiteralPath $_ }) }
    } -ArgumentList $GuestUsername
    if ($guestPreflight.serviceStatus -ne 'Running' -or -not $guestPreflight.accountEnabled -or -not $guestPreflight.administrator -or $guestPreflight.sensitiveUnattendRemaining.Count -ne 0) { throw 'Replacement guest control or sensitive-unattend cleanup validation failed.' }
    Save-Json $guestPreflight (Join-Path $EvidenceRoot 'guest-preflight.json')

    $operationPhase = 'stock-msi-staging'
    $guestMsiDirectory = Split-Path -Parent $GuestStockMsiPath
    Invoke-Command -Session $session -ScriptBlock { param($Path) New-Item -ItemType Directory -Path $Path -Force | Out-Null } -ArgumentList $guestMsiDirectory -ErrorAction Stop
    Copy-Item -LiteralPath $StockMsiPath -Destination $GuestStockMsiPath -ToSession $session -ErrorAction Stop
    $guestMsi = Invoke-Command -Session $session -ScriptBlock { param($Path) $item=Get-Item -LiteralPath $Path -ErrorAction Stop; [pscustomobject]@{path=$item.FullName;bytes=$item.Length;sha256=(Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()} } -ArgumentList $GuestStockMsiPath -ErrorAction Stop
    if ($guestMsi.bytes -ne $ExpectedStockMsiBytes -or $guestMsi.sha256 -ne $ExpectedStockMsiSha256) { throw 'Staged guest MSI size or hash mismatch.' }
    Save-Json $guestMsi (Join-Path $EvidenceRoot 'staged-stock-msi.json')

    $operationPhase = 'clean-shell-checkpoint'
    Remove-PSSession -Session $session -ErrorAction Stop
    $session = $null
    Request-GracefulStop $StagingVmName
    $stagingVm = Get-TargetVm $StagingVmName
    Assert-Off $stagingVm
    Assert-NoHostAttachedVmDisk $StagingVmName
    Checkpoint-VM -VM $stagingVm -SnapshotName $CheckpointName -ErrorAction Stop | Out-Null
    $snapshot = Get-VMSnapshot -VM $stagingVm -Name $CheckpointName -ErrorAction Stop

    $operationPhase = 'credential-commit'
    $credentialDirectory = Split-Path -Parent $CredentialPath
    New-Item -ItemType Directory -Path $credentialDirectory -Force | Out-Null
    Move-Item -LiteralPath $tempCredential -Destination $CredentialPath -ErrorAction Stop
    Set-CurrentUserOnlyAcl $CredentialPath
    $credentialCommitted = $true
    Save-Json ([ordered]@{ schema=1; vmName=$VmName; vmId=$stagingVm.Id.Guid; username=$GuestUsername; credentialPath=$CredentialPath; protection='DPAPI current-user plus current-user-only ACL'; createdUtc=[DateTime]::UtcNow.ToString('o'); deleteWithVm=$true }) $CredentialMetadataPath

    $operationPhase = 'transactional-promotion'
    Rename-VM -VM $oldVm -NewName $RetiredVmName -ErrorAction Stop
    $oldRenamed = $true
    try {
        Rename-VM -VM $stagingVm -NewName $VmName -ErrorAction Stop
        $stagingPromoted = $true
        $replacement = Get-TargetVm $VmName
        Assert-Off $replacement
        Assert-NoHostAttachedVmDisk $VmName
        $replacementCheckpoints = @((Get-VMSnapshot -VM $replacement -ErrorAction Stop) | ForEach-Object Name)
        if ($replacementCheckpoints.Count -ne 1 -or $replacementCheckpoints[0] -ne $CheckpointName) { throw 'Promoted replacement checkpoint validation failed.' }
    }
    catch {
        if ($stagingPromoted) {
            Rename-VM -Name $VmName -NewName $StagingVmName -ErrorAction Stop
            $stagingPromoted = $false
        }
        if ($oldRenamed) {
            Rename-VM -Name $RetiredVmName -NewName $VmName -ErrorAction Stop
            $oldRenamed = $false
        }
        throw
    }

    $operationPhase = 'retired-vm-delete'
    $retired = Get-TargetVm $RetiredVmName
    Assert-Off $retired
    Assert-NoHostAttachedVmDisk $RetiredVmName
    Remove-VM -VM $retired -Force -ErrorAction Stop
    if (Test-Path -LiteralPath $ExpectedOldVmRoot) { Remove-Item -LiteralPath $ExpectedOldVmRoot -Recurse -Force -ErrorAction Stop }
    $oldRenamed = $false

    $operationPhase = 'final-state-record'
    Save-Json ([ordered]@{ schema=2; action='zero-touch-rebuilt'; vmName=$VmName; vmId=$replacement.Id.Guid; vmPath=$replacement.Path; diskPath=$StagingVhdPath; checkpoint=$CheckpointName; checkpointId=$snapshot.Id.Guid; credentialMetadata=$CredentialMetadataPath; createdUtc=[DateTime]::UtcNow.ToString('o') }) $StatePath
    Save-Json ([ordered]@{ safe=$true; vmName=$VmName; vmId=$replacement.Id.Guid; state=[string]$replacement.State; checkpoints=$replacementCheckpoints; hostMountedVmDisks=0; credentialPaired=$true; stockMsiStaged=$true; completedUtc=[DateTime]::UtcNow.ToString('o') }) (Join-Path $EvidenceRoot 'final-state.json')
}
catch {
    $operationFailure = $_
    Save-FailureEvidence $operationPhase $_
    throw
}
finally {
    $passwordPlain = $null
    $passwordSecure = $null
    $credential = $null
    if ($null -ne $session) { Remove-PSSession -Session $session -ErrorAction SilentlyContinue }
    if ($vhdMountAttempted -and (Test-Path -LiteralPath $StagingVhdPath)) {
        $vhdImage = Get-DiskImage -ImagePath $StagingVhdPath -ErrorAction SilentlyContinue
        if ($vhdImage -and $vhdImage.Attached) { Dismount-VHD -Path $StagingVhdPath -ErrorAction SilentlyContinue }
    }
    if ($isoMountAttempted) {
        $isoImage = Get-DiskImage -ImagePath $WindowsMedia -ErrorAction SilentlyContinue
        if ($isoImage -and $isoImage.Attached) { Dismount-DiskImage -ImagePath $WindowsMedia -ErrorAction SilentlyContinue }
    }
    if ($null -ne $operationFailure -and -not $stagingPromoted -and $stagingCreated) {
        $failedStaging = Get-VM -Name $StagingVmName -ErrorAction SilentlyContinue
        if ($failedStaging) {
            if ($failedStaging.State -ne [Microsoft.HyperV.PowerShell.VMState]::Off) { Stop-VM -Name $StagingVmName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null }
            $deadline = [DateTime]::UtcNow.AddMinutes(5)
            do { Start-Sleep -Seconds 2; $failedStaging=Get-VM -Name $StagingVmName -ErrorAction SilentlyContinue } while ($failedStaging -and $failedStaging.State -ne [Microsoft.HyperV.PowerShell.VMState]::Off -and [DateTime]::UtcNow -lt $deadline)
            if ($failedStaging -and $failedStaging.State -eq [Microsoft.HyperV.PowerShell.VMState]::Off) { Remove-VM -VM $failedStaging -Force -ErrorAction SilentlyContinue }
        }
        if ((-not (Get-VM -Name $StagingVmName -ErrorAction SilentlyContinue)) -and (Test-Path -LiteralPath $StagingRoot)) { Remove-Item -LiteralPath $StagingRoot -Recurse -Force -ErrorAction SilentlyContinue }
    }
    if (($null -ne $operationFailure) -and (-not $stagingCreated) -and (Test-Path -LiteralPath $StagingRoot)) {
        Remove-Item -LiteralPath $StagingRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    if ($null -ne $operationFailure -and $credentialCommitted -and -not $stagingPromoted) {
        Remove-Item -LiteralPath $CredentialPath,$CredentialMetadataPath -Force -ErrorAction SilentlyContinue
    }
    if (($null -ne $operationFailure) -and (-not (Get-VM -Name $StagingVmName -ErrorAction SilentlyContinue)) -and (Test-Path -LiteralPath $tempCredential)) {
        Remove-Item -LiteralPath $tempCredential -Force -ErrorAction SilentlyContinue
    }
}
