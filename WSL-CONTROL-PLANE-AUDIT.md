# WSL control-plane boundary

Microsoft’s Linux-side `/init` serves a broad WSL product. Minimal Viable WSL retains only the host/guest contract needed to control one registered distro through `wsl.exe`.

## Why `/init` matters

The kernel does not enter a registered distro directly. Microsoft’s initramfs starts `mini_init`, which communicates with `wslservice.exe`, receives the attached distro disk, establishes the distro execution context, launches commands, and relays their results.

The retained contract is:

- service handshake and capabilities;
- per-distro VHDX attachment and ext4 mount;
- minimum root transition or isolation;
- process/session creation;
- stdin, stdout, stderr, and exit-status relay;
- child-exit notification and shutdown.

Replacing this entire chain would produce a small Hyper-V VM, not a WSL system controllable by `wsl.exe`.

## Stock control-plane tax

Stock `mini_init` also performs or supports work outside the target:

- cgroup policy;
- Windows executable registration through `binfmt_misc`;
- shared resolver/tmpfs policy;
- networking, GNS, DNS tunnelling, and localhost tracking;
- Microsoft’s system distro and writable overlay;
- WSLg/GPU integration;
- module and swap VHDs;
- memory-reclaim and resource policy;
- disk import/export/format/resize operations;
- cross-distro mounts and debugging services.

A facility is not part of Minimal Viable WSL merely because stock init requests it. Current discovery uses stock init to expose the platform one failure at a time; the reduced control plane must later remove stock-only dependencies.

## Pinned source map

The retained path is traced against the recovery-validated package’s exact public source: WSL tag `2.7.12`, commit `68f601bba8eac1df20a0bbd403c6c87c92369ade`. The previously audited 2.7.11 mapped files differ only by an unrelated two-line change in `WslCoreVm::MountRootNamespaceFolder`; the control-path references below are unchanged. Line numbers identify the pinned 2.7.12 revision.

| Contract step | Guest implementation | Host implementation | Required behavior |
|---|---|---|---|
| VM channel | `src/linux/init/main.cpp:4086-4105` connects two Hyper-V sockets | `src/windows/service/exe/WslCoreVm.cpp:324-351` listens before starting the VM | Keep the primary control channel and termination notification; port `50000` is defined in `src/shared/inc/lxinitshared.h:110-148`. |
| Initial handshake | `main.cpp:3637-3673` sends `LX_INIT_GUEST_CAPABILITIES` | `WslCoreVm.cpp:516-533` sends `LX_MINI_INIT_EARLY_CONFIG_MESSAGE` | Keep version/capability negotiation but report only retained facilities. |
| Distro storage | `main.cpp:2461-2495` mounts the supplied LUN | `WslCoreVm.cpp:1170-1226` attaches the registered VHDX and sends LUN, `ext4`, and mount options | Keep one per-distro VHDX attachment and ext4 mount. |
| Isolation and root transition | `main.cpp:3221-3243` creates IPC, mount, PID, and UTS namespaces; `main.cpp:247-265` moves the mount and chroots; `main.cpp:2581-2594` launches distro init | `WslCoreVm.cpp:1225-1246` waits for the distro channel | Determine experimentally which namespaces can be removed; retain the root transition and absolute-symlink correctness. |
| Distro control loop | `src/linux/init/init.cpp:2248-2315` adopts inherited fd `100` and reports instance creation; `init.cpp:2407-2527` handles initialization, sessions, processes, and termination | `src/windows/service/exe/WslCoreInstance.cpp` owns the corresponding instance channel | Keep only initialization needed for direct command execution and lifecycle. |
| Command creation | `init.cpp:1339-1427` advertises a per-command VSOCK port; `init.cpp:1490-1690` creates pipes/PTY and execs; `init.cpp:1810-2069` relays stdio and returns `LxInitMessageExitStatus` | `WslCoreInstance.cpp:143-242` sends `LxInitMessageCreateProcessUtilityVm` and connects five sockets | Keep stdin, stdout, stderr, control, process creation, and exit status. Disable the fifth interop path rather than implement Windows executable interop. |
| Termination | `init.cpp:2514-2518` handles `LxInitMessageTerminateInstance`; `init.cpp:2733-2768` powers off | `WslCoreInstance.cpp:465-489` requests termination | Keep forced and clean termination without Plan 9 or systemd policy. |

The wire structures and message identifiers are centralized in `src/shared/inc/lxinitshared.h`. The minimum candidate subset is `LX_MINI_INIT_MESSAGE`, `LX_MINI_INIT_CREATE_INSTANCE_RESULT`, `LX_INIT_CREATE_PROCESS_UTILITY_VM`, `LX_INIT_PROCESS_EXIT_STATUS`, and `LX_INIT_TERMINATE_INSTANCE`, plus their common message and process fields.

## Required host and guest reductions

A guest-only replacement is insufficient. Immediately after early configuration, stock `WslCoreVm.cpp:535-545` waits for a guest networking-service connection. Stock early configuration also supplies the Microsoft system-distro device, and `main.cpp:3313-3317` mounts it before normal instance creation. Therefore the controlled WSL package must change both sides:

- host: do not attach or advertise the system distro, and do not wait for GNS, DNS, DrvFs, WSLg, or other excluded channels;
- guest `mini_init`: skip system-distro overlay construction and dispatch only retained instance operations;
- distro `/init`: keep the inherited control channel, direct command path, relay, and poweroff behavior while omitting networking, DrvFs, interop, systemd, and Plan 9 setup;
- shared protocol: preserve existing layouts where practical so unmodified `wsl.exe` remains the client.

This is a source-level candidate contract, not proof that every listed namespace, message field, or socket is necessary. `control-plane/minimal-v1-audit.md` confirms that the first patch still compiles or dispatches broad stock operations and still requests IPC, mount, PID, and UTS namespaces. The next static gate is therefore a layered fail-closed candidate followed by stock-namespace and mount-only variants. Runtime ablation must establish the final minimum.

## Runtime stopping gate

`K-OVERLAY-DIAG-001` confirmed the source-map boundary. Overlay construction completed without the prior crash, then the host logged `Expected message LxGnsMessageResult, but socket GNS was closed`. NAT and no-network fallbacks did not recover the already closed control path. The guest then shut down cleanly.

This selects host/guest control-plane reduction, not another kernel bundle. Networking and GNS are outside the target, so no Hyper-V network, seccomp, cgroup, PTP, `/proc` children, or console additions follow from this trial. Detailed timing, guest logs, ETW, and analysis are preserved under `recovery-harness/trials/K-OVERLAY-DIAG-001/`.

## Selected design

Build a reduced single-user host and Linux control plane from a source revision matched to the tested package. Keep normal select/start/execute/terminate/shutdown behavior for registered distros, but omit general management and integration services.

The per-distro VHDX remains because it is WSL’s simple container for a native Linux filesystem. Microsoft’s separate system-distro VHD and overlay are excluded.

`minimal-v1` is preserved as the first reproducible reduction. Subsequent work must layer new patches and records rather than rewrite its hashes. `minimal-v2-fail-closed` will retain only the mapped contract messages; namespace variants then isolate whether launch needs more than `CLONE_NEWNS`. Neither source variant selects kernel requirements without runtime evidence.

## Deployment constraint

WSL supports an external kernel through `.wslconfig` but exposes no equivalent custom-initrd setting. Kernel discovery can therefore run on the host with the guarded recovery harness. Reduced-init testing must use a controlled WSL build in a disposable Hyper-V Windows VM; do not replace the host’s installed initrd.

## Primary sources

- WSL boot process: <https://wsl.dev/technical-documentation/boot-process/>
- `mini_init`: <https://wsl.dev/technical-documentation/mini_init/>
- per-distro init: <https://wsl.dev/technical-documentation/init/>
- WSL source: <https://github.com/microsoft/WSL>

Exact trial/source correlations are preserved in `recovery-harness/trials/*/analysis.json` and candidate reviews rather than repeated here.
