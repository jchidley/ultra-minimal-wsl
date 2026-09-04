# AGENTS.md

## Objective

Build `minimal-viable-wsl-v1` from the mkroot/Toybox floor plus only proven Hyper-V entry, VSOCK, registered-distro VHDX mount, root transition, `wsl.exe` command relay, termination, and recovery requirements. Then add only requirements proved by Alpine, Arch, and Debian to produce `ultra-minimal-wsl-v1`.

The experiment target is the WSL Linux configuration. Outer Windows/VM transport is a prerequisite only; do not turn fixture automation, remoting, or checkpoint mechanics into project milestones.

Networking, DNS, DrvFs, Windows interop, WSLg, systemd, containers, cgroup policy, USB, general disk management, and cross-distro integration are out of scope.

## Read first

Read `STATUS.md`, `TASKS.md`, `MINIMAL-BOOT-PLAN.md`, and `build-host/README.md`. Query Kconfig relationships in generated `inventory/kconfig-dependencies.sqlite` and experiment state in committed `inventory/experiments.sqlite`; update the latter only through `tools/experiment.py`. `inventory/annotations.csv` remains the durable Kconfig-review input.

## Documentation and relay ownership

- `STATUS.md` owns verified current facts; `TASKS.md` owns incomplete work; `MINIMAL-BOOT-PLAN.md` owns durable strategy and acceptance criteria.
- Exact candidates, artifacts, operations, dispositions, configs, trials, and append-only interpretation corrections belong in committed `inventory/experiments.sqlite`; immutable trial evidence belongs in trial directories. Read effective trial views by default; inspect raw records only with their correction history. `control-plane/deferred-runtime-plan.v1.json` and the `inventory/*.v1.csv` files are frozen migration inputs and must never be edited.
- Keep `README.md` and `PROJECT-MODEL.md` explanatory. Do not copy transient blockers, hashes, or task detail into them.
- `NEXT-SESSION.md` is Relay-owned generated output, not canonical truth. Use it only when it agrees with `STATUS.md`, `TASKS.md`, and `MINIMAL-BOOT-PLAN.md`; reconcile it through `/relay`, not ordinary edits.
- Before relaying, update only canonical documents whose facts or tasks changed, validate them, and ensure the generated session name matches the bounded objective.
- Keep one active writer and fixture operator for this checkout. Other concurrent sessions are read-only reviewers; they must not edit, commit, launch a broker, or operate the fixture.

## Local inputs

Ordinary build, extraction, and trial workflows must reuse pinned, hash-verified local inputs rather than repeatedly downloading them. Where reusable archives are necessary, use an explicitly configured local cache: accept only verified cache hits, download and atomically cache a missing or invalid entry, then verify it before use. Provide an offline mode that fails closed instead of accessing the network.

## Shell and command presentation

Present Windows host and Pi session commands in PowerShell first. Agent-executed Windows scripts still cross the shell boundary through `windows-env/ps-exec`; Linux builds and source work run through `windows-env/wsl-exec` on `LFS-Builder`. Provide Git Bash alternatives only when useful.

## Current phase

- The v1 baseline is frozen at its pinned Toybox/cold-start and Alpine/Arch/Debian smoke boundary, not proven globally minimal. Preserve unresolved facility classifications and historical evidence; completed source-selection findings are not new work orders.
- Do not add `CONFIG_INOTIFY_USER`, storage hotplug, PCI, networking, IPC namespaces, or UTS namespaces speculatively, and do not rerun a finalized candidate unchanged.
- Debian3 practical bootstrap/migration work belongs to the `dotfiles` project and its sessions, not this frozen experiment. `STATUS.md` owns the complete verified boundary and `TASKS.md` the bounded active action. Never copy an active operation number into this file: obtain exact executable state with `uv run python tools/experiment.py active`.

Operations wholly confined to the dedicated disposable fixture are standing-authorized when they use pinned hash-verified offline inputs, preserve evidence, follow the recorded recovery path, and finish with independently verified fixture state. No standing authorization crosses into the physical host or a shared WSL instance. Record and plan-validate produced hashes and exact installation/restoration commands before runtime; these are agent-executed technical checks, not human approval points.

## Candidate records

Before any kernel-candidate boot:

1. Record the full config, parent, hash, and trial ID transactionally through `tools/experiment.py`.
2. Review explicit and selected symbols with `tools/inventory.py`; update annotations only through `tools/inventory.py set`.

Before any controlled-package trial, use phase-specific schema-v2 generation: the build phase creates only the controlled build script and build controller; after package identity exists, the runtime phase creates only the trial runner and runtime controller. Never create placeholder outputs, commit derived display `.diff` files, or copy and broadly replace a prior script. Record candidate lineage, genuinely new file identities, reused artifacts, and role links atomically through `candidate-prepare`; derive the operation from a terminal parent and an immutable template rather than reconstructing unchanged artifact roles or contract fields. Retries must reference the failed attempt through `operation-retry`. Require `tools/experiment.py validate` and inspect `tools/experiment.py diff-head`. For every trial type, also run `uv run python tools/inventory_records.py`, require integrity `ok`, and plan-validate the exact operation and recovery. Complete repository work and disposable-fixture work autonomously without asking the operator to review plans, approve stages, open gates, or confirm routine choices. Obtain explicit approval only if the operation can affect the physical host, a shared WSL instance, or another resource outside the disposable fixture envelope.

After a trial, preserve the harness evidence, finalize the operation and trial in one transactional CLI workflow, and resynchronize the generated Kconfig query database. Never rewrite terminal database rows or trial evidence.

## Safety

- Require explicit approval before `-Execute`, WSL shutdown, `.wslconfig` changes, elevation, installation, or custom-kernel/control-plane boot on the physical host or any shared WSL instance.
- Inside the dedicated disposable fixture, those operations and WPR/ETW diagnostics are standing-authorized only within the pinned, offline, hash-verified, plan-validated, recoverable experiment envelope. Hash mismatch, network access, an unrecorded executable, failed recovery, or an uncertain target must fail closed rather than fall through to broader access.
- Never directly write under the physical host's `C:\Program Files\WSL` or replace its initrd. A hash-bound MSI transaction may modify the disposable fixture only.
- Keep kernel builds and source worktrees on `LFS-Builder` ext4.
- Do not accept new packaged WSL hashes without a completed stock recovery trial.
- A timeout does not prove a remote or elevated process stopped; verify durable state independently.
- UAC cancellation or expiry before durable elevated-worker start is an infrastructure launch failure, not a build, package, or candidate failure. Record that no worker started and no fixture mutation occurred, then use a fresh operation ID for the unchanged hash-bound controller. An existing approval or standing fixture authorization remains applicable to that fresh launch when scope and controller content are unchanged; do not alter the experiment or diagnose a build problem solely because the operator was unavailable for UAC.
- At the beginning of each attended runtime run, use `tools/fixture-broker/` to snapshot the independently reviewed controller into an administrator-protected, ephemeral allowlist. Never execute an elevated controller, credential, result, or evidence path from the normal-user-writable repository or `approval-state` tree. The broker queue is hostile input and may select only a preapproved workload; it must never accept host commands, script paths, hashes, executables, or arbitrary VM/storage identities.
- Freeze the broker at the exact tested facility needed by the active trial. Change it only when a reproduced transport defect prevents that trial; do not add generalized fixture features. After two pre-probe failures with the same cause, stop retrying and make one bounded root-cause repair before another launch.
- Before elevation, require AST parsing, PSScriptAnalyzer, exact hash and size binding, execution-domain path checks, evidence-root ordering, real `Start-Process` parameter/quoting validation, the runner fault matrix, inventory integrity, and recovery-plan validation. Enter `uac-requested` only through `experiment.py operation-request-uac`, which runs the invariant suite immediately before the transition. Describe state precisely: `prepared`, `UAC requested`, `worker started`, `first probe started`, or `candidate finalized`; never call a trial running before durable worker start or classify a candidate before the first probe starts.

## Commands

From PowerShell:

```powershell
uv run python tools/experiment.py active
uv run python tools/experiment.py validate
uv run python tools/experiment.py diff-head
uv run python tools/inventory.py trial
uv run python tools/inventory.py show CONFIG_<SYMBOL>
uv run python tools/inventory_records.py
uv run python -m unittest tools.test_build_host_profile tools.test_experiment tools.test_inventory_records tools.test_extract_guest_logs tools.test_process_commit tools.test_control_plane_protocol tools.test_control_plane_records tools.test_fixture_broker
& tools/Test-ProcessCommit.ps1
& ~/git/agent-skills/skills/windows-env/Invoke-PsLint.ps1 -Offline -Settings .PSScriptAnalyzerSettings.psd1 -Path tools,control-plane/controlled-package-offline
```

On `LFS-Builder`:

```bash
bash tools/bootstrap-lfs-builder.sh --check
git ls-files '*.sh' -z | xargs -0 shellcheck --severity=warning -x
```

Run Windows scripts through `windows-env/ps-exec`. Use `tools/Test-WslSafeState.ps1` for live state and `tools/Test-WslKernelTrial.ps1` for non-mutating validation.
