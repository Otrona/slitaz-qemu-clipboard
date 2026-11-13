#!/bin/sh
# Start SliTaz in QEMU with the SPICE agent channel (clipboard sharing).
#
#   ISO=path/to.iso ./start-slitaz.sh            live ISO
#   ISO=... DISK=slitaz.qcow2 ./start-slitaz.sh  also attach a virtual disk
#   TABLET=1 ...                                 seamless mouse (usb-tablet)
#
# Create a disk once with: qemu-img create -f qcow2 slitaz.qcow2 20G

ISO=${ISO:-slitaz-firefox-x86_64-cooking.iso}
MEM=${MEM:-4G}
CPUS=${CPUS:-4}

set -- \
	-enable-kvm -cpu host -smp "$CPUS" -m "$MEM" \
	-cdrom "$ISO" -boot d \
	-vga qxl \
	-device virtio-serial-pci \
	-chardev spicevmc,id=vdagent,name=vdagent \
	-device virtserialport,chardev=vdagent,name=com.redhat.spice.0 \
	-display spice-app

[ -n "$DISK" ] && set -- "$@" -drive file="$DISK",if=ide
[ -n "$TABLET" ] && set -- "$@" -device qemu-xhci -device usb-tablet

exec qemu-system-x86_64 "$@"
