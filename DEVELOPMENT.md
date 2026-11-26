# Developing kirkus for Apple Silicon

How kirkus for Apple Silicon is put together, for anyone changing it or building their own image. If
you just want to install and use it, see the [README](README.md).

This is the Apple Silicon port of [kirkus](https://github.com/goseahawk/kirkus). The desktop
(`overlay/installed`: theme, login screen, splash, About page, updates, firewall) is the same; what's
different is everything below it: Arch Linux ARM instead of Arch, the Asahi kernel and boot chain, a
disk image written from macOS instead of an ISO, and a setup window on the first start instead of an
installer.

## Project layout

| Path | What it is |
|---|---|
| `build.sh` | builds the install image on 64-bit ARM Linux |
| `build-docker.sh` | builds it anywhere else, in a container |
| `image/setup.sh` | runs inside the image while it's built: packages, GRUB, branding, services |
| `image/mirrorlist.asahi-alarm` | where the Asahi ALARM packages come from |
| `asahi/install.sh` | the script people run in macOS's Terminal; published with each release |
| `asahi/make-installer-data.py` | writes `installer_data.json` for the Asahi installer |
| `asahi/kirkus.icns` | the icon in the Mac's startup picker (`branding/tools/make-icns.py` makes it) |
| `apply-to-installed.sh` | updates an existing install to the current project |
| `overlay/installed/` | files in every installed system, including the first-start setup |
| `branding/` | the logo files and the tools that make every screen image from them |
| `site/` | the website, published to GitHub Pages by `.github/workflows/website.yml` |
| `.github/workflows/build-image.yml` | builds the image on GitHub's ARM servers and publishes a release |

## How a Mac starts kirkus

    Apple's boot picker → m1n1 (stage 1, written by the installer into kirkus's macOS-style stub)
      → m1n1 stage 2 + U-Boot + device trees   (EFI partition: m1n1/boot.bin)
      → GRUB                                    (EFI partition: EFI/BOOT/BOOTAA64.EFI)
      → linux-asahi + initramfs                 (root filesystem: /@/boot)

- The **Asahi installer**, run from macOS, shrinks macOS, makes three partitions (a small APFS stub
  that holds stage 1 and appears in the boot picker, a 500 MB EFI partition, and the root
  partition), copies the Mac's firmware into the EFI partition (`vendorfw/`), and writes kirkus's
  `root.img` and `esp/` files.
- `m1n1/boot.bin` is kept up to date by `update-m1n1` (from `asahi-scripts`), which pacman runs
  whenever m1n1, U-Boot or the kernel changes. It's built into the image at `/boot/efi/m1n1/` and
  copied to the EFI partition's tree by `build.sh`.
- **GRUB** can't be set up with `grub-install` in an image, so `image/setup.sh` builds it with
  `grub-mkimage` (as Asahi ALARM does): a small image that finds the root filesystem by UUID and
  reads its modules, theme and `grub.cfg` from `/@/boot/grub`. That image never changes after
  installing; GRUB package updates only change the menu tools.
- The initramfs starts with Asahi's `asahi` hook, which unpacks the Mac's firmware (Wi-Fi, Bluetooth
  and so on) from the EFI partition. Keep it first, right after `base`; `apply-to-installed.sh`
  refuses to rebuild the initramfs if it's missing.
- **Never write a Mac's EFI boot variables** and never touch the APFS stub from Linux. Choosing what
  starts is done with Startup Disk (Asahi's `startup-disk`, or macOS's) or the boot picker.

The UUIDs of the root filesystem (`984ab7e1-...`) and the EFI partition (`4B1D-2E5A`) are fixed in
`build.sh` and the same on every install, as with Asahi ALARM's images: the installer copies the
filesystems as they are, and GRUB, fstab and Timeshift rely on them. Two kirkus installs on one Mac
would clash; that's not supported.

## Building the image

- **On 64-bit ARM Linux:** `sudo ./build.sh`. Needs `bsdtar`, `arch-chroot` (arch-install-scripts),
  `btrfs-progs`, `zip`, `rsync`, `curl`, `python3` and loop devices. Ubuntu and Debian have all of
  them (`apt install libarchive-tools arch-install-scripts btrfs-progs zip rsync`), so the host
  doesn't need to be Arch.
- **Anywhere else:** `./build-docker.sh` does the same in a privileged Ubuntu container. Native on
  an Apple Silicon Mac (Docker Desktop, or Podman with a rootful machine); emulated, and slow, on
  Intel and AMD computers.
- **On GitHub:** Actions → **Build image** → Run workflow. It runs on `ubuntu-24.04-arm`, so nothing is
  emulated.

`KIRK_VERSION` sets the version (default: today's date), and `KIRK_REPO` the GitHub repository the
release will be published in (default `goseahawk/kirki`; it ends up in `installer_data.json` and
`install.sh`). Expect 30–90 minutes, and about 20 GB of free space.

What `build.sh` does:

1. Downloads the Arch Linux ARM root filesystem (`ArchLinuxARM-aarch64-latest.tar.gz`, checked
   against its `.md5`; reused for a week) and unpacks it.
2. Runs `image/setup.sh` inside it with `arch-chroot`. That adds the Asahi ALARM repository and its
   signing key, swaps the generic kernel for `linux-asahi` + `asahi-meta` + `asahi-desktop-meta`,
   installs the kirkus desktop, builds the GRUB image, writes fstab, installs `overlay/installed`,
   rebuilds the initramfs and enables the services. Packages in its `OPTIONAL` list (Timeshift,
   grub-btrfs, ufw, plasma-firewall, fastfetch) are skipped with a warning if Arch Linux ARM doesn't
   have them; everything else is required.
3. Makes `root.img`: Btrfs with the kirkus subvolumes `@`, `@home`, `@log` and `@cache`, written with
   zstd compression to keep the image small, then runs `grub-mkconfig` on it.
4. Zips `root.img`, the EFI partition files (`esp/`) and `kirkus.icns` into
   `out/kirkus-VERSION-asahi.zip`, and writes `installer_data.json`, `install.sh` and checksums.

**Size:** GitHub release files must be under 2 GiB, and the workflow stops if the zip is bigger.
The package list in `image/setup.sh` is where to make room.

## Installing: `install.sh` and the Asahi installer

`asahi/install.sh` is published with each release, so the install command always runs the newest
one. It:

1. downloads `installer_data.json` from the newest release,
2. downloads the image named in its `kirkus` block to `/tmp/kirkus-download` (resumable) and checks
   its SHA-256,
3. downloads the Asahi installer as Asahi ALARM publishes it (`asahi-alarm.org/latest`), and
4. starts it with `REPO_BASE` pointing at the local copy.

Why download first: the Asahi installer reads the zip over HTTP with range requests, and when it
follows a redirect it keeps only the path and drops the query string. GitHub's release downloads
redirect to signed URLs whose signature is in the query string, so the installer can't read them.
Giving it a local file avoids that, and means GitHub Releases is the only hosting kirkus needs.

`installer_data.json` follows the Asahi installer's format: one OS entry with a 500 MB EFI partition
(`copy_firmware`, `copy_installer_data`, files from `esp/`) and the root partition (`root.img`,
`expand`: it takes the rest of the space you give kirkus). The top-level `kirkus` block is ours;
the installer ignores it.

### Testing an image

Build it, then on an Apple Silicon Mac, from the folder with the `out/` files:

    KIRK_INSTALLER_DATA=file://$PWD/out/installer_data.json KIRK_PACKAGE=$PWD/out/kirkus-*-asahi.zip sh out/install.sh

Or publish a **draft** release from the workflow: drafts aren't "latest", so nobody else gets them.
Point `KIRK_INSTALLER_DATA` at the draft's `installer_data.json` (download it first; draft files need
you to be signed in).

## The first start

The image has no accounts (Arch Linux ARM's `alarm` account is removed and root is locked).
`kirk-setup.service` runs before the login screen (`Before=display-manager.service`) and shows
**Calamares** full screen in the `cage` compositor, configured in
`overlay/installed/usr/share/calamares-kirkus/`: welcome, language and time zone (suggested from
`ipapi.co`, as kirkus on PCs does), keyboard, and the account. It's the same approach and the same
Calamares package as Asahi ALARM's own first-boot setup, without its "choose a desktop" step.

- `kirk-setup` reads the Mac's keyboard type from the device tree (as Asahi does) and pre-selects the
  matching layout.
- When Calamares has made the account, `kirk-setup-finish` records the install date in
  `/etc/kirk-release`, locks root, writes `/var/lib/kirkus/setup-done` and disables the service. Then
  the login screen starts.
- If Calamares is closed or crashes before that, it's shown again (three times), and then at the
  next start. Weekly updates and release updates wait until setup is done.
- Logs: `journalctl -u kirk-setup`.

## Hardware detection

`kirk-detect` reads the device tree, since Apple Silicon Macs have no DMI tables:

| Variable | From |
|---|---|
| `KIRK_APPLE_SILICON` | `apple,arm-platform` in `/proc/device-tree/compatible` |
| `KIRK_MODEL` | `/proc/device-tree/model`, e.g. "Apple MacBook Air (M1, 2020)" |
| `KIRK_CHIP` | the `apple,tNNNN` entry, e.g. t8103 (M1), t8112 (M2), t6020 (M2 Pro) |
| `KIRK_LAPTOP` | a system battery in `/sys/class/power_supply` (Asahi calls it `macsmc-battery`) |

The battery and power checks (`kirk-about-battery`, `kirk-auto-update`, `kirk-touchpad-setup`) go by
a power supply's `type` rather than its name, so they work with Asahi's `macsmc-battery` and
`macsmc-ac`. Everything else Mac-specific (keyboard, Touch Bar, speakers, firmware) comes from the
Asahi packages; kirkus doesn't add its own fixes. `speakersafetyd` is enabled, since the speakers stay
off without it.

## Applying changes to an installed system

Get the project onto the Mac (`git clone https://github.com/goseahawk/kirki.git`, or `git pull`),
then from its folder:

    sudo ./apply-to-installed.sh

It installs the same files and settings as the image without reinstalling, takes a snapshot before
rebuilding the initramfs, and never touches the EFI partition. It refuses to run on anything but an
Apple Silicon Mac (`KIRK_FORCE=yes` overrides that), so a PC can't pick up this project by mistake.

## How updates work

The same as kirkus on PCs (see its DEVELOPMENT.md), with these differences:

- Weekly updates refresh `archlinuxarm-keyring` and `asahi-alarm-keyring` first, then `pacman -Su`.
  "Restart needed" is decided by whether `linux-asahi` changed.
- Releases come from `REPO=goseahawk/kirki` in `/etc/kirk-update.conf`.
- The pre-upgrade snapshot hook also covers `linux-asahi`, `m1n1`, `uboot-asahi`, `asahi-scripts` and
  `asahi-fwextract`.
- Arch's news is still what holds automatic updates back: Arch Linux ARM follows Arch.

## Versions and releases

Versions are the build date, `YY.MM.DD`, or `YY.MM.DD.N` for later builds the same day, as on kirkus
for PCs. Tag releases with the bare version. A release must contain every file in `out/`:
`install.sh`, `installer_data.json` and the zip with its checksum. The workflow does this.

Published releases reach every installed system after its next `pacman -Syu`, and new installs at
once (the install command follows "latest"). Test with a draft first.

## The website

`site/` is the website, at https://goseahawk.github.io/kirki/, made from kirkus's: plain HTML and
CSS, with DM Sans bundled (SIL Open Font License, `site/fonts/OFL.txt`) so nothing loads from other
sites. Instead of a download button it shows the install command with a Copy button. The command
never changes, since it always follows the latest release. `release.js` asks GitHub's API for the
latest release and shows its version, download size and date under it; if that fails, the plain
description stays. So publishing a release updates the website by itself.

Any change to `site/` on main is published by the **Website** workflow. One-time setup: Settings →
Pages → Source: **GitHub Actions**.

## Not yet confirmed on real hardware

Everything here has only been checked by syntax checks and by running the scripts against mock
commands and fake device trees. Not yet confirmed on a Mac: a complete image build, the install from
macOS, the first start (GRUB theme and splash under U-Boot, Plymouth, the setup window), and that
Arch Linux ARM has every package in the list.
