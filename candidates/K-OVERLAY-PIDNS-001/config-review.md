# K-OVERLAY-PIDNS-001 config review

Parent: `K-OVERLAY-001`, full-config SHA-256 `ab0c68a2e96b36a397226f71e45d59a99c59f10ac1019c62bfde4e321a45e3f7`.

The prior `K-PIDNS-001` interval booted, exchanged mini-init configuration, and then failed dynamic registered-distro VHDX association at B2. `K-OVERLAY-001` is the only preserved reduced-kernel sibling already proved beyond that storage boundary. This candidate retains its coherent overlay closure and adds only the independently proven `CONFIG_PID_NS` requirement.

`CONFIG_PID_NS` depends only on existing `CONFIG_NAMESPACES=y`, has no incoming select/imply relationship, and selects nothing. `olddefconfig` selected no additional symbol. The exact delta from the parent is `PID_NS n -> y`; IPC and UTS remain disabled.

Two fresh offline local clones on `LFS-Builder` ext4 produced byte-identical configs and kernels:

- full config SHA-256 `22a8d81761cbe852cacc5d1d25890a3fb181a7d2f22fdf86f298c8f5366df1e7`;
- kernel SHA-256 `5e6e4fcf3bded61d96787ea8c46f1941f09099ef086b045a98e31652f97320ca`;
- kernel size 3,781,632 bytes.

This sibling tests whether the known post-B3 overlay parent changes the observed storage-adapter lifetime. Static source reachability still predicts overlay is unnecessary under the reduced control plane; a repeated B2 failure will reject overlay as the explanation and select a different narrow dynamic-storage facility.
