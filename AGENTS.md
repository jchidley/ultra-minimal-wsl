# AGENTS.md

## Objective

Produce the smallest reproducible WSL kernel config that boots the mkroot
Toybox system, then Alpine. Defer networking, DrvFs, systemd, containers, GUI,
and unrelated Microsoft control-plane policy.

## Read first

Read `STATUS.md`, `TASKS.md`, and `MINIMAL-BOOT-PLAN.md`. Treat
`inventory/kconfig-dependencies.sqlite` as the searchable experiment record and
the CSV manifests under `inventory/` as its durable inputs.

## Record every candidate

Before any boot:

1. Add the full config, parent, hash, and trial ID to
   `inventory/config-snapshots.csv`.
2. Review explicit and selected symbols with `tools/inventory.py`; update
   annotations only through `tools/inventory.py set`.
3. Run `uv run python tools/inventory_records.py` and require SQLite integrity
   `ok`.
4. Plan-validate the candidate and obtain explicit user approval.

After a trial, require the harness to append `inventory/trials.csv`; add one
`inventory/trial-metadata.csv` row, preserve `analysis.json`, and rerun the
inventory synchronizer. Never rewrite completed ledger rows or trial evidence.

## Safety

- Require explicit approval before `-Execute`, WSL shutdown, `.wslconfig`
  changes, elevation, or custom-kernel boot.
- Never write under `C:\Program Files\WSL` or replace its initrd.
- Keep builds and source worktrees on `LFS-Builder` ext4.
- Commit configs, metadata, hashes, extracted evidence, and analysis; exclude
  reproducible binaries and raw ETL/XML.
- Do not accept new WSL package hashes without an approved stock recovery trial.

## Commands

```bash
uv run python tools/inventory.py trial
uv run python tools/inventory.py show CONFIG_<SYMBOL>
uv run python tools/inventory_records.py
uv run python -m unittest tools.test_inventory_records
```

Run Windows scripts only through `windows-env/ps-exec`. Use
`tools/Test-WslSafeState.ps1` for live state and `tools/Test-WslKernelTrial.ps1`
for non-mutating trial validation. A timeout does not prove a remote or elevated
process stopped; verify durable status independently.

Historical paths in completed trial records may refer to the former Downloads
location. Preserve them.
