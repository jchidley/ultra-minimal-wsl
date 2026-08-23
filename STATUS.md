# Project status

This file contains verified present facts and the achieved boundary. Immutable trial history is in `inventory/trials.csv` and `recovery-harness/trials/`; detailed source/build evidence is under `control-plane/`.

## Safety state

- Microsoft’s packaged kernel remains the recovery kernel; no reduced init or custom WSL package has been deployed.
- No project file has been written beneath `C:\Program Files\WSL`, and host WSL state was not changed.
- The approved disposable VM `ultra-minimal-wsl-dev` is Off after applying Windows offline. Its verified stock WSL package was staged into the active differencing disk, but the stock baseline was not established. PowerShell Direct is now the selected guest-control mechanism, using a dedicated random 12-character VM-only local account; the account still requires one fixed bootstrap procedure before PowerShell Direct can authenticate.
- The validated host baseline remains WSL 2.7.12.0 with the packaged kernel and initrd unchanged; exact recovery hashes belong to `recovery-harness/expected-safe-state.json`.
- Live distro/process state is intentionally not recorded here. Re-query it with `tools/Test-WslSafeState.ps1`; never stop a running distro automatically.
- Custom boot, WSL shutdown, `.wslconfig` changes, candidate installation, or runtime trials require canonical `safe:true`, plan validation, and fresh explicit approval.

## Achieved boundary

- The mkroot/Toybox baseline passes `G4` under QEMU.
- WSL trials proved kernel/init entry (`B1`), VMBus and Hyper-V VSOCK (`B2`), and Hyper-V storage plus ext4 mount (`B3`).
- `K-OVERLAY-DIAG-001` proved stock system-distro overlay construction and then stopped at the excluded GNS networking service. Additive stock-init kernel discovery is frozen there; B4 is not proved.
- Every completed custom trial restored the exact stock configuration and proved stock Debian startup. Trial details and recovery evidence remain in the immutable ledgers and trial directories.

## Inventory and build host

- Inventory contains 9 config snapshots, 10 completed trials, and 174 reviewed annotations; synchronization integrity is `ok`.
- Durable inputs are `inventory/annotations.csv`, `inventory/config-snapshots.csv`, `inventory/trials.csv`, and `inventory/trial-metadata.csv`.
- `LFS-Builder` profile 1 is the pinned Debian 13 amd64 ext4 build environment; its exact bundle identity belongs to `build-host/SHA256SUMS`.
- Two build jobs are the proven default on the 8 GiB builder; higher fan-out remains unverified.

## Reduced control-plane boundary

- The retained host/guest contract is pinned to WSL 2.7.12 commit `68f601bba8eac1df20a0bbd403c6c87c92369ade` and mapped in `WSL-CONTROL-PLANE-AUDIT.md`.
- Preserved `minimal-v1` and all `minimal-v2` records remain unchanged. Replacement `minimal-v3-fail-closed`, stock-namespace, and mount-only records add only the mini-init interop-removal layer and coherent namespace variant; all three built byte-identically twice offline in distinct ext4 directories.
- Focused regression coverage requires the new layer to remove mini-init's unconditional `binfmt_misc` mount and `WSLInterop` registration without changing protocol policy. The retained protocol, policy, record, and mutation behavior still passes.
- These candidates prove source policy and Linux artifact identity only. No Windows component has been compiled and no candidate has reached B4, B5, or B6-T.
- Both namespace siblings remain unselected. Static source preference does not select `CONFIG_IPC_NS`, `CONFIG_PID_NS`, or `CONFIG_UTS_NS`.
- `CONFIG_ANON_VMA_NAME` is reviewed `DEFERRED`: pinned and reduced source has no anonymous-map naming or maps/smaps consumer, and neither relay, lifecycle, nor the smoke contract selects it.

## Current boundary and milestone gap

The source-only runtime-readiness queue is complete: the known excluded interop hard-fail is removed, replacement candidates are recorded and reproducible, and the non-executable runtime plan is synchronized to them. Do not select another Kconfig group merely to continue static review.

The controlled Windows build/runtime phase remains deferred. The verified Windows media, pinned WSL source, NuGet packages, NuGet 5.10.0, pinned FetchContent archives, complete verified Community offline layout, and exact Microsoft WSL 2.7.12.0 x64 stock MSI are cached; the older Build Tools layout remains prerequisite-incomplete and is not the compiler input. The approved disposable VM contains offline-applied Windows and remains Off. The verified stock package was staged into its active differencing disk, but stock WSL installation and the controlled baseline checkpoint were not established. The controller selected PowerShell Direct with a unique disposable VM-only account; its random 12-character user ID is recorded in the non-executable plan, while its random 12-character password is deliberately excluded from Git. Because the new account does not yet exist in the guest, commission and approve one fixed bootstrap procedure before using PowerShell Direct. Do not install the MSI or create the checkpoint until that unchanged procedure is plan-validated and freshly approved. Do not install inbox/latest WSL, use an unpinned package, or synthesize a stock package. The fail-closed offline package-build, output, install, checkpoint, and stock-recovery procedure remains source-backed and recorded in `control-plane/deferred-runtime-plan.json`; no candidate was compiled or installed, and no host WSL state or runtime was changed. Minimal Viable WSL must then pass minimality and cold-start gates before Alpine, Arch, and Debian compatibility work can produce `ultra-minimal-wsl-v1`.

`TASKS.md` owns incomplete work; `MINIMAL-BOOT-PLAN.md` owns the durable strategy and acceptance criteria; `NEXT-SESSION.md` is the restart entry point.
