# Work queue

`STATUS.md` owns current facts; `MINIMAL-BOOT-PLAN.md` owns strategy and acceptance criteria. This file contains incomplete work only.

## Active action

Recommend one of the two viable guest-control paths—manual VMConnect or credential-backed PowerShell Direct—against the recorded deterministic execution, credential exposure, evidence capture, and VM-Off recovery constraints. The authoritative capability comparison is complete in `control-plane/deferred-runtime-plan.json`; Guest Service Interface is insufficient alone. Do not select, enable, or execute a path, invent mechanics, access credentials, or operate the VM. Return control for the user or stronger reviewing model to accept or reject the recommendation and commission one fixed approval artifact.

## Following boundary

After the controller selects one mechanism, commission and review its exact artifact or manual procedure, command, secret handling, side effects, recovery procedure, and exclusions. Only fresh approval of that unchanged packet may authorize stock MSI installation inside the disposable VM and establishment of the stock WSL baseline/checkpoint. Compiler installation/build, candidate installation, and runtime proof remain later fixed boundaries; the acceptance path remains owned by `MINIMAL-BOOT-PLAN.md`.

## Blocked

- Controlled compilation is blocked because no approved guest execution channel is available for stock MSI installation; the staged package, stock baseline, and controlled checkpoint remain incomplete.
- Do not enable Guest Service Interface, automate console interaction, install the MSI, or create the checkpoint until the guest-control path is separately decided and approved; no candidate was compiled or installed.
- Namespace selection and Kconfig promotion remain blocked on controlled runtime evidence.
- No additional Kconfig group or speculative source reduction is queued; serial static review must not substitute for the B4/B5/B6-T milestone gap.

## Immediate constraints

- Keep the disposable VM Off until the guest-control path and next operation are plan-validated and freshly approved; do not alter host WSL state or run candidate installation/runtime.
- Reuse only the recorded stock MSI cache hit with its release identity, size, SHA-256, signature, and recovery assertions; fail closed on mismatch or absence.
- Keep builds and source worktrees on `LFS-Builder` ext4 with pinned, hash-verified offline caches.
- Preserve every completed trial and all `minimal-v1`, `minimal-v2`, and `minimal-v3` candidate evidence; the replacement records do not rewrite their parents.
- Keep both namespace siblings unselected until controlled runtime comparison proves necessity.
