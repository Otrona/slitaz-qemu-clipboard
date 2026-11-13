#!/bin/sh
# Load the kernel modules spice-vdagentd needs, then start it. Run as root.
# Modules come from linux-lts-virt (virtio_pci) and linux-lts-extra
# (virtio_console); see README section 4.

for m in virtio_pci virtio_console uinput; do
	modprobe "$m" 2>/dev/null || echo "warning: could not load $m (built in or missing)" >&2
done

# spice-vdagentd exits with "Fatal uinput error" without this node
[ -e /dev/uinput ] || mknod /dev/uinput c 10 223

# This build uses /var/run; on SliTaz that may differ from /run
mkdir -p /run/spice-vdagentd /var/run/spice-vdagentd

if [ ! -e /dev/virtio-ports/com.redhat.spice.0 ]; then
	echo "No /dev/virtio-ports/com.redhat.spice.0." >&2
	echo "Was QEMU started with the SPICE agent channel (host/start-slitaz.sh)?" >&2
	exit 1
fi

killall spice-vdagentd 2>/dev/null
spice-vdagentd
