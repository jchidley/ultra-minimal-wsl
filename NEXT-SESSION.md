# Next-session restart brief

## Bounded objective

Resolve the compiler-layout acquisition task in `TASKS.md`: establish and evidence a supported, non-installing way to acquire the pinned offline compiler inputs, then verify and record the reusable layout. This is preparation only; it proves no WSL runtime gate and authorizes no installation, VM operation, or trial.

## Rebuild context

Read, in order:

1. `AGENTS.md` — operating and approval boundaries
2. `STATUS.md` — verified current facts and blocker
3. `TASKS.md` — active critical path
4. `MINIMAL-BOOT-PLAN.md` — durable proof order and acceptance rules
5. `control-plane/deferred-runtime-plan.json` — exact acquisition evidence and missing inputs

Run from the repository root in PowerShell:

```powershell
git status --short --branch
git rev-parse HEAD
git rev-parse origin/main
uv run python tools/inventory_records.py
$Plan = Get-Content -Raw control-plane/deferred-runtime-plan.json | ConvertFrom-Json
$Plan | Select-Object executable, approval_carried_forward, missing_before_plan_validation
```

Require inventory integrity `ok`, both plan flags `false`, and the committed candidate/evidence set to remain intact. Stop on an unexpected ref, changed approval state, missing evidence, or integrity failure. Do not reset, clean, or rewrite completed ledgers to hide a mismatch.

## Execute only the bounded action

1. Treat `control-plane/deferred-runtime-plan.json` as the authority for exact product, catalog, source, cache, bootstrapper, prior-attempt, and hash evidence.
2. Identify an official acquisition mechanism that binds the pinned inputs without installation or silent movement to a live catalog. Record the supported command and its evidence in the existing plan before use.
3. Do not install a product, substitute a different product, follow a live channel, operate a VM, request elevation, change WSL, or execute the deferred runtime plan.
4. If acquisition succeeds, run the official layout verification, generate the deterministic external relative-path SHA-256 manifest, and record the layout identity, manifest identity, file count, byte count, and verification result in the existing plan.
5. Update `STATUS.md` and `TASKS.md` only after the recorded evidence changes. Keep detailed acquisition evidence out of overview and conceptual documents.

## Validate

```powershell
Get-Content -Raw control-plane/deferred-runtime-plan.json | ConvertFrom-Json | Out-Null
uv run python tools/inventory_records.py
git diff --check
```

If code, scripts, fixtures, manifests, or inventory records change, also run the applicable unit, PSScriptAnalyzer, ShellCheck, protocol-fixture, and manifest gates listed in `AGENTS.md`.

## Following boundary

After the compiler gate passes, the next preparation task is to pin the exact offline package-build outputs and recovery procedure. Any elevation, installation, Hyper-V VM operation, WSL shutdown, `.wslconfig` change, custom boot, or runtime trial still requires a fixed plan, canonical `safe:true`, and fresh explicit approval. The later proof sequence remains canonical in `MINIMAL-BOOT-PLAN.md`: controlled compilation, `B4/B5/B6-T` and lifecycle/recovery proof, namespace comparison, kernel ablation, cold-start acceptance, Minimal Viable WSL freeze, then Alpine/Arch/Debian compatibility.

## Manual restart command

```powershell
Set-Location -LiteralPath 'C:\Users\jackc\git\ultra-minimal-wsl'
pi `
  --name 'Acquire Community Offline Compiler Layout' `
  'Read and execute NEXT-SESSION.md'
```
