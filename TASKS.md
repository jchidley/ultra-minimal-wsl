# Work queue

`STATUS.md` owns current facts; `MINIMAL-BOOT-PLAN.md` owns strategy and acceptance criteria. This file contains incomplete work only.

## Active action

Attempt five exhausted the documented explicit-credential PowerShell Direct readiness window without establishing a guest session. In-artifact shutdown did not prove Off within five minutes, but separately reviewed ordinary `Stop-VM` recovery succeeded; final evidence proves VM Off, zero attached disks, only `clean-shell`, and no MSI installation. The active action is no longer another install retry: prepare a bounded, non-installing guest `vmicvmsession` diagnosis consistent with Microsoft PowerShell Direct troubleshooting, including safe shutdown and independent final-state verification. Only after that diagnosis is plan-validated, freshly approved, and proves guest control may the stock-baseline packet be reconsidered.

## Following boundary

Plan and obtain fresh explicit approval for a non-installing PowerShell Direct service diagnosis. If guest control is restored and safe cleanup is independently proved, review a new stock-baseline execution boundary. Compiler installation/build, candidate installation, and runtime proof remain later fixed boundaries; the acceptance path remains owned by `MINIMAL-BOOT-PLAN.md`.

## Blocked

- Controlled compilation is blocked until the staged stock package, stock baseline, and controlled checkpoint are completed under one approved PowerShell Direct artifact.
- Do not operate the VM again until the non-installing `vmicvmsession` diagnostic is fixed, plan-validated, and freshly approved; no candidate was compiled or installed.
- Do not retry stock installation while PowerShell Direct guest control remains unresolved; the conservative MSI exit-code policy remains a later review constraint.
- Namespace selection and Kconfig promotion remain blocked on controlled runtime evidence.
- No additional Kconfig group or speculative source reduction is queued; serial static review must not substitute for the B4/B5/B6-T milestone gap.

## Immediate constraints

- Keep the disposable VM Off until the non-installing PowerShell Direct service diagnosis is plan-validated and freshly approved; do not alter host WSL state or run stock/candidate installation or runtime.
- Use only the proven disposable VM account identity. Do not reuse a personal credential or commit the generated password to Git.
- Reuse only the recorded stock MSI cache hit with its release identity, size, SHA-256, signature, and recovery assertions; fail closed on mismatch or absence.
- Keep builds and source worktrees on `LFS-Builder` ext4 with pinned, hash-verified offline caches.
- Preserve every completed trial and all `minimal-v1`, `minimal-v2`, and `minimal-v3` candidate evidence; the replacement records do not rewrite their parents.
- Keep both namespace siblings unselected until controlled runtime comparison proves necessity.
