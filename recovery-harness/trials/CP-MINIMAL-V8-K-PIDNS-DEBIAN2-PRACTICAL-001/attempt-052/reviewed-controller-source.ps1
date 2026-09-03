#Requires -Version 7.0
# FixtureBroker-SecureWorkload: 1
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$vmName = 'ultra-minimal-wsl-dev'
$vmId = 'dcbf722c-0702-444e-9496-04a4623c3198'
$checkpoint = 'clean-shell'
$trial = 'CP-MINIMAL-V8-K-PIDNS-DEBIAN2-PRACTICAL-001'
$recovery = "$trial-RECOVERY"
$project = 'C:\Users\jackc\git\ultra-minimal-wsl'
$root = [Environment]::GetEnvironmentVariable('ULTRAMINIMALWSL_SECURE_RUN_ROOT')
$credentialPath = [Environment]::GetEnvironmentVariable('ULTRAMINIMALWSL_SECURE_CREDENTIAL')
if (-not $root -or -not $credentialPath) { throw 'Protected broker environment is required.' }
$root = [IO.Path]::GetFullPath($root).TrimEnd('\')
$expectedRoot = [IO.Path]::GetFullPath((Join-Path $env:ProgramData 'UltraMinimalWslFixtureBroker\Runs')).TrimEnd('\')
if (-not $root.StartsWith($expectedRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Protected run root mismatch.' }
$resultPath = Join-Path $root 'results\workload-operation-result.json'
$extract = Join-Path $root 'results\extracted'
$credential = Import-Clixml -LiteralPath $credentialPath
$runnerSource = Join-Path $project 'control-plane\controlled-package-offline\Invoke-MinimalV8KPidNsDebian2PracticalTrial.ps1'
$manifestSource = Join-Path $project 'control-plane\trial-manifests\minimal-v8-k-pidns-001.json'
$kernelSource = Join-Path $project 'candidates\K-PIDNS-001\linux-kernel'
$configSource = Join-Path $project 'candidates\K-PIDNS-001\linux-fullconfig'
$packageSource = 'C:\Users\jackc\AppData\Local\ultra-minimal-wsl\controlled-outputs\minimal-v8-no-binfmt-mount\wsl.msi'
$probeSource = Join-Path $project 'tools\Invoke-WslDebian2PracticalProbe.ps1'
$articleVhdxHash = '0c803f68d7cb3b0f8e0b29022df5413a43bd96bcb0a947f47712155d1895d388'
$runnerHash = 'ac32970601650f5095f20d2c4590d82ab33afdbf8c1dde19132c2fa4b10f4a37'
$manifestHash = 'f31ccc299f57b0c7a8c5c96c9d239a90b8ebd6f4c9874bc8377ca528deec98a4'
$kernelHash = '24c768730ba2b66e0afde5a53cbbc95e92440bb90510552ad9b9bf4ddf73c959'
$configHash = 'e7e10f27f0b802142a2ecbb52763ba49523da61f42efc23d61bab0046d9ad563'
$packageHash = '8207049ae7a6f8a0e7da14bf4becbed438297e5a8b52c215d0d9011cdc3a5765'
$probeHash = 'feedb4f54297305d5ca1baa2e44dedbc2979b1e09ade73c6768d2fe93e16522d'
$expectedArticleVhdxHash = $articleVhdxHash
$recoveryProbeHash = '424b0d4f26cef5c717a4805b2577feebf6973de4656778d7800474aad1bf4ebb'
$recoveryRootfsHash = 'a8e81e6d29eac6afa7b9438916df3db00de6f833faf8ab8dfaed482bb9a16fa4'
$wprHash = '3f829a9af733d6dce9454a1df2e2aa07096acaaed5b6865ffb5c202d089479f2'
function Hash([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Save([object]$Value) { [IO.File]::WriteAllText($resultPath, ($Value | ConvertTo-Json -Depth 30), [Text.UTF8Encoding]::new($false)) }
if ((Test-Path -LiteralPath $resultPath) -or (Test-Path -LiteralPath $extract)) { throw 'Runtime output already exists.' }
foreach ($identity in @(@($runnerSource,$runnerHash),@($manifestSource,$manifestHash),@($kernelSource,$kernelHash),@($configSource,$configHash),@($packageSource,$packageHash),@($probeSource,$probeHash))) {
    if ((Hash $identity[0]) -ne $identity[1]) { throw "Source identity mismatch: $($identity[0])" }
}
# This hash-bound controller is the protected executable contract. Its exact
# identities are selected from experiments.sqlite before the broker snapshots it;
# privileged execution never trusts mutable repository planning state.
$vm = Get-VM -Name $vmName -ErrorAction Stop
if (@(Get-VMNetworkAdapter -VM $vm -ErrorAction Stop).Count -ne 0) { throw 'Fixture must begin with zero network adapters.' }
if ($vm.Id.Guid -ne $vmId -or $vm.State -ne [Microsoft.HyperV.PowerShell.VMState]::Off) { throw 'Disposable fixture identity/state mismatch.' }
$snapshots = @(Get-VMSnapshot -VM $vm | Select-Object -ExpandProperty Name)
if ($snapshots.Count -ne 1 -or $snapshots[0] -ne $checkpoint) { throw 'Disposable fixture checkpoint mismatch.' }
$session = $null
$started = $false
$registration = $null
$remote = $null
$cleanup = $null
$outerFailure = $null
try {
    Start-VM -VM $vm | Out-Null
    $started = $true
    $deadline = [DateTime]::UtcNow.AddMinutes(10)
    do {
        try { $session = New-PSSession -VMName $vmName -Credential $credential -ErrorAction Stop }
        catch { Start-Sleep -Seconds 5 }
    } while (-not $session -and [DateTime]::UtcNow -lt $deadline)
    if (-not $session) { throw 'PowerShell Direct unavailable.' }
    Invoke-Command -Session $session -ScriptBlock {
        $paths = @(
            'C:\controlled-inputs\ultra-minimal-wsl\procedure\controlled-package-offline',
            'C:\controlled-inputs\ultra-minimal-wsl\trial-manifests',
            'C:\controlled-inputs\ultra-minimal-wsl\candidate-kernels\K-PIDNS-001',
            'C:\controlled-inputs\ultra-minimal-wsl\candidate-packages\minimal-v8-no-binfmt-mount'
        )
        foreach ($path in $paths) { [IO.Directory]::CreateDirectory($path) | Out-Null }
    }
    Copy-Item -ToSession $session -LiteralPath $runnerSource -Destination 'C:\controlled-inputs\ultra-minimal-wsl\procedure\controlled-package-offline\Invoke-MinimalV8KPidNsDiagnosticTrial.ps1' -Force
    Copy-Item -ToSession $session -LiteralPath $manifestSource -Destination 'C:\controlled-inputs\ultra-minimal-wsl\trial-manifests\minimal-v8-k-pidns-001.json' -Force
    Copy-Item -ToSession $session -LiteralPath $kernelSource -Destination 'C:\controlled-inputs\ultra-minimal-wsl\candidate-kernels\K-PIDNS-001\linux-kernel' -Force
    Copy-Item -ToSession $session -LiteralPath $configSource -Destination 'C:\controlled-inputs\ultra-minimal-wsl\candidate-kernels\K-PIDNS-001\linux-fullconfig' -Force
    Copy-Item -ToSession $session -LiteralPath $packageSource -Destination 'C:\controlled-inputs\ultra-minimal-wsl\candidate-packages\minimal-v8-no-binfmt-mount\wsl.msi' -Force
    Copy-Item -ToSession $session -LiteralPath $probeSource -Destination 'C:\controlled-inputs\ultra-minimal-wsl\procedure\Invoke-WslDebian2PracticalProbe.ps1' -Force
    $registration = Invoke-Command -Session $session -ScriptBlock {
        param($ExpectedVhdxHash)
        Set-StrictMode -Version Latest
        $ErrorActionPreference = 'Stop'
        $wsl = 'C:\Windows\System32\wsl.exe'
        $vhdx = 'C:\controlled-inputs\ultra-minimal-wsl\registered-distros\Debian2\ext4.vhdx'
        $listed = (& $wsl --list --quiet).Replace("`0", '') -split "`r?`n"
        if ($LASTEXITCODE -ne 0 -or $listed -notcontains 'Debian2') { throw 'Retained Debian2 is not registered.' }
        & $wsl --shutdown
        if ($LASTEXITCODE -ne 0) { throw 'Pre-comparison WSL shutdown failed.' }
        if ((Get-FileHash -LiteralPath $vhdx -Algorithm SHA256).Hash.ToLowerInvariant() -ne $ExpectedVhdxHash) { throw 'Retained Debian2 VHDX identity mismatch.' }
        if (Test-Path -LiteralPath (Join-Path $env:USERPROFILE '.wslconfig')) { throw 'Fixture .wslconfig must be absent.' }
        [pscustomobject][ordered]@{registered=$true;distribution='Debian2';vhdx=$vhdx;vhdxSha256=$ExpectedVhdxHash;completedUtc=[DateTime]::UtcNow.ToString('o')}
    } -ArgumentList $expectedArticleVhdxHash
    $remote = Invoke-Command -Session $session -ScriptBlock {
        param($Trial,$Recovery,$RunnerHash,$ManifestHash,$KernelHash,$ConfigHash,$PackageHash,$ProbeHash,$ArticleVhdxHash,$RecoveryProbeHash,$RecoveryRootfsHash,$WprHash)
        Set-StrictMode -Version Latest
        $ErrorActionPreference = 'Stop'
        Set-ExecutionPolicy -Scope Process Bypass -Force
        function Hash([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
        function Verify-Manifest([string]$Directory) {
            $path = Join-Path $Directory 'evidence-manifest.json'
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing evidence manifest: $path" }
            $manifest = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
            foreach ($entry in @($manifest.files)) {
                $file = Join-Path $Directory ([string]$entry.path)
                if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Missing manifested file: $file" }
                if ((Get-Item -LiteralPath $file).Length -ne [int64]$entry.bytes -or (Hash $file) -ne [string]$entry.sha256) { throw "Evidence manifest mismatch: $file" }
            }
            @($manifest.files).Count + 1
        }
        $paths = [ordered]@{
            runner='C:\controlled-inputs\ultra-minimal-wsl\procedure\controlled-package-offline\Invoke-MinimalV8KPidNsDiagnosticTrial.ps1'
            manifest='C:\controlled-inputs\ultra-minimal-wsl\trial-manifests\minimal-v8-k-pidns-001.json'
            kernel='C:\controlled-inputs\ultra-minimal-wsl\candidate-kernels\K-PIDNS-001\linux-kernel'
            config='C:\controlled-inputs\ultra-minimal-wsl\candidate-kernels\K-PIDNS-001\linux-fullconfig'
            package='C:\controlled-inputs\ultra-minimal-wsl\candidate-packages\minimal-v8-no-binfmt-mount\wsl.msi'
            probe='C:\controlled-inputs\ultra-minimal-wsl\procedure\Invoke-WslDebian2PracticalProbe.ps1'
            articleVhdx='C:\controlled-inputs\ultra-minimal-wsl\registered-distros\Debian2\ext4.vhdx'
            recoveryProbe='C:\controlled-inputs\ultra-minimal-wsl\procedure\Invoke-WslCandidateProbe.ps1'
            recoveryRootfs='C:\controlled-inputs\ultra-minimal-wsl\toybox-minimal-wsl-rootfs.tar.gz'
            wpr='C:\controlled-inputs\ultra-minimal-wsl\diagnostics\wsl.wprp'
        }
        $expected = [ordered]@{runner=$RunnerHash;manifest=$ManifestHash;kernel=$KernelHash;config=$ConfigHash;package=$PackageHash;probe=$ProbeHash;articleVhdx=$ArticleVhdxHash;recoveryProbe=$RecoveryProbeHash;recoveryRootfs=$RecoveryRootfsHash;wpr=$WprHash}
        foreach ($name in $paths.Keys) { if ((Hash $paths[$name]) -ne $expected[$name]) { throw "Staged $name hash mismatch." } }
        if ((Get-Item -LiteralPath $paths.kernel).Length -ne 3720192 -or (Get-Item -LiteralPath $paths.package).Length -ne 174403584) { throw 'Staged candidate size mismatch.' }
        if (Test-Path -LiteralPath (Join-Path $env:USERPROFILE '.wslconfig')) { throw 'Fixture .wslconfig must remain absent.' }
        $evidenceParent = 'C:\controlled-wsl-trials'
        foreach ($path in @((Join-Path $evidenceParent $Trial),(Join-Path $evidenceParent $Recovery))) { if (Test-Path -LiteralPath $path) { throw "Reserved evidence path exists: $path" } }
        foreach ($name in @("$Trial-stock-remove.log","$Trial-candidate-install.log","$Trial-candidate-remove.log","$Trial-stock-restore.log","$Trial-runner.stdout.log","$Trial-runner.stderr.log")) { if(Test-Path -LiteralPath (Join-Path $evidenceParent $name)){throw "Reserved runtime log exists: $name"} }
        $selfTest = & $paths.runner -SelfTest | ConvertFrom-Json
        if (-not $selfTest.passed -or @($selfTest.failurePaths).Count -ne 19) { throw 'Runner fault matrix failed.' }
        $validation = & $paths.runner -Validate | ConvertFrom-Json
        if (-not $validation.validated -or $validation.execute -or -not $validation.diagnosticDebugConsole -or $validation.candidateGate -ne 'P6-PI-PACKAGE') { throw 'Runner diagnostic validation failed.' }
        $stdout = Join-Path $evidenceParent "$Trial-runner.stdout.log"
        $stderr = Join-Path $evidenceParent "$Trial-runner.stderr.log"
        $runnerFailure = $null
        $process = $null
        try {
            $process = Start-Process -FilePath 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -ArgumentList @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$paths.runner,'-Execute') -RedirectStandardOutput $stdout -RedirectStandardError $stderr -Wait -PassThru
            if ($process.ExitCode -ne 0) { throw "Exact trial runner failed with exit $($process.ExitCode)." }
        }
        catch { $runnerFailure = $_.Exception.Message }
        Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
public static class RuntimeMsiState {
 [DllImport("msi.dll", CharSet=CharSet.Unicode)] public static extern int MsiQueryProductState(string product);
}
'@
        $stockState = [RuntimeMsiState]::MsiQueryProductState('{020F8AC8-A788-4E39-8E9B-8FECFA843632}')
        $candidateState = [RuntimeMsiState]::MsiQueryProductState('{65E3A12F-0AF8-4D54-A19A-29A07D5186E3}')
        $candidatePath = Join-Path $evidenceParent $Trial
        $recoveryPath = Join-Path $evidenceParent $Recovery
        $candidateResult = if (Test-Path -LiteralPath (Join-Path $candidatePath 'result.json')) { Get-Content -LiteralPath (Join-Path $candidatePath 'result.json') -Raw | ConvertFrom-Json } else { $null }
        $recoveryResult = if (Test-Path -LiteralPath (Join-Path $recoveryPath 'result.json')) { Get-Content -LiteralPath (Join-Path $recoveryPath 'result.json') -Raw | ConvertFrom-Json } else { $null }
        $candidateFiles = if ($candidateResult) { Verify-Manifest $candidatePath } else { 0 }
        $recoveryFiles = if ($recoveryResult) { Verify-Manifest $recoveryPath } else { 0 }
        if (Test-Path -LiteralPath (Join-Path $env:USERPROFILE '.wslconfig')) { throw 'Candidate kernel selection was not removed.' }
        $diagnosticRelayCount = @(Get-Process -Name 'wslrelay' -ErrorAction SilentlyContinue).Count
        if ($diagnosticRelayCount -ne 0) { throw 'Diagnostic relay remained after runner recovery.' }
        foreach ($id in @($Trial,$Recovery)) {
            $source = Join-Path $evidenceParent $id
            if (Test-Path -LiteralPath $source -PathType Container) { Compress-Archive -LiteralPath $source -DestinationPath (Join-Path $evidenceParent ($id + '.zip')) -CompressionLevel Optimal }
        }
        [pscustomobject][ordered]@{schema=1;selfTestFailurePaths=@($selfTest.failurePaths).Count;validation=$validation;runnerFailure=$runnerFailure;runnerExitCode=if($process){$process.ExitCode}else{$null};stockProductState=$stockState;candidateProductState=$candidateState;wslconfigExists=$false;diagnosticRelayCount=$diagnosticRelayCount;candidateEvidenceExists=[bool]$candidateResult;recoveryEvidenceExists=[bool]$recoveryResult;candidateManifestFilesVerified=$candidateFiles;recoveryManifestFilesVerified=$recoveryFiles;candidateResult=$candidateResult;recoveryResult=$recoveryResult;completedUtc=[DateTime]::UtcNow.ToString('o')}
    } -ArgumentList $trial,$recovery,$runnerHash,$manifestHash,$kernelHash,$configHash,$packageHash,$probeHash,$expectedArticleVhdxHash,$recoveryProbeHash,$recoveryRootfsHash,$wprHash
    [IO.Directory]::CreateDirectory($extract) | Out-Null
    foreach ($name in @("$trial.zip","$recovery.zip","$trial-stock-remove.log","$trial-candidate-install.log","$trial-candidate-remove.log","$trial-stock-restore.log","$trial-runner.stdout.log","$trial-runner.stderr.log","$trial-stock-article-verification.json")) {
        $guestPath = Join-Path 'C:\controlled-wsl-trials' $name
        if (Invoke-Command -Session $session -ScriptBlock { param($Path) Test-Path -LiteralPath $Path -PathType Leaf } -ArgumentList $guestPath) { Copy-Item -FromSession $session -LiteralPath $guestPath -Destination (Join-Path $extract $name) }
    }
}
catch { $outerFailure = $_ }
finally {
    if ($session) {
        try {
            $cleanup = Invoke-Command -Session $session -ScriptBlock {
                Set-StrictMode -Version Latest
                $ErrorActionPreference = 'Stop'
                $wsl = 'C:\Windows\System32\wsl.exe'
                $vhdx = 'C:\controlled-inputs\ultra-minimal-wsl\registered-distros\Debian2\ext4.vhdx'
                & $wsl --shutdown
                if ($LASTEXITCODE -ne 0) { throw 'Final WSL shutdown failed.' }
                $listed = (& $wsl --list --quiet).Replace("`0", '') -split "`r?`n"
                if ($LASTEXITCODE -ne 0 -or $listed -notcontains 'Debian2' -or -not (Test-Path -LiteralPath $vhdx)) { throw 'Retained Debian2 final-state verification failed.' }
                [pscustomobject][ordered]@{registered=$true;vhdxSha256=(Get-FileHash -LiteralPath $vhdx -Algorithm SHA256).Hash.ToLowerInvariant();wslconfigAbsent=-not (Test-Path -LiteralPath (Join-Path $env:USERPROFILE '.wslconfig'));completedUtc=[DateTime]::UtcNow.ToString('o')}
            }
        }
        catch { if (-not $outerFailure) { $outerFailure = $_ } }
        [IO.Directory]::CreateDirectory($extract) | Out-Null
        Remove-PSSession $session -ErrorAction SilentlyContinue
    }
    if ($started) {
        $current = Get-VM -Name $vmName -ErrorAction Stop
        if ($current.Id.Guid -ne $vmId) { throw 'Fixture identity changed before shutdown.' }
        if ($current.State -ne [Microsoft.HyperV.PowerShell.VMState]::Off) { Stop-VM -VM $current -Confirm:$false | Out-Null }
        $deadline = [DateTime]::UtcNow.AddMinutes(5)
        do { Start-Sleep -Seconds 2; $current = Get-VM -Name $vmName } while ($current.State -ne [Microsoft.HyperV.PowerShell.VMState]::Off -and [DateTime]::UtcNow -lt $deadline)
        if ($current.State -ne [Microsoft.HyperV.PowerShell.VMState]::Off) { throw 'Disposable fixture did not return Off.' }
    }
}
$final = Get-VM -Name $vmName -ErrorAction Stop
if (@(Get-VMNetworkAdapter -VM $final -ErrorAction Stop).Count -ne 0) { throw 'Fixture must finish with zero network adapters.' }
$extracted = [ordered]@{}
if (Test-Path -LiteralPath $extract) { foreach($file in Get-ChildItem -LiteralPath $extract -File | Sort-Object Name){$extracted[$file.Name]=[ordered]@{bytes=$file.Length;sha256=Hash $file.FullName}} }
Save ([ordered]@{schema=1;registration=$registration;remote=$remote;cleanup=$cleanup;outerFailure=if($outerFailure){$outerFailure.Exception.Message}else{$null};extracted=$extracted;finalVmId=$final.Id.Guid;finalVmState=[string]$final.State;completedUtc=[DateTime]::UtcNow.ToString('o')})
if ($outerFailure) { throw $outerFailure }
if (-not $registration.registered -or -not $cleanup.registered -or -not $cleanup.wslconfigAbsent) { throw 'Debian2 article preservation requirement failed.' }
if ($remote.stockProductState -ne 5 -or $remote.candidateProductState -eq 5 -or $remote.wslconfigExists -or $remote.diagnosticRelayCount -ne 0 -or -not $remote.recoveryResult -or -not $remote.recoveryResult.passed) { throw 'Independent stock recovery and diagnostic cleanup requirement failed.' }
if ($remote.runnerFailure) { throw $remote.runnerFailure }
if (-not $remote.candidateResult -or -not $remote.candidateResult.passed -or $remote.candidateResult.observedGate -ne 'P6-PI-PACKAGE') { throw 'Practical-workload checkpoint requirement failed.' }
