# Reduced control-plane development

This directory contains the layered source-level candidates for the host and guest path described in `WSL-CONTROL-PLANE-AUDIT.md`. They are buildable prototypes, not runtime proof of Minimal Viable WSL.

## Pinned protocol fixture

`protocol/wsl-2.7.12.json` records message identifiers, constants, sizes, and offsets compiled from WSL 2.7.12's shared host/guest header. Verify it on `LFS-Builder`:

```bash
SOURCE=/root/src/WSL-2.7.12 \
  /mnt/c/Users/jackc/git/ultra-minimal-wsl/tools/extract-control-plane-protocol.sh check
```

Protocol extraction and Linux control-plane builds first require the pinned `LFS-Builder` profile in `../build-host/` to pass. New build metadata records that profile's bundle SHA-256.

The fixture retains handshake, instance creation, initialization, command creation, exit status, and termination ABI. A value appearing in the fixture does not by itself prove runtime necessity. Strict framing and policy tests exercise malformed lengths, every excluded configuration field, all process-flag combinations, sampled signed exit statuses, and termination flags. Mutation evidence is recorded in `protocol/test-evidence.md`:

```bash
uv run python -m unittest tools.test_control_plane_protocol tools.test_control_plane_records
~/git/agent-skills/skills/windows-env/ps-lint \
  --offline --settings .PSScriptAnalyzerSettings.psd1 tools control-plane/controlled-package-offline
git ls-files '*.sh' -z | xargs -0 shellcheck --severity=warning -x
```

## Candidate `minimal-v1`

`patches/0001-minimal-control-plane-v1.patch` applies to commit `68f601bba8eac1df20a0bbd403c6c87c92369ade`. It makes the first coarse reduction:

- host: supplies no system distro, swap, kernel-modules disk, GNS, DNS, networking engine, WSLg, DrvFs, interop, or OOBE policy;
- mini init: rejects excluded early/initial configuration and non-launch instance operations;
- distro host path: sends a zero-feature direct-command configuration and clears DrvFs, elevation, interop, and OOBE process flags;
- retained: primary and notification VSOCK channels, one registered distro VHDX/ext4 launch, distro-init channel, command sockets, stdio, exit status, and termination code.

The Linux side compiles reproducibly. `candidates/minimal-v1/` records the complete source-diff hash, build inputs, output hashes, size comparison, and two-clean-build comparison. `minimal-v1-audit.md` distinguishes removed, rejected, ABI-retained, and still-reachable stock paths. `kernel-contract-review.md` records the corresponding static Kconfig review without promoting unproved requirements. The Windows service side still requires a controlled Windows build and runtime test in the disposable VM.

To build a clean applied worktree offline, calculate the source diff hash after applying the patch and pass it explicitly:

```bash
base=68f601bba8eac1df20a0bbd403c6c87c92369ade
patch_sha=$(git diff --binary "$base" | sha256sum | cut -d' ' -f1)
SOURCE=$PWD BUILD=/root/experiments/minimal-wsl/control-plane-build/minimal-v1 \
OFFLINE=1 MINIMAL_LINK=1 EXPECTED_SOURCE_PATCH_SHA256="$patch_sha" \
  /mnt/c/Users/jackc/git/ultra-minimal-wsl/tools/build-control-plane-linux.sh
```

## Completed `minimal-v2` source-only phase

The recorded layers preserve `minimal-v1`:

1. `patches/0002-minimal-v2-fail-closed.patch` adds the shared policy seam in `policy/minimal-v2-policy.h`, rejects all non-contract channel messages, constrains launch to one unflagged LUN/ext4 device, rejects excluded process/configuration flags, and prevents distro-local policy from re-enabling excluded integration;
2. the compiler-derived fixture and tests enumerate all 52 recorded message families on every inbound channel; focused add-import and remove-termination allowlist mutations were caught;
3. `minimal-v2-stock-ns` is tree-identical to the fail-closed parent, while `patches/0003-minimal-v2-mount-ns.patch` changes only IPC/mount/PID/UTS to mount-only launch;
4. the parent and both siblings each produced byte-identical `init`, `init.debug`, and `initrd.img` in two separate `OFFLINE=1 MINIMAL_LINK=1` builds with verified cache hits;
5. `candidates/minimal-v2-*` and `minimal-v2-audit.md` record parent, layer, complete-diff, artifact, size, and reproducibility evidence.

All `minimal-v2` records remain preserved as historical parents.

## Completed `minimal-v3` source-only readiness phase

`patches/0004-minimal-v3-no-interop.patch` layers on `minimal-v2-fail-closed` and removes only mini-init's unconditional `binfmt_misc` mount and `WSLInterop` registration hard-fail. Focused record tests require both operations and their local definitions to be removed without changing distro-init policy or protocol dispatch. `minimal-v3-stock-ns` is tree-identical to the new fail-closed parent; `patches/0005-minimal-v3-mount-ns.patch` changes only the coherent namespace bundle to mount-only.

All three replacement candidates built byte-identically twice with `OFFLINE=1` and `MINIMAL_LINK=1` in separate ext4 directories. `minimal-v3-audit.md` and `candidates/minimal-v3-*` preserve source, patch, profile, artifact, size, and reproducibility evidence. Stock WSL calibration now passes `B6-T`; no custom candidate has runtime evidence. The non-executable build procedure produced the recorded `minimal-v3-stock-ns` MSI, and `controlled-package-offline/Invoke-MinimalV3StockNsTrial.ps1` has since passed hash-bound staging, installed-product detection, and fail-closed recovery-path validation. The candidate remains uninstalled and unrun behind the separately recorded execution gate.

## Runtime comparison boundary

`deferred-runtime-plan.json` is deliberately non-executable. It records pinned inputs, reproducible build mechanics, candidate identities, the fixed Toybox probe, evidence requirements, recovery assertions, and stop conditions. Operations wholly confined to the disposable fixture are standing-authorized within that recorded envelope; the plan grants no authorization over the physical host or a shared WSL instance. The next candidate trial ID may be reserved for planning, but no ledger row exists until complete candidate and recovery evidence is finalized.

The project does not own a general VM-control stack. A disposable Windows fixture may isolate package trials, but fixture start, transport, installation, extraction, and rollback are outer preconditions. Candidate measurement starts with the first `wsl.exe` process in `tools/Invoke-WslCandidateProbe.ps1`. A fixture failure creates no B-gate result and must not trigger more fixture automation work.

## Evidence boundary

The v3 records establish source-policy and Linux-artifact reproducibility only; they do not establish controlled Windows compilation or any runtime gate. Preserve each generation: a later source or ABI change creates a new layer and repeats the policy, mutation, and reproducibility gates.

`STATUS.md` owns the present boundary, `TASKS.md` the immediate queue, and `MINIMAL-BOOT-PLAN.md` the proof order and authorization rules. Exact compiler, source, candidate, build-procedure, probe, and recovery inputs belong in `deferred-runtime-plan.json`; that evidence grants no authorization outside the disposable-fixture envelope.
