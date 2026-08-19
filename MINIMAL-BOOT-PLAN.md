# Minimal Viable WSL and distribution compatibility plan

## Objective

Build two measured profiles:

1. **Minimal Viable WSL (`minimal-viable-wsl-v1`)** — the smallest reproducible mkroot/Toybox-based kernel and control plane that starts as the WSL 2 VM, retains basic registered-distribution control through `wsl.exe`, mounts a distro’s VHDX-backed ext4 root, executes a command, relays stdio and exit status, and shuts down reliably.
2. **Ultra-minimal WSL (`ultra-minimal-wsl-v1`)** — that unchanged core plus only facilities proved necessary for command execution in Alpine, Arch, and Debian.

Networking, Windows-drive mounting, Windows executable interop, WSLg/GPU, systemd, containers, USB, additional filesystems and other services are outside both profiles unless evidence proves one indispensable to the retained command path.

The starting point is Toybox `mkroot`'s x86-64 Linux microconfig, expanded by Kconfig against the Microsoft WSL kernel source. Rob Landley’s documented derivation and test method is captured in `MKROOT-MINIMAL-BOOT-METHOD.md` and governs how that baseline is established. The known-good Stage 1 configuration is the upper bound and recovery/reference configuration.

## Important distinction

A generic mkroot kernel can boot Toybox directly as an initramfs under QEMU. WSL adds a host/guest contract before Windows can launch a command in a registered distribution. That minimum consists of a host handshake, per-distribution VHDX attachment and filesystem mount, enough root transition/isolation to enter the distro, process creation, stdio and exit-status relay, exit notification, and lifecycle shutdown. “Basic control” means list/select, cold-start, execute, terminate, and shut down registered distros; install, import/export, resize, mount arbitrary disks, and other general management operations are not acceptance criteria.

Microsoft’s stock `mini_init` also starts audience-wide services. Stock-init discovery can temporarily select facilities—such as the Microsoft system distro and its writable overlay—that are not accepted as final Minimal Viable WSL requirements until the reduced control plane proves them necessary.

Requirements are classified separately as:

- generic mkroot/Toybox Linux requirements;
- Hyper-V virtual-machine requirements;
- retained WSL management and command-dispatch requirements;
- stock Microsoft control-plane implementation requirements;
- Alpine, Arch, or Debian compatibility requirements;
- optional Windows-integration and post-boot services.

This prevents stock-init policy or one distribution’s userspace requirement from being incorrectly described as part of generic minimal Linux or the WSL management floor.

## Selected control-plane target

The open-source WSL 2.7.11 audit in `WSL-CONTROL-PLANE-AUDIT.md` confirms that stock `mini_init` unconditionally requests facilities beyond generic Linux boot. The selected target is a **patched single-user WSL control plane preserving `wsl.exe` command dispatch**.

The retained minimum is the service handshake/capability contract, per-distribution VHDX attachment and ext4 mount, only the namespaces/root transition actually required to enter the distro, process/session creation and stdio/exit-status relay, child exit notification, and shutdown. A VHDX is retained as the simple native-Linux filesystem container used by registered WSL distributions. Microsoft’s separate system distro, writable overlay, and audience-wide services are not presumed required merely because stock `mini_init` starts them.

The matching unmodified Linux-side init/initrd now has a reproducible build path. Microsoft supports external custom kernels through `.wslconfig`; removing `kernel=` restores the untouched packaged kernel. Kernel discovery trials will therefore begin with Microsoft’s stock initrd and must not modify installed WSL artifacts.

Reduced-init testing is a separate later track. WSL 2.7.11 exposes no custom-initrd setting and reads the installed tools-directory initrd. The preferred Microsoft-aligned route is a controlled WSL build deployed to a disposable Hyper-V Windows VM. The approximately 3 GB Windows build workload remains an optional user-invoked task in `TASKS.md`; it must not be installed automatically.

## Fixed experimental conditions

Use the same inputs throughout a minimisation run:

- Kernel source: `/root/src/WSL2-Linux-Kernel`
- Source revision: record the exact commit before every run
- Toolchain: record compiler and linker versions
- Lower bound: mkroot-generated x86-64 config
- Upper bound: `config-wsl-ultramin-stage1`
- Minimal-core test distro: `Toybox-Minimal`
- First compatibility distro: `Alpine`
- Later compatibility distros: Arch and Debian registrations whose exact names, rootfs/VHDX hashes, and versions must be fixed before their first trials
- Stock kernel retained as the recovery kernel

Do not update WSL, Windows, the kernel source, Toybox, a test distro/rootfs, or the compiler in the middle of a run. A changed input begins a new run.

## Configuration rules

1. Generate the lower-bound config from mkroot; do not hand-create an approximation.
2. Generate it against the same Microsoft kernel tree used for all candidate builds.
3. Run `make olddefconfig` after every config composition.
4. Save both the requested fragment and resulting full `.config`.
5. Treat automatically selected Kconfig dependencies separately from explicitly requested symbols.
6. Make candidates additive until the first successful boot. Do not remove anything from the mkroot baseline during discovery.
7. After reaching a successful candidate, prove necessity by subtraction.
8. Never change unrelated symbols while diagnosing one failure.
9. Before adding or removing a symbol, query its outgoing and incoming Kconfig relationships in the external dependency inventory.
10. Never interpret a flattened edge without its condition: `A depends on B || C` does not mean that both B and C are mandatory.

## External dependency and review inventory

The experiment uses machine-searchable artifacts under `inventory/`, generated from the exact 6.18 Kconfig tree:

- `kconfig-dependencies.sqlite` — canonical searchable graph, config snapshots, annotations, and trial inventory;
- `config-snapshots.csv` — durable config path, parent, hash, and trial manifest;
- `annotations.csv` — editable checklist and classification data, one row per symbol;
- `dependencies.csv` — all dependency, select, imply, default, range and prompt-condition edges;
- `symbols.csv` — symbol type, prompt, help, full dependency expression and source locations;
- `config-values.csv` — values in every captured config;
- `config-differences.csv` — pairwise config differences, automatically including mkroot once added;
- `review-queue.csv` — dependency summaries plus checklist/classification columns;
- `stage1-enabled-review.csv` — smaller working set containing symbols enabled in Stage 1;
- `summary.json` — generation counts and inputs;
- `trials.csv` — immutable append-only boot-trial ledger;
- `trial-metadata.csv` — durable supplements for omitted historical ledger fields.

The inventory must be regenerated whenever the kernel source revision, architecture, mkroot config or candidate configs change. `annotations.csv` is imported during regeneration so reviewed classifications survive. The generated database records parser compatibility transformations and source paths.

### Relationship meanings

| Relation | Meaning |
|---|---|
| `depends_on` | The target is referenced by the source symbol's full visibility/dependency expression; inspect `condition_expr` for AND/OR/negation |
| `selects` | Enabling the source forces the target when the recorded condition is true |
| `implies` | Enabling the source weakly requests the target when its condition permits |
| `prompt_depends_on` | The target controls whether a user-facing prompt is visible; not necessarily a runtime dependency |
| `default_ref` / `default_condition` | The target influences a default value; not automatically a hard requirement |
| `range_ref` / `range_condition` | The target affects a numeric range or its applicability |

“Depends on what” is answered with outgoing edges. “What depends on this” is answered with incoming edges. Both directions are indexed in SQLite.

### Checklist workflow

1. Query a symbol before changing it:

   ```powershell
   uv run python tools/inventory.py show CONFIG_HYPERV
   ```

2. List unchecked symbols enabled in Stage 1:

   ```powershell
   uv run python tools/inventory.py todo --enabled-in stage1
   ```

3. Record classification, evidence and completion atomically in SQLite and `annotations.csv`:

   ```powershell
   uv run python tools/inventory.py set CONFIG_HYPERV `
     review_status=REVIEWED checked=yes `
     documentation_status=DOCUMENTED_PLATFORM layer=HYPERV `
     feature_group=hyperv-core source_url=https://... `
     rationale="Hyper-V guest core"
   ```

4. Do not manually edit generated CSVs; treat `annotations.csv`, `config-snapshots.csv`, `trials.csv`, and `trial-metadata.csv` as durable inputs.
5. Before a trial, add the candidate full config and hash to `config-snapshots.csv`, ensure every requested/selected symbol is reviewed, and inspect incoming `selects`/`implies` plus dependency expressions.
6. Run `uv run python tools/inventory_records.py`; require SQLite integrity `ok` and a queryable candidate snapshot.
7. After Kconfig expansion, compare requested versus resulting values and classify newly auto-selected symbols as `TRANSITIVE` or return the fragment for review.

CSV supports spreadsheet review; SQLite supports exact graph queries and joins. The SQLite schema stores `symbols`, `edges`, `configs`, `config_values` and `annotations`, with `dependency_list`, `config_differences` and `review_queue` views.

## Requirement classification

Every explicit symbol or coherent feature group is entered in the experiment ledger with one of these statuses:

| Status | Meaning |
|---|---|
| `BASE` | Supplied by mkroot's generic minimal Linux configuration |
| `PROVEN_WSL_REQUIRED` | Removing it from an otherwise working candidate reproducibly prevents WSL startup |
| `PROVEN_TOYBOX_REQUIRED` | WSL starts, but removing it prevents the Toybox Minimal Viable WSL milestone |
| `PROVEN_ALPINE_REQUIRED` | Minimal Viable WSL still works, but removing it prevents the Alpine smoke test |
| `PROVEN_ARCH_REQUIRED` | Earlier targets still work, but removing it prevents the Arch smoke test |
| `PROVEN_DEBIAN_REQUIRED` | Earlier targets still work, but removing it prevents the Debian smoke test |
| `TRANSITIVE` | Selected by Kconfig as a dependency; not independently requested |
| `DOCUMENTED_PLATFORM` | Microsoft documents it as part of WSL/Hyper-V operation |
| `DOCUMENTED_SCENARIO` | Microsoft enabled it for an optional user scenario such as USB/IP, Ceph or Kubernetes |
| `MAINTENANCE_INHERITED` | Carried from Microsoft's Azure Linux base for maintenance alignment, without a WSL-specific requirement stated |
| `NOT_REQUIRED_STAGE1` | Historical Stage-1 removal classification; the exact tested distro suite must remain recorded with the trial |
| `DEFERRED` | Not needed for Minimal Viable WSL or the selected distro suite; reconsider only for later integration profiles |
| `UNRESOLVED` | Present in a successful bundle but not yet isolated or removed |
| `INCOMPATIBLE` | Causes a build or runtime regression when enabled/disabled as tested |

Documentation status and experimental requirement status are separate columns. For example, Ceph can be `DOCUMENTED_SCENARIO` and `DEFERRED`, while a Hyper-V facility can be `DOCUMENTED_PLATFORM` and later become `PROVEN_WSL_REQUIRED`.

A feature is not called “required” merely because it appears in Microsoft’s config or in a successful candidate. It becomes proven required only after a controlled ablation fails twice and restoring it passes. Conversely, documented rationale should be recorded before testing so that we do not rediscover an already-known purpose from crash logs.

The immutable ledger is `inventory/trials.csv`; `inventory/trial-metadata.csv` supplements omitted historical fields without rewriting evidence. Their SQLite `trial_inventory` view currently records status/timestamps, source and toolchain, parent/change group, requested and auto-selected symbols, config/image hashes, boot level, Toybox and Alpine results, failure evidence, analysis path, classification, and stock restoration. Before Arch or Debian trials, extend the durable schema and harness so those results and checkpoints are first-class fields. No new trial may begin until the previous row has a terminal status and recovery result and both inputs have been synchronized.

## Boot checkpoints

First establish the generic mkroot baseline independently under QEMU:

| Level | Generic checkpoint |
|---|---|
| `G0` | Kernel image rejected or no useful serial output |
| `G1` | Kernel enters and initializes the configured QEMU board/console |
| `G2` | Initramfs is unpacked and `/init` is found |
| `G3` | Toybox `/init` runs as PID 1 and mounts its virtual filesystems |
| `G4` | Toybox shell smoke test exits successfully |

Then each WSL trial receives the highest checkpoint reached:

| Level | WSL checkpoint |
|---|---|
| `B0` | Kernel image rejected or no useful kernel output |
| `B1` | Kernel enters and initializes basic CPU/memory/console facilities |
| `B2` | Hyper-V/VMBus devices enumerate |
| `B3` | WSL system storage is detected and its ext4 root is mounted |
| `B4` | Microsoft `mini_init` starts and remains alive |
| `B5` | WSL accepts and dispatches a command into a distribution |
| `B6-T` | Toybox smoke test passes; candidate can enter Minimal Viable WSL minimality proof |
| `B6-A` | Alpine smoke test passes |
| `B6-ARCH` | Arch smoke test passes; add this checkpoint to the durable schema before use |
| `B6-D` | Debian smoke test passes; add this checkpoint to the durable schema before use |

This classification is essential: later exact evidence places the Stage 3-equivalent post-ext4 `mini_init` crash at `B3`, whereas Stage 2 failed much earlier. Those are different missing dependency groups. `B6-T` establishes the functional core; the remaining `B6-*` checkpoints measure distribution compatibility without redefining that core.

## Minimal smoke tests

The target does not require networking or systemd. Tests verify only command dispatch, kernel/userspace execution, and fundamental virtual filesystems.

Toybox:

```sh
/bin/toybox sh -c '
  test -r /proc/self/status &&
  test -d /sys &&
  test -c /dev/null &&
  printf toybox-ok
'
```

Alpine:

```sh
/bin/sh -c '
  test -r /proc/self/status &&
  test -d /sys &&
  test -c /dev/null &&
  /bin/busybox true &&
  printf alpine-ok
'
```

Arch:

```sh
/bin/sh -c '
  test -r /proc/self/status &&
  test -d /sys &&
  test -c /dev/null &&
  /bin/true &&
  printf arch-ok
'
```

Debian:

```sh
/bin/sh -c '
  test -r /proc/self/status &&
  test -d /sys &&
  test -c /dev/null &&
  /bin/true &&
  printf debian-ok
'
```

Do not include DNS, package management, Windows executables, `/mnt/c`, systemd or container tests; those would silently expand the selected target.

## Feature bundles for discovery

Keep additions coherent so that logs remain interpretable. Derive exact symbols by comparing the mkroot lower bound with known-good Stage 1; do not rely solely on this descriptive list.

1. **Generic mkroot base**
   - x86-64, ELF, initramfs, basic VFS, devtmpfs, procfs, sysfs, tmpfs, PTYs and basic networking supplied by mkroot.
2. **Hyper-V execution and console**
   - Hyper-V guest detection, clocks/timers, interrupts, VMBus and the console/logging path needed to observe subsequent failures.
3. **WSL system storage**
   - Hyper-V storage, SCSI/block dependencies, partition handling and built-in ext4 needed before userspace is available.
4. **WSL host control channel**
   - Hyper-V sockets/VSOCK and other host/guest communication used to create and command distributions.
5. **WSL init execution substrate**
   - Kernel process, syscall, namespace, mount, event, credential and IPC facilities actually required by `mini_init`.
6. **Distribution command dispatch**
   - PTYs, pseudofilesystems and execution facilities needed to enter an imported root filesystem and run a command.
7. **Windows filesystem integration**
   - 9P/virtiofs/DrvFs-related support, deferred unless WSL cannot reach `B5` without it.
8. **Networking**
   - Hyper-V `netvsc` and the desired IP stack, deferred beyond `ultra-minimal-wsl-v1`.
9. **Later services**
   - systemd/cgroups, containers, firewalling, VPN/tunnelling, USB, filesystems and observability, all deferred.

## Trial strategy: minimise the number of boots

### Phase 0A — Apply Landley’s documented derivation

Before adapting anything to WSL:

1. Read `MKROOT-MINIMAL-BOOT-METHOD.md` and its primary sources.
2. Treat the current pinned `mkroot/mkroot.sh` as authoritative where historical talks differ.
3. Preserve mkroot’s microconfig, miniconfig and dependency-expanded fullconfig separately.
4. Retain its known QEMU board, console, initramfs and `/init` contract.
5. Run the generated QEMU launcher and establish `G4` before interpreting any WSL failure.
6. Record which common symbols support only mkroot’s broader block/clock/network smoke tests rather than shell boot.

This prevents WSL-specific experimentation from obscuring whether the generic minimal system itself is valid.

### Phase 0B — Exhaust WSL rationale before WSL trials

Before changing a symbol:

1. Search the WSL2 kernel repository's commit history for that symbol and subsystem.
2. Search merged and closed pull requests and linked `microsoft/WSL` issues.
3. Check Microsoft Learn documentation and WSL release notes.
4. Read the symbol's upstream Kconfig help and dependency expression.
5. Where Microsoft says the config was inherited from Azure Linux, inspect the corresponding Azure Linux config change.
6. Record the source URL, quoted rationale, kernel version and whether the rationale still applies to the current 6.18 config.

Use `KERNEL-CONFIG-PROVENANCE.md` as the initial evidence index. Documentation can classify optional scenarios without spending a WSL boot trial, but only a controlled test can prove that a facility is dispensable from our selected profile.

### Phase 1A — Lower bounds established (complete)

Completed evidence:

1. The exact mkroot x86-64 microconfig, miniconfig and fullconfig were generated in protected worktrees.
2. The untouched kernel/initramfs passed `G4` with its generated QEMU launcher.
3. Configs, logs and artifact hashes were archived.
4. Mkroot was added to the dependency inventory, producing the 1,792-symbol mkroot-to-Stage-1 delta.
5. Matching unmodified WSL 2.7.11 `init` and deterministic initrd artifacts were built twice with identical hashes.

### Phase 1B — Validate supported kernel recovery (complete)

1. The kernel-only `.wslconfig` switch/test/restore harness passed its isolated and plan-only tests.
2. Static inspection and plan tests verify no write path beneath `C:\Program Files\WSL`; unrelated `.wslconfig` settings and exact original bytes are preserved.
3. `K-RECOVERY-001` selected `candidates\wsl-2.7.11-stock-kernel`, the external byte-identical copy of Microsoft’s packaged kernel.
4. Toybox passed `B6-T`; the harness restored the exact original `.wslconfig`, verified the packaged-kernel hash, and proved a stock Debian boot.
5. A PowerShell 5.1 lazy ledger-read handle was diagnosed after journaled recovery reverified stock startup. Ledger headers are now read eagerly, genuine transient locks are retried, and repeated finalization is idempotent.

### Phase 1C — First mkroot-kernel WSL trial with stock init (complete)

1. `K-MKROOT-001` selected the unchanged mkroot kernel while retaining Microsoft’s untouched stock initrd.
2. `Toybox-Minimal` produced no output or command dispatch and exceeded the strict 45-second timeout.
3. With no useful kernel output, dmesg, crash artifact, or specific Windows error, the highest evidenced checkpoint is `B0`.
4. Exact `.wslconfig` and packaged hashes were restored and stock Debian booted successfully.
5. The QEMU `G4` pass isolates this as a WSL integration failure rather than a broken generic baseline.

### Phase 2A — Hyper-V execution and diagnostic retry (complete, advanced to B1)

`K-HVCORE-001` added only `HYPERVISOR_GUEST`, `HYPERV`, and their seven Kconfig-selected/default execution dependencies. Unrelated KVM/haltpoll/paravirtual-clock defaults were held at the mkroot/Stage-1 values. The initial trial produced no output or command dispatch and was conservatively classified `B0`; exact stock recovery passed.

`K-HVCORE-DIAG-001` reran the byte-identical artifact under Microsoft's pinned WSL ETW profile with transactionally enabled `debugConsole=true`. It proved `B1`: Linux entered, detected Hyper-V, unpacked the stock initramfs, and ran stock `/init`. It did not enumerate VMBus devices, so `B2` was not reached. Missing `/dev/hvc1` and `/dev/console` were observed, followed by the fatal control-plane error `UtilConnectVsock: socket failed 97` (`EAFNOSUPPORT`). Recovery and ETL finalization passed.

Approved `K-HOSTCHAN-001` added the minimal ACPI/platform-enumeration closure plus built-in `VSOCKETS` and `HYPERV_VSOCKETS`. It proved VMBus 5.3 enumeration, AF_VSOCK/`hv_sock`, and mini-init host messaging, advancing to `B2`. Exact WSL 2.7.12 source correlation later mapped the terminal exception to `GetLunDeviceName` timing out because Hyper-V storage was absent. The cgroup error was non-terminal, mirrored fallback was caused by absent seccomp, and GNS closure was consequential. No root mount appeared, so `B3` was not assigned. The ACPI/VSOCK bundle is retained provisionally. Approved `K-STORAGE-001` added only `SCSI_LOWLEVEL` plus `HYPERV_STORAGE` and proved `B3`: `storvsc` attached two disks and mounted the system-distro ext4 root. `mini_init` then reproduced Stage 3's exact post-mount segfault and panic. Exact source next calls `UtilMountOverlayFs`, while both failing configs have `OVERLAY_FS=n`. `K-OVERLAY-001` now contains the reviewed narrow `OVERLAY_FS`/selected-`FS_STACK` closure with optional overlay defaults disabled; it is built, hashed, inventoried, and plan-validated but has not been booted. See `POST-B2-CLOSURE-ANALYSIS.md` and `recovery-harness/trials/K-STORAGE-001/analysis.json`.

### Phase 1D — Reduced control-plane track

After kernel discovery has useful evidence—or earlier only if stock init prevents meaningful progress:

1. define retained command-dispatch paths and compile-time exclusions;
2. let the user separately install the optional full Windows build prerequisites;
3. build a controlled WSL package or service-level initrd override;
4. deploy it to a disposable Hyper-V Windows VM using Microsoft’s documented deployment script;
5. build the reduced init/initrd twice with identical outputs and test it in that isolated environment.

Transient replacement of the host’s installed initrd is not part of the default plan and requires a separate explicit decision.

### Phase 2 — Error-directed additions

Do not enable symbols one at a time.

1. Map the failure checkpoint to the next coherent bundle.
2. Add that bundle’s dependency closure from Stage 1.
3. Rebuild and retest.
4. If the checkpoint advances, retain the bundle provisionally as `UNRESOLVED`.
5. If it does not advance, revert it and inspect the earliest new or unchanged failure before selecting another bundle.

Examples:

- No VMBus enumeration: investigate the Hyper-V execution bundle.
- No WSL system disk: investigate Hyper-V storage/SCSI/block support.
- Root mounts but `mini_init` dies: investigate the WSL init substrate, not more storage drivers.
- Commands dispatch but one compatibility distro fails after earlier targets pass: investigate that userspace’s ELF loader, syscall, pseudo-filesystem, and terminal expectations before changing Hyper-V support.

### Phase 3 — Use Stage 1 as the upper bound

If an error does not identify a narrow subsystem, use config delta debugging rather than guessing:

1. Compute the explicit feature-group difference between the failing candidate and Stage 1.
2. Add half of the remaining groups.
3. If the checkpoint advances or boot succeeds, continue within that half.
4. Otherwise test the other half.
5. Re-expand every candidate through Kconfig before comparing it.

Feature groups, rather than arbitrary halves of individual symbols, avoid invalid combinations and account for dependencies. This normally isolates a missing subsystem in logarithmically fewer trials than enabling options individually, although interacting requirements can require follow-up tests.

### Phase 4 — Prove the Minimal Viable WSL core

Once Toybox passes `B6-T` through the retained WSL management path:

1. Remove each provisional WSL bundle in turn.
2. For a failing removal, split that bundle and use delta debugging to identify its smallest required subset.
3. Repeat the failure once.
4. Restore the suspected requirement and repeat the success once.
5. Remove stock-init-only facilities, including the Microsoft system distro/overlay path where the reduced control plane permits it.
6. Run `make listnewconfig` and inspect all remaining explicit selections.
7. Freeze the reproducible result as `minimal-viable-wsl-v1`.

### Phase 5 — Add distribution compatibility

Starting from the frozen Minimal Viable WSL core:

1. Run the unchanged smoke test in Alpine, then Arch, then Debian.
2. If a distro fails, add only the coherent compatibility bundle selected by its earliest stable failure.
3. Prove each addition necessary by removal and restoration while rerunning all earlier target smoke tests.
4. Classify additions as `PROVEN_ALPINE_REQUIRED`, `PROVEN_ARCH_REQUIRED`, or `PROVEN_DEBIAN_REQUIRED`; do not fold them into the generic WSL floor.
5. Freeze the combined result as `ultra-minimal-wsl-v1` after all four targets pass.

Both results are minimal only relative to the pinned source revision, WSL version, Hyper-V interface, control-plane implementation, and selected root filesystems—not universal Linux minima.

## Failure handling and safety

A custom WSL kernel is global to all WSL 2 distributions. Every host kernel trial must therefore:

1. Record the installed WSL version and packaged-kernel hash.
2. Save the original `.wslconfig` byte-for-byte.
3. Validate and hash the external candidate kernel.
4. Write only the candidate `kernel=` setting, preserving unrelated configuration.
5. Run `wsl.exe --shutdown` and confirm the VM stopped.
6. Start only the designated test distro with a strict timeout.
7. Capture command output, best-effort in-guest `dmesg`, Windows events and panic files; use Microsoft’s ETL/debug-console workflow when failure occurs before command dispatch.
8. Restore the original `.wslconfig` in an unconditional `finally` path.
9. Run `wsl.exe --shutdown` again.
10. Verify the packaged-kernel and `.wslconfig` hashes and prove that a stock distro starts.

The host kernel harness must first pass with an external byte-identical stock-kernel copy and must never write under `C:\Program Files\WSL`. Never leave a failed kernel selected. Do not run parallel trials because WSL uses one shared VM/kernel.

Initrd, Windows-service and package trials follow a separate recovery plan in a disposable Hyper-V Windows VM. They are not covered by the host kernel harness.

## Completion criteria

### `minimal-viable-wsl-v1`

The core is complete when one candidate:

- retains a reproducible mkroot baseline that passes `G4` under QEMU;
- passes `B6-T` through basic registered-distro selection/start and `wsl.exe` command dispatch;
- retains only the proved host handshake, distro VHDX/ext4 mount, root transition/isolation, process/stdio relay, exit notification, and shutdown contract;
- passes ten cold-start cycles after `wsl.exe --shutdown`;
- has no unexpected kernel warnings, oopses or init crashes in captured logs;
- has reproducible source, config and image hashes;
- has every non-mkroot explicit feature classified;
- can be replaced by the stock kernel through the tested host recovery procedure, with any reduced-init package independently recoverable in its isolated test environment.

### `ultra-minimal-wsl-v1`

The distribution target is complete when the frozen core plus classified additions:

- passes Toybox, Alpine, Arch, and Debian smoke tests;
- reruns all earlier targets after every compatibility addition;
- records each non-core addition against the distribution that proved it necessary;
- passes the same reproducibility, cold-start, warning-free, and recovery gates as the core.

Networking, Windows filesystem integration, Windows executable interop, WSLg, systemd, containers, USB, and alternative filesystems remain separate additive profiles so the measured core stays intact.
