# Project status

This file contains verified present facts and the achieved boundary. `TASKS.md` owns incomplete work; `MINIMAL-BOOT-PLAN.md` owns the experiment contract. Completed trial evidence is immutable in `inventory/trials.csv`, `inventory/trial-metadata.csv`, and `recovery-harness/trials/`.

## Safety state

- Microsoft's packaged WSL 2.7.12 kernel and initrd remain the recovery baseline.
- No reduced control-plane package or new candidate kernel has been deployed by the current work.
- The last reviewed disposable-fixture evidence reported the Windows VM Off, exact `clean-shell` restored, and zero host-attached disks. Live state is not asserted here.
- Any WSL shutdown, custom boot, package installation, fixture operation, or runtime trial still requires plan validation and fresh explicit approval.

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

The only active runtime path is candidate comparison:

1. calibrate the fixed probe against stock WSL 2.7.12 and the exact Toybox rootfs;
2. test `minimal-v3-stock-ns` with the same probe;
3. restore the same baseline and test `minimal-v3-mount-ns`;
4. classify the earliest supported B-gate from captured evidence;
5. use the comparison to select the next configuration change.

`tools/Invoke-WslCandidateProbe.ps1` is the retained guest-local measurement tool. It records exact candidate/rootfs hashes, bounded `wsl.exe` process results, WSL ETW/events/crashes, shutdown, and an evidence hash manifest. Fixture start, package placement, rollback, and evidence extraction are prerequisites around the experiment, not objects being minimized and not separate acceptance ledgers.

The pinned source, build dependencies, stock package, candidate identities, and non-executable trial contract are recorded in `control-plane/deferred-runtime-plan.json`. The exact stock calibration and independent stock-recovery probe are repository-validated and stopped at the fresh-approval boundary. That record carries no approval and authorizes no execution.

## Inventory

The durable inventory contains 9 config snapshots, 10 completed trials, and 174 reviewed annotations; synchronization integrity was last verified `ok`. Candidate runtime work must reuse the existing ledgers and evidence directories rather than creating infrastructure-specific records.
