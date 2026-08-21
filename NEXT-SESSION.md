# Next-session restart brief

## Goal

Continue the deferred, source-only reduced WSL control-plane phase. Preserve `minimal-v1`, create a layered fail-closed parent, derive two namespace variants, and produce tested reproducible Linux artifacts. Do not provision or run the Windows environment.

## Verify before editing

1. Read `AGENTS.md`, `STATUS.md`, `TASKS.md`, `MINIMAL-BOOT-PLAN.md`, and `control-plane/README.md`.
2. Require a clean `main` matching `origin/main`; investigate rather than discard unexpected changes.
3. Run:

```bash
uv run python tools/inventory_records.py
uv run python -m unittest \
  tools.test_inventory_records \
  tools.test_control_plane_protocol \
  tools.test_control_plane_records
~/git/agent-skills/skills/windows-env/ps-lint \
  --offline --settings .PSScriptAnalyzerSettings.psd1 tools
git ls-files '*.sh' -z | xargs -0 shellcheck --severity=warning -x
```

4. On `LFS-Builder`, verify `/root/src/WSL-2.7.12` is clean at `68f601bba8eac1df20a0bbd403c6c87c92369ade` and run `tools/extract-control-plane-protocol.sh check`.
5. Verify the `minimal-v1` patch and hashes; do not amend or replace them.
6. Require `windows-env/ps-lint --offline` to use PSScriptAnalyzer 1.25.0 from the package pinned as SHA-256 `14e634c828eb98efb9f40b2918ba90f139ed5eccdf663a2a747736d996995d60`; require ShellCheck 0.11 or newer at warning severity.

## Safety boundary

- Do not download a Windows ISO or Visual Studio.
- Do not create, start, stop, or checkpoint a Hyper-V VM.
- Do not request elevation.
- Do not modify the host WSL package, installed initrd, `.wslconfig`, or running distributions.
- Do not execute `control-plane/deferred-runtime-plan.json`; it is non-executable and carries no approval.
- Do not add `CONFIG_IPC_NS`, `CONFIG_PID_NS`, or `CONFIG_UTS_NS` from static source evidence.

## Work sequence

### 1. Layer the fail-closed parent

Create `minimal-v2-fail-closed` on top of the preserved `minimal-v1` source diff. Permit only:

- guest capabilities and early/initial minimal configuration;
- one registered LUN/ext4 distro launch;
- minimal distro initialization;
- direct process/session plumbing required by unmodified `wsl.exe`;
- stdin/stdout/stderr/control relay and exit status;
- clean and forced termination plus required child-exit notification.

Explicitly reject mini-init and distro-init operations for import/export, arbitrary mount/unmount/detach/resize, DrvFs, timezone, networking/DNS, WSLg/GPU, interop, systemd, Plan 9, OOBE, cgroups, and other management policy. Prefer a small shared allowlist/policy seam used by implementation and tests over duplicated conditionals.

Record the layer patch and the complete base-to-candidate source-diff hash separately. Do not rewrite `control-plane/patches/0001-minimal-control-plane-v1.patch` or `control-plane/candidates/minimal-v1/`.

### 2. Strengthen protocol-policy tests

Regenerate the compiler-derived fixture if additional message IDs or offsets are needed. Test every retained and rejected message family, malformed sizes, excluded flags, direct process flags, exit status, and termination. Perform at least two focused semantic mutations of the dispatch allowlist and record whether they are caught.

### 3. Derive namespace siblings

From the exact fail-closed parent, create:

- `minimal-v2-stock-ns`: current `CLONE_NEWIPC | CLONE_NEWNS | CLONE_NEWPID | CLONE_NEWUTS` launch;
- `minimal-v2-mount-ns`: mount namespace only (`CLONE_NEWNS`) while preserving the same root transition and command contract.

The variants must differ only in the coherent namespace bundle. Record their parent and complete diff hashes.

### 4. Build and record

For the fail-closed parent and both namespace variants, build twice in distinct `LFS-Builder` output directories using verified cache hits:

```bash
OFFLINE=1 MINIMAL_LINK=1 EXPECTED_SOURCE_PATCH_SHA256=<complete-diff-sha256> \
SOURCE=<clean-candidate-worktree> BUILD=<unique-ext4-build-dir> \
  /mnt/c/Users/jackc/git/ultra-minimal-wsl/tools/build-control-plane-linux.sh
```

Require byte-identical `init`, `init.debug`, and `initrd.img`. Record metadata, SHA-256 values, reproducibility, and size deltas in new candidate directories.

### 5. Synchronize plans and docs

Update `STATUS.md`, `TASKS.md`, `MINIMAL-BOOT-PLAN.md`, `WSL-CONTROL-PLANE-AUDIT.md`, `control-plane/README.md`, source/kernel audits, and `control-plane/deferred-runtime-plan.json`. Keep the runtime plan non-executable and all runtime outcomes unclaimed.

## Completion checks

- All patch manifests verify and apply cleanly to their recorded parents.
- Protocol fixture check passes against pinned source.
- Inventory, protocol, record, and new dispatch tests pass.
- Mutation evidence records at least two caught semantic mutations.
- Each Linux candidate is byte-identical across two clean output directories.
- No durable kernel annotation is promoted without runtime evidence.
- PSScriptAnalyzer 1.25.0 reports no findings under the PowerShell 5.1 project profile.
- ShellCheck reports no warning-or-higher findings for tracked shell scripts.
- Markdown links and `git diff --check` pass.
- Commit and push only after the working tree is clean and `main` matches `origin/main`.

## Start a genuinely new Pi session

From PowerShell:

```powershell
Set-Location 'C:\Users\jackc\git\ultra-minimal-wsl'
pi --name 'minimal-v2 fail-closed reduction' `
  '@NEXT-SESSION.md' `
  'Execute this restart brief autonomously. Verify all recorded state before changing files.'
```

Git Bash alternative:

```bash
cd /c/Users/jackc/git/ultra-minimal-wsl
pi --name "minimal-v2 fail-closed reduction" \
  @NEXT-SESSION.md \
  "Execute this restart brief autonomously. Verify all recorded state before changing files."
```

Alternatively, enter `/new` in Pi and submit:

```text
@NEXT-SESSION.md Execute this restart brief autonomously. Verify all recorded state before changing files.
```
