# Project status

This file contains verified present facts and the achieved boundary. `TASKS.md` owns incomplete work; `MINIMAL-BOOT-PLAN.md` owns the experiment contract. Completed trial evidence is immutable in `inventory/trials.csv`, `inventory/trial-metadata.csv`, and `recovery-harness/trials/`.

## Safety state

- Microsoft's packaged WSL 2.7.12 kernel and initrd remain the recovery baseline.
- No reduced control-plane package or new candidate kernel has been deployed by the current work.
- The accepted stock calibration and independent recovery returned the disposable Windows VM to Off with no probe, trace, or shutdown failure. The retained `clean-shell` checkpoint was not restored or changed. Live state is not asserted here.
- Physical-host changes and operations affecting a shared WSL instance require fresh explicit approval. Operations wholly confined to the disposable fixture are standing-authorized within the pinned, offline, hash-verified, plan-validated, recoverable experiment envelope; they must fail closed on boundary or recovery failure.
- The prior non-runtime build attempt returned the fixture Off before input staging or installation.

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
- No v3 candidate has runtime evidence for `B4`, `B5`, or `B6-T`; no namespace or Kconfig requirement may be promoted from static preference.

## Active experiment boundary

The project is no longer developing general Hyper-V, PowerShell Direct, checkpoint-race, baseline-installer, or VM-rebuild tooling. Those attempts are historical infrastructure work, not project milestones.

The only active experiment path is the fixed candidate comparison:

1. stock WSL 2.7.12 calibration with the exact Toybox rootfs — accepted at `B6-T` in `CP-STOCK-2.7.12-003`;
2. compile and hash the `minimal-v3-stock-ns` controlled package without installing it;
3. record produced hashes, separately plan-validate, install, and test `minimal-v3-stock-ns` with the same probe inside the disposable fixture;
4. restore the accepted baseline and repeat the same build/runtime contract for `minimal-v3-mount-ns`;
5. classify the earliest supported B-gate and use the comparison to select the next configuration change.

`tools/Invoke-WslCandidateProbe.ps1` is the retained guest-local measurement tool. It records exact candidate/rootfs hashes, bounded `wsl.exe` process results, WSL ETW/events/crashes, shutdown, and an evidence hash manifest. Fixture start, package placement, rollback, and evidence extraction are prerequisites around the experiment, not objects being minimized and not separate acceptance ledgers.

The pinned source, build dependencies, stock package, candidate identities, and non-executable trial contract are recorded in `control-plane/deferred-runtime-plan.json`. Approved attempt `CP-STOCK-2.7.12-001` proved only that the fixture lacked an installed WSL product: both fixed intervals reported that WSL was not installed, neither reached distro enumeration or Toybox, both evidence manifests verified, and no candidate ledger row was created. This is infrastructure failure, not stock-candidate failure.

Approved baseline attempt `CP-STOCK-2.7.12-002` installed the pinned stock MSI and verified WSL 2.7.12.0, then stopped before either fixed probe because Toybox import found both required Windows optional features disabled. Nested virtualization is exposed, the guest sees a hypervisor, no Toybox import directory or candidate evidence was created, and the fixture returned Off. This is another infrastructure failure and has no candidate ledger row.

Approved `CP-STOCK-2.7.12-003` enabled both optional features, completed a controlled reboot, imported the pinned Toybox rootfs, and calibrated the fixed probe against stock WSL 2.7.12. The candidate and independent recovery intervals both passed management checks, printed `toybox-ok`, reached `B6-T`, captured complete trace/event/process evidence, verified 19-file manifests, and shut WSL down cleanly. The immutable evidence and terminal ledger row are preserved under `recovery-harness/trials/CP-STOCK-2.7.12-003/`.

`minimal-v3-stock-ns` remains uncompiled and untested. Attempt 001 stopped because the fixture lacked PowerShell 7. Attempt 002 staged every verified input and installed pinned PowerShell 7.6.5, then Visual Studio stopped at exit 5003. Attempt 003 proved the offline fixture needed Microsoft Windows Code Signing PCA 2024; after that exact Microsoft certificate was pinned and imported, Visual Studio installed successfully. Compilation then selected and corrected two fail-closed procedure defects: Windows `tar.exe` rejected GNU-only `--force-local`, and the complete-diff gate omitted the new intent-to-add file. The subsequent build retry still exited 1 before producing a package. Extraction of its retained log was stopped when the UAC prompt was explicitly cancelled. No package or candidate result exists; the fixture shutdown guard completed after the build failure. Candidate-package installation and runtime remain blocked on produced hashes and separate plan validation.

## Inventory

The durable inventory contains 9 config snapshots, 11 completed trials, and 174 reviewed annotations; synchronization integrity was last verified `ok`. Candidate runtime work must reuse the existing ledgers and evidence directories rather than creating infrastructure-specific records.
