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

Repository-only preparation of the fixed comparison—stock WSL 2.7.12 calibration, `minimal-v3-stock-ns`, then `minimal-v3-mount-ns`—is authorized. Keep the probe, inputs, timeouts, evidence schema, and recovery requirements identical across candidates. Compilation, fixture operation, elevation, package installation, WSL shutdown, `.wslconfig` changes, custom boot, and runtime execution remain deferred and unauthorized. `control-plane/deferred-runtime-plan.json` carries no approval.

## Candidate records

Before any boot:

1. Record the full config, parent, hash, and trial ID in `inventory/config-snapshots.csv`.
2. Review explicit and selected symbols with `tools/inventory.py`; update annotations only through `tools/inventory.py set`.
3. Run `uv run python tools/inventory_records.py` and require integrity `ok`.
4. Plan-validate and obtain explicit user approval.

After a trial, preserve the harness evidence, append metadata, and resynchronize SQLite. Never rewrite completed ledger rows or trial evidence.

## Safety

- Require explicit approval before `-Execute`, WSL shutdown, `.wslconfig` changes, elevation, or custom-kernel boot.
- Use the ordinary unelevated harness unless separately approved WPR/ETW diagnostics are necessary.
- Never write under `C:\Program Files\WSL` or replace its initrd.
- Keep kernel builds and source worktrees on `LFS-Builder` ext4.
- Do not accept new packaged WSL hashes without an approved stock recovery trial.
- A timeout does not prove a remote or elevated process stopped; verify durable state independently.

## Commands

```bash
bash tools/bootstrap-lfs-builder.sh --check  # run inside LFS-Builder
uv run python tools/inventory.py trial
uv run python tools/inventory.py show CONFIG_<SYMBOL>
uv run python tools/inventory_records.py
uv run python -m unittest tools.test_build_host_profile tools.test_inventory_records tools.test_control_plane_protocol tools.test_control_plane_records
& ~/git/agent-skills/skills/windows-env/Invoke-PsLint.ps1 -Offline -Settings .PSScriptAnalyzerSettings.psd1 -Path tools
git ls-files '*.sh' -z | xargs -0 shellcheck --severity=warning -x
```

Run Windows scripts through `windows-env/ps-exec`. Use `tools/Test-WslSafeState.ps1` for live state and `tools/Test-WslKernelTrial.ps1` for non-mutating validation.
