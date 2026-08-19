# AGENTS.md

## Objective

Build `minimal-viable-wsl-v1` from the mkroot/Toybox floor plus only proven Hyper-V entry, VSOCK, registered-distro VHDX mount, root transition, `wsl.exe` command relay, termination, and recovery requirements. Then add only requirements proved by Alpine, Arch, and Debian to produce `ultra-minimal-wsl-v1`.

Networking, DNS, DrvFs, Windows interop, WSLg, systemd, containers, cgroup policy, USB, general disk management, and cross-distro integration are out of scope.

## Read first

Read `STATUS.md`, `TASKS.md`, and `MINIMAL-BOOT-PLAN.md`. Query `inventory/kconfig-dependencies.sqlite`; durable inputs are `inventory/annotations.csv`, `config-snapshots.csv`, `trials.csv`, and `trial-metadata.csv`.

## Local inputs

Ordinary build, extraction, and trial workflows must not download dependencies or artifacts. Consume pinned, hash-verified local inputs; where reusable archives are necessary, use an explicitly configured local cache and fail closed when an entry is missing or corrupt. Populate that cache only as a separate, deliberate operation.

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
uv run python tools/inventory.py trial
uv run python tools/inventory.py show CONFIG_<SYMBOL>
uv run python tools/inventory_records.py
uv run python -m unittest tools.test_inventory_records
```

Run Windows scripts through `windows-env/ps-exec`. Use `tools/Test-WslSafeState.ps1` for live state and `tools/Test-WslKernelTrial.ps1` for non-mutating validation.
