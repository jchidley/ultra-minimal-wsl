# Next-session restart brief

## Goal

Continue source-only reduction/Kconfig review from the reproducible `minimal-v2` fail-closed/namespace candidates; keep all Windows runtime work deferred.

## Verified current state

- `main` and `origin/main` were both `9c74f6ce0b2501836a88454b60bd284dfa5efb00` before relay edits.
- Pinned WSL source `/root/src/WSL-2.7.12` was clean at `68f601bba8eac1df20a0bbd403c6c87c92369ade`; the compiler-derived fixture check passed under build-host profile `35284f8aecb56a5e2bf6af091e1877ed7ed9c8730211aee2600766c05e586543`.
- Durable `minimal-v2` patch, policy, candidate, artifact-hash, mutation, and non-executable runtime-plan records exist and are internally synchronized. They prove source policy/build identity, not B4/B5/B6 or namespace necessity.
- Higher-fan-out Clang builds were unreliable on the 8 GiB builder, but all six fresh `JOBS=1` candidate builds completed in distinct ext4 directories and exactly matched committed source/profile metadata and artifact hashes.
- A further offline `JOBS=2` fail-closed build completed with verified cache hits and matching hashes. `tools/build-control-plane-linux.sh` now defaults to that proven bound instead of `nproc`; higher explicit fan-out remains unverified.
- No Windows ISO/toolchain was downloaded, no Hyper-V VM was created or operated, no elevation was requested, and no host WSL configuration/package was changed.

## Completed in this session

- Created the layered fail-closed policy seam, exhaustive 52-family protocol policy tests, two caught semantic dispatch mutations, and stock/mount namespace siblings.
- Recorded layered and complete source-diff hashes plus candidate build/reproducibility metadata; preserved `minimal-v1` unchanged.
- Adopted and verified the pinned Debian 13 `LFS-Builder` profile and synchronized build metadata to its bundle hash.
- Reconciled current-state, work-queue, conceptual, control-plane, build-host, deferred-plan, and follow-on documentation; corrected the stale target-gap description.
- Rechecked patch application, protocol extraction, manifests, repository tests/lints, and documentation links.
- Independently reproduced all six candidate builds and selected the smallest evidence-backed build-script change: a two-job default on this 8 GiB build host.
- Completed the retained-path Kconfig review: nine mkroot-supplied facilities are durably `BASE`; IPC/PID/UTS namespace options are reviewed but remain unresolved and unselected.

## Continue with

1. Verify repository/build-host state and run all gates after the bounded-job build-script change.
2. Continue the next coherent source-only reduction/Kconfig group from the fail-closed contract; the retained-path group in `control-plane/kernel-contract-review.md` is complete.
3. Keep both namespace siblings unselected and preserve all existing candidate records. Any candidate source, ABI, or toolchain change requires a new record and two distinct offline builds.
4. Keep the Windows controlled-package/runtime phase deferred and `control-plane/deferred-runtime-plan.json` non-executable.

## Context rebuild

- Current state: `STATUS.md` — verified milestones, safety state, reproducibility result, target gap, and restart point
- Work queue: `TASKS.md` — first incomplete diagnostic/rebuild actions and subsequent source-only sequence
- Active plan: `MINIMAL-BOOT-PLAN.md` — canonical contract, phases, evidence gates, acceptance criteria, and stopping conditions
- Operating instructions: `AGENTS.md` — repository commands, build-host boundary, record discipline, and approval rules
- Decisions: `WSL-CONTROL-PLANE-AUDIT.md` — retained control-plane boundary and rationale for host/guest reduction and namespace comparison
- Evidence: `control-plane/minimal-v2-audit.md` — source-layer hashes, policy coverage, namespace delta, build claims, and links to candidate records

## Constraints and approvals

- Do not download Windows installation media or Visual Studio; do not create/start/stop/checkpoint a Hyper-V VM; do not request elevation.
- Do not modify the host WSL package, installed initrd, `.wslconfig`, or running distributions, and do not execute `control-plane/deferred-runtime-plan.json`.
- Any custom boot, WSL shutdown, `-Execute`, elevation, or runtime trial needs fresh explicit approval and the guarded recovery process.
- Keep builds/worktrees on `LFS-Builder` ext4 and use pinned, hash-verified offline caches. Do not promote `CONFIG_IPC_NS`, `CONFIG_PID_NS`, or `CONFIG_UTS_NS` from static evidence.

## Validation and working tree

- Final relay checks passed: inventory integrity `ok`; 23 build-host/inventory/protocol/record tests; PSScriptAnalyzer 1.25.0; ShellCheck 0.11; build-host and patch manifests; pinned-source protocol fixture; 24-file Markdown link scan; `git diff --check`.
- Fresh rebuild validation is complete: six serial candidate runs and one two-job fail-closed run exactly matched committed metadata and artifact hashes; verified offline caches were used and no build/Clang process remained afterward.
- `STATUS.md`, `TASKS.md`, `NEXT-SESSION.md`, `control-plane/kernel-contract-review.md`, `inventory/annotations.csv`, and `tools/build-control-plane-linux.sh` are intentionally modified after clean pushed commit `9c74f6c`; verify `git status`, active Linux processes, and `origin/main` again before editing or committing.

## Manual restart command

Shell: PowerShell

```powershell
Set-Location -LiteralPath 'C:\Users\jackc\git\ultra-minimal-wsl'; pi '@NEXT-SESSION.md' 'Use the attached NEXT-SESSION.md as the single restart entry point. Rebuild context from its ordered sources, verify current state, and continue the first incomplete safe action.'
```

## Provenance and fallback

Parent Pi session: 01a025e1-2f9f-7db3-8fd7-4e0a1d5293c9

The parent session is historical evidence only. Open it only when a documented claim is ambiguous or needs auditing, not during normal context rebuild; the ordered project sources above are sufficient for normal continuation.
