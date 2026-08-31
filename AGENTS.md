# AGENTS.md

## Objective

Build `minimal-viable-wsl-v1` from the mkroot/Toybox floor plus only proven Hyper-V entry, VSOCK, registered-distro VHDX mount, root transition, `wsl.exe` command relay, termination, and recovery requirements. Then add only requirements proved by Alpine, Arch, and Debian to produce `ultra-minimal-wsl-v1`.

The experiment target is the WSL Linux configuration. Outer Windows/VM transport is a prerequisite only; do not turn fixture automation, remoting, or checkpoint mechanics into project milestones.

Networking, DNS, DrvFs, Windows interop, WSLg, systemd, containers, cgroup policy, USB, general disk management, and cross-distro integration are out of scope.

## Read first

Read `STATUS.md`, `TASKS.md`, `MINIMAL-BOOT-PLAN.md`, and `build-host/README.md`. Query `inventory/kconfig-dependencies.sqlite`; durable inputs are `inventory/annotations.csv`, `config-snapshots.csv`, `trials.csv`, and `trial-metadata.csv`.

## Documentation and relay ownership

- `STATUS.md` owns verified current facts; `TASKS.md` owns incomplete work; `MINIMAL-BOOT-PLAN.md` owns durable strategy and acceptance criteria.
- Exact preparation inputs, commands, hashes, failures, and execution blockers belong in `control-plane/deferred-runtime-plan.json`; immutable trial evidence belongs in the inventory and trial directories.
- Keep `README.md` and `PROJECT-MODEL.md` explanatory. Do not copy transient blockers, hashes, or task detail into them.
- `NEXT-SESSION.md` is Relay-owned generated output, not canonical truth. Use it only when it agrees with `STATUS.md`, `TASKS.md`, and `MINIMAL-BOOT-PLAN.md`; reconcile it through `/relay`, not ordinary edits.
- Before relaying, update only canonical documents whose facts or tasks changed, validate them, and ensure the generated session name matches the bounded objective.

## Local inputs

Ordinary build, extraction, and trial workflows must reuse pinned, hash-verified local inputs rather than repeatedly downloading them. Where reusable archives are necessary, use an explicitly configured local cache: accept only verified cache hits, download and atomically cache a missing or invalid entry, then verify it before use. Provide an offline mode that fails closed instead of accessing the network.

## Shell and command presentation

Present Windows host and Pi session commands in PowerShell first. Agent-executed Windows scripts still cross the shell boundary through `windows-env/ps-exec`; Linux builds and source work run through `windows-env/wsl-exec` on `LFS-Builder`. Provide Git Bash alternatives only when useful.

## Current phase

- Stock and the retained mount-plus-PID control plane pass `B6-T`; IPC and UTS remain omitted. The PID-enabled storage-floor and overlay-floor kernels both stop at `B2` after mini-init configuration, so overlay is not the missing facility.
- The `minimal-v6-excluded-initialize` source layer and two byte-identical offline Linux builds are complete. Finish its controlled package, then retest `K-PIDNS-001`. Do not add `CONFIG_INOTIFY_USER`, storage hotplug, PCI, networking, IPC namespaces, or UTS namespaces speculatively.
- Do not rerun finalized v3, v4, v5, `K-PIDNS-001`, or `K-OVERLAY-PIDNS-001` candidates unchanged. `STATUS.md` owns the complete verified boundary and `TASKS.md` the exact active action.

Operations wholly confined to the dedicated disposable fixture are standing-authorized when they use pinned hash-verified offline inputs, preserve evidence, follow the recorded recovery path, and finish with independently verified fixture state. No standing authorization crosses into the physical host or a shared WSL instance. Record and plan-validate produced hashes and exact installation/restoration commands before runtime; these are agent-executed technical checks, not human approval points.

## Candidate records

Before any kernel-candidate boot:

1. Record the full config, parent, hash, and trial ID in `inventory/config-snapshots.csv`.
2. Review explicit and selected symbols with `tools/inventory.py`; update annotations only through `tools/inventory.py set`.

Before any controlled-package trial, record the source parent/diff, output manifest, package hash, candidate manifest, and reserved trial ID. For every trial type, run `uv run python tools/inventory_records.py`, require integrity `ok`, and plan-validate the exact operation and recovery. Complete repository work and disposable-fixture work autonomously without asking the operator to review plans, approve stages, open gates, or confirm routine choices. Obtain explicit approval only if the operation can affect the physical host, a shared WSL instance, or another resource outside the disposable fixture envelope.

After a trial, preserve the harness evidence, append metadata, and resynchronize SQLite. Never rewrite completed ledger rows or trial evidence.

## Safety

- Require explicit approval before `-Execute`, WSL shutdown, `.wslconfig` changes, elevation, installation, or custom-kernel/control-plane boot on the physical host or any shared WSL instance.
- Inside the dedicated disposable fixture, those operations and WPR/ETW diagnostics are standing-authorized only within the pinned, offline, hash-verified, plan-validated, recoverable experiment envelope. Hash mismatch, network access, an unrecorded executable, failed recovery, or an uncertain target must fail closed rather than fall through to broader access.
- Never directly write under the physical host's `C:\Program Files\WSL` or replace its initrd. A hash-bound MSI transaction may modify the disposable fixture only.
- Keep kernel builds and source worktrees on `LFS-Builder` ext4.
- Do not accept new packaged WSL hashes without a completed stock recovery trial.
- A timeout does not prove a remote or elevated process stopped; verify durable state independently.

## Commands

From PowerShell:

```powershell
uv run python tools/inventory.py trial
uv run python tools/inventory.py show CONFIG_<SYMBOL>
uv run python tools/inventory_records.py
uv run python -m unittest tools.test_build_host_profile tools.test_inventory_records tools.test_control_plane_protocol tools.test_control_plane_records
& ~/git/agent-skills/skills/windows-env/Invoke-PsLint.ps1 -Offline -Settings .PSScriptAnalyzerSettings.psd1 -Path tools,control-plane/controlled-package-offline
```

On `LFS-Builder`:

```bash
bash tools/bootstrap-lfs-builder.sh --check
git ls-files '*.sh' -z | xargs -0 shellcheck --severity=warning -x
```

Run Windows scripts through `windows-env/ps-exec`. Use `tools/Test-WslSafeState.ps1` for live state and `tools/Test-WslKernelTrial.ps1` for non-mutating validation.
