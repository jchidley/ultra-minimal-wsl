# `LFS-Builder` build-host profile

`LFS-Builder` is the dedicated WSL 2 **build host** for this project. It is not
the mkroot/Toybox lower bound, a candidate minimal system, or the Debian
compatibility target. Its Debian userspace supplies development tools only;
nothing installed here is evidence that a facility belongs in a target kernel
or root filesystem.

```text
Windows host and Pi
        |
        v
LFS-Builder (pinned Debian build host on ext4)
        |  source builds, Kconfig analysis, protocol extraction,
        |  QEMU generic tests, reproducibility checks
        v
Candidate artifacts and evidence
        |
        v
Guarded WSL trials and separate Toybox/Alpine/Arch/Debian targets
```

The historical name refers to its builder role and is retained because source
and artifact paths already use the registered WSL distro name.

## Profile 1

The profile fixes the inputs that can affect ordinary project work:

- Debian 13 (`trixie`), `amd64`, with the distro root on ext4;
- an immutable Debian snapshot timestamp and signed `InRelease` SHA-256;
- exact versions of explicitly required Debian packages in `packages.tsv`;
- exact uv and uvx release archive and binary hashes;
- exact ShellCheck 0.11 release archive and binary hashes;
- conventional Linux command paths, including `/usr/local/bin/fd` rather than
  an inherited Windows `fd.exe`;
- a checked `SHA256SUMS` manifest and one bundle hash recorded in every new
  control-plane build's metadata.

`debian-snapshot.list` is passed directly to APT. Provisioning does not rewrite
the distro's normal APT configuration. APT authenticates package indexes and
package hashes through Debian's signed snapshot metadata; the bootstrap also
checks the immutable `InRelease` object against the recorded SHA-256 before an
online install.

Extra interactive packages may exist, but every command used by standard
builds is required to resolve to Linux, and every declared package must match
its exact version. Build-specific downloaded inputs remain separately pinned
and hash-verified by their build scripts.

## Provision and verify

From PowerShell in the repository root:

```powershell
$Project = (Get-Location).Path
$WslProject = (wsl.exe --distribution LFS-Builder -- wslpath -a $Project).Trim()
wsl.exe --distribution LFS-Builder --user root -- `
  bash "$WslProject/tools/bootstrap-lfs-builder.sh"
```

The default mode accesses only the recorded Debian snapshot and pinned GitHub
release URLs. Downloads are written to a temporary path, hash-verified, and
then moved into `/root/cache/ultra-minimal-wsl/lfs-builder` atomically.

Non-mutating verification:

```powershell
wsl.exe --distribution LFS-Builder -- `
  bash "$WslProject/tools/bootstrap-lfs-builder.sh" --check
```

Cache-only repair or installation:

```powershell
wsl.exe --distribution LFS-Builder --user root -- `
  bash "$WslProject/tools/bootstrap-lfs-builder.sh" --offline
```

Offline mode never updates APT or downloads a release archive. It accepts an
already-correct installation, otherwise it fails unless the required package
and release archives are available in the configured cache.

## Updating the profile

Do not silently follow Debian or tool updates. Create a new profile revision by:

1. selecting a new immutable Debian snapshot;
2. recording and verifying its signed `InRelease` SHA-256;
3. updating exact package versions and release artifact hashes;
4. provisioning and passing `--check`;
5. rebuilding relevant artifacts twice in separate ext4 directories;
6. recording changed output hashes or proving byte identity;
7. reviewing and committing the profile and resulting evidence together.

A profile update changes the experimental toolchain boundary even if candidate
source and configuration are unchanged.
