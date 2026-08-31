# Project status

This file contains verified present facts and the achieved boundary. `TASKS.md` owns incomplete work; `MINIMAL-BOOT-PLAN.md` owns the experiment contract. Completed trial evidence is immutable in `inventory/trials.csv`, `inventory/trial-metadata.csv`, and `recovery-harness/trials/`.

## Safety state

- Microsoft's packaged WSL 2.7.12 kernel and initrd remain the recovery baseline.
- No reduced control-plane package or new candidate kernel is currently deployed; the completed `minimal-v5-mount-pid-ns` interval restored the pinned stock package.
- The accepted stock calibration and independent recovery returned the disposable Windows VM to Off with no probe, trace, or shutdown failure. The retained `clean-shell` checkpoint was not restored or changed. Live state is not asserted here.
- Physical-host changes and operations affecting a shared WSL instance require fresh explicit approval. Operations wholly confined to the disposable fixture are standing-authorized within the pinned, offline, hash-verified, plan-validated, recoverable experiment envelope and require no human stage review or confirmation; they must fail closed on boundary or recovery failure.
- Exact `minimal-v4-stock-ns` runner validation staged and independently hash-verified its MSI, candidate manifest, and runner without installing or probing the candidate. Windows Installer reported the pinned stock product installed and that candidate absent; the fixture returned Off.
- The `minimal-v4-mount-ns` build completed with pinned offline inputs and extracted identities independently reverified. Exact runner validation then independently verified staged hashes, all 13 fault paths, stock-only MSI state, absent candidate evidence, and final fixture Off without installation or probing.
- Three v4 runtime elevation launches stopped before worker start and produced no operation result. Fresh launch 004 completed the v4 candidate and recovery intervals; stock product state `5`, candidate state `-1`, final fixture Off, and independent recovery `B6-T` are verified.
- Fresh v5 validation launch 002 verified every staged hash, all 13 fault paths, stock-only state, absent evidence, and final fixture Off. Runtime launch 001 then completed both fixed intervals; the candidate and independent recovery passed `B6-T`, stock product state is `5`, candidate state is `-1`, and the fixture returned Off.
- `K-PIDNS-001` and `K-OVERLAY-PIDNS-001` each completed one valid controlled-package interval at `B2`; both restored stock state, removed the temporary external-kernel `.wslconfig`, passed independent stock `B6-T` recovery, and returned the fixture Off. One overlay launch stopped at a pre-probe size guard and created no candidate result.

## Proven boundary

- The mkroot/Toybox lower bound passes `G4` under QEMU.
- WSL trials proved kernel/init entry (`B1`), VMBus and Hyper-V VSOCK (`B2`), and Hyper-V storage plus ext4 mount (`B3`).
- `K-OVERLAY-DIAG-001` reached stock system-distro overlay construction and stopped at excluded GNS networking policy. This is the reason additive stock-init discovery stopped; it is not a requirement to add networking.
- Every completed custom-kernel trial restored the exact stock configuration and proved stock Debian startup.

## Candidate state

- The retained source base is WSL 2.7.12 commit `68f601bba8eac1df20a0bbd403c6c87c92369ade`.
- `minimal-v3-fail-closed` removes the known excluded interop hard-fail while retaining only the minimal command-control policy.
- `minimal-v3-stock-ns` is finalized at `B2`; its initial-configuration rejection selected the v4 sender correction, not a namespace or Kconfig requirement.
- `minimal-v4-stock-ns` and `minimal-v4-mount-ns` are reproducible siblings that differ only in the coherent namespace bundle. Stock namespaces passed `B6-T`; mount-only reached `B3` and closed its control socket after ext4 mount, selecting the full bundle as the passing baseline without isolating IPC, PID, or UTS individually.
- Every v3 and v4 Linux artifact built byte-identically twice offline in separate ext4 directories. The `minimal-v5-mount-pid-ns` source candidate also built byte-identically twice offline and passed `B6-T`.
- The controlled comparison isolates PID semantics: mount-only failed after `B3`, while mount plus PID passed `B6-T` with IPC and UTS still omitted. `CONFIG_PID_NS` is now `PROVEN_WSL_REQUIRED`; IPC and UTS namespace options are `DEFERRED` for the tested minimal contract.
- The storage-parent-plus-PID and overlay-parent-plus-PID reduced kernels both booted and exchanged mini-init capabilities plus early/initial configuration, then the utility VM ended before dynamic registered-distro attachment completed. ETW shows storage-adapter teardown preceded the HCS invalid-handle result, so the host storage error is consequential. Overlay did not change the boundary.
- Source ordering selects mini-init `Initialize` as the next reduction boundary. Its hard-failing write to `/proc/sys/fs/inotify/max_user_watches` requires `CONFIG_INOTIFY_USER`, which every reduced kernel omits and the source justifies only for excluded Visual Studio Code Remote integration. Do not add the symbol; remove the excluded hard-fail in the next source layer after reviewing the rest of `Initialize`.

## Active experiment boundary

The project is no longer developing general Hyper-V, PowerShell Direct, checkpoint-race, baseline-installer, or VM-rebuild tooling. Those attempts are historical infrastructure work, not project milestones.

The only active experiment path is the fixed candidate comparison:

1. stock WSL 2.7.12 calibration with the exact Toybox rootfs — accepted at `B6-T` in `CP-STOCK-2.7.12-003`;
2. `minimal-v3-stock-ns` diagnostic interval — finalized at `B2` in `CP-MINIMAL-V3-STOCK-NS-001`;
3. evidence-corrected `minimal-v4-stock-ns` — finalized at `B6-T` in `CP-MINIMAL-V4-STOCK-NS-001`;
4. `minimal-v4-mount-ns` — finalized at `B3` in `CP-MINIMAL-V4-MOUNT-NS-001`;
5. provisional v4 decision — retain the full coherent bundle pending a narrow PID ablation;
6. `minimal-v5-mount-pid-ns` — finalized at `B6-T` in `CP-MINIMAL-V5-MOUNT-PID-NS-001`, selecting mount plus PID and rejecting IPC and UTS;
7. `K-PIDNS-001` with the finalized control plane — finalized at `B2` in `CP-MINIMAL-V5-K-PIDNS-001`;
8. conservative `K-OVERLAY-PIDNS-001` sibling — finalized at the same `B2`, rejecting overlay as the missing facility;
9. remove the excluded inotify hard-fail from the retained guest initialization path, rebuild reproducibly, and retest `k-pidns-001`.

`tools/Invoke-WslCandidateProbe.ps1` is the retained guest-local measurement tool. It records exact candidate/rootfs hashes, bounded `wsl.exe` process results, WSL ETW/events/crashes, shutdown, and an evidence hash manifest. Fixture start, package placement, rollback, and evidence extraction are prerequisites around the experiment, not objects being minimized and not separate acceptance ledgers.

The pinned source, build dependencies, stock package, candidate identities, and non-executable trial contract are recorded in `control-plane/deferred-runtime-plan.json`. Approved attempt `CP-STOCK-2.7.12-001` proved only that the fixture lacked an installed WSL product: both fixed intervals reported that WSL was not installed, neither reached distro enumeration or Toybox, both evidence manifests verified, and no candidate ledger row was created. This is infrastructure failure, not stock-candidate failure.

Approved baseline attempt `CP-STOCK-2.7.12-002` installed the pinned stock MSI and verified WSL 2.7.12.0, then stopped before either fixed probe because Toybox import found both required Windows optional features disabled. Nested virtualization is exposed, the guest sees a hypervisor, no Toybox import directory or candidate evidence was created, and the fixture returned Off. This is another infrastructure failure and has no candidate ledger row.

Approved `CP-STOCK-2.7.12-003` enabled both optional features, completed a controlled reboot, imported the pinned Toybox rootfs, and calibrated the fixed probe against stock WSL 2.7.12. The candidate and independent recovery intervals both passed management checks, printed `toybox-ok`, reached `B6-T`, captured complete trace/event/process evidence, verified 19-file manifests, and shut WSL down cleanly. The immutable evidence and terminal ledger row are preserved under `recovery-harness/trials/CP-STOCK-2.7.12-003/`.

The non-runtime `minimal-v3-stock-ns` controlled package build is complete. Attempt 003 installed the pinned toolchain after adding the exact Microsoft Windows Code Signing PCA 2024 required offline, then evidence-selected three procedure corrections: remove GNU-only `tar.exe --force-local`, include intent-to-add files in the complete diff, and normalize CMake-facing paths. Retry r5 compiled and packaged successfully, reproduced complete source diff `97935c…76ad`, produced unsigned MSI SHA-256 `e9c415…fe77` (174,407,680 bytes) and output-manifest SHA-256 `ab307e…f6de`, extracted and independently reverified them, and returned the fixture Off.

Exact installation/recovery runner validation is also complete. The hash-bound runner passed 13 local and fixture-side failure injections, including partial MSI transitions and recovery failures; every post-mutation path restored stock-only product state, and every path capable of doing so invoked the unchanged independent recovery probe. Fixture validation independently verified all staged hashes and 174,407,680-byte package size, reported Windows Installer state `5` for stock and `-1` for the candidate, found no candidate evidence, and returned the exact fixture Off. The first validation attempt was an infrastructure failure before runner execution because guest script execution was disabled; retrying with process-local `Bypass` succeeded.

`CP-MINIMAL-V3-STOCK-NS-001` then completed as a valid candidate failure. Management checks passed; ETW GuestLog records `/init`, WSL 2.7.12, storvsc, VSOCK, and mini-init processing before `Rejected excluded initial configuration`. No ext4 mount occurred, and Toybox returned `Wsl/Service/CreateInstance/E_ABORT`, so the highest directly supported gate is `B2`. Both 20-file evidence manifests verified, the exact stock package was restored, the independent recovery interval passed `B6-T`, and the fixture returned Off. The immutable evidence and terminal ledger row are preserved under `recovery-harness/trials/CP-MINIMAL-V3-STOCK-NS-001/`.

The evidence-selected `minimal-v4` layer explicitly zeros every excluded GUI, GPU, and networking initial-configuration field on the Windows sender without changing guest or namespace code. The parent, stock-namespace, and mount-namespace records are complete; stock and mount each built byte-identically twice offline in separate ext4 build directories. After two earlier elevation launches never started, the controlled `minimal-v4-stock-ns` Windows build completed: the unsigned MSI is 174,411,776 bytes with SHA-256 `50f17b…6cda`, the output manifest is `b8d887…1826`, extracted identities reverified, and the fixture returned Off. ProductCode is `{929334FC-D0AF-423B-A33D-0068D4AC506B}`.

The v4 runner preserves the accepted probe, timeouts, transaction, and independent recovery mechanics with only candidate identities changed. All 13 fault-injection paths passed; fixture validation independently verified staged hashes, stock installed state `5`, candidate state `-1`, no candidate evidence, and final fixture Off without installing or probing. Two infrastructure-only attempts stopped before runner execution and created no candidate result.

`CP-MINIMAL-V4-STOCK-NS-001` then completed at `B6-T`. Management checks passed, the registered Toybox ext4 filesystem mounted, instance creation succeeded, the exact smoke command printed `toybox-ok` with exit zero, and termination was graceful. Both 20-file evidence manifests verified, the exact stock package was restored, independent recovery passed `B6-T`, and the fixture returned Off. The immutable evidence and terminal ledger row are preserved under `recovery-harness/trials/CP-MINIMAL-V4-STOCK-NS-001/`. This establishes corrected-control-plane viability, not that IPC/PID/UTS namespaces are required.

The evidence-selected `minimal-v4-mount-ns` controlled Windows build subsequently started under fresh operation ID 003 and completed from the unchanged pinned offline inputs. The unsigned MSI is 174,403,584 bytes with SHA-256 `0348f4…2518`, ProductCode `{13294BEB-3E05-4814-A642-84742C1DAFAF}`, output-manifest SHA-256 `db215c…3e61`, and complete source diff `197804…a13a`; extracted identities independently reverified and the fixture returned Off. The exact hash-bound `CP-MINIMAL-V4-MOUNT-NS-001` runner preserves the accepted probe and recovery mechanics and passes all 13 local fault injections. After two validation launches stopped before worker start, fresh validation operation 003 independently verified every staged hash, package size, all 13 fixture-side fault paths, stock product state `5`, candidate state `-1`, absent candidate evidence, and final fixture Off without installation or probing.

After three runtime launches stopped before worker start, fresh launch 004 completed a valid candidate interval. Management checks passed, `/init`, VSOCK, and Hyper-V storage initialized, and the registered Toybox ext4 filesystem mounted read-write. The mount-only launch child then unmounted it and closed `WslCorePort` before returning `LxMiniInitMessageCreateInstanceResult`; the host reported `Wsl/Service/CreateInstance/E_UNEXPECTED`. The highest directly supported gate is `B3`. Both 20-file manifests verify, the pinned stock MSI was restored, independent recovery passed `B6-T`, and the fixture returned Off. Immutable evidence and the terminal ledger row are preserved under `recovery-harness/trials/CP-MINIMAL-V4-MOUNT-NS-001/`.

The sibling result initially retained the full IPC/mount/PID/UTS namespace bundle as the passing baseline. The narrow `minimal-v5-mount-pid-ns` ablation then restored PID semantics while continuing to remove IPC and UTS. Its complete source diff is `cfd8cd…efe8`; two pinned offline Linux builds produced byte-identical `init`, `init.debug`, and `initrd.img`. The pinned controlled Windows build produced unsigned MSI SHA-256 `343f90…f50d`, ProductCode `{796B7461-B342-4554-AF96-A8CFEF80EE5B}`, and output-manifest SHA-256 `67385c…7569`; extracted identities independently reverified.

Fresh validation operation 002 independently verified every staged hash, package size, all 13 fixture-side fault paths, stock product state `5`, candidate state `-1`, absent candidate evidence, and final fixture Off without installation or probing. The exact runtime controller was then hash-bound and plan-validated. Runtime operation 001 passed management checks, mounted the registered Toybox ext4 filesystem, returned CreateInstanceResult successfully, printed `toybox-ok` with exit zero, and terminated gracefully. Both 20-file manifests verify, no GuestLog fatal signature was observed, the pinned stock MSI was restored, independent recovery passed `B6-T`, and the fixture returned Off. Immutable evidence and the terminal ledger row are preserved under `recovery-harness/trials/CP-MINIMAL-V5-MOUNT-PID-NS-001/`.

The controlled delta from mount-only `B3` to mount-plus-PID `B6-T` selects PID namespace semantics. IPC and UTS remained omitted in the passing candidate and are not required by the tested minimal contract.

The first reduced kernel, `K-PIDNS-001`, derived from `K-STORAGE-001` and changed only `CONFIG_PID_NS=n` to `y`. Two separate offline ext4 builds produced byte-identical full configs and kernels. `CP-MINIMAL-V5-K-PIDNS-001` booted that exact kernel and exchanged mini-init capabilities, EarlyConfig, and InitialConfig, then HCS failed to associate the registered Toybox VHDX because the storage-adapter handle had already become invalid. No ext4 mount occurred, so the evidence ceiling is `B2`. The candidate shutdown timed out, but the guarded transaction removed `.wslconfig`, restored the exact stock package, passed independent `B6-T` recovery, and returned the fixture Off.

The evidence-selected conservative sibling, `K-OVERLAY-PIDNS-001`, retained the only reduced-kernel parent previously observed beyond B3 and added only PID namespaces. It also built byte-identically twice offline. One launch failed its size guard before runner execution and created no candidate result; the corrected fresh-ID launch reproduced the exact `B2` adapter-lifetime failure. Stock recovery again passed `B6-T` and the fixture returned Off. This rejects overlay as the missing facility.

ETW ordering shows mini-init configuration exchange followed by storage-adapter teardown before the HCS invalid-handle result. The next work is therefore source reduction, not speculative storage or PCI additions. The retained EarlyConfig handler calls `Initialize`, whose hard-failing inotify sysctl write is justified only for excluded Visual Studio Code Remote integration and cannot succeed with `CONFIG_INOTIFY_USER=n`. The next source layer must remove that excluded hard-fail, review subsequent `Initialize` operations for contract reachability, preserve fail-closed policy, and retest `k-pidns-001`.

## Inventory

The durable inventory contains 11 config snapshots, 17 completed trials, and 175 reviewed annotations; synchronization integrity is verified `ok`. Candidate runtime work must reuse the existing ledgers and evidence directories rather than creating infrastructure-specific records.
