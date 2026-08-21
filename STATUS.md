# Project status

Updated 2026-08-21. This file contains current facts only; immutable history is in `inventory/trials.csv` and `recovery-harness/trials/`.

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
- 125 reviewed annotations;
- SQLite integrity `ok` at the last synchronization.

Durable inputs are `annotations.csv`, `config-snapshots.csv`, `trials.csv`, and `trial-metadata.csv`. Other inventory exports are generated locally.

## Build host

`LFS-Builder` is a dedicated Debian 13 amd64 build host on ext4, not a target distribution. Profile 1 pins its Debian snapshot, exact required package versions, uv/uvx, and ShellCheck 0.11 with verified hashes. Standard control-plane builds and protocol extraction now fail closed unless `tools/bootstrap-lfs-builder.sh --check` passes; build-specific archives retain their separate verified caches.

## Control-plane preparation

The retained host/guest path is mapped against the recovery baseline’s exact public source, WSL tag `2.7.12` at commit `68f601bba8eac1df20a0bbd403c6c87c92369ade`, in `WSL-CONTROL-PLANE-AUDIT.md`. The map identifies the VSOCK handshake, registered-distro VHDX message, namespace/root transition, inherited distro-init channel, command sockets, stdio/exit relay, and termination messages. The Linux-side init and deterministic initrd build byte-identically in two clean runs from separate working directories; hashes are recorded under `control-plane-build/native-build/`.

Source inspection also proves that a guest-only reduced init is insufficient: the stock host waits for an excluded GNS connection after early configuration and advertises the Microsoft system distro. Reduced-control-plane testing must patch both the Windows service and Linux init inside the disposable VM.

## Reduced control-plane candidates

The source-only reduction is recorded under `control-plane/` against pinned WSL 2.7.12:

- the preserved `minimal-v1` patch and hashes remain unchanged;
- the compiler-derived fixture now pins all 52 init/mini-init control message families used by the fail-closed policy tests;
- layered `minimal-v2-fail-closed` uses one shared policy seam to permit only early/initial configuration, one LUN/ext4 launch, initialization/session/direct-process plumbing, console-only process flags, exit status, and termination;
- guest configuration prevents `/etc/wsl.conf` or host fields from re-enabling DrvFs, timezone, networking/DNS, interop, systemd/boot commands, Plan 9, GPU, cgroups, or other excluded policy;
- `minimal-v2-stock-ns` is tree-identical to the fail-closed parent and retains IPC/mount/PID/UTS namespaces; `minimal-v2-mount-ns` differs only by retaining the mount namespace;
- tests enumerate every retained and rejected family on each inbound channel, malformed lengths, excluded fields and flags, signed exit statuses, and clean/forced termination framing;
- semantic mutations that added mini-init import and removed distro termination were both caught and reverted;
- each fail-closed/namespace candidate built twice offline in distinct ext4 directories with verified cache hits and byte-identical `init`, `init.debug`, and `initrd.img`; a later independent six-build recheck reproduced every artifact and metadata hash;
- fail-closed/stock stripped `init` is 2,450,672 bytes, 60,360 bytes (2.4%) below `minimal-v1`; mount-only has the same size but a distinct expected hash;
- the deferred runtime/recovery plan carries all candidate hashes but remains non-executable and carries no approval;
- no Windows component has been compiled and no candidate has been runtime-tested.

Hyper-V VM creation and baseline-checkpoint scripts are plan-validated. The environment-dependent phase is explicitly deferred because Windows installation media and the Visual Studio toolchain are large inputs. No ISO will be downloaded, no disposable VM will be created, and no Hyper-V elevation will be attempted until that later test is separately selected and approved.

## Reproducibility recheck

After the pinned build-host profile was finalized, builds with higher Clang fan-out repeatedly failed during object finalization with `unable to rename temporary ... .o.tmp ... No such file or directory`. The ext4 filesystem was healthy, space was ample, a trivial compile succeeded, and no persistent OOM or I/O evidence was available after restart. All six required candidate rechecks subsequently completed in separate ext4 directories at `JOBS=1`; their source/profile metadata and all artifact hashes exactly match the durable records. A fresh `JOBS=2` offline fail-closed build also completed with verified cache hits and matching hashes. The build script now defaults to that proven bound rather than host `nproc`; higher explicit fan-out remains unverified on this 8 GiB builder.

## Restart point

The `minimal-v2` source, durable records, and independent reproducibility recheck are complete. The retained-path Kconfig review now classifies nine mkroot-supplied facilities as `BASE` and leaves IPC/PID/UTS namespace options reviewed but unresolved. Continue source-only control-plane reduction or the next coherent Kconfig group while keeping both namespace siblings unselected. Keep the Windows environment deferred; do not provision, elevate, boot, or promote namespace Kconfig without fresh authorization and runtime evidence.

`NEXT-SESSION.md` is the copy/paste restart brief for that boundary.

## Target gap

No mkroot-derived candidate has reached Toybox command dispatch under WSL. Additive stock discovery stopped at an excluded service boundary, and the source-only reduced host/guest candidates now preserve VSOCK, distro VHDX mounting, root transition, command relay, termination, and recovery while rejecting the system distro, GNS, and unrelated stock policy. The remaining gap is deferred Windows compilation and controlled runtime proof of B4/B5/B6-T, including namespace selection and later minimality ablation. Neither `minimal-viable-wsl-v1` nor the Alpine/Arch/Debian compatibility profile exists yet.
