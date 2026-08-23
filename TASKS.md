# Work queue

`STATUS.md` owns current facts; `MINIMAL-BOOT-PLAN.md` owns strategy and acceptance criteria. This file contains incomplete work only.

## Active action

Commission one exact PowerShell Direct stock-baseline approval artifact using the proven disposable VM-only administrator account recorded in `control-plane/deferred-runtime-plan.json`. Fix the elevated host command, local credential input, staged stock MSI hash verification, installation and exit-code capture, WSL version/status/list checks, packaged kernel/initrd/config hash checks, evidence capture, interruption handling, clean guest shutdown, independent VM-Off verification, checkpoint command, side effects, recovery procedure, and exclusions. The disposable password must not be committed to Git. Do not operate the VM, install the MSI, or create the checkpoint while preparing the artifact.

## Following boundary

Review and plan-validate the fixed artifact. Only fresh approval of that unchanged packet may authorize stock MSI installation inside the disposable VM and establishment of the stock WSL baseline/checkpoint. Compiler installation/build, candidate installation, and runtime proof remain later fixed boundaries; the acceptance path remains owned by `MINIMAL-BOOT-PLAN.md`.

## Blocked

- Controlled compilation is blocked until the staged stock package, stock baseline, and controlled checkpoint are completed under one approved PowerShell Direct artifact.
- Do not operate the VM, install the MSI, or create the checkpoint until the exact stock-baseline artifact is plan-validated and freshly approved; no candidate was compiled or installed.
- Namespace selection and Kconfig promotion remain blocked on controlled runtime evidence.
- No additional Kconfig group or speculative source reduction is queued; serial static review must not substitute for the B4/B5/B6-T milestone gap.

## Immediate constraints

- Keep the disposable VM Off until the PowerShell Direct stock-baseline operation is plan-validated and freshly approved; do not alter host WSL state or run candidate installation/runtime.
- Use only the proven disposable VM account identity. Do not reuse a personal credential or commit the generated password to Git.
- Reuse only the recorded stock MSI cache hit with its release identity, size, SHA-256, signature, and recovery assertions; fail closed on mismatch or absence.
- Keep builds and source worktrees on `LFS-Builder` ext4 with pinned, hash-verified offline caches.
- Preserve every completed trial and all `minimal-v1`, `minimal-v2`, and `minimal-v3` candidate evidence; the replacement records do not rewrite their parents.
- Keep both namespace siblings unselected until controlled runtime comparison proves necessity.
