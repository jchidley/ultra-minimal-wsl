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

## Stock-init discovery boundary

`K-OVERLAY-001` derived from `K-STORAGE-001` with explicit `CONFIG_OVERLAY_FS=y` and selected `CONFIG_FS_STACK=y`. The ordinary run was unobservable beyond B0, so the byte-identical `K-OVERLAY-DIAG-001` rerun used the approved elevated ETW path.

The diagnostic rerun proved B3 and advanced the failure boundary:

- the system-distro ext4 filesystem mounted;
- overlay construction returned without the prior `mini_init` segfault or kernel panic;
- stock startup then failed because the excluded GNS networking socket closed before `LxGnsMessageResult`;
- the host attempted NAT and then no-network fallback, but the control channel was already closed;
- the guest powered down cleanly and stock recovery passed.

B4 is not proved. Overlayfs is required by Microsoft’s stock system-distro path, not accepted for Minimal Viable WSL. GNS is the first stable blocker and networking is explicitly excluded, so additive stock-init kernel discovery stops here.

Post-trial recovery independently reported `safe:true`: the exact `.wslconfig` and packaged hashes were restored, stock Debian booted, no distro or utility VM remained running, WPR was idle, and the diagnostic relay was removed.

## Inventory

- 9 config snapshots;
- 10 completed trials;
- 113 reviewed annotations;
- SQLite integrity `ok` at the last synchronization.

Durable inputs are `annotations.csv`, `config-snapshots.csv`, `trials.csv`, and `trial-metadata.csv`. Other inventory exports are generated locally.

## Control-plane preparation

The retained host/guest path is mapped against the recovery baseline’s exact public source, WSL tag `2.7.12` at commit `68f601bba8eac1df20a0bbd403c6c87c92369ade`, in `WSL-CONTROL-PLANE-AUDIT.md`. The map identifies the VSOCK handshake, registered-distro VHDX message, namespace/root transition, inherited distro-init channel, command sockets, stdio/exit relay, and termination messages. The Linux-side init and deterministic initrd build byte-identically in two clean runs from separate working directories; hashes are recorded under `control-plane-build/native-build/`.

Source inspection also proves that a guest-only reduced init is insufficient: the stock host waits for an excluded GNS connection after early configuration and advertises the Microsoft system distro. Reduced-control-plane testing must patch both the Windows service and Linux init inside the disposable VM.

## Reduced control-plane prototype

The first source candidate is preserved under `control-plane/` against pinned WSL 2.7.12:

- a compiler-extracted protocol fixture pins retained message IDs, constants, structure sizes, and offsets to the shared-header hash;
- `minimal-v1` patches both `WslCoreVm`/`WslCoreInstance` and Linux `mini_init` to omit or reject the system distro, GNS/networking/DNS, WSLg, DrvFs, interop, OOBE, swap, modules, and memory policy while retaining the registered-distro launch and command/lifecycle channel;
- the patch applies cleanly and its complete source diff matches the recorded SHA-256;
- strict protocol tests cover malformed lengths, independently mutated excluded fields, process flags, exit statuses, and termination framing;
- the source audit separates removed paths from runtime rejection and identifies the unresolved IPC/PID/UTS namespace mismatch;
- `MINIMAL_LINK=1` removes unreachable sections, reducing stripped `init` from 2,835,320 to 2,511,032 bytes (11.4%); two clean builds are byte-identical and hashes are recorded in `control-plane/candidates/minimal-v1/`;
- a static retained-kernel review confirms that no new Kconfig addition follows before namespace ablation;
- the deferred runtime/recovery plan is recorded but explicitly non-executable;
- the Windows side has not yet been built or runtime-tested.

Hyper-V VM creation and baseline-checkpoint scripts are plan-validated. The environment-dependent phase is explicitly deferred because Windows installation media and the Visual Studio toolchain are large inputs. No ISO will be downloaded, no disposable VM will be created, and no Hyper-V elevation will be attempted until that later test is separately selected and approved.

## Target gap

No mkroot-derived candidate has reached Toybox command dispatch under WSL. Additive stock discovery has now reached an excluded service boundary, so the next phase is the reduced host and guest control plane. It must preserve VSOCK, distro VHDX mounting, root transition, command relay, termination, and recovery while removing the system distro, GNS, and unrelated stock policy. Neither `minimal-viable-wsl-v1` nor the Alpine/Arch/Debian compatibility profile exists yet.
