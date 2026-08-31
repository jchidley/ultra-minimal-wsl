# Reduced control-plane development

This directory preserves layered reductions of WSL 2.7.12's Windows/guest command path. Source, tests, and reproducible builds establish candidate identity and fail-closed policy; only guarded runtime trials establish a `B` gate. Current facts belong in `../STATUS.md`, incomplete work in `../TASKS.md`, and exact build/runtime identities in `deferred-runtime-plan.json`.

## Pinned boundary

All layers apply to WSL tag 2.7.12, commit `68f601bba8eac1df20a0bbd403c6c87c92369ade`. The retained contract is one registered ext4 distro launch, command creation, stdio and signed exit-status relay, termination, and shutdown. Networking, DNS, GNS, DrvFs, Windows interop, WSLg/GPU, systemd, cgroup policy, general disk management, and cross-distro integration remain excluded.

`protocol/wsl-2.7.12.json` is compiler-extracted from the pinned shared header. It records ABI facts, not runtime requirements. The strict validator and record tests enumerate all recorded message families, malformed framing, excluded policy fields, launch/process flags, exit status, and termination. Mutation results are preserved in `protocol/test-evidence.md`.

## Preserved lineage

| Generation | Narrow purpose | Durable evidence |
|---|---|---|
| `minimal-v1` | Broadly remove excluded host and guest product policy. | `minimal-v1-audit.md`, `candidates/minimal-v1/` |
| `minimal-v2` | Add shared fail-closed channel/configuration policy and coherent namespace siblings. | `minimal-v2-audit.md`, `candidates/minimal-v2-*` |
| `minimal-v3` | Remove unconditional `binfmt_misc`/`WSLInterop` initialization rather than enabling excluded kernel support. | `minimal-v3-audit.md`, `candidates/minimal-v3-*` |
| `minimal-v4` | Zero excluded GUI, GPU, and networking fields on the retained Windows sender. | `candidates/minimal-v4-*`, runtime trial evidence |
| `minimal-v5` | Retain mount plus PID namespaces while omitting IPC and UTS. | `candidates/minimal-v5-mount-pid-ns/`, runtime trial evidence |
| next layer | Remove only reachable `Initialize` hard-fails that implement excluded policy, then retest the reduced PID kernel. | `kernel-contract-review.md`, `TASKS.md` |

Earlier generations are immutable evidence, not alternative current plans. `minimal-v5-mount-pid-ns` is the passing control-plane baseline: stock-like namespaces passed, mount-only stopped after `B3`, and mount plus PID restored `B6-T`. Runtime proof and exact hashes remain in the trial and candidate records rather than being repeated here.

## Validation

Run from the repository root in PowerShell:

```powershell
uv run python tools/inventory_records.py
uv run python -m unittest tools.test_build_host_profile tools.test_inventory_records tools.test_control_plane_protocol tools.test_control_plane_records
& ~/git/agent-skills/skills/windows-env/Invoke-PsLint.ps1 -Offline -Settings .PSScriptAnalyzerSettings.psd1 -Path tools,control-plane/controlled-package-offline
```

Verify Linux tooling and shell scripts on `LFS-Builder`:

```bash
bash tools/bootstrap-lfs-builder.sh --check
git ls-files '*.sh' -z | xargs -0 shellcheck --severity=warning -x
```

Linux control-plane builds use `tools/build-control-plane-linux.sh` with `OFFLINE=1`, `MINIMAL_LINK=1`, and an independently calculated complete source-diff hash. Candidate directories preserve source, profile, artifact, size, and two-build reproducibility records.

## Runtime boundary

`deferred-runtime-plan.json` is a non-executable, hash-bound contract. It records pinned inputs, package and candidate identities, the fixed Toybox probe, recovery assertions, and stop conditions. A prepared plan grants no authority outside the dedicated disposable fixture.

The candidate interval begins with the first `wsl.exe` process in `tools/Invoke-WslCandidateProbe.ps1`. Fixture start, transport, package placement, and rollback are prerequisites; failure there is infrastructure failure and creates no candidate ledger row. A valid candidate result requires immutable interval evidence, stock restoration, independent recovery, and one terminal ledger row.
