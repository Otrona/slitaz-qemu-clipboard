# SliTaz 5.1 (x86_64) in QEMU: host ⇄ guest clipboard

How to get copy and paste working between a Linux host and a SliTaz 5.1
guest running in QEMU. SliTaz does not ship `spice-vdagent`, so this repo
contains the receipts to cook it, the kernel modules it needs, and the
fixes for every error hit along the way.

It also includes a fallback that needs no agent at all: a tiny HTTP
clipboard bridge between host and guest.

## Tested setup

| | |
|---|---|
| Host | Xubuntu 26.04 (X11), QEMU with a SPICE viewer |
| Guest | SliTaz 5.1 cooking, x86_64 *firefox* ISO (built 10 Nov 2026) |
| Guest kernel | 6.12.115-slitaz (`linux-lts`) |
| Guest toolchain | GCC 6.3.0, glibc 2.20, GLib 2.56.4, GTK3 3.22.30 |

## Repository layout

```
host/start-slitaz.sh        QEMU command line with the SPICE agent channel
host/vmclip.py              fallback: host side of the HTTP clipboard bridge
guest/spice-agent.sh        loads kernel modules and starts spice-vdagentd (root)
guest/hostclip, toclip      fallback: guest side of the HTTP clipboard bridge
wok/spice-protocol/receipt  SliTaz receipt, spice-protocol 0.14.1
wok/spice-vdagent/receipt   SliTaz receipt, spice-vdagent 0.20.0
wok/xsel/receipt            SliTaz receipt, xsel 1.2.1 (needed by the fallback)
```

---

## 1. Start the VM (host)

```sh
ISO=~/Downloads/slitaz-firefox-x86_64-cooking.iso ./host/start-slitaz.sh
```

The lines that matter for the clipboard are the virtio serial port and
the SPICE agent channel:

```
-device virtio-serial-pci
-chardev spicevmc,id=vdagent,name=vdagent
-device virtserialport,chardev=vdagent,name=com.redhat.spice.0
```

The viewer (`-display spice-app`) needs `virt-viewer` on the host.

## 2. Fix cook.conf on x86_64 (guest)

On the x86_64 cooking ISO, `/etc/slitaz/cook.conf` still had i486 values.
Every package that compiles C code fails with:

```
error: CPU you selected does not support x86-64 instruction set
configure: error: C compiler cannot create executables
```

Fix (as root):

```sh
cp /etc/slitaz/cook.conf /etc/slitaz/cook.conf.bak
sed -i \
	-e 's/^ARCH="i486"/ARCH="x86_64"/' \
	-e 's/i486-slitaz-linux/x86_64-slitaz-linux/g' \
	-e 's/-march=i486/-march=x86-64 -mtune=generic/g' \
	/etc/slitaz/cook.conf
grep -n i486 /etc/slitaz/cook.conf    # should print nothing
```

Header-only packages (like spice-protocol) cook fine even with the wrong
settings, because they never run the compiler. Don't let that mislead you.

## 3. Cook spice-protocol and spice-vdagent (guest, root)

```sh
cook setup                                   # once, if /home/slitaz does not exist
cp -r wok/spice-protocol wok/spice-vdagent /home/slitaz/wok/

cook spice-protocol
tazpkg install /home/slitaz/packages/spice-protocol-*.tazpkg --forced
pkg-config --modversion spice-protocol      # 0.14.1

cook spice-vdagent
tazpkg install /home/slitaz/packages/spice-vdagent-*.tazpkg
```

Finished packages go to the `PKGS=` path in `cook.conf`
(`/home/slitaz/packages` by default). Build logs are in
`/home/slitaz/log/<package>.log`.

### Why these versions

- **spice-vdagent 0.21 and newer need GLib ≥ 2.58.** SliTaz 5.1 has 2.56.4.
- **spice-vdagent 0.20.0** declares GLib 2.50 but uses one 2.58 macro,
  `G_SOURCE_FUNC`. The receipt replaces it with a plain cast (the same fix
  upstream and RHEL 8 applied).
- **spice-vdagent 0.20.0 needs spice-protocol ≥ 0.14.1.** 0.12.x fails at
  configure.
- 0.20.0 predates the security fixes of 0.21 (CVE-2020-25650 to 25653).
  Acceptable for an agent inside your own VM talking to your own QEMU.

## 4. Kernel modules (guest, root)

The SliTaz kernel is split into module packages. The agent needs three
drivers:

| Module | Package | Purpose |
|---|---|---|
| `virtio_pci` | `linux-lts-virt` | connects virtio devices to the PCI bus |
| `virtio_console` | `linux-lts-extra` | provides `/dev/virtio-ports/*` |
| `uinput` | already available (no extra package needed) | spice-vdagentd exits without `/dev/uinput` |

All `modprobe` commands must run as **root**. As a normal user they fail
with `Operation not permitted`, which is easy to mistake for a missing
module.

```sh
tazpkg info linux-lts-virt     # Version must equal `uname -r` (6.12.115)
tazpkg get-install linux-lts-virt
tazpkg get-install linux-lts-extra
depmod -a
```

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

## 5. Start the agent

As root:

```sh
sh guest/spice-agent.sh
```

As the desktop user (tux), inside the X session:

```sh
spice-vdagent &
```

Plain Ctrl+C / Ctrl+V now works in both directions.

To make it permanent: add `sh /path/to/spice-agent.sh` to
`/etc/init.d/local.sh`, and `spice-vdagent &` to the user's Openbox
autostart (`~/.config/openbox/autostart.sh`).

## 6. Troubleshooting (errors met and their fixes)

| Error | Cause | Fix |
|---|---|---|
| `CPU you selected does not support x86-64` | i486 values in `cook.conf` | section 2 |
| `unknown dep libpciaccess-dev` | SliTaz prefixes X.org libraries with `xorg-` | use `xorg-libpciaccess-dev` |
| `Unknown initscript flavour no` | `--with-init-script=no` is not valid in 0.20.0 | omit the option (default `check`) |
| `spice-protocol >= 0.14.1` required | spice-protocol 0.12.x installed | cook 0.14.1, install with `--forced` |
| `Module virtio_console not found` | module not installed | `linux-lts-extra` |
| no `/sys/bus/virtio` after loading `virtio_console` | `virtio_pci` missing | `linux-lts-virt` |
| agent: `connected` … `disconnected` right away | daemon died; read the daemon log | run `spice-vdagentd -x -d` |
| daemon: `open /dev/uinput: No such file` / `Fatal uinput error` | `uinput` not loaded | `modprobe uinput` as root (or `mknod /dev/uinput c 10 223`) |
| `modprobe: ... Operation not permitted` | ran as a normal user | `su -`, then `modprobe` |

Debug both halves in the foreground, in two terminals:

```sh
spice-vdagentd -x -d          # root
spice-vdagent  -x -d          # desktop user
```

---

## Alternative: HTTP clipboard bridge (no agent, no kernel modules)

Useful before spice-vdagent is built, or on a VM started without the SPICE
channel. With QEMU's default user-mode networking, the guest reaches the
host at `10.0.2.2`.

**Host** (needs `python3` and `xclip`; `wl-clipboard` on Wayland):

```sh
sudo apt install xclip
python3 host/vmclip.py &
```

The server listens on `127.0.0.1:8765` only; QEMU's user networking still
lets the guest in.

**Guest** (needs `xsel`; cook it from `wok/xsel`):

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

Hotkeys, inside `<keyboard>` of the Openbox config (find the file with
`cat /proc/$(pidof openbox)/cmdline | tr '\0' ' '`):

```xml
<keybind key="C-A-v">
  <action name="Execute"><command>hostclip -c</command></action>
</keybind>
<keybind key="C-A-c">
  <action name="Execute"><command>toclip -c</command></action>
</keybind>
```

Then `openbox --reconfigure`.

`hostclip > /home/slitaz/wok/<pkg>/receipt` is the most reliable way to
move receipts into the guest: text arrives byte for byte, with no curly
quotes or dashes from copy and paste.

---

## Notes

- **Live sessions forget everything on reboot.** Install SliTaz to a
  virtual disk (`qemu-img create -f qcow2 slitaz.qcow2 20G` and
  `-drive file=slitaz.qcow2,if=ide`), or save `/home/slitaz/wok`,
  `/home/slitaz/packages` and `/etc/slitaz/cook.conf` to the host first.
- **Seamless mouse (no Shift+F12 release):** add
  `-device qemu-xhci -device usb-tablet` to the QEMU line.
  Not yet tested on this setup.
