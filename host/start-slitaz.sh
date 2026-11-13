#!/bin/sh
# Start SliTaz in QEMU with the SPICE agent channel (clipboard sharing).
#
#   ISO=path/to.iso ./start-slitaz.sh                 live ISO
#   ISO=... DISK=slitaz.qcow2 ./start-slitaz.sh       ISO + virtual disk
#   ... BOOT=c ./start-slitaz.sh                      boot the installed disk
#
# Create a disk once with: qemu-img create -f qcow2 slitaz.qcow2 30G
#
# The disk is IDE, not virtio: the SliTaz ISO has no virtio_pci driver, so a
# virtio disk is invisible to the installer and the installed system could
# not find its root disk at boot.
#
# No usb-tablet: it conflicts with spice-vdagent's mouse mode.

ISO=${ISO:-slitaz-firefox-x86_64-cooking.iso}
MEM=${MEM:-4G}
CPUS=${CPUS:-4}
BOOT=${BOOT:-d}

set -- \
	-enable-kvm -cpu host -smp "$CPUS" -m "$MEM" \
	-cdrom "$ISO" -boot "$BOOT" \
	-vga qxl \
	-device virtio-serial-pci \
	-chardev spicevmc,id=vdagent,name=vdagent \
	-device virtserialport,chardev=vdagent,name=com.redhat.spice.0 \
	-display spice-app

[ -n "$DISK" ] && set -- "$@" -drive file="$DISK",if=ide

exec qemu-system-x86_64 "$@"
