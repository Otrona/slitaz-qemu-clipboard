# SliTaz 5.1 (x86_64) in QEMU: host ⇄ guest clipboard

How to get copy and paste working between a Linux host and a SliTaz 5.1
guest running in QEMU, plus the VM setup fixes found along the way.
Since November 2026 `spice-vdagent` is an official SliTaz package
(`tazpkg get-install spice-vdagent`). This repo keeps the original receipts,
the notes on the kernel modules it needs, and a fallback that needs no agent
at all: a tiny HTTP clipboard bridge.

> **Korean input?** kime for SliTaz 5.1 lives in its own repo:
> [slitaz-kime](https://github.com/Otrona/slitaz-kime)
> (SliTaz 5.1용 kime 한글 입력기).

## Tested setup

| | |
|---|---|
| Host | Xubuntu 26.04 (X11), QEMU + KVM, SPICE viewer |
| Guest | SliTaz 5.1 cooking, x86_64 *firefox* ISO (built 10 Nov 2026), installed to a virtual disk |
| Guest kernel | 6.12.115-slitaz (`linux-lts`) |
| Guest toolchain | GCC 6.3.0, glibc 2.20, GLib 2.56.4, GTK3 3.22.30 |

## Repository layout

```
host/start-slitaz.sh        QEMU command line (SPICE agent channel, IDE disk)
host/svm.example            example launcher with ISO and disk on an external drive
host/vmclip.py              fallback clipboard: host side of the HTTP bridge
guest/spice-agent.sh        loads kernel modules and starts spice-vdagentd (root)
guest/hostclip, toclip      fallback clipboard: guest side of the HTTP bridge
guest/save.sh, restore.sh   save your work to an archive / restore it on a fresh system
wok/spice-protocol          receipt, spice-protocol 0.14.1
wok/spice-vdagent           receipt, spice-vdagent 0.20.0
wok/xsel                    receipt, xsel 1.2.1 (used by the fallback clipboard)
```

Copy a `wok/<package>` folder to `/home/slitaz/wok/` in the guest and run
`cook <package>`.

---

## 1. The VM

### 1.1 Start QEMU

```sh
qemu-img create -f qcow2 slitaz.qcow2 30G
ISO=slitaz-firefox-x86_64-cooking.iso DISK=slitaz.qcow2 MEM=8G CPUS=6 ./host/start-slitaz.sh
```

After installing SliTaz to the disk, boot it with `BOOT=c`.

- **The disk must be IDE, not virtio.** The ISO has no `virtio_pci` driver,
  so a virtio disk is invisible to the installer (only `sr0` shows in
  GParted), and an installed system on it could not find its root disk.
- **KVM matters most for speed.** `/dev/kvm` must exist on the host (enable
  SVM/VT-x in the firmware); inside the guest, `dmesg | grep -i hypervisor`
  should say `KVM`.
- **Graphics stay on fbdev.** SliTaz 5.1 ships no virtual GPU driver
  (`virtio-gpu`, `qxl` or `bochs`), so X uses the slow fbdev driver whatever
  `-vga` you pick, and the guest cannot follow the viewer's window size.

### 1.2 Install to the disk

1. Partition `/dev/sda` with GParted (msdos table, one ext4 partition).
   Graphical tools as root: `tazbox su gparted`, not `su -` (which loses the
   display: "cannot open display").
2. Run the installer (`tazbox su tazinst`): full install to `/dev/sda1`, GRUB
   on `/dev/sda`, BIOS.
3. `poweroff`, then start QEMU with `BOOT=c`.

### 1.3 After installing: network, cookutils

The installed system needed two things the live session had:

```sh
# Network: make sure DHCP is configured (and run it once now)
grep -E '^(INTERFACE|DHCP|STATIC)=' /etc/network.conf   # eth0 / yes / no
udhcpc -i eth0

# cookutils is not installed by tazinst
tazpkg get-install cookutils
cook setup
```


### 1.4 Fix cook.conf (x86_64)

`/etc/slitaz/cook.conf` on the x86_64 ISO (and the one `cook setup` writes)
still has i486 values. Every package that compiles C code fails with:

```
error: CPU you selected does not support x86-64 instruction set
configure: error: C compiler cannot create executables
```

Fix, as root, after every `cook setup`:

```sh
cp /etc/slitaz/cook.conf /etc/slitaz/cook.conf.bak
sed -i \
	-e 's/^ARCH="i486"/ARCH="x86_64"/' \
	-e 's/i486-slitaz-linux/x86_64-slitaz-linux/g' \
	-e 's/-march=i486/-march=x86-64 -mtune=generic/g' \
	/etc/slitaz/cook.conf
grep -c i486 /etc/slitaz/cook.conf    # must print 0
```

Header-only packages (like spice-protocol) cook fine even with the wrong
settings, because they never run the compiler. Don't let that mislead you.

Finished packages go to `/home/slitaz/packages`, build logs to
`/home/slitaz/log/<package>.log`, configure logs to
`/home/slitaz/wok/<package>/source/<package>-<version>/config.log`.

---

## 2. Clipboard with spice-vdagent

### 2.1 Install spice-vdagent (root)

spice-vdagent, spice-protocol and xsel are official SliTaz packages
(x86_64) since November 2026:

```sh
tazpkg get-install spice-vdagent
```

This also pulls in the kernel module packages of 2.2. To cook it yourself,
use the receipts in the SliTaz wok, or the originals in `wok/` here:
`cp -r wok/spice-protocol wok/spice-vdagent /home/slitaz/wok/`, then
`cook spice-protocol` and `cook spice-vdagent`.

Why these versions:

- **spice-vdagent 0.21 and newer need GLib ≥ 2.58.** SliTaz 5.1 has 2.56.4.
- **spice-vdagent 0.20.0** declares GLib 2.50 but uses one 2.58 macro,
  `G_SOURCE_FUNC`. The receipt replaces it with a plain cast (the same fix
  upstream and RHEL 8 applied).
- **spice-vdagent 0.20.0 needs spice-protocol ≥ 0.14.1.** 0.12.x fails at
  configure.
- 0.20.0 predates the security fixes of 0.21 (CVE-2020-25650 to 25653).
  Acceptable for an agent inside your own VM talking to your own QEMU.

### 2.2 Kernel modules (root)

The SliTaz kernel is split into module packages. The agent needs:

| Module | Package | Purpose |
|---|---|---|
| `virtio_pci` | `linux-lts-virt` | connects virtio devices to the PCI bus |
| `virtio_console` | `linux-lts-extra` | provides `/dev/virtio-ports/*` |
| `uinput` | already available | spice-vdagentd exits without `/dev/uinput` |

```sh
tazpkg info linux-lts-virt     # Version must equal `uname -r` (6.12.115)
tazpkg get-install linux-lts-virt
tazpkg get-install linux-lts-extra
depmod -a
```

- All `modprobe` commands must run as **root**; as a normal user they fail
  with `Operation not permitted`, which looks like a missing module.
- Install only `linux-lts-*` packages whose version matches `uname -r`.
  `linux-kvm` and `linux-libre-kvm` belong to other kernels.
- Do not upgrade `linux-lts` itself in a live session (see the 5.1 release
  notes): the running kernel comes from the ISO.

Check the SPICE port exists at the PCI level (no driver needed):

```sh
for d in /sys/bus/pci/devices/*; do
	[ "$(cat $d/vendor)" = 0x1af4 ] && echo "$d $(cat $d/device)"
done
# a line ending in 0x1003 (or 0x1043) = virtio serial device present
```

### 2.3 Start the agent

The package has an init script. To start the daemon at every boot, add
`spice-vdagentd` to `RUN_DAEMONS` in `/etc/rcS.conf`; to start it now:

```sh
/etc/init.d/spice-vdagentd start      # root
```

The session agent starts at login by itself (XDG autostart), so log out and
in once. Plain Ctrl+C / Ctrl+V then works in both directions.
`guest/spice-agent.sh` does the same as the init script, by hand.

**Mouse:** with the agent running, SPICE's client mouse mode gives a free
mouse (no Shift+F12). Before the agent starts (boot, login screen) click into
the window to grab the mouse. Do not add `-device usb-tablet`: it conflicts
with the agent. If the cursor jumps around, set the viewer to normal zoom and
turn off its automatic resize (fbdev cannot resize).

### 2.4 Alternative: HTTP clipboard bridge (no agent, no kernel modules)

Useful before spice-vdagent is built, or on a VM without the SPICE channel.
With QEMU's user networking the guest reaches the host at `10.0.2.2`, which
maps to the host's `127.0.0.1`.

**Host** (needs `python3` and `xclip`; `wl-clipboard` on Wayland):

```sh
python3 host/vmclip.py &      # listens on 127.0.0.1:8765 only
```

**Guest** (needs `xsel`, from `wok/xsel`, and `curl` for `toclip`):

```sh
cp guest/hostclip guest/toclip /usr/local/bin/
chmod +x /usr/local/bin/hostclip /usr/local/bin/toclip
```

| Command | Effect |
|---|---|
| `hostclip -c` | host clipboard → guest clipboard |
| `toclip -c` | guest clipboard → host clipboard |
| `hostclip > file` | write host clipboard straight to a file (works without xsel) |
| `cmd \| toclip` | send command output to the host clipboard |

Openbox hotkeys, inside `<keyboard>` of the Openbox config (find the file
with `cat /proc/$(pidof openbox)/cmdline | tr '\0' ' '`), then
`openbox --reconfigure`:

```xml
<keybind key="C-A-v">
  <action name="Execute"><command>hostclip -c</command></action>
</keybind>
<keybind key="C-A-c">
  <action name="Execute"><command>toclip -c</command></action>
</keybind>
```

---

## 3. Save and restore

The live system keeps everything in RAM, and the installed system empties
`/tmp` at boot. `guest/save.sh` (root) packs cooked packages, the kernel
module packages, cookutils, receipts, sources and config into
`/root/slitaz-save.tgz`. Move it between host and guest with netcat; nothing
stays listening, and `127.0.0.1` is not reachable from the network:

```sh
nc -l 127.0.0.1 9000 > ~/tmp/slitaz-save.tgz     # host: receive
nc 10.0.2.2 9000 < /root/slitaz-save.tgz         # guest: send

nc -l 127.0.0.1 9000 < ~/tmp/slitaz-save.tgz     # host: serve
nc 10.0.2.2 9000 > /root/s.tgz                   # guest: receive
tar xzf /root/s.tgz -C /root && sh /root/slitaz-save/restore.sh
```

Compare `md5sum` on both sides. If the guest's `nc` does not exit by itself,
press Ctrl+C once the host's `nc` has returned.

---

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `CPU you selected does not support x86-64` | i486 values in `cook.conf` | section 1.4 |
| `Command 'cook' not found` on the installed system | tazinst does not install cookutils | `tazpkg get-install cookutils` |
| GParted shows only `sr0` | virtio disk, no `virtio_pci` on the ISO | IDE disk (1.1) |
| `cannot open display` after `su -` | `su -` drops the X environment | `tazbox su <program>` |
| `unknown dep libpciaccess-dev` | SliTaz prefixes X.org libraries with `xorg-` | `xorg-libpciaccess-dev` |
| `Unknown initscript flavour no` | `--with-init-script=no` invalid in 0.20.0 | omit the option |
| `spice-protocol >= 0.14.1` required | spice-protocol 0.12.x installed | cook 0.14.1, install with `--forced` |
| `Module virtio_console not found` | module not installed | `linux-lts-extra` |
| no `/sys/bus/virtio` after loading `virtio_console` | `virtio_pci` missing | `linux-lts-virt` |
| `modprobe: ... Operation not permitted` | ran as a normal user | `su -`, then `modprobe` |
| agent: `connected` … `disconnected` right away | the daemon died; read its log | `spice-vdagentd -x -d` |
| daemon: `open /dev/uinput: No such file` / `Fatal uinput error` | `uinput` not loaded | `modprobe uinput` as root |
| xsel cook fails | missing build deps | autoconf, automake, libtool, `xorg-libXt-dev` |

Debug the agent in the foreground, in two terminals:

```sh
spice-vdagentd -x -d          # root
spice-vdagent  -x -d          # desktop user
```

## SliTaz 5.1 issues found (x86_64 cooking ISO, 10 Nov 2026)

For the SliTaz developers; details and workarounds are in the sections above.

1. `/etc/slitaz/cook.conf` has i486 values on x86_64 (also the one `cook setup` writes): every C package fails to configure.
2. On an installed system, busybox `wget` gets "Connection reset by peer" from `https://mirror.slitaz.org`, so tazpkg cannot install anything until the mirror is switched to HTTP.
3. `tazinst` does not install cookutils, although the live ISO has it.
4. The ISO has no `virtio_pci`: virtio disks are invisible, and `linux-lts-virt` is needed for any virtio device.
5. No virtual GPU driver (`virtio-gpu`, `qxl`, `bochs`) in any kernel package: under QEMU/KVM X always falls back to fbdev.
6. No `spice-vdagent` package (receipts in this repo).
7. Cook's strip step breaks Rust's `librustc_driver`, and busybox `unxz` fails on Rust's official `.tar.xz` (see [slitaz-kime](https://github.com/Otrona/slitaz-kime)).

## License

The scripts and receipts in this repository are licensed under GPL-3.0 (see [LICENSE](LICENSE)).
