#!/bin/sh
# Restore saved SliTaz work (see "Save and restore" in the README) and start
# the SPICE clipboard agent. Run as root from inside the unpacked archive:
#   sh /root/slitaz-save/restore.sh
S=$(dirname "$(readlink -f "$0")")

# busybox wget gets "Connection reset by peer" from the HTTPS mirror:
# fall back to plain HTTP if the HTTPS mirror does not answer
M=/var/lib/tazpkg/mirror
if grep -q '^https:' $M && ! wget -q --spider "$(cat $M)bundle.tar.lzma"; then
	sed -i 's|^https:|http:|' $M
	tazpkg recharge
fi

# Kernel modules, cookutils and cooked packages
for f in $S/mods/*.tazpkg $S/packages/*.tazpkg; do
	tazpkg install "$f" --forced
done
depmod -a

# cookutils from the mirror if it was not in the archive
command -v cook >/dev/null || tazpkg get-install cookutils

# cook setup writes a default (i486) cook.conf, so run it first,
# then put the fixed x86_64 cook.conf in place
[ -d /home/slitaz/wok ] || cook setup
cp $S/config/cook.conf /etc/slitaz/cook.conf

mkdir -p /home/slitaz
cp -a $S/wok $S/src /home/slitaz/

cp $S/config/hostclip $S/config/toclip /usr/local/bin/
chmod +x /usr/local/bin/hostclip /usr/local/bin/toclip

# Openbox autostart: clipboard agent first
mkdir -p /home/tux/.config
cp -a $S/config/openbox /home/tux/.config/
A=/home/tux/.config/openbox/autostart.sh
grep -q spice-vdagent $A 2>/dev/null || echo 'spice-vdagent &' >> $A
chown -R tux /home/tux/.config/openbox


# Kernel modules and the SPICE agent daemon
for m in virtio_pci virtio_console uinput; do modprobe $m; done
[ -e /dev/uinput ] || mknod /dev/uinput c 10 223
mkdir -p /run/spice-vdagentd /var/run/spice-vdagentd
killall spice-vdagentd 2>/dev/null
spice-vdagentd

echo
echo "Done. Log out and back in (or, as tux: spice-vdagent &)."
