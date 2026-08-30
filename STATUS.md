# Project status

This file contains verified present facts and the achieved boundary. `TASKS.md` owns incomplete work; `MINIMAL-BOOT-PLAN.md` owns the experiment contract. Completed trial evidence is immutable in `inventory/trials.csv`, `inventory/trial-metadata.csv`, and `recovery-harness/trials/`.

## Safety state

- Microsoft's packaged WSL 2.7.12 kernel and initrd remain the recovery baseline.
- No reduced control-plane package or new candidate kernel is currently deployed; the completed `minimal-v3-stock-ns` interval restored the pinned stock package.
- The accepted stock calibration and independent recovery returned the disposable Windows VM to Off with no probe, trace, or shutdown failure. The retained `clean-shell` checkpoint was not restored or changed. Live state is not asserted here.
- Physical-host changes and operations affecting a shared WSL instance require fresh explicit approval. Operations wholly confined to the disposable fixture are standing-authorized within the pinned, offline, hash-verified, plan-validated, recoverable experiment envelope and require no human stage review or confirmation; they must fail closed on boundary or recovery failure.
- Exact runner validation staged and independently hash-verified the produced MSI, candidate manifest, and runner without installing or probing the candidate. Windows Installer reported the pinned stock product installed and the candidate absent; the fixture returned Off.

## Proven boundary

- The mkroot/Toybox lower bound passes `G4` under QEMU.
- WSL trials proved kernel/init entry (`B1`), VMBus and Hyper-V VSOCK (`B2`), and Hyper-V storage plus ext4 mount (`B3`).
- `K-OVERLAY-DIAG-001` reached stock system-distro overlay construction and stopped at excluded GNS networking policy. This is the reason additive stock-init discovery stopped; it is not a requirement to add networking.
- Every completed custom-kernel trial restored the exact stock configuration and proved stock Debian startup.

## Candidate state

- The retained source base is WSL 2.7.12 commit `68f601bba8eac1df20a0bbd403c6c87c92369ade`.
- `minimal-v3-fail-closed` removes the known excluded interop hard-fail while retaining only the minimal command-control policy.
- `minimal-v3-stock-ns` and `minimal-v3-mount-ns` are reproducible siblings that differ only in the coherent namespace bundle. Neither is selected.
- All three v3 Linux artifacts built byte-identically twice offline in separate ext4 directories.
- `minimal-v3-stock-ns` has runtime evidence through `B2` only. It rejected the initial configuration before ext4 mount; no namespace or Kconfig requirement may be promoted from this result.

## Active experiment boundary

The project is no longer developing general Hyper-V, PowerShell Direct, checkpoint-race, baseline-installer, or VM-rebuild tooling. Those attempts are historical infrastructure work, not project milestones.

The only active experiment path is the fixed candidate comparison:

1. stock WSL 2.7.12 calibration with the exact Toybox rootfs — accepted at `B6-T` in `CP-STOCK-2.7.12-003`;
2. compile and hash the `minimal-v3-stock-ns` controlled package without installing it;
3. record produced hashes, agent-validate the executable plan, then immediately install and test `minimal-v3-stock-ns` with the same probe inside the disposable fixture — complete at `B2` in `CP-MINIMAL-V3-STOCK-NS-001`;
4. restore the accepted baseline and repeat the same build/runtime contract for `minimal-v3-mount-ns`;
5. classify the earliest supported B-gate and use the comparison to select the next configuration change.

`tools/Invoke-WslCandidateProbe.ps1` is the retained guest-local measurement tool. It records exact candidate/rootfs hashes, bounded `wsl.exe` process results, WSL ETW/events/crashes, shutdown, and an evidence hash manifest. Fixture start, package placement, rollback, and evidence extraction are prerequisites around the experiment, not objects being minimized and not separate acceptance ledgers.

The pinned source, build dependencies, stock package, candidate identities, and non-executable trial contract are recorded in `control-plane/deferred-runtime-plan.json`. Approved attempt `CP-STOCK-2.7.12-001` proved only that the fixture lacked an installed WSL product: both fixed intervals reported that WSL was not installed, neither reached distro enumeration or Toybox, both evidence manifests verified, and no candidate ledger row was created. This is infrastructure failure, not stock-candidate failure.

Approved baseline attempt `CP-STOCK-2.7.12-002` installed the pinned stock MSI and verified WSL 2.7.12.0, then stopped before either fixed probe because Toybox import found both required Windows optional features disabled. Nested virtualization is exposed, the guest sees a hypervisor, no Toybox import directory or candidate evidence was created, and the fixture returned Off. This is another infrastructure failure and has no candidate ledger row.

Approved `CP-STOCK-2.7.12-003` enabled both optional features, completed a controlled reboot, imported the pinned Toybox rootfs, and calibrated the fixed probe against stock WSL 2.7.12. The candidate and independent recovery intervals both passed management checks, printed `toybox-ok`, reached `B6-T`, captured complete trace/event/process evidence, verified 19-file manifests, and shut WSL down cleanly. The immutable evidence and terminal ledger row are preserved under `recovery-harness/trials/CP-STOCK-2.7.12-003/`.

The non-runtime `minimal-v3-stock-ns` controlled package build is complete. Attempt 003 installed the pinned toolchain after adding the exact Microsoft Windows Code Signing PCA 2024 required offline, then evidence-selected three procedure corrections: remove GNU-only `tar.exe --force-local`, include intent-to-add files in the complete diff, and normalize CMake-facing paths. Retry r5 compiled and packaged successfully, reproduced complete source diff `97935c…76ad`, produced unsigned MSI SHA-256 `e9c415…fe77` (174,407,680 bytes) and output-manifest SHA-256 `ab307e…f6de`, extracted and independently reverified them, and returned the fixture Off.

Exact installation/recovery runner validation is also complete. The hash-bound runner passed 13 local and fixture-side failure injections, including partial MSI transitions and recovery failures; every post-mutation path restored stock-only product state, and every path capable of doing so invoked the unchanged independent recovery probe. Fixture validation independently verified all staged hashes and 174,407,680-byte package size, reported Windows Installer state `5` for stock and `-1` for the candidate, found no candidate evidence, and returned the exact fixture Off. The first validation attempt was an infrastructure failure before runner execution because guest script execution was disabled; retrying with process-local `Bypass` succeeded.

`CP-MINIMAL-V3-STOCK-NS-001` then completed as a valid candidate failure. Management checks passed; ETW GuestLog records `/init`, WSL 2.7.12, storvsc, VSOCK, and mini-init processing before `Rejected excluded initial configuration`. No ext4 mount occurred, and Toybox returned `Wsl/Service/CreateInstance/E_ABORT`, so the highest directly supported gate is `B2`. Both 20-file evidence manifests verified, the exact stock package was restored, the independent recovery interval passed `B6-T`, and the fixture returned Off. The immutable evidence and terminal ledger row are preserved under `recovery-harness/trials/CP-MINIMAL-V3-STOCK-NS-001/`.

The evidence-selected `minimal-v4` layer explicitly zeros every excluded GUI, GPU, and networking initial-configuration field on the Windows sender without changing guest or namespace code. The parent, stock-namespace, and mount-namespace records are complete; stock and mount each built byte-identically twice offline in separate ext4 build directories. The controlled `minimal-v4-stock-ns` Windows package procedure is hash-bound and ready. Two bounded elevated controller launches remained at the UAC `launching` state, created no worker status/log/result, and therefore performed no recorded fixture build action; live fixture state after those controller timeouts is not asserted.

## Inventory

The durable inventory contains 9 config snapshots, 12 completed trials, and 174 reviewed annotations; synchronization integrity is verified `ok`. Candidate runtime work must reuse the existing ledgers and evidence directories rather than creating infrastructure-specific records.
