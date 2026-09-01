# Project status

This file contains verified present facts and the achieved boundary. `TASKS.md` owns incomplete work; `MINIMAL-BOOT-PLAN.md` owns the experiment contract. Exact candidate, artifact, operation, disposition, config, and trial identities live in committed `inventory/experiments.sqlite`; immutable evidence lives in candidate records and `recovery-harness/trials/`.

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
- Under minimal v5, the PID-enabled storage-floor and overlay-floor reduced kernels both finalized at `B2`: mini-init exchanged configuration, then storage association failed before registered-distro mount. Under minimal v6, `K-PIDNS-001` advanced to `B3`: registered-distro association succeeded and `LaunchInit` began, then `_init` crashed with signal 11 in the known absent-overlay path before `CreateInstanceResult`.
- Minimal v6 plus `K-OVERLAY-PIDNS-001` also finalized at `B3`. Overlay removed the prior signal-11 signature, but `WslCorePort` closed after `LaunchInit` without `CreateInstanceResult`. The selected diagnostic captured 216 guest records and proved `LaunchDistro` still unconditionally moved the intentionally absent cross-distro share: ENOENT at `main.cpp:1676` entered the broad read-only/full-filesystem catch, overlay construction succeeded, then the repeated absent mount terminated `_init`.
- Every completed custom-kernel or controlled-package candidate has independent stock recovery evidence.

## Retained candidate state

- WSL source is pinned to tag 2.7.12, commit `68f601bba8eac1df20a0bbd403c6c87c92369ade`.
- The retained passing control-plane baseline is mount plus PID namespace semantics with IPC and UTS omitted.
- The minimal-v6 plus `K-PIDNS-001`, plus `K-OVERLAY-PIDNS-001`, and diagnostic combinations are finalized at `B3` and must not be rerun unchanged. The diagnostic selects a new control-plane source layer removing only the excluded `LaunchDistro` cross-distro temporary-mount block; it selects no kernel facility.
- `minimal-v6-excluded-initialize` removes only the inotify, IP-loopback, and cross-distro/GNS-DNS setup selected by the retained `Initialize` review. Its reproducible controlled package fixed the prior dynamic VHDX-association boundary. Operations 012 and 013 each restored stock, passed independent `B6-T` recovery, preserved complete evidence, and returned the fixture Off.
- The disposable fixture disk was expanded from 100 GiB to 160 GiB after a recorded capacity inspection; C: has 60+ GiB free, the `clean-shell` checkpoint is preserved, and the fixture returned Off. Build operation 007 then completed after guarded cleanup of operation 003. Runtime operations 008 and 009 stopped at UAC before worker start and touched neither fixture nor candidate. Unlaunched operation 010 was superseded after host-security review found its controller and output root user-writable. Operation 011 created the protected controller snapshot but its broker child never executed because the Program Files path was not preserved as one argument; no Hyper-V command or candidate interval began. Operations 012 and 013 completed their candidate intervals and recovery through the corrected protected broker. Diagnostic operation 014 ended before durable worker start with no mutation; fresh operation 015 completed the diagnostic and recovery, removed all relays, and returned the fixture Off. Exact active identities and dispositions are queried from `inventory/experiments.sqlite`; the former JSON plan is frozen migration history.
- Do not add inotify, storage-hotplug, PCI, networking, IPC namespace, or UTS namespace support without new runtime evidence.

## Evidence ownership

- Current work: `TASKS.md`.
- Contract, gates, and completion criteria: `MINIMAL-BOOT-PLAN.md`.
- Exact preparation inputs, candidate identities, operations, and terminal trials: `inventory/experiments.sqlite`.
- Kconfig classifications and generated relationship queries: `inventory/annotations.csv` and `inventory/kconfig-dependencies.sqlite`.
- Immutable runtime evidence and analysis: `recovery-harness/trials/<TRIAL_ID>/`.
- Layer-specific source and reproducibility evidence: `control-plane/candidates/`, `control-plane/*-audit.md`, and `candidates/`.
