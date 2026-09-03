# Work queue

`STATUS.md` owns verified current facts. `MINIMAL-BOOT-PLAN.md` owns strategy and acceptance criteria. This file contains incomplete work only.

## Active action

Prepare `Debian2` as the first practical-workload test article inside the dedicated disposable fixture. Import the pinned clean Debian 13.5 rootfs under stock WSL, create user `jack`, apply the committed core dotfiles/chezmoi bootstrap from immutable repository bundles, install fixed fnm, Node.js, McFly, and Pi inputs, verify shell startup and `pi --version`, remove any fixture-wide `.wslconfig` written by personal-machine dotfiles, record the resulting VHDX and installed-version identities, leave `Debian2` registered, and return the fixture Off.

This preparation must copy no secret, credential, SSH key, history, or mutable working-tree content. On failure it must remove a partial `Debian2` registration and install path. It does not rerun or modify the frozen Toybox, Alpine, Arch, or Debian compatibility candidates. After preparation, a separate bounded action may boot this article under the frozen reduced WSL baseline to identify the first practical-workload failure.

## Blocked

- No finalized v3, v4, v5, `K-PIDNS-001`, or `K-OVERLAY-PIDNS-001` candidate is eligible for an unchanged candidate-comparison rerun.
- No speculative Kconfig group or replacement fixture infrastructure is queued.

## Constraints

- Keep the frozen Toybox baseline and all completed Toybox, Alpine, Arch, and Debian evidence unchanged.
- A failure before the first probe `wsl.exe` process is infrastructure failure and creates no candidate result.
- Preserve completed candidate records, terminal ledger rows, and trial evidence.
- Keep Linux builds on `LFS-Builder` ext4 and use only pinned, hash-verified offline inputs.
- Proceed autonomously inside the disposable-fixture envelope. Require fresh explicit approval for any physical-host or shared-WSL effect and fail closed if isolation, hashes, offline status, or recovery cannot be proved.
