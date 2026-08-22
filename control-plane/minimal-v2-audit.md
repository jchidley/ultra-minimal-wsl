# `minimal-v2` fail-closed and namespace audit

This is static source and reproducible-build evidence against pinned WSL 2.7.12. It is not Windows compilation or runtime evidence, and it proves no B4/B5/B6 result.

## Layering

`minimal-v2-fail-closed` is layered on the preserved `minimal-v1` source commit `f3d502ab4073c24fa31bd3f3ad4f6009a36076fa`. Patch `patches/0002-minimal-v2-fail-closed.patch` has SHA-256 `47d57f86685e3adf00cf73866c1e27779b5195357c14eeda5fa441ce0e1934a0`; the complete pinned-base-to-candidate diff has SHA-256 `6cb9e58956fc492230665acfe8791aa180dd62a0120070062ed5396e8e349759`.

The source uses the small policy seam recorded in `policy/minimal-v2-policy.h`. The patch embeds the same header, and record tests require byte-for-byte equality so implementation and tests cannot drift silently.

## Allowed inbound requests

| Channel | Allowed request families | Everything else |
|---|---|---|
| mini-init | early configuration, initial configuration, one distro launch | rejected before dispatch |
| distro control | initialize, create session, direct-process plumbing, terminate | rejected before dispatch |
| session | create process in the utility VM | rejected before dispatch |

The launch must be one supplied LUN, use `ext4`, and carry no launch flags. Early and initial configuration reject system distro, swap, modules, DNS, networking, memory policy, GUI/GPU, and related fields. Instance initialization rejects DrvFs volumes, feature flags, and DrvFs mount modes. Direct-process messages permit only the three console bits; elevation, interop, OOBE, and unknown bits are rejected.

Distro-local `/etc/wsl.conf` can no longer re-enable automount/fstab, timezone updates, boot commands/systemd, Windows-path interop, hosts/resolver generation, Plan 9, GPU libraries, or cgroup initialization on this path. Broad stock functions remain in source where deletion is not yet required, but the inbound dispatch and configuration gates fail closed and minimal linking removes newly unreachable sections. This preserved v2 generation still has one excluded utility-VM path reachable: mini-init's retained early initialization unconditionally mounts `binfmt_misc` and registers `WSLInterop`, returning failure on error. Replacement `minimal-v3` removes it rather than selecting `CONFIG_BINFMT_MISC`; see `minimal-v3-audit.md`. The historical gap does not change v2's static Kconfig conclusions.

## Namespace siblings

Both siblings have exact parent `minimal-v2-fail-closed` (`6869aac89f3d859de6a707861ed1bd05d8ee087d`).

- `minimal-v2-stock-ns` is tree-identical to the parent and retains `CLONE_NEWIPC | CLONE_NEWNS | CLONE_NEWPID | CLONE_NEWUTS`; its complete diff hash is `6cb9e58956fc492230665acfe8791aa180dd62a0120070062ed5396e8e349759`.
- `minimal-v2-mount-ns` differs only by replacing that coherent bundle with `CLONE_NEWNS`. Patch `patches/0003-minimal-v2-mount-ns.patch` has SHA-256 `f2bef4d7ebb0915d521cd5b8a4d020e196d3d2d35fefc31b996d336567c7d3b1`; its complete diff hash is `b3c8cb69ae1a88b648c7dfa021dccaaf108930a337c1cff72e4768de936c4358`.

The fail-closed parent is also built separately even though its tree and artifacts are expected to equal the stock-namespace sibling. Candidate records under `candidates/` preserve that fact rather than inventing a content difference.

## Test boundary

The compiler-derived fixture records all 52 init/mini-init control message families through resize response. Tests enumerate every family on every inbound channel, malformed frame sizes, excluded configuration fields, LUN/ext4 launch policy, all low direct-process flag combinations, signed exit status, and clean/forced termination framing.

Focused semantic mutations that added import to the mini-init allowlist and removed termination from the distro-control allowlist were both caught and reverted. See `protocol/test-evidence.md`.

## Kernel conclusion

The source variants select no Kconfig requirement. In particular, static preference does not promote `CONFIG_IPC_NS`, `CONFIG_PID_NS`, or `CONFIG_UTS_NS`. Deferred controlled-package runtime evidence must choose between the siblings and prove command relay and lifecycle behavior.
