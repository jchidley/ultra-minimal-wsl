# Work queue

`STATUS.md` owns current facts; `MINIMAL-BOOT-PLAN.md` owns strategy and acceptance criteria. This file contains incomplete work only.

## Active action

The credential-prompt/manual-VMConnect diagnostic route is retired. Attempts r1-r7 remain immutable evidence; r7 failed safely when Hyper-V could not initialize its fixed 4096 MiB startup memory despite its free-memory precondition. After the operator rebooted, read-only observation found 9.14 GiB free physical memory and 26% commit use. A transient `vmmemWSL` was initially visible, but an immediate follow-up reported every registered distro Stopped; no VM was operated, and ordinary free memory still does not prove Hyper-V allocatable capacity. The plan-validated r8 artifact changes only r7's unique staging, retired-VM, staging-root, and evidence identities while preserving the fixed memory contract and every fail-closed safety gate. Obtain fresh approval for exact SHA-256 `a66161b738d0c0a5364470773326c4af69aaf9e77cfb3e2d3c2b12150f9c8dce`; do not execute without it.

## Following boundary

After fresh exact-hash approval, execute r8 once as the fail-closed Hyper-V capacity and zero-touch replacement test. If the replacement proves automatic guest control and safe cleanup, review a new stock-baseline execution boundary. Compiler installation/build, candidate installation, and runtime proof remain later fixed boundaries; the acceptance path remains owned by `MINIMAL-BOOT-PLAN.md`.

## Blocked

- Controlled compilation is blocked until the staged stock package, stock baseline, and controlled checkpoint are completed under one approved PowerShell Direct artifact.
- Do not operate, repair, or prompt for credentials on the old VM; only the reviewed zero-touch replacement packet may supersede it after fresh exact-hash approval.
- Do not retry stock installation while PowerShell Direct guest control remains unresolved; the conservative MSI exit-code policy remains a later review constraint.
- Namespace selection and Kconfig promotion remain blocked on controlled runtime evidence.
- No additional Kconfig group or speculative source reduction is queued; serial static review must not substitute for the B4/B5/B6-T milestone gap.

## Immediate constraints

- Keep the old disposable VM Off until the zero-touch replacement is freshly approved; do not alter host WSL state or run stock/candidate installation or runtime.
- Never prompt for, display, recover, or ask the operator to know a disposable guest credential. Generate it in automation, store it DPAPI-encrypted for exactly the VM lifetime, and discard/rebuild the VM/credential pair if either side is lost.
- Reuse only the recorded stock MSI cache hit with its release identity, size, SHA-256, signature, and recovery assertions; fail closed on mismatch or absence.
- Keep builds and source worktrees on `LFS-Builder` ext4 with pinned, hash-verified offline caches.
- Preserve every completed trial and all `minimal-v1`, `minimal-v2`, and `minimal-v3` candidate evidence; the replacement records do not rewrite their parents.
- Keep both namespace siblings unselected until controlled runtime comparison proves necessity.
