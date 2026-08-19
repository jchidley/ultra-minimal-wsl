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

## Selected design

Build a reduced single-user control plane from matching WSL source. Keep normal select/start/execute/terminate/shutdown behavior for registered distros, but omit general management and integration services.

The per-distro VHDX remains because it is WSL’s simple container for a native Linux filesystem. Microsoft’s separate system-distro VHD and overlay are excluded if the retained command path works without them.

## Deployment constraint

WSL supports an external kernel through `.wslconfig` but exposes no equivalent custom-initrd setting. Kernel discovery can therefore run on the host with the guarded recovery harness. Reduced-init testing must use a controlled WSL build in a disposable Hyper-V Windows VM; do not replace the host’s installed initrd.

## Primary sources

- WSL boot process: <https://wsl.dev/technical-documentation/boot-process/>
- `mini_init`: <https://wsl.dev/technical-documentation/mini_init/>
- per-distro init: <https://wsl.dev/technical-documentation/init/>
- WSL source: <https://github.com/microsoft/WSL>

Exact trial/source correlations are preserved in `recovery-harness/trials/*/analysis.json` and candidate reviews rather than repeated here.
