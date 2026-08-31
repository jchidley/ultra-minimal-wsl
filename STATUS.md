# Project status

This file contains verified present facts and the achieved boundary. `TASKS.md` owns incomplete work; `MINIMAL-BOOT-PLAN.md` owns the experiment contract. Exact identities and immutable evidence live in `control-plane/deferred-runtime-plan.json`, the inventory ledgers, candidate records, and `recovery-harness/trials/`.

## Safety state

- Microsoft's packaged WSL 2.7.12 kernel and initrd remain the recovery baseline.
- No reduced control-plane package or candidate kernel is recorded as deployed. Every finalized candidate interval restored the pinned stock package, passed independent stock `B6-T` recovery, and returned the disposable fixture Off. This file does not assert live fixture state.
- The retained `clean-shell` checkpoint was not restored or changed.
- Disposable-fixture operations are standing-authorized only within the pinned, offline, hash-verified, plan-validated, recoverable envelope. Physical-host or shared-WSL effects require fresh explicit approval.

## Verified boundary

- The mkroot/Toybox lower bound passes QEMU `G4`.
- Stock WSL 2.7.12 passes the fixed Toybox probe at `B6-T` in `CP-STOCK-2.7.12-003`.
- Additive kernel discovery proved WSL entry (`B1`), VMBus/VSOCK (`B2`), and Hyper-V storage plus ext4 mount (`B3`). Stock system-distro overlay discovery then stopped at excluded GNS policy, selecting control-plane reduction rather than networking additions.
- Corrected `minimal-v4-stock-ns` passed `B6-T`. Its mount-only sibling reached `B3`, then closed the control path before `CreateInstanceResult`.
- `minimal-v5-mount-pid-ns` restored PID namespace semantics while continuing to omit IPC and UTS; it passed `B6-T`. The controlled delta proves PID namespace semantics are required by the tested contract. IPC and UTS namespace options remain `DEFERRED`.
- The PID-enabled storage-floor and overlay-floor reduced kernels both finalized at `B2`: mini-init exchanged capabilities and configuration, then storage-adapter teardown preceded the consequential HCS invalid-handle result before registered-distro mount. The overlay sibling rejects overlay as the missing facility.
- Every completed custom-kernel or controlled-package candidate has independent stock recovery evidence.

## Retained candidate state

- WSL source is pinned to tag 2.7.12, commit `68f601bba8eac1df20a0bbd403c6c87c92369ade`.
- The retained passing control-plane baseline is mount plus PID namespace semantics with IPC and UTS omitted.
- `K-PIDNS-001`, derived from the proved Hyper-V storage floor, is the kernel to retest after the next source reduction. `K-OVERLAY-PIDNS-001` is finalized and must not be rerun.
- `minimal-v6-excluded-initialize` removes only the inotify, IP-loopback, and cross-distro/GNS-DNS setup selected by the retained `Initialize` review. Its Linux artifacts built byte-identically twice offline, and its controlled unsigned MSI is built and independently identity-verified. No runtime result exists yet.
- The disposable fixture disk was expanded from 100 GiB to 160 GiB after a recorded capacity inspection; C: has 60+ GiB free, the `clean-shell` checkpoint is preserved, and the fixture returned Off. Build operation 007 then completed after guarded cleanup of operation 003. Runtime operations 008 and 009 stopped at UAC before worker start and touched neither fixture nor candidate. Unlaunched operation 010 was superseded after host-security review found its controller and output root user-writable. Operation 011 preserves the candidate contract but requires the tested ephemeral protected broker before launch. Exact hashes and dispositions are in `control-plane/deferred-runtime-plan.json`.
- Do not add inotify, storage-hotplug, PCI, networking, IPC namespace, or UTS namespace support without new runtime evidence.

## Evidence ownership

- Current work: `TASKS.md`.
- Contract, gates, and completion criteria: `MINIMAL-BOOT-PLAN.md`.
- Exact preparation inputs, candidate identities, and recovery operation: `control-plane/deferred-runtime-plan.json`.
- Kconfig classifications and terminal trial ledger: `inventory/`.
- Immutable runtime evidence and analysis: `recovery-harness/trials/<TRIAL_ID>/`.
- Layer-specific source and reproducibility evidence: `control-plane/candidates/`, `control-plane/*-audit.md`, and `candidates/`.
