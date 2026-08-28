# Work queue

`STATUS.md` owns current facts; `MINIMAL-BOOT-PLAN.md` owns strategy and acceptance criteria. This file contains incomplete work only.

## Active action

R8 completed the zero-touch replacement after reboot and proved automatic PowerShell Direct, the lifecycle-bound DPAPI credential, safe unattended cleanup, exact stock-MSI staging, transactional old-VM deletion, and final Off/zero-disk/`clean-shell` state. Its detached launcher returned a false exit 1 only after successful completion because StrictMode read unset `$LASTEXITCODE`; preserve the evidence and do not retry r8. Review the unchanged stock-baseline installation artifact against the new replacement VM identity and credential metadata, prepare any strictly necessary identity-binding update as a new exact-hash packet, and stop for fresh approval.

## Following boundary

After fresh exact-hash approval, establish stock WSL 2.7.12 inside the replacement VM, verify the stock command and recovery hashes, leave the VM Off, and create `controlled-package-baseline`. Compiler installation/build, candidate installation, and runtime proof remain later fixed boundaries; the acceptance path remains owned by `MINIMAL-BOOT-PLAN.md`.

## Blocked

- Controlled compilation is blocked until the staged stock package, stock baseline, and controlled checkpoint are completed under one approved PowerShell Direct artifact.
- Do not retry r8 or operate any retired identity; use only the replacement VM ID and its paired DPAPI credential.
- Do not execute stock installation until the existing packet is reconciled to the replacement identity, plan-validated, and freshly approved; the conservative MSI exit-code policy remains in force.
- Namespace selection and Kconfig promotion remain blocked on controlled runtime evidence.
- No additional Kconfig group or speculative source reduction is queued; serial static review must not substitute for the B4/B5/B6-T milestone gap.

## Immediate constraints

- Keep the replacement disposable VM Off until the stock-baseline packet is freshly approved; do not alter host WSL state or run stock/candidate installation or runtime.
- Never prompt for, display, recover, or ask the operator to know the disposable guest credential. Import only the VM-paired DPAPI credential; discard/rebuild the VM/credential pair if either side is lost.
- Reuse only the recorded stock MSI cache hit with its release identity, size, SHA-256, signature, and recovery assertions; fail closed on mismatch or absence.
- Keep builds and source worktrees on `LFS-Builder` ext4 with pinned, hash-verified offline caches.
- Preserve every completed trial and all `minimal-v1`, `minimal-v2`, and `minimal-v3` candidate evidence; the replacement records do not rewrite their parents.
- Keep both namespace siblings unselected until controlled runtime comparison proves necessity.
