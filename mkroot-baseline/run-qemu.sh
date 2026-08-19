DIR="$(dirname $0)"; qemu-system-x86_64 -m 256 "$@" -nographic -no-reboot -kernel "$DIR"/linux-kernel -initrd "$DIR"/initramfs.cpio.gz -append "HOST=x86_64 console=ttyS0 $KARGS"
echo -e '\e[?7h'
