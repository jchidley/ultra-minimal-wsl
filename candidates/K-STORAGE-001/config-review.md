# K-STORAGE-001 config review

Prepared and reviewed 2026-08-19. It was subsequently approved and booted as the `K-STORAGE-001` diagnostic trial, reaching `B3`; runtime evidence is under `recovery-harness/trials/K-STORAGE-001/`.

Parent: `K-HOSTCHAN-001`, full-config SHA-256 `8a6d7bd1731e6af350a6138a92dc157e5d7c0b36602cf87a697520fd125bbc6e`.

## Evidence-selected changes

| Symbol | Parent | Candidate | Classification |
|---|---:|---:|---|
| `CONFIG_SCSI_LOWLEVEL` | n | y | Kconfig prerequisite for Hyper-V storage; transitive |
| `CONFIG_HYPERV_STORAGE` | absent/n | y | Direct B3 discovery addition selected by the `GetLunDeviceName` timeout |

`CONFIG_SCSI=y` and runtime-proven `CONFIG_HYPERV_VMBUS=y` were already present. Kconfig enabled no additional symbols. The kernel grew from 3,712,000 to 3,720,192 bytes (8,192 bytes).

## Disabled menu exposure

Enabling `SCSI_LOWLEVEL` exposed 51 unrelated low-level SCSI/iSCSI driver symbols in the serialized full config. Every one remained `n`; `config-delta.txt` lists them individually. Fifty were classified in `inventory/annotations.csv` as `DEFERRED`, `OPTIONAL`, feature group `held-storage-default`.

Linux's mixed-case symbol `CONFIG_SCSI_DC395x` also remained `n`. `tools/inventory.py set` currently uppercases its argument and therefore cannot address that exact symbol; it is classified here rather than bypassing the required helper by editing generated inventory state directly.

## Explicit exclusions verified

The resulting full config retains:

- `CONFIG_CGROUPS=n`
- `CONFIG_NET_NS=n`
- `CONFIG_SECCOMP=n`
- `CONFIG_HYPERV_NET=n`
- `CONFIG_VIRTIO_CONSOLE=n`

These paths are non-terminal or deferred according to `POST-B2-CLOSURE-ANALYSIS.md`.

## Artifact integrity

- Full config SHA-256: `b8d9068b9dc901ad66a4e5ff03fdfd78b02a09261ffebfdc006699b91a437bd8`
- Kernel SHA-256: `3d3a4f9cee018590d986912b4379119cf22bb8b6e4aee3c29ad43f5450efa367`
- Kernel size: 3,720,192 bytes
- `SHA256SUMS`: verified after copying from the protected ext4 worktree

Diagnostic plan-only harness validation passed without starting WPR, shutting WSL down, or changing `.wslconfig`; see `plan-validation.txt`. The later approved activation restored exact stock state and proved B3. Any further activation requires a new explicit approval and the normal safe-state/recovery gates.
