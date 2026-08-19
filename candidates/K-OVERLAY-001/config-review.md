# K-OVERLAY-001 config review

Prepared and reviewed 2026-08-19. This candidate has not been booted.

Parent: `K-STORAGE-001`, full-config SHA-256 `b8d9068b9dc901ad66a4e5ff03fdfd78b02a09261ffebfdc006699b91a437bd8`.

## Evidence-selected changes

| Symbol | Parent | Candidate | Classification |
|---|---:|---:|---|
| `CONFIG_OVERLAY_FS` | n | y | Direct post-B3 discovery addition; unresolved pending runtime evidence |
| `CONFIG_FS_STACK` | absent/n | y | Selected Kconfig closure; transitive |

`CONFIG_EXPORTFS=y` was already present. The generated config contains no other newly enabled symbol. The kernel grew from 3,720,192 to 3,777,536 bytes (57,344 bytes).

The selection is based on immutable `K-STORAGE-001` evidence: stock `mini_init` mounted the read-only system-distro ext4 filesystem and then reproduced Stage 3's exact segfault. Exact WSL 2.7.12 source next invokes `UtilMountOverlayFs` unconditionally, while both failing configs have overlayfs disabled.

## Optional overlay defaults held disabled

Enabling overlayfs exposes seven policy/debug options. All were reviewed and classified `DEFERRED` in the inventory. The generated config keeps the six visible options disabled; `OVERLAY_FS_NFS_EXPORT` remains absent because its `OVERLAY_FS_INDEX` dependency is false.

In particular, Kconfig would default `OVERLAY_FS_REDIRECT_ALWAYS_FOLLOW` and `OVERLAY_FS_XINO_AUTO` to `y`. They are explicitly held at `n`: WSL's system-distro mount does not request redirect behavior or automatic inode mapping, and neither is required merely to provide overlayfs. Stage 1 also disables xino and every other optional overlay feature; it enables redirect-always-follow only as a compatibility default, not an observed WSL requirement.

## Explicit exclusions verified

The resulting full config retains:

- `CONFIG_CGROUPS=n`
- `CONFIG_NET_NS=n`
- `CONFIG_SECCOMP=n`
- `CONFIG_HYPERV_NET=n`
- `CONFIG_VIRTIO_CONSOLE=n`

The exact source/trace correlation is preserved in `recovery-harness/trials/K-HOSTCHAN-001/analysis.json`; these paths remain non-terminal or outside the selected target.

## Artifact integrity and validation

- Source commit: `14794180686c2fb6307fbe359c359bec765249f3`
- Full config SHA-256: `ab0c68a2e96b36a397226f71e45d59a99c59f10ac1019c62bfde4e321a45e3f7`
- Kernel SHA-256: `3f5d6708e4a9eaaa230054a1962c584ac3e0a47f28485c1ab87a12c8e51dff3b`
- Kernel size: 3,777,536 bytes
- Compiler: x86_64 musl GCC 15.1.0; linker: GNU binutils 2.44

The ordinary unelevated harness plan and its safety tests passed without `-Execute`. Plan validation observed the already-running `Debian-Recovered` distribution and did not stop it. Canonical live state therefore remains `safe:false`; a future trial requires `safe:true` and fresh explicit approval.
