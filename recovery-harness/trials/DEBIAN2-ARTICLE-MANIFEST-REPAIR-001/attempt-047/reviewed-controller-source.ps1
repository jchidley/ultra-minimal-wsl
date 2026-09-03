#Requires -Version 7.0
# FixtureBroker-SecureWorkload: 1
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$vmName = 'ultra-minimal-wsl-dev'
$vmId = 'dcbf722c-0702-444e-9496-04a4623c3198'
$checkpoint = 'clean-shell'
$project = 'C:\Users\jackc\git\ultra-minimal-wsl'
$repairSource = Join-Path $project 'control-plane\test-article\Repair-Debian2Manifest.sh'
$repairHash = '1c9c4be9ebd5105191bff45387c4b26d8d583952b627e20b8b2ffbb9407f7d76'
$priorVhdxHash = 'c210ba2def3877a1ed6ffd4f1f93195482075aeb3bf341d2538dfd6ef1db2d2e'
$root = [Environment]::GetEnvironmentVariable('ULTRAMINIMALWSL_SECURE_RUN_ROOT')
$credentialPath = [Environment]::GetEnvironmentVariable('ULTRAMINIMALWSL_SECURE_CREDENTIAL')
if (-not $root -or -not $credentialPath) { throw 'Protected broker environment is required.' }
$root = [IO.Path]::GetFullPath($root).TrimEnd('\')
$expectedRoot = [IO.Path]::GetFullPath((Join-Path $env:ProgramData 'UltraMinimalWslFixtureBroker\Runs')).TrimEnd('\')
if (-not $root.StartsWith($expectedRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Protected run root mismatch.' }
$operationId = Split-Path $root -Leaf
if ($operationId -notmatch '^debian2-article-manifest-repair-[0-9]{3}$') { throw 'Protected run ID is not a Debian2 manifest repair operation.' }
$resultDirectory = Join-Path $root 'results\debian2'
$resultPath = Join-Path $root 'results\workload-operation-result.json'
$credential = Import-Clixml -LiteralPath $credentialPath
function Hash([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Save([object]$Value) { [IO.File]::WriteAllText($resultPath, ($Value | ConvertTo-Json -Depth 20), [Text.UTF8Encoding]::new($false)) }
if ((Hash $repairSource) -ne $repairHash) { throw 'Manifest repair source identity mismatch.' }

$vm = Get-VM -Name $vmName -ErrorAction Stop
if ($vm.Id.Guid -ne $vmId -or $vm.State -ne [Microsoft.HyperV.PowerShell.VMState]::Off) { throw 'Disposable fixture identity/state mismatch.' }
$snapshots = @(Get-VMSnapshot -VM $vm | Select-Object -ExpandProperty Name)
if ($snapshots.Count -ne 1 -or $snapshots[0] -ne $checkpoint) { throw 'Disposable fixture checkpoint mismatch.' }
if (@(Get-VMNetworkAdapter -VM $vm -ErrorAction Stop).Count -ne 0) { throw 'Fixture must begin with zero network adapters.' }

$session = $null
$started = $false
$remote = $null
$failure = $null
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
        $stage = 'C:\controlled-inputs\ultra-minimal-wsl\debian2\manifest-repair'
        $evidence = 'C:\controlled-wsl-trials\DEBIAN2-ARTICLE-MANIFEST-REPAIR-001'
        if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
        if (Test-Path $evidence) { Remove-Item $evidence -Recurse -Force }
        [IO.Directory]::CreateDirectory($stage) | Out-Null
        [IO.Directory]::CreateDirectory($evidence) | Out-Null
    }
    Copy-Item -ToSession $session -LiteralPath $repairSource -Destination 'C:\controlled-inputs\ultra-minimal-wsl\debian2\manifest-repair\Repair-Debian2Manifest.sh'
    $remote = Invoke-Command -Session $session -ScriptBlock {
        param($RepairHash,$PriorVhdxHash)
        Set-StrictMode -Version Latest
        $ErrorActionPreference = 'Stop'
        $wsl = 'C:\Windows\System32\wsl.exe'
        $name = 'Debian2'
        $install = 'C:\controlled-inputs\ultra-minimal-wsl\registered-distros\Debian2'
        $repair = 'C:\controlled-inputs\ultra-minimal-wsl\debian2\manifest-repair\Repair-Debian2Manifest.sh'
        $evidence = 'C:\controlled-wsl-trials\DEBIAN2-ARTICLE-MANIFEST-REPAIR-001'
        function Hash([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
        function Join-WindowsCommandLine([string[]]$Arguments) {
            @($Arguments | ForEach-Object { if ($_ -notmatch '[\s"]') { $_ } else { '"' + ([regex]::Replace($_, '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1') + '"' } }) -join ' '
        }
        function Invoke-Captured([string[]]$Arguments) {
            $info=[Diagnostics.ProcessStartInfo]::new();$info.FileName=$wsl;$info.Arguments=Join-WindowsCommandLine $Arguments;$info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
            $process=[Diagnostics.Process]::new();$process.StartInfo=$info;if(-not $process.Start()){throw 'Failed to start manifest repair.'}
            $stdoutTask=$process.StandardOutput.ReadToEndAsync();$stderrTask=$process.StandardError.ReadToEndAsync();$timedOut=-not $process.WaitForExit(120000)
            if($timedOut){$killer=Start-Process 'C:\Windows\System32\taskkill.exe' -ArgumentList @('/PID',[string]$process.Id,'/T','/F') -Wait -PassThru -WindowStyle Hidden;$null=$process.WaitForExit(10000)}
            $streams=[Threading.Tasks.Task]::WaitAll(@($stdoutTask,$stderrTask),10000);$stdout=if($stdoutTask.IsCompleted){$stdoutTask.GetAwaiter().GetResult()}else{'<timeout>'};$stderr=if($stderrTask.IsCompleted){$stderrTask.GetAwaiter().GetResult()}else{'<timeout>'}
            [IO.File]::WriteAllText((Join-Path $evidence 'repair.stdout.log'),$stdout,[Text.UTF8Encoding]::new($false));[IO.File]::WriteAllText((Join-Path $evidence 'repair.stderr.log'),$stderr,[Text.UTF8Encoding]::new($false))
            if($timedOut -or -not $streams -or $process.ExitCode -ne 0){throw "Manifest repair failed: timeout=$timedOut streams=$streams exit=$($process.ExitCode)."}
            $stdout
        }
        if ((Hash $repair) -ne $RepairHash) { throw 'Staged manifest repair identity mismatch.' }
        $listed=(& $wsl --list --quiet).Replace("`0",'') -split "`r?`n";if($LASTEXITCODE-ne 0 -or $listed -notcontains $name){throw 'Debian2 is not registered.'}
        $config=Join-Path $env:USERPROFILE '.wslconfig';if(Test-Path $config){throw 'Fixture .wslconfig must be absent.'}
        $vhdx=Join-Path $install 'ext4.vhdx';if((Hash $vhdx)-ne$PriorVhdxHash){throw 'Debian2 pre-repair VHDX identity mismatch.'}
        $manifestText=Invoke-Captured @('--distribution',$name,'--user','root','--exec','/bin/bash','/mnt/c/controlled-inputs/ultra-minimal-wsl/debian2/manifest-repair/Repair-Debian2Manifest.sh')
        & $wsl --shutdown;if($LASTEXITCODE-ne 0){throw 'WSL shutdown failed after manifest repair.'}
        $manifest=$manifestText|ConvertFrom-Json
        if($manifest.npm -notmatch '^[0-9]+\.' -or $manifest.pi -ne '0.84.4' -or $manifest.secrets -ne 'none'){throw 'Corrected manifest fields are invalid.'}
        [IO.File]::WriteAllText((Join-Path $evidence 'article-manifest.json'),$manifestText,[Text.UTF8Encoding]::new($false))
        [pscustomobject]@{distribution=$name;defaultUser=$manifest.defaultUser;npm=$manifest.npm;pi=$manifest.pi;priorVhdxSha256=$PriorVhdxHash;vhdxBytes=(Get-Item $vhdx).Length;vhdxSha256=Hash $vhdx;wslconfigAbsent=-not(Test-Path $config)}
    } -ArgumentList $repairHash,$priorVhdxHash
    [IO.Directory]::CreateDirectory($resultDirectory) | Out-Null
    foreach($name in @('repair.stdout.log','repair.stderr.log','article-manifest.json')){Copy-Item -FromSession $session -LiteralPath (Join-Path 'C:\controlled-wsl-trials\DEBIAN2-ARTICLE-MANIFEST-REPAIR-001' $name) -Destination (Join-Path $resultDirectory $name)}
    Save ([ordered]@{schema=1;operation=$operationId;repair=$remote;completedUtc=[DateTime]::UtcNow.ToString('o')})
}
catch { $failure=$_; Save ([ordered]@{schema=1;operation=$operationId;failure=$_.Exception.Message;completedUtc=[DateTime]::UtcNow.ToString('o')}) }
finally {
    if($session){Remove-PSSession $session -ErrorAction SilentlyContinue}
    if($started){$current=Get-VM -Name $vmName;if($current.State-ne[Microsoft.HyperV.PowerShell.VMState]::Off){Stop-VM -VM $current -Confirm:$false|Out-Null};$deadline=[DateTime]::UtcNow.AddMinutes(5);do{Start-Sleep 2;$current=Get-VM -Name $vmName}while($current.State-ne[Microsoft.HyperV.PowerShell.VMState]::Off -and [DateTime]::UtcNow-lt$deadline);if($current.State-ne[Microsoft.HyperV.PowerShell.VMState]::Off){throw 'Fixture did not return Off.'}}
}
if($failure){throw $failure}
$final=Get-VM -Name $vmName
if($final.State-ne[Microsoft.HyperV.PowerShell.VMState]::Off -or @(Get-VMNetworkAdapter -VM $final).Count-ne 0){throw 'Fixture final state mismatch.'}
if(-not $remote -or $remote.pi-ne'0.84.4' -or -not $remote.wslconfigAbsent){throw 'Manifest repair acceptance failed.'}
