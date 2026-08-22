# `minimal-v3` interop-removal and namespace audit

This is static source and reproducible Linux-build evidence against pinned WSL 2.7.12. It is not a Windows package build or runtime result and proves no B4, B5, B6-T, termination, recovery, or namespace necessity.

## Layering and source boundary

`minimal-v3-fail-closed` preserves `minimal-v2-fail-closed` at commit `6869aac89f3d859de6a707861ed1bd05d8ee087d` and adds only `patches/0004-minimal-v3-no-interop.patch` (SHA-256 `e68611ecc12ac556b8a8ffd84e7af9045ef552bf58cb6ddac2fe78a44825b981`). The resulting source commit is `bb1d95680a63103b5bb6a9509d22ae3e57aa0cf0`; its complete pinned-base diff SHA-256 is `97935ccd9541bb221e87cf2dee746cdcff221b5b69d98d3e43b42fddf69576ad`.

The layer changes only `src/linux/init/main.cpp`. It removes mini-init's `binfmt.h` include, local `WSLInterop` registration constants, unconditional `binfmt_misc` mount, and registration write from retained early initialization. It does not enable `CONFIG_BINFMT_MISC`, alter the wire protocol, broaden policy, or edit distro-init's stock interop functions. Those broad functions remain constrained by the preserved fail-closed configuration and process-flag policy.

Focused record tests require the layer to touch only `main.cpp` and to remove both hard-fail calls and their definitions. Existing protocol tests still enumerate all 52 message families on every inbound channel, reject excluded fields and process flags, preserve signed exit status, and validate termination framing. The recorded policy mutations remain applicable because the policy seam is unchanged. Two additional v3 mutations—reintroducing the binfmt mount deletion as an addition and replacing the mount-only clone bundle with the stock bundle—were independently caught and reverted; `protocol/test-evidence.md` records the results.

## Namespace siblings

Both replacement siblings derive from `minimal-v3-fail-closed`:

- `minimal-v3-stock-ns` is an explicitly recorded tree-identical sibling at `ec37cac016fb949f783c1c107c693477a4446511`; it retains IPC, mount, PID, and UTS namespace requests and the same complete diff hash as its parent.
- `minimal-v3-mount-ns` is commit `f149988635e3fe9ecbcb0577899e82d7e61464e4`. Patch `patches/0005-minimal-v3-mount-ns.patch` (SHA-256 `7bf14daf6388b322db5bf69eb05394f84baa3260b3c1127efaae0fc62e473515`) changes only the coherent clone bundle to `CLONE_NEWNS`; its complete pinned-base diff SHA-256 is `5c36be2fce4bf497d1c480f7fac570089f9ba906b236b6fa9503f5820166058c`.

Neither sibling selects kernel configuration. `CONFIG_IPC_NS`, `CONFIG_PID_NS`, and `CONFIG_UTS_NS` remain unselected pending controlled runtime comparison.

## Reproducible Linux builds

Each candidate was built twice with `OFFLINE=1`, `MINIMAL_LINK=1`, two jobs, verified cache hits, and distinct ext4 build directories under pinned `LFS-Builder` profile 1 (`35284f8aecb56a5e2bf6af091e1877ed7ed9c8730211aee2600766c05e586543`). Every run pair was byte-identical.

| Candidate | `init` SHA-256 | `init.debug` SHA-256 | `initrd.img` SHA-256 |
|---|---|---|---|
| `minimal-v3-fail-closed` | `99828be3e706c29e26eaaf7ca6e423d897dd334ab88a4e4410a70a5d2d1726aa` | `3a14ebe773f20ea4a9d63b7f82d2c24054abfeb333f676314019bb06ae59faf3` | `a7e3f9f14ede0ecf626da9a74b71fc156b4550496908001a1cfbd1c54eda6989` |
| `minimal-v3-stock-ns` | `99828be3e706c29e26eaaf7ca6e423d897dd334ab88a4e4410a70a5d2d1726aa` | `3a14ebe773f20ea4a9d63b7f82d2c24054abfeb333f676314019bb06ae59faf3` | `a7e3f9f14ede0ecf626da9a74b71fc156b4550496908001a1cfbd1c54eda6989` |
| `minimal-v3-mount-ns` | `f9acda771051b7aecafcb0d39dc232d1953c741b0e28cef4f26d1b453574abad` | `8e9d85e66c71c1f53df0942dad3edcd8755d879f2a5c5c201d1ef1f65e862fe5` | `d6260c83155713c6c3cfa9e92f9fcba3d65cad8937ffa1d265cc32da78368f2c` |

Candidate directories preserve source, patch, profile, toolchain, size, artifact, and reproducibility records. All prior v1/v2 patches and candidate records remain unchanged.

## Result and stopping boundary

The known source-only runtime-readiness blocker is removed, and replacement candidates are reproducible. The next evidence milestone is controlled Windows package compilation and runtime proof of B4/B5/B6-T, lifecycle, recovery, and namespace necessity. `STATUS.md` and `TASKS.md` own the preparation still required before that milestone. `deferred-runtime-plan.json` is non-executable and carries no approval forward.
