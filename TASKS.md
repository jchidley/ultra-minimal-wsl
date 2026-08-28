# Work queue

`STATUS.md` owns current facts; `MINIMAL-BOOT-PLAN.md` owns strategy and acceptance criteria. This file contains incomplete work only.

## Active action

The credential-prompt/manual-VMConnect diagnostic route is retired. After r1-r3 failed safely before staging and r4 was cancelled before elevation, authoritative Microsoft review exposed unsupported OOBE assumptions. Approved r5 execution reached staging-VM creation after its old-VM preflight, then failed closed because `New-VM` created a default network adapter. Its finally block removed the staging root; no lifecycle credential or final-state evidence remains. Preserve its immutable failure evidence. Approved r6 execution removed every staging adapter, then failed closed at `Start-VM` because Hyper-V could not allocate its fixed 6144 MiB startup memory (`0x800705AA`). Its staging root and lifecycle credential are absent after cleanup; preserve its immutable evidence. Approved r7 execution verified WSL's utility VM was off and its 5 GiB host-free-memory precondition before staging, but Hyper-V could not initialize 4096 MiB startup memory (`0x8007000E`). Its staging root and lifecycle credential are absent after cleanup; preserve its immutable evidence. Free-memory measurement alone does not prove Hyper-V allocatable capacity. Diagnose the host's Hyper-V memory pressure or capacity before preparing another packet; do not retry automatically. Preserve the documented explicit OOBE settings, exactly-once automatic profile creation, build-before-delete ordering, no-network staging VM, machine-generated DPAPI credential bound to the VM lifecycle, automatic guest-control validation, transactional promotion rollback, and independent Off/no-disk proof.

## Following boundary

Diagnose Hyper-V allocatable memory capacity without changing WSL or host state, then prepare a uniquely identified packet and obtain fresh exact-hash approval. If the replacement proves automatic guest control and safe cleanup, review a new stock-baseline execution boundary. Compiler installation/build, candidate installation, and runtime proof remain later fixed boundaries; the acceptance path remains owned by `MINIMAL-BOOT-PLAN.md`.

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
