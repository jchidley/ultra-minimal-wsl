#!/bin/bash
set -euo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
qemu-system-x86_64 \
    -m 256 \
    "$@" \
    -nographic \
    -no-reboot \
    -kernel "$DIR/linux-kernel" \
    -initrd "$DIR/initramfs.cpio.gz" \
    -append "HOST=x86_64 console=ttyS0 ${KARGS:-}"
