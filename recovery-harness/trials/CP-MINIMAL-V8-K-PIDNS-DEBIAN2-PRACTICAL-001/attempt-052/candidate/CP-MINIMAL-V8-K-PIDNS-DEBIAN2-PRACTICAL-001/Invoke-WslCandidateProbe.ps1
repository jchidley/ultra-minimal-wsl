#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$')]
    [string]$TrialId,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$')]
    [string]$CandidateId,

    [Parameter(Mandatory = $true)]
    [string]$CandidateManifestPath,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-fA-F]{64}$')]
    [string]$ExpectedCandidateManifestSha256,

    [Parameter(Mandatory = $true)]
    [string]$PackagePath,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-fA-F]{64}$')]
    [string]$ExpectedPackageSha256,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-fA-F]{64}$')]
    [string]$ExpectedProbeSha256,

    [string]$Distribution = 'Debian2',
    [string]$ExpectedWslVersion = '2.7.12.0',
    [string]$ArticleVhdxPath = 'C:\controlled-inputs\ultra-minimal-wsl\registered-distros\Debian2\ext4.vhdx',
    [ValidatePattern('^[0-9a-fA-F]{64}$')]
    [string]$ExpectedArticleVhdxSha256 = '0c803f68d7cb3b0f8e0b29022df5413a43bd96bcb0a947f47712155d1895d388',
    [string]$WprProfilePath = 'C:\controlled-inputs\ultra-minimal-wsl\diagnostics\wsl.wprp',
    [ValidatePattern('^[0-9a-fA-F]{64}$')]
    [string]$ExpectedWprProfileSha256 = '3f829a9af733d6dce9454a1df2e2aa07096acaaed5b6865ffb5c202d089479f2',
    [string]$EvidenceParent = 'C:\controlled-wsl-trials',
    [ValidateRange(5, 600)]
    [int]$TimeoutSeconds = 45,
    [switch]$Execute,
    [switch]$SelfTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Checkpoints = [ordered]@{
    '01-debian-base' = @('--distribution',$Distribution,'--user','jack','--exec','/bin/bash','-c','/bin/true && test -r /proc/self/status && test -d /sys && test -c /dev/null && printf checkpoint-01-ok')
    '02-article-manifest' = @('--distribution',$Distribution,'--user','root','--exec','/bin/bash','-c','set -e; m=/var/lib/debian2-article/manifest.json; test -r "$m"; grep -F ''"articleId": "debian2-stock-bootstrap-v10"'' "$m"; grep -F ''"defaultUser": "jack"'' "$m"; grep -F ''"secrets": "none"'' "$m"; printf checkpoint-02-ok')
    '03-login-shell' = @('--distribution',$Distribution,'--user','jack','--exec','/bin/bash','-lic','test "$HOME" = /home/jack; printf checkpoint-03-ok')
    '04-tool-versions' = @('--distribution',$Distribution,'--user','jack','--exec','/bin/bash','-lic','set -e; test "$(node --version)" = v22.19.0; test "$(npm --version)" = 10.9.3; test "$(fnm --version)" = ''fnm 1.38.1''; test "$(mcfly --version)" = ''mcfly 0.9.4''; test "$(chezmoi --version | head -n1)" = ''chezmoi version v2.69.4''; printf checkpoint-04-ok')
    '05-core-repositories' = @('--distribution',$Distribution,'--user','jack','--exec','/bin/bash','-lic','set -e; for d in "$HOME/.local/share/chezmoi" "$HOME/git/agent-skills" "$HOME/tools"; do test -d "$d/.git"; done; printf checkpoint-05-ok')
    '06-pi-package' = @('--distribution',$Distribution,'--user','jack','--exec','/bin/bash','-lic','set -e; test "$(pi --version)" = 0.84.4; pi list | tr -d "\r" | grep -F "$HOME/git/agent-skills" >/dev/null; printf checkpoint-06-ok')
}
$SuccessMarker = 'checkpoint-06-ok'
$EvidenceRoot = Join-Path $EvidenceParent $TrialId
$WslExe = Join-Path $env:SystemRoot 'System32\wsl.exe'
$ProbePath = $MyInvocation.MyCommand.Path

function Get-Sha256([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Required file is missing: $Path" }
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Write-JsonAtomic([object]$Value, [string]$Path) {
    $temporary = "$Path.$([Guid]::NewGuid().ToString('N')).tmp"
    try {
        [IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 16), [Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temporary -Destination $Path -ErrorAction Stop
    }
    finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
    }
}

function Join-WindowsCommandLine([string[]]$Arguments) {
    @($Arguments | ForEach-Object {
        if ($_ -notmatch '[\s"]') { $_ }
        else { '"' + ([regex]::Replace($_, '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1') + '"' }
    }) -join ' '
}

function ConvertFrom-WslConsoleText([string]$Text) {
    $Text.Replace("`0", '')
}

function Invoke-BoundedProcess([string]$Name, [string[]]$Arguments, [int]$Timeout, [string]$OutputDirectory) {
    $attemptPath = Join-Path $OutputDirectory "$Name-attempt.json"
    $resultPath = Join-Path $OutputDirectory "$Name-result.json"
    Write-JsonAtomic ([ordered]@{
        schema = 1; name = $Name; file = $WslExe; arguments = $Arguments
        attemptedUtc = [DateTime]::UtcNow.ToString('o')
    }) $attemptPath

    $started = [DateTime]::UtcNow
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $WslExe
    $info.Arguments = Join-WindowsCommandLine $Arguments
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $info
    if (-not $process.Start()) { throw "Failed to start process '$Name'." }
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $timedOut = -not $process.WaitForExit($Timeout * 1000)
    $taskkillExit = $null
    if ($timedOut) {
        $killer = Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\taskkill.exe') -ArgumentList @('/PID', [string]$process.Id, '/T', '/F') -Wait -PassThru -WindowStyle Hidden
        $taskkillExit = $killer.ExitCode
        $null = $process.WaitForExit(10000)
    }
    $streamsCompleted = [Threading.Tasks.Task]::WaitAll(@($stdoutTask, $stderrTask), 10000)
    $result = [ordered]@{
        schema = 1; name = $Name; file = $WslExe; arguments = $Arguments; processId = $process.Id
        startedUtc = $started.ToString('o'); completedUtc = [DateTime]::UtcNow.ToString('o')
        timedOut = $timedOut; streamsCompleted = $streamsCompleted; taskkillExitCode = $taskkillExit
        exitCode = if ($process.HasExited) { $process.ExitCode } else { $null }
        stdout = if ($stdoutTask.IsCompleted) { $stdoutTask.GetAwaiter().GetResult() } else { '<stdout collection timed out>' }
        stderr = if ($stderrTask.IsCompleted) { $stderrTask.GetAwaiter().GetResult() } else { '<stderr collection timed out>' }
    }
    Write-JsonAtomic $result $resultPath
    [pscustomobject]$result
}

function Save-NewCrashFiles([string]$Destination, [datetime]$SinceUtc) {
    $source = Join-Path $env:TEMP 'wsl-crashes'
    if (-not (Test-Path -LiteralPath $source -PathType Container)) { return }
    $target = Join-Path $Destination 'wsl-crashes'
    foreach ($file in Get-ChildItem -LiteralPath $source -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTimeUtc -ge $SinceUtc }) {
        [IO.Directory]::CreateDirectory($target) | Out-Null
        Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $target $file.Name) -ErrorAction Stop
    }
}

function Save-WindowsEvents([string]$Path, [datetime]$SinceUtc) {
    try {
        $events = Get-WinEvent -FilterHashtable @{ LogName = @('System', 'Application'); StartTime = $SinceUtc } -ErrorAction Stop |
            Where-Object { $_.ProviderName -match 'WSL|Lxss|Hyper-V|Host Compute|Service Control Manager' } |
            Select-Object TimeCreated, Id, LevelDisplayName, ProviderName, LogName, Message
        Write-JsonAtomic @($events) $Path
    }
    catch {
        Write-JsonAtomic ([ordered]@{ schema=1; category='event-capture-failure'; exceptionType=$_.Exception.GetType().FullName }) ($Path + '.error.json')
    }
}

function Write-EvidenceManifest([string]$Directory) {
    $files = @(Get-ChildItem -LiteralPath $Directory -Recurse -File | Where-Object Name -ne 'evidence-manifest.json' | Sort-Object FullName | ForEach-Object {
        [ordered]@{
            path = $_.FullName.Substring($Directory.Length).TrimStart('\')
            bytes = $_.Length
            sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    })
    Write-JsonAtomic ([ordered]@{ schema=1; trialId=$TrialId; candidateId=$CandidateId; files=$files }) (Join-Path $Directory 'evidence-manifest.json')
}

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Candidate probe execution requires elevated PowerShell for WPR capture.' }
}

if ($SelfTest) {
    $quoted = Join-WindowsCommandLine $Checkpoints['06-pi-package']
    if ($quoted -notmatch 'pi list' -or $Checkpoints.Count -ne 6) { throw 'Checkpoint command-line self-test failed.' }
    $temporary = Join-Path ([IO.Path]::GetTempPath()) ('wsl-candidate-probe-' + [Guid]::NewGuid().ToString('N'))
    try {
        [IO.Directory]::CreateDirectory($temporary) | Out-Null
        [IO.File]::WriteAllText((Join-Path $temporary 'evidence.txt'), 'probe', [Text.UTF8Encoding]::new($false))
        Write-EvidenceManifest $temporary
        $manifest = Get-Content -LiteralPath (Join-Path $temporary 'evidence-manifest.json') -Raw | ConvertFrom-Json
        if ($manifest.files.Count -ne 1 -or $manifest.files[0].sha256 -ne 'ba9c736f19e7f60b7f6764adb0b7908c0a2b394e09b6c09863528c7f2bc86095') { throw 'Evidence manifest self-test failed.' }
    }
    finally { Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue }
    [pscustomobject][ordered]@{ schema=1; selfTest=$true; passed=$true; checkpoints=@($Checkpoints.Keys); successMarker=$SuccessMarker } | ConvertTo-Json -Compress
    exit 0
}

$plan = [ordered]@{
    schema = 1; action = 'wsl-candidate-probe'; execute = [bool]$Execute; safe = $false
    trialId = $TrialId; candidateId = $CandidateId; distribution = $Distribution; expectedWslVersion = $ExpectedWslVersion
    candidateManifest = $CandidateManifestPath; expectedCandidateManifestSha256 = $ExpectedCandidateManifestSha256.ToLowerInvariant()
    package = $PackagePath; expectedPackageSha256 = $ExpectedPackageSha256.ToLowerInvariant()
    probe = $ProbePath; expectedProbeSha256 = $ExpectedProbeSha256.ToLowerInvariant()
    articleVhdx = $ArticleVhdxPath; expectedArticleVhdxSha256 = $ExpectedArticleVhdxSha256.ToLowerInvariant()
    wprProfile = $WprProfilePath; expectedWprProfileSha256 = $ExpectedWprProfileSha256.ToLowerInvariant()
    evidenceRoot = $EvidenceRoot; timeoutSeconds = $TimeoutSeconds; debugConsoleCapture = 'disabled-for-fixed-comparison'
    checkpoints = @($Checkpoints.Keys)
    note = 'Candidate measurement only. Fixture start, transport, package installation, evidence extraction, ledger append, and recovery are external preconditions and must not affect candidate classification.'
}
$plan | ConvertTo-Json -Depth 8
if (-not $Execute) { exit 0 }

Assert-Administrator
if (Test-Path -LiteralPath $EvidenceRoot) { throw "Evidence root already exists: $EvidenceRoot" }
if ((Get-Sha256 $CandidateManifestPath) -ne $ExpectedCandidateManifestSha256.ToLowerInvariant()) { throw 'Candidate manifest SHA-256 mismatch.' }
if ((Get-Sha256 $PackagePath) -ne $ExpectedPackageSha256.ToLowerInvariant()) { throw 'WSL package SHA-256 mismatch.' }
if ((Get-Sha256 $ProbePath) -ne $ExpectedProbeSha256.ToLowerInvariant()) { throw 'Candidate probe SHA-256 mismatch.' }
if ((Get-Sha256 $ArticleVhdxPath) -ne $ExpectedArticleVhdxSha256.ToLowerInvariant()) { throw 'Debian2 article VHDX SHA-256 mismatch.' }
if ((Get-Sha256 $WprProfilePath) -ne $ExpectedWprProfileSha256.ToLowerInvariant()) { throw 'WSL WPR profile SHA-256 mismatch.' }
if (-not (Test-Path -LiteralPath $WslExe -PathType Leaf)) { throw 'wsl.exe is missing.' }
if (-not (Get-Command wpr.exe -ErrorAction SilentlyContinue)) { throw 'wpr.exe is unavailable.' }
[IO.Directory]::CreateDirectory($EvidenceRoot) | Out-Null
$preparationStarted = [DateTime]::UtcNow
$candidateStarted = $null
$wprStarted = $false
$primaryFailure = $null
$infrastructureFailure = $null
$traceFailure = $null
$shutdownFailure = $null
$results = [ordered]@{}
$tracePath = Join-Path $EvidenceRoot 'windows-wsl.etl'

Copy-Item -LiteralPath $CandidateManifestPath -Destination (Join-Path $EvidenceRoot 'candidate-manifest.json')
Copy-Item -LiteralPath $ProbePath -Destination (Join-Path $EvidenceRoot 'Invoke-WslCandidateProbe.ps1')
Write-JsonAtomic ([ordered]@{
    schema=1; trialId=$TrialId; candidateId=$CandidateId
    candidateManifestSha256=$ExpectedCandidateManifestSha256.ToLowerInvariant()
    packagePath=$PackagePath; packageSha256=$ExpectedPackageSha256.ToLowerInvariant()
    probeSha256=$ExpectedProbeSha256.ToLowerInvariant()
    articleVhdxPath=$ArticleVhdxPath; articleVhdxSha256=$ExpectedArticleVhdxSha256.ToLowerInvariant()
    wprProfilePath=$WprProfilePath; wprProfileSha256=$ExpectedWprProfileSha256.ToLowerInvariant()
    expectedWslVersion=$ExpectedWslVersion; distribution=$Distribution; timeoutSeconds=$TimeoutSeconds
    checkpoints=@($Checkpoints.Keys); debugConsoleCapture='disabled-for-fixed-comparison'
}) (Join-Path $EvidenceRoot 'input-identities.json')

try {
    $wprOutput = & wpr.exe -start ($WprProfilePath + '!WSL') -filemode 2>&1
    $wprCode = $LASTEXITCODE
    [IO.File]::WriteAllLines((Join-Path $EvidenceRoot 'wpr-start.log'), [string[]]@($wprOutput), [Text.UTF8Encoding]::new($false))
    if ($wprCode -ne 0) { throw "WPR start failed with exit $wprCode." }
    $wprStarted = $true

    $candidateStarted = [DateTime]::UtcNow
    Write-JsonAtomic ([ordered]@{
        schema=1; action='candidate-interval-start'; trialId=$TrialId; candidateId=$CandidateId
        startedUtc=$candidateStarted.ToString('o')
    }) (Join-Path $EvidenceRoot 'interval-start.json')
    $results.version = Invoke-BoundedProcess 'wsl-version' @('--version') $TimeoutSeconds $EvidenceRoot
    $versionText = ConvertFrom-WslConsoleText (([string]$results.version.stdout) + ([string]$results.version.stderr))
    if ($versionText -match 'Windows Subsystem for Linux is not installed') {
        $infrastructureFailure = [System.Management.Automation.ErrorRecord]::new(
            [InvalidOperationException]::new('The fixture does not have WSL installed.'),
            'WslNotInstalled', [System.Management.Automation.ErrorCategory]::NotInstalled, $WslExe)
        throw $infrastructureFailure
    }
    $results.status = Invoke-BoundedProcess 'wsl-status' @('--status') $TimeoutSeconds $EvidenceRoot
    $statusText = ConvertFrom-WslConsoleText (([string]$results.status.stdout) + ([string]$results.status.stderr))
    if ($statusText -match 'WSL2 is unable to start since virtualization is not enabled' -or
        $statusText -match 'Virtual Machine Platform.*optional component.*enabled') {
        $infrastructureFailure = [System.Management.Automation.ErrorRecord]::new(
            [InvalidOperationException]::new('The fixture WSL optional-component prerequisites are disabled.'),
            'WslPrerequisitesDisabled', [System.Management.Automation.ErrorCategory]::NotEnabled, $WslExe)
        throw $infrastructureFailure
    }
    $results.list = Invoke-BoundedProcess 'wsl-list-quiet' @('--list','--quiet') $TimeoutSeconds $EvidenceRoot
    $listed = ([string]$results.list.stdout).Replace("`0", '') -split "`r?`n"
    if (-not $results.list.timedOut -and $results.list.exitCode -eq 0 -and $listed -notcontains $Distribution) {
        $infrastructureFailure = [System.Management.Automation.ErrorRecord]::new(
            [InvalidOperationException]::new("Required registered distro '$Distribution' is absent."),
            'RequiredDistroAbsent', [System.Management.Automation.ErrorCategory]::ObjectNotFound, $Distribution)
        throw $infrastructureFailure
    }
    if ($results.list.timedOut -or $results.list.exitCode -ne 0) { throw 'The candidate did not complete distro enumeration; trace analysis is required.' }
    foreach ($checkpoint in $Checkpoints.GetEnumerator()) {
        $result = Invoke-BoundedProcess $checkpoint.Key $checkpoint.Value $TimeoutSeconds $EvidenceRoot
        $results[$checkpoint.Key] = $result
        $expectedMarker = 'checkpoint-' + $checkpoint.Key.Substring(0,2) + '-ok'
        if ($result.timedOut -or -not $result.streamsCompleted -or $result.exitCode -ne 0 -or -not ([string]$result.stdout).Contains($expectedMarker)) { break }
    }
}
catch {
    $primaryFailure = $_
    if ($null -eq $candidateStarted) { $infrastructureFailure = $_ }
}
finally {
    try { $results.shutdown = Invoke-BoundedProcess 'wsl-shutdown' @('--shutdown') 30 $EvidenceRoot }
    catch { $shutdownFailure = $_ }
    if ($wprStarted) {
        try {
            $wprStopOutput = & wpr.exe -stop $tracePath 2>&1
            $wprStopCode = $LASTEXITCODE
            [IO.File]::WriteAllLines((Join-Path $EvidenceRoot 'wpr-stop.log'), [string[]]@($wprStopOutput), [Text.UTF8Encoding]::new($false))
            if ($wprStopCode -ne 0 -or -not (Test-Path -LiteralPath $tracePath -PathType Leaf)) { throw "WPR stop failed with exit $wprStopCode." }
        }
        catch { $traceFailure = $_; & wpr.exe -cancel 2>&1 | Out-File -LiteralPath (Join-Path $EvidenceRoot 'wpr-cancel.log') -Encoding utf8 }
    }
    Save-WindowsEvents (Join-Path $EvidenceRoot 'windows-events.json') $preparationStarted
    Save-NewCrashFiles $EvidenceRoot $preparationStarted

    $completedCheckpoints = @($Checkpoints.Keys | Where-Object {
        $r = $results[$_]
        $marker = 'checkpoint-' + $_.Substring(0,2) + '-ok'
        $r -and -not $r.timedOut -and $r.streamsCompleted -and $r.exitCode -eq 0 -and ([string]$r.stdout).Contains($marker)
    })
    $earliestFailure = @($Checkpoints.Keys | Where-Object { $_ -notin $completedCheckpoints } | Select-Object -First 1)
    $practicalPassed = $completedCheckpoints.Count -eq $Checkpoints.Count
    $eventCaptureFailed = Test-Path -LiteralPath (Join-Path $EvidenceRoot 'windows-events.json.error.json')
    $observedGate = if ($practicalPassed) { 'P6-PI-PACKAGE' } elseif ($completedCheckpoints.Count) { 'P' + $completedCheckpoints.Count } else { 'UNRESOLVED-TRACE-REQUIRED' }
    $classification = if ($infrastructureFailure) { 'NOT-A-CANDIDATE-RESULT' } elseif ($traceFailure -or $shutdownFailure -or $eventCaptureFailed) { 'INCOMPLETE-EVIDENCE' } else { $observedGate }
    $candidateResult = $null -eq $infrastructureFailure
    $disposition = if ($infrastructureFailure) { 'infrastructure-failure' } elseif ($practicalPassed) { 'candidate-pass' } else { 'candidate-evidence-requires-analysis' }
    $managementChecksPassed = $results.Contains('version') -and $results.Contains('status') -and $results.Contains('list') -and
        -not $results.version.timedOut -and $results.version.exitCode -eq 0 -and (ConvertFrom-WslConsoleText ([string]$results.version.stdout)).Contains($ExpectedWslVersion) -and
        -not $results.status.timedOut -and $results.status.exitCode -eq 0 -and
        -not $results.list.timedOut -and $results.list.exitCode -eq 0
    $passed = $practicalPassed -and $managementChecksPassed -and $null -eq $primaryFailure -and $null -eq $traceFailure -and $null -eq $shutdownFailure
    Write-JsonAtomic ([ordered]@{
        schema=1; trialId=$TrialId; candidateId=$CandidateId
        preparationStartedUtc=$preparationStarted.ToString('o'); candidateStartedUtc=if($candidateStarted){$candidateStarted.ToString('o')}else{$null}; completedUtc=[DateTime]::UtcNow.ToString('o')
        candidateResult=$candidateResult; disposition=$disposition; observedGate=$observedGate; classification=$classification; managementChecksPassed=$managementChecksPassed; passed=$passed
        completedCheckpoints=$completedCheckpoints; earliestFailure=if($earliestFailure.Count){$earliestFailure[0]}else{$null}
        articleVhdxSha256AfterCandidateShutdown=if(Test-Path -LiteralPath $ArticleVhdxPath){Get-Sha256 $ArticleVhdxPath}else{$null}
        primaryFailure=if($primaryFailure){$primaryFailure.Exception.GetType().FullName}else{$null}
        infrastructureFailure=if($infrastructureFailure){$infrastructureFailure.Exception.GetType().FullName}else{$null}
        traceFailure=if($traceFailure){$traceFailure.Exception.GetType().FullName}else{$null}
        shutdownFailure=if($shutdownFailure){$shutdownFailure.Exception.GetType().FullName}else{$null}
        results=$results
    }) (Join-Path $EvidenceRoot 'result.json')
    Write-EvidenceManifest $EvidenceRoot
}

if ($primaryFailure) { throw $primaryFailure }
if ($traceFailure) { throw $traceFailure }
if ($shutdownFailure) { throw $shutdownFailure }
if ((Get-Content -LiteralPath (Join-Path $EvidenceRoot 'result.json') -Raw | ConvertFrom-Json).passed -ne $true) { throw 'Controlled WSL practical-workload probe did not complete all checkpoints.' }
