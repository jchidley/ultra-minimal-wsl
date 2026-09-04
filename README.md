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

Everything beyond this boundary is an optional integration profile. A separate, inactive follow-on project for a practical Rust userspace is chartered in `RUST-MINIMAL-WSL-FOLLOW-ON.md`; it must not change either measured baseline.

## Achieved boundary

The frozen `ultra-minimal-wsl-v1` baseline passes Toybox, ten cold starts, and the pinned Alpine, Arch, and Debian smoke contracts without compatibility additions. It retains mount plus PID namespace semantics, omits IPC/UTS and overlay, and has independent stock-recovery evidence.

This is a measured baseline, not proof of global minimality or general-purpose distro compatibility; some retained facilities remain individually unresolved. See `STATUS.md` for the exact evidence boundary and practical-workload ownership, `MINIMAL-BOOT-PLAN.md` for the acceptance contract, and `TASKS.md` for any authorized incomplete work.

## Documentation

- `PROJECT-MODEL.md` — control-plane concepts, evidence gates, what tests prove, and the path to working minimal WSL.
- `MINIMAL-BOOT-PLAN.md` — canonical target contract, experiment rules, gates, and completion criteria.
- `STATUS.md` — current verified state.
- `TASKS.md` — active work only.
- `WSL-DEVELOPMENT-AND-RECOVERY.md` — safe kernel-trial and recovery runbook.
- `WSL-CONTROL-PLANE-AUDIT.md` — why stock `/init` is not the final minimum.
- `MKROOT-MINIMAL-BOOT-METHOD.md` — rationale for the generic lower bound.
- `inventory/README.md` — Kconfig graph and durable experiment records.
- `control-plane/README.md` — reduced control-plane artifacts, tests, offline package build, and runtime boundary.
- `build-host/README.md` — pinned `LFS-Builder` role, profile, and provisioning.
- `RUST-MINIMAL-WSL-FOLLOW-ON.md` — inactive charter for a `wsl.exe`-controllable Rust userspace after Minimal Viable WSL is frozen.
- `session-history/README.md` — historical, grep-friendly project-session transcripts.

## Provision `LFS-Builder`

`LFS-Builder` is the dedicated Debian build host, not a target distribution.
Its profile fixes Debian 13 on ext4, an immutable APT snapshot, exact build and
agent package versions, and hash-pinned uv and ShellCheck binaries. Provision
it idempotently from PowerShell:

```powershell
$Project = (Get-Location).Path
$WslProject = (wsl.exe --distribution LFS-Builder -- wslpath -a $Project).Trim()
wsl.exe --distribution LFS-Builder --user root -- `
  bash "$WslProject/tools/bootstrap-lfs-builder.sh"
```

Use `--check` for non-mutating verification or `--offline` for a cache-only
installation that fails closed. The profile, architecture boundary, cache
behavior, and controlled update procedure are documented in
`build-host/README.md`. Build-specific source archives remain governed by each
workflow's separate verified cache.

## Verify the repository

From PowerShell:

```powershell
uv run python tools/inventory_records.py
uv run python -m unittest tools.test_build_host_profile tools.test_inventory_records tools.test_control_plane_protocol tools.test_control_plane_records
& ~/git/agent-skills/skills/windows-env/Invoke-PsLint.ps1 -Offline -Settings .PSScriptAnalyzerSettings.psd1 -Path tools,control-plane/controlled-package-offline
```

From `LFS-Builder`:

```bash
bash tools/bootstrap-lfs-builder.sh --check
git ls-files '*.sh' -z | xargs -0 shellcheck --severity=warning -x
```

The PowerShell check uses pinned PSScriptAnalyzer 1.25.0 under PowerShell 7 from the verified `windows-env` cache. The generated SQLite database must already exist; rebuild instructions are in `inventory/README.md`.

On the physical host or any shared WSL installation, a kernel trial changes global WSL state, shuts down every WSL 2 distro, and requires the guarded recovery harness plus fresh explicit approval. Equivalent operations wholly confined to the dedicated disposable fixture are standing-authorized within the repository's pinned, offline, hash-verified, plan-validated recovery envelope and proceed autonomously without stage-by-stage operator confirmation.

## Licensing

Original project code and documentation are available under either Apache-2.0 or MIT. Generated configurations, extracted logs, and third-party material retain their upstream terms; see `THIRD_PARTY_NOTICES.md`.
