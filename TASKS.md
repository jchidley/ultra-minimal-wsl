# Work queue

`STATUS.md` owns current facts; `MINIMAL-BOOT-PLAN.md` owns strategy and acceptance criteria. This file contains incomplete work only.

## Active critical path

1. Resolve the compiler-product blocker before package building. The pinned catalog/license audit confirms that Community is applicable to this Apache-2.0/MIT open-source build and that all requested prerequisites are in its x64 dependency closure. Acquisition is now blocked because Visual Studio Setup 4.9.50.62957 rejects the forwarded `--channelUri` needed to bind the pinned local manifest. Record any supported fix with evidence and acquire a separate verified Community layout; do not follow the live channel, silently substitute Professional, mark the current Build Tools layout complete, or guess an add ID.
2. Pin the controlled-package build procedure and recovery checkpoint inputs, then plan-validate the fixed operation and obtain fresh explicit approval before any elevation, VM operation, package installation, WSL shutdown, `.wslconfig` change, custom boot, or runtime trial.
3. In the separately approved disposable environment, compile the recorded `minimal-v3-stock-ns` and `minimal-v3-mount-ns` controlled packages and prove B4, B5, B6-T, clean/forced termination, checkpoint recovery, and namespace necessity.
4. Only after that proof, ablate provisional WSL kernel bundles, pass minimality and cold-start gates, freeze `minimal-viable-wsl-v1`, and begin Alpine, Arch, then Debian compatibility work.

## Blocked

- Windows package compilation and controlled runtime proof are blocked on completion of the pinned compiler layout and build procedure, plan validation, and fresh explicit approval.
- Namespace selection and Kconfig promotion remain blocked on controlled runtime evidence.
- No additional Kconfig group or speculative source reduction is queued; serial static review must not substitute for the B4/B5/B6-T milestone gap.

## Immediate constraints

- Windows media/compiler acquisition is authorized only as reusable, hash-verified preparation. Do not provision or operate a Hyper-V VM, request elevation, install a controlled package, alter host WSL state, or execute `control-plane/deferred-runtime-plan.json`.
- Keep builds and source worktrees on `LFS-Builder` ext4 with pinned, hash-verified offline caches.
- Preserve every completed trial and all `minimal-v1`, `minimal-v2`, and `minimal-v3` candidate evidence; the replacement records do not rewrite their parents.
- Keep both namespace siblings unselected until controlled runtime comparison proves necessity.
