# Third-party material

The Apache-2.0/MIT choice applies only to original project code and documentation. It does not relicense third-party or generated material.

| Material | Source | Terms |
|---|---|---|
| Microsoft WSL diagnostic profile under `references/microsoft/WSL-2.7.11/` | <https://github.com/microsoft/WSL/tree/2.7.11> | Microsoft MIT license copied alongside it |
| Linux kernel configurations and Kconfig-derived inventory | <https://github.com/microsoft/WSL2-Linux-Kernel> and upstream Linux | Generated/derived material; consult upstream GPL-2.0-only notices and source |
| Toybox-generated configs and `mkroot-baseline/toybox-init` | <https://github.com/landley/toybox> | Consult Toybox’s upstream 0BSD license and generated-file notices |
| Build and runtime logs | Outputs of the named upstream projects and local experiments | Factual evidence; embedded excerpts retain applicable upstream terms |

Downloaded Linux kernels, initramfs images, toolchains, rootfs archives, and WSL binaries are intentionally excluded from Git. Their hashes and reproducible metadata may remain.

Microsoft, Windows, WSL, Hyper-V, Linux, Toybox, Alpine, Arch, and Debian names belong to their respective owners. Their use here identifies compatibility targets and does not imply endorsement.
