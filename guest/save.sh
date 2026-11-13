#!/bin/sh
# Collect cooked packages, kernel module packages, receipts, sources and
# config into /root/slitaz-save.tgz. Run as root. Restore with restore.sh.
S=/root/slitaz-save
mkdir -p $S/packages $S/mods $S/wok $S/config

# Packages cooked in this wok
cp /home/slitaz/packages/*.tazpkg $S/packages/

# Mirror packages needed again on a fresh system
cd $S/mods
for p in linux-lts-extra linux-lts-virt cookutils; do
	ls $p-*.tazpkg >/dev/null 2>&1 || tazpkg get $p
done

# Receipts, plus stuff/ folders (e.g. the fonts for fonts-kr)
for d in /home/slitaz/wok/*/; do
	p=$(basename $d)
	mkdir -p $S/wok/$p
	cp $d/receipt $S/wok/$p/
	[ -d $d/stuff ] && cp -a $d/stuff $S/wok/$p/
done

# Source tarballs, except the 380 MB Rust one (easy to download again)
mkdir -p $S/src
for f in /home/slitaz/src/*; do
	case $(basename $f) in rust-*) ;; *) cp -a $f $S/src/ ;; esac
done

# Config and scripts
cp /etc/slitaz/cook.conf $S/config/
cp /usr/local/bin/hostclip /usr/local/bin/toclip $S/config/ 2>/dev/null
cp -a /home/tux/.config/openbox $S/config/
cp /etc/init.d/local.sh $S/config/ 2>/dev/null
R=$(dirname "$(readlink -f "$0")")/restore.sh
[ -f "$R" ] && cp "$R" $S/

tazpkg list > $S/installed-packages.txt

cd /root && tar czf slitaz-save.tgz slitaz-save
ls -lh /root/slitaz-save.tgz
md5sum /root/slitaz-save.tgz
