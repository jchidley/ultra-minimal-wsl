# Experiment and Kconfig inventory

The inventory uses two SQLite databases with deliberately different ownership.

## Committed experiment database

`experiments.sqlite` is the canonical transactional source for:

- candidate lineage;
- artifact paths, hashes, sizes, package identities, and roles;
- build and runtime operations;
- append-only operation dispositions;
- kernel configuration snapshots;
- immutable terminal trials and evidence links.

Use only the repository CLI:

```powershell
uv run python tools/experiment.py active
uv run python tools/experiment.py show operation minimal-v6-k-overlay-pidns-runtime-013
uv run python tools/experiment.py contract minimal-v6-k-overlay-pidns-runtime-013
uv run python tools/experiment.py broker-command minimal-v6-k-overlay-pidns-runtime-013
uv run python tools/experiment.py query "SELECT * FROM trial_summary ORDER BY trial_id"
uv run python tools/experiment.py validate
uv run python tools/experiment.py diff-head
```

Write commands accept small reviewed JSON records and execute one checked transaction. Do not modify the canonical database with ad hoc SQL. Tests must copy it to a temporary path before mutation.

Before commit, validation requires SQLite integrity and foreign-key checks, at most one executable operation, exact repository/host artifact identities, and no `-wal` or `-shm` sidecar. Terminal trials and operation dispositions are protected by database triggers. The binary is committed because this project has one active writer; `tools/experiment.py diff-head` provides the logical review surface Git cannot.

Privileged execution never queries this normal-user-writable database. Preflight selects and validates the operation from SQL, then the protected broker snapshots the exact hash-bound controller. The controller carries the compact executable contract and does not trust mutable planning state.

`control-plane/deferred-runtime-plan.v1.json`, `config-snapshots.v1.csv`, `trials.v1.csv`, and `trial-metadata.v1.csv` are frozen migration inputs. Never edit them. `tools/import_experiments.py --output <temporary-path>` reproduces the migration for verification; it refuses to replace the canonical database unless the exceptional `--replace-canonical` flag is explicit.

## Generated Kconfig query database

`kconfig-dependencies.sqlite` remains a reproducible, ignored query database because its approximately 78 MB dependency graph is derived from pinned kernel source and configurations. `tools/inventory_records.py` now synchronizes config and trial views into it from `experiments.sqlite`.

`annotations.csv` remains the durable Git input for reviewed Kconfig classifications. Update it only through:

```powershell
uv run python tools/inventory.py set CONFIG_HYPERV `
  review_status=REVIEWED checked=yes `
  documentation_status=DOCUMENTED_PLATFORM `
  requirement_status=UNRESOLVED `
  layer=HYPERV feature_group=hyperv-core `
  source_url=https://example.invalid/evidence `
  rationale="Hyper-V guest core"
```

Query the generated graph with:

```powershell
uv run python tools/inventory.py show CONFIG_HYPERV
uv run python tools/inventory.py todo --enabled-in stage1
uv run python tools/inventory.py trial
```

A graph edge is conditional evidence, not a flat requirement. Inspect relation type, complete dependency expression, and both incoming and outgoing edges. Do not mark a symbol `PROVEN_*_REQUIRED` merely because Microsoft enables it or because it appears in a successful bundle.

## Rebuild and validate

On `LFS-Builder`, rebuild the generated Kconfig database from the pinned source and recorded configs, then synchronize experiments:

```bash
bash tools/bootstrap-lfs-builder.sh --check
uv run --with kconfiglib==14.1.0 python tools/build-kconfig-inventory.py \
  --srctree /root/src/WSL2-Linux-Kernel \
  --output-dir inventory \
  --annotations inventory/annotations.csv \
  --config mkroot=mkroot-baseline/linux-fullconfig \
  --config baseline=config-wsl-baseline \
  --config stage1=config-wsl-ultramin-stage1 \
  --config stage2=config-wsl-ultramin-stage2 \
  --config stage3=config-wsl-ultramin-stage3 \
  --config k-hvcore-001=candidates/K-HVCORE-001/linux-fullconfig \
  --config k-hostchan-001=candidates/K-HOSTCHAN-001/linux-fullconfig \
  --config k-storage-001=candidates/K-STORAGE-001/linux-fullconfig \
  --config k-overlay-001=candidates/K-OVERLAY-001/linux-fullconfig \
  --config k-pidns-001=candidates/K-PIDNS-001/linux-fullconfig \
  --config k-overlay-pidns-001=candidates/K-OVERLAY-PIDNS-001/linux-fullconfig
uv run python tools/inventory_records.py
uv run python tools/experiment.py validate
```
