# Kconfig dependency inventory

This directory is the external dependency graph and review checklist for the minimal WSL kernel experiment.

## Files

- `kconfig-dependencies.sqlite`: canonical searchable database for symbols, config snapshots, annotations, and trial records.
- `config-snapshots.csv`: durable manifest of every baseline and candidate full config, its parent, hash, and trial.
- `annotations.csv`: editable, persistent checklist/classification input.
- `dependencies.csv`: one row per directed Kconfig relationship.
- `symbols.csv`: prompts, help, expressions and source locations.
- `config-values.csv`: symbol values for baseline and experimental configs.
- `config-differences.csv`: all pairwise differences between loaded configs.
- `review-queue.csv`: all symbols with direct/reverse summaries and annotations.
- `stage1-enabled-review.csv`: review queue restricted to Stage 1 `y`/`m` symbols.
- `mkroot-stage1-delta.csv`: scoped lower-to-upper-bound review list.
- `summary.json`: counts and generation inputs.
- `trials.csv`: immutable append-only boot-trial ledger covering the generic QEMU baseline, recovery validations, and supported WSL kernel trials through `K-STORAGE-001`.
- `trial-metadata.csv`: durable supplements for omitted historical ledger fields; never rewrite a completed ledger row.

`annotations.csv`, `config-snapshots.csv`, `trials.csv`, and `trial-metadata.csv` are durable inputs. SQLite and the remaining CSV files are generated/searchable views. Use `tools/inventory.py set` rather than editing annotations in SQLite directly. Run `tools/inventory_records.py` after adding a config, trial, or supplemental metadata row.

`dependencies.csv` is a graph, not a flat list of unconditional requirements. Always inspect `relation` and `condition_expr`. In particular, symbols appearing in an OR expression are alternatives, and `default_ref` is not a hard dependency.

## Search

From `C:\Users\jackc\git\ultra-minimal-wsl`:

```powershell
uv run python tools/inventory.py show CONFIG_HYPERV
uv run python tools/inventory.py todo --enabled-in stage1 --limit 50
uv run python tools/inventory.py trial
uv run python tools/inventory.py trial K-STORAGE-001
```

Show what directly references `CONFIG_HYPERV` using SQLite:

```sql
SELECT source, relation, condition_expr
FROM edges
WHERE target='HYPERV'
ORDER BY relation, source;
```

Show what `CONFIG_HYPERV` references or selects:

```sql
SELECT target, relation, condition_expr
FROM edges
WHERE source='HYPERV'
ORDER BY relation, target;
```

Show baseline-to-Stage-1 changes:

```sql
SELECT symbol, value_a AS baseline, value_b AS stage1
FROM config_differences
WHERE config_a='baseline' AND config_b='stage1'
ORDER BY symbol;
```

Show unchecked Stage 1 symbols:

```sql
SELECT rq.*
FROM review_queue rq
JOIN config_values cv ON cv.symbol=substr(rq.symbol, 8)
WHERE cv.config_name='stage1' AND cv.value IN ('y','m') AND rq.checked=0
ORDER BY rq.symbol;
```

## Check off and classify

Use the helper so SQLite and `annotations.csv` remain synchronized:

```powershell
uv run python tools/inventory.py set CONFIG_HYPERV `
  review_status=REVIEWED checked=yes `
  documentation_status=DOCUMENTED_PLATFORM `
  requirement_status=UNRESOLVED `
  layer=HYPERV feature_group=hyperv-core `
  source_url=https://example.invalid/evidence `
  rationale="Hyper-V guest core"
```

The annotations distinguish documented purpose from experimentally proven necessity. Do not mark a symbol `PROVEN_*_REQUIRED` merely because it is enabled or selected. Use `PROVEN_WSL_REQUIRED` or `PROVEN_TOYBOX_REQUIRED` for the Minimal Viable WSL core; reserve `PROVEN_ALPINE_REQUIRED`, `PROVEN_ARCH_REQUIRED`, and `PROVEN_DEBIAN_REQUIRED` for compatibility additions isolated after that core is frozen. `MINIMAL-BOOT-PLAN.md` is the canonical status definition.

## Synchronize records

From the project root, verify hashes and import all candidate configs and trial evidence:

```powershell
uv run python tools/inventory_records.py
```

Candidate snapshots are derived from their recorded parent plus the complete generated `.config`; the next full Kconfig rebuild independently regenerates all values.

## Full Kconfig rebuild

Kconfig parsing must run inside `LFS-Builder`, where compiler-detection scripts use the Linux toolchain. uv 0.12.5 is installed at `/root/.local/bin/uv` for this purpose:

```bash
cd /mnt/c/Users/jackc/git/ultra-minimal-wsl
/root/.local/bin/uv run --with kconfiglib==14.1.0 python tools/build-kconfig-inventory.py \
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
/root/.local/bin/uv run python tools/inventory_records.py
```

The exact mkroot-expanded 6.18 config is loaded from `mkroot-baseline/linux-fullconfig`; `mkroot-stage1-delta.csv` is the primary review queue. Add every generated candidate full config to both this rebuild command and `config-snapshots.csv` before any boot.

The released `kconfiglib` parser predates two Linux 6.18 grammar properties. The generator safely translates the new `modules` property to its legacy `option modules` equivalent and ignores only the metadata marker `transitional`; symbols and dependency/default expressions are retained. This transformation is recorded in the database metadata.
