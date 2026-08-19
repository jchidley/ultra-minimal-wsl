# AGENTS.md

## Read first

Current facts and work order are in `STATUS.md` and `TASKS.md`. Trial rules are
in `MINIMAL-BOOT-PLAN.md`; recovery details are in
`WSL-DEVELOPMENT-AND-RECOVERY.md` and `recovery-harness/README.md`.

## Non-disruptive commands

Run Windows PowerShell through `windows-env/ps-exec` from Git Bash:

```bash
~/git/agent-skills/skills/windows-env/ps-exec --stdin <<'POWERSHELL'
$project = 'C:\Users\jackc\git\ultra-minimal-wsl'
& "$project\tools\Test-WslSafeState.ps1"
POWERSHELL

~/git/agent-skills/skills/windows-env/ps-exec --stdin <<'POWERSHELL'
$project = 'C:\Users\jackc\git\ultra-minimal-wsl'
& "$project\tools\Test-WslKernelTrial.ps1" -ProjectRoot $project
POWERSHELL
```

The safe-state verifier emits JSON and may intentionally exit 1 when installed
WSL state differs from the recovery-validated baseline. Diagnose; do not edit
the baseline merely to make it pass.

## Boundaries

- WSL kernel selection and shutdown affect every WSL 2 distribution.
- Require explicit user approval before any `-Execute` trial, WSL shutdown,
  `.wslconfig` change, elevation, or custom-kernel boot.
- Never write under `C:\Program Files\WSL` or manually replace its initrd.
- Preserve completed trial directories and ledger rows as immutable evidence.
- Do not accept new WSL version/package hashes without a successful approved
  stock recovery validation.
- Keep builds and source worktrees on `LFS-Builder` ext4, not `/mnt/c`.
- Keep ignored binaries and raw traces out of Git; commit configs, metadata,
  hashes, extracted evidence, and analysis.

## Gotchas

- Use `windows-env/wsl-exec` and `windows-env/ps-exec` at shell boundaries;
  do not reconstruct nested `wsl.exe` or PowerShell command strings.
- A caller timeout does not prove a destination build or elevated process
  stopped. Use durable status/log files and verify independently.
- Paths recorded in prior trial logs and `inventory/trials.csv` are historical
  evidence and may refer to the former Downloads location; do not rewrite them.
