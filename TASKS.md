# Work queue

`STATUS.md` owns verified current facts. `MINIMAL-BOOT-PLAN.md` owns strategy and acceptance criteria. This file contains incomplete work only.

## Active action

Complete the `minimal-v6-excluded-initialize` package and retest the finalized `K-PIDNS-001` kernel:

1. let the recorded retry controller extract the failed build logs, prove attempt 001 produced no MSI identity, and clean only its partial fixture directories;
2. rebuild and independently verify the hash-bound controlled package;
3. plan-validate and run one fixed `K-PIDNS-001` candidate interval in the disposable fixture, restore stock, prove independent stock `B6-T` recovery, preserve evidence, and finalize the ledger.

The source-policy review, tests, and two byte-identical offline Linux builds are complete. The first package build returned the fixture Off without an accepted package identity; its exact record is in `control-plane/deferred-runtime-plan.json`. Do not treat package-preparation files as a completed runtime candidate.

## Blocked

- Alpine, Arch, and Debian compatibility testing waits for a frozen Toybox-capable `minimal-viable-wsl-v1`.
- No finalized v3, v4, v5, `K-PIDNS-001`, or `K-OVERLAY-PIDNS-001` candidate is eligible for an unchanged rerun.
- No speculative Kconfig group or replacement fixture infrastructure is queued.

## Constraints

- Keep the fixed Toybox smoke command, timeouts, instrumentation, classification rules, and recovery proof unchanged.
- A failure before the first probe `wsl.exe` process is infrastructure failure and creates no candidate result.
- Preserve completed candidate records, terminal ledger rows, and trial evidence.
- Keep Linux builds on `LFS-Builder` ext4 and use only pinned, hash-verified offline inputs.
- Proceed autonomously inside the disposable-fixture envelope. Require fresh explicit approval for any physical-host or shared-WSL effect and fail closed if isolation, hashes, offline status, or recovery cannot be proved.
