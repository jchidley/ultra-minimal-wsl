# Work queue

`STATUS.md` owns verified current facts. `MINIMAL-BOOT-PLAN.md` owns strategy and acceptance criteria. This file contains incomplete work only.

## Active action

Resume the non-runtime `minimal-v3-stock-ns` build only after operator consent to the required UAC prompt: extract the retained attempt-003-r4 build log, apply only its evidence-selected correction, rerun the hash-bound build from fresh generated directories, extract and verify produced hashes, and return the fixture Off. Visual Studio and PowerShell are installed and the two discovered procedure defects are fixed. Candidate-package installation and the reserved runtime trial remain excluded until produced hashes are recorded and separately plan-validated.

## Comparison queue

1. stock WSL 2.7.12 calibration with `toybox-minimal-wsl-rootfs.tar.gz` — complete at `B6-T` in `CP-STOCK-2.7.12-003`;
2. `minimal-v3-stock-ns`;
3. `minimal-v3-mount-ns`;
4. evidence-selected namespace decision;
5. one evidence-selected kernel/configuration change or minimality ablation.

Every comparison uses the identical Toybox smoke command, timeouts, instrumentation, rootfs, classification rules, and recovery proof.

## Blocked

- `minimal-v3-stock-ns` package compilation is blocked on extracting the retained attempt-003-r4 failure log; the last UAC prompt was explicitly cancelled.
- `minimal-v3-stock-ns` runtime classification is blocked until its pinned controlled package is compiled reproducibly and installation/recovery is plan-validated against the produced hashes.
- Namespace selection and Kconfig promotion are blocked on controlled runtime evidence.
- Alpine, Arch, and Debian compatibility testing is blocked until `minimal-viable-wsl-v1` passes Toybox and is frozen.
- No speculative Kconfig group, VM-control diagnostic, or replacement infrastructure packet is queued.

## Constraints

- Do not retry or extend historical VM-rebuild, baseline-installer, command-diagnostic, PowerShell Direct, or checkpoint-race work.
- A fixture start/transport/recovery failure is infrastructure failure and creates no candidate result.
- Preserve completed candidate and trial evidence; never rewrite terminal ledger rows.
- Keep Linux builds on `LFS-Builder` ext4 and use only pinned, hash-verified offline inputs.
- Disposable-fixture operations are standing-authorized only inside the pinned, offline, hash-verified, plan-validated recovery envelope. Require fresh explicit approval for any physical-host or shared-WSL effect; fail closed if target isolation, hashes, offline status, or recovery cannot be proved.
