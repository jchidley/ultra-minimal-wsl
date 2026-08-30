# Work queue

`STATUS.md` owns verified current facts. `MINIMAL-BOOT-PLAN.md` owns strategy and acceptance criteria. This file contains incomplete work only.

## Active action

Retry the hash-bound `minimal-v4-mount-ns` controlled Windows package build under a fresh operation ID when the elevation broker can start its worker. The build script, complete source diff `197804…a13a`, controller, pinned offline inputs, and exact output contract are plan-validated; two bounded launches remained at `launching` without a worker or output. After package identities exist, independently reverify them, validate the runner, and continue directly through one fixed candidate interval and mandatory stock recovery. Do not rerun the completed `minimal-v4-stock-ns` baseline or create a candidate result for build infrastructure failure.

## Comparison queue

1. stock WSL 2.7.12 calibration with `toybox-minimal-wsl-rootfs.tar.gz` — complete at `B6-T` in `CP-STOCK-2.7.12-003`;
2. `minimal-v3-stock-ns` — superseded after its B2 sender-policy evidence;
3. `minimal-v4-stock-ns` — complete at `B6-T` in `CP-MINIMAL-V4-STOCK-NS-001`;
4. `minimal-v4-mount-ns`;
5. evidence-selected namespace decision;
6. one evidence-selected kernel/configuration change or minimality ablation.

Every comparison uses the identical Toybox smoke command, timeouts, instrumentation, rootfs, classification rules, and recovery proof.

## Blocked

- `minimal-v3-stock-ns` is finalized at `B2`; do not rerun the byte-identical candidate.
- Namespace selection and Kconfig promotion are blocked until the evidence-selected initial-configuration correction reaches the namespace-dependent launch path.
- Alpine, Arch, and Debian compatibility testing is blocked until `minimal-viable-wsl-v1` passes Toybox and is frozen.
- No speculative Kconfig group, VM-control diagnostic, or replacement infrastructure packet is queued.

## Constraints

- Do not retry or extend historical VM-rebuild, baseline-installer, command-diagnostic, PowerShell Direct, or checkpoint-race work.
- A fixture start/transport/recovery failure is infrastructure failure and creates no candidate result.
- Preserve completed candidate and trial evidence; never rewrite terminal ledger rows.
- Keep Linux builds on `LFS-Builder` ext4 and use only pinned, hash-verified offline inputs.
- Disposable-fixture operations are standing-authorized inside the pinned, offline, hash-verified, plan-validated recovery envelope and proceed without human stage reviews or confirmations. Require fresh explicit approval for any physical-host or shared-WSL effect; fail closed if target isolation, hashes, offline status, or recovery cannot be proved.
