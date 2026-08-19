# Project status

Updated 2026-08-19. This file contains current facts only; immutable history is in `inventory/trials.csv` and `recovery-harness/trials/`.

## Safety state

- Microsoft’s packaged kernel remains the recovery kernel.
- No project file writes beneath `C:\Program Files\WSL`.
- No reduced init or custom WSL package has been deployed.
- Run `tools/Test-WslSafeState.ps1` for live state; never stop a running distro automatically.
- Any custom boot still requires canonical `safe:true` and fresh explicit approval.

Validated package baseline:

- WSL: 2.7.12.0
- packaged kernel SHA-256: `d540850bfbf1beba3ded6b2965b9d0249b23fbcb3e90e7dc0845ac7ad86bc861`
- packaged initrd SHA-256: `a76ddd9b8bad0771c100a32a715cfc15d8553464f4deffcb516454610cd6b118`

## Proven progression

| Artifact/trial | Result |
|---|---|
| mkroot baseline | `G4`: Toybox `/init` and shell smoke test pass under QEMU |
| `K-MKROOT-001` | `B0`: no observable WSL command dispatch |
| `K-HVCORE-DIAG-001` | `B1`: kernel and stock `/init` execute; VSOCK absent |
| `K-HOSTCHAN-001` | `B2`: VMBus and Hyper-V VSOCK operate |
| `K-STORAGE-001` | `B3`: Hyper-V storage attaches and system ext4 mounts; stock `mini_init` then crashes in its overlay path |

Every completed custom trial restored the exact stock configuration and proved stock Debian startup. Detailed evidence remains in each trial’s `analysis.json` and manifest.

## Prepared candidate

`K-OVERLAY-001` is derived from `K-STORAGE-001` with only:

- explicit `CONFIG_OVERLAY_FS=y`;
- selected `CONFIG_FS_STACK=y`.

Facts:

- kernel size: 3,777,536 bytes;
- kernel SHA-256: `3f5d6708e4a9eaaa230054a1962c584ac3e0a47f28485c1ab87a12c8e51dff3b`;
- full-config SHA-256: `ab0c68a2e96b36a397226f71e45d59a99c59f10ac1019c62bfde4e321a45e3f7`;
- optional overlay policy/debug defaults remain disabled;
- config review, inventory synchronization, hashes, and ordinary plan validation pass;
- it has not been booted or approved for boot.

Overlayfs is being measured only because stock `mini_init` enters Microsoft’s system-distro overlay path. It is not accepted as a final Minimal Viable WSL requirement.

## Inventory

- 9 config snapshots;
- 8 completed trials;
- 113 reviewed annotations;
- SQLite integrity `ok` at the last synchronization.

Durable inputs are `annotations.csv`, `config-snapshots.csv`, `trials.csv`, and `trial-metadata.csv`. Other inventory exports are generated locally.

## Control-plane preparation

The retained host/guest path is mapped against the nearest pinned public source, WSL tag `2.7.11` at commit `acbcb81fc61079b74835ea7dc2563046b2557033`, in `WSL-CONTROL-PLANE-AUDIT.md`. The installed recovery baseline is 2.7.12.0 and the local public-source clone exposes no corresponding tag, so exact source identity remains to be established before implementation. The map identifies the VSOCK handshake, registered-distro VHDX message, namespace/root transition, inherited distro-init channel, command sockets, stdio/exit relay, and termination messages.

Source inspection also proves that a guest-only reduced init is insufficient: the stock host waits for an excluded GNS connection after early configuration and advertises the Microsoft system distro. Reduced-control-plane testing must patch both the Windows service and Linux init inside the disposable VM.

## Target gap

No mkroot-derived candidate has reached Toybox command dispatch under WSL. Therefore neither `minimal-viable-wsl-v1` nor the Alpine/Arch/Debian compatibility profile exists yet. The final result requires a reduced host and guest control plane that preserves VSOCK, distro VHDX mounting, root transition, command relay, termination, and recovery while removing unrelated stock policy.
