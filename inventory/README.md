# Kconfig and trial inventory

The inventory separates durable experiment records from reproducible query outputs.

## Durable Git inputs

- `annotations.csv` — reviewed symbol classifications and evidence.
- `config-snapshots.csv` — candidate path, parent, hash, and trial mapping.
- `trials.csv` — immutable append-only trial ledger.
- `trial-metadata.csv` — supplements fields omitted by historical ledger rows.

Never rewrite completed trial rows. Update annotations only through `tools/inventory.py set` so CSV and SQLite remain synchronized.

## Generated local outputs

`tools/build-kconfig-inventory.py` creates:

- `kconfig-dependencies.sqlite`;
- symbol, dependency, config-value, difference, and review CSV exports;
- `summary.json`.

These outputs are ignored by Git because they are reproducible and exceed the useful review surface. SQLite is the canonical query interface during work.

## Query and classify

```bash
uv run python tools/inventory.py show CONFIG_HYPERV
uv run python tools/inventory.py todo --enabled-in stage1
uv run python tools/inventory.py trial
```

Record a reviewed annotation atomically:

```bash
uv run python tools/inventory.py set CONFIG_HYPERV \
  review_status=REVIEWED checked=yes \
  documentation_status=DOCUMENTED_PLATFORM \
  requirement_status=UNRESOLVED \
  layer=HYPERV feature_group=hyperv-core \
  source_url=https://example.invalid/evidence \
  rationale="Hyper-V guest core"
```

Do not mark a symbol `PROVEN_*_REQUIRED` merely because it is enabled. Use WSL/Toybox classifications for the Minimal Viable WSL core and Alpine/Arch/Debian classifications only for additions isolated during compatibility testing.

A graph edge is conditional evidence, not a flat requirement. Inspect relation type, complete dependency expression, and both incoming and outgoing edges.

## Rebuild

Kconfig parsing must run on Linux with the pinned kernel tree and verified build-host profile. From the project root in `LFS-Builder`:

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
  --config k-overlay-001=candidates/K-OVERLAY-001/linux-fullconfig
uv run python tools/inventory_records.py
uv run python -m unittest tools.test_inventory_records
```

Before any boot, add the candidate full config to both the rebuild command and `config-snapshots.csv`, classify all explicit/selected symbols, synchronize records, and require SQLite integrity `ok`.
