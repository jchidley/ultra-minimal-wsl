# Ultra-minimal WSL

This project derives the smallest practical WSL 2 system from Toybox `mkroot`, then adds only what is proven necessary for WSL command dispatch and selected Linux distributions.

## Targets

### Minimal Viable WSL

`minimal-viable-wsl-v1` consists of:

1. an mkroot-derived kernel and Toybox userspace;
2. the Hyper-V facilities needed to enter WSL;
3. VSOCK communication with `wslservice.exe`;
4. attachment and mounting of a registered distro VHDX;
5. the minimum root transition or isolation needed to enter that distro;
6. command execution through `wsl.exe`;
7. stdin, stdout, stderr, and exit-status relay;
8. reliable startup, termination, and stock-kernel recovery.

It does not require networking, DNS, DrvFs, Windows executable interop, WSLg/GPU, systemd, containers, cgroup policy, USB, general disk management, or cross-distribution integration. Microsoft’s system distro and overlay are excluded if the reduced control plane proves avoidable.

### Distribution compatibility

After Toybox proves the mechanism, the same core is tested against:

1. Alpine — musl and BusyBox;
2. Arch — glibc and rolling userspace;
3. Debian — glibc and stable userspace.

Only experimentally necessary additions are retained and attributed to the distribution that selected them.

```text
mkroot/Toybox generic Linux
    + minimum WSL control contract
        = Minimal Viable WSL

Minimal Viable WSL
    + proven Alpine requirements
    + proven Arch requirements
    + proven Debian requirements
        = ultra-minimal-wsl-v1
```

Everything beyond this boundary is an optional integration profile.

## Current position

The untouched mkroot kernel passes its Toybox QEMU smoke test. WSL candidates have proved Hyper-V entry, VMBus/VSOCK, Hyper-V storage, and successful stock system-distro overlay construction. `K-OVERLAY-DIAG-001` then exposed excluded GNS networking as the next stock blocker, so additive stock-init kernel discovery is frozen. `minimal-v1` now provides a reproducible first host/guest reduction and strict protocol-policy tests. The immediate source-only phase is a layered fail-closed candidate followed by mount-namespace-only versus stock-namespace variants. Windows media, Visual Studio, Hyper-V VM creation, and runtime testing remain deferred. See `STATUS.md`, `TASKS.md`, and `NEXT-SESSION.md`.

## Documentation

- `MINIMAL-BOOT-PLAN.md` — target contract, experiment method, checkpoints, and completion criteria.
- `STATUS.md` — current verified state.
- `TASKS.md` — active work only.
- `WSL-DEVELOPMENT-AND-RECOVERY.md` — safe kernel-trial and recovery runbook.
- `WSL-CONTROL-PLANE-AUDIT.md` — why stock `/init` is not the final minimum.
- `MKROOT-MINIMAL-BOOT-METHOD.md` — rationale for the generic lower bound.
- `inventory/README.md` — Kconfig graph and durable experiment records.
- `control-plane/README.md` — reduced control-plane artifacts, tests, and deferred runtime gate.
- `NEXT-SESSION.md` — verified restart brief for the immediate source-only phase.
- `session-history/README.md` — historical, grep-friendly project-session transcripts.

## Verify the repository

```bash
uv run python tools/inventory_records.py
uv run python -m unittest tools.test_inventory_records tools.test_control_plane_protocol tools.test_control_plane_records
~/git/agent-skills/skills/windows-env/ps-lint --offline --settings .PSScriptAnalyzerSettings.psd1 tools
git ls-files '*.sh' -z | xargs -0 shellcheck --severity=warning -x
```

The PowerShell check uses pinned PSScriptAnalyzer 1.25.0 under Windows PowerShell 5.1 from the verified `windows-env` cache. The generated SQLite database must already exist; rebuild instructions are in `inventory/README.md`.

No kernel trial is authorized by this README. A trial changes the global WSL kernel, shuts down every WSL 2 distro, and must use the guarded recovery harness with fresh explicit approval.

## Licensing

Original project code and documentation are available under either Apache-2.0 or MIT. Generated configurations, extracted logs, and third-party material retain their upstream terms; see `THIRD_PARTY_NOTICES.md`.
