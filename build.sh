#!/usr/bin/env bash
# Builds the kirki for Apple Silicon install image: a zip the Asahi installer writes onto a Mac.
#
#     sudo ./build.sh
#
# Run it on 64-bit ARM Linux (an Apple Silicon Mac running Asahi, a Linux VM or container on an
# Apple Silicon Mac, an ARM cloud machine, or GitHub's ubuntu-24.04-arm runners). On any other
# computer, use ./build-docker.sh. It needs: bsdtar, arch-chroot (arch-install-scripts), btrfs-progs,
# zip, rsync, curl, python3 and loop devices.
#
# Settings (environment):
#   KIRK_VERSION   the version, YY.MM.DD or YY.MM.DD.N (default: today's date)
#   KIRK_REPO      the GitHub repository releases are published from (default goseahawk/kirki); it
#                  goes into installer_data.json and install.sh, which download from its releases
#
# Output, in out/:
#   kirki-VERSION-asahi.zip   the image: root.img (Btrfs), esp/ (EFI partition files), kirki.icns
#   installer_data.json        tells the Asahi installer how to install it
#   install.sh                 the command people run in macOS's Terminal
#   *.sha256                   checksums
set -euo pipefail
[[ $EUID -eq 0 ]] || exec sudo KIRK_VERSION="${KIRK_VERSION:-}" KIRK_REPO="${KIRK_REPO:-}" "$0" "$@"

VERSION=${KIRK_VERSION:-$(date +%y.%m.%d)}
[[ $VERSION =~ ^[0-9]{2}\.[0-9]{2}\.[0-9]{2}(\.[0-9]+)?$ ]] || { echo "Bad version '$VERSION': use YY.MM.DD or YY.MM.DD.N, e.g. 26.11.18 or 26.11.18.1"; exit 1; }
REPO=${KIRK_REPO:-goseahawk/kirki}
[[ $REPO =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo "Bad repository '$REPO': use owner/name"; exit 1; }
echo "Building kirki $VERSION for Apple Silicon (releases from github.com/$REPO)"

HERE=$(cd "$(dirname "$0")" && pwd)
WORK=$HERE/build
DL=$WORK/dl
ROOT=$WORK/root
IMG=$WORK/img
STAGE=$WORK/stage
OUT=$HERE/out
NAME=kirki-$VERSION-asahi
# Fixed per image, as Asahi ALARM's are: the installer copies the filesystems as they are.
ROOT_UUID=984ab7e1-a547-43b4-949b-dda0fb90a8e5
EFI_UUID=4B1D-2E5A
BASE_URL=https://archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz

# ---------------------------------------------------------------------------------------- checks
case $(uname -m) in
  aarch64|arm64) ;;
  *) if [[ ! -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ]]; then
       echo "This computer is $(uname -m), and the image is 64-bit ARM. Use ./build-docker.sh, or install"
       echo "qemu-user-static with binfmt support to build under emulation (very slow)."
       exit 1
     fi
     echo "Not an ARM computer: building under qemu emulation. Expect several hours." ;;
esac
missing=()
for c in bsdtar arch-chroot mkfs.btrfs btrfs zip rsync curl python3 losetup; do
  command -v "$c" >/dev/null || missing+=("$c")
done
if ((${#missing[@]})); then
  echo "Missing tools: ${missing[*]}"
  echo "  Debian/Ubuntu: apt install libarchive-tools arch-install-scripts btrfs-progs zip rsync curl python3"
  echo "  Arch:          pacman -S libarchive arch-install-scripts btrfs-progs zip rsync curl python"
  exit 1
fi

# Never leave anything mounted, whatever happens. The body is a subshell, so its "set +e" stays in
# here: in a normal function it would turn error checking off for the rest of the build.
cleanup() (
  set +e
  for m in "$IMG" "$ROOT"; do
    while grep -q " ${m}[/ ]" /proc/mounts 2>/dev/null; do
      awk -v m="$m" '$2 == m || index($2, m "/") == 1 {print $2}' /proc/mounts | sort -r | xargs -r umount -l
      sleep 0.2
    done
  done
)
trap 'cleanup; [[ -n ${loopdev-} ]] && losetup -d "$loopdev" 2>/dev/null; true' EXIT

# ---------------------------------------------------------------------------------------- base
cleanup
rm -rf "$ROOT" "$IMG" "$STAGE"
mkdir -p "$DL" "$ROOT" "$IMG" "$STAGE" "$OUT"
if [[ ! -s $DL/base.tar.gz ]] || [[ -n $(find "$DL/base.tar.gz" -mtime +6 2>/dev/null) ]]; then
  echo "== Downloading Arch Linux ARM =="
  curl -fL --retry 3 -o "$DL/base.tar.gz.part" "$BASE_URL"
  curl -fsSL --retry 3 -o "$DL/base.tar.gz.md5" "$BASE_URL.md5"
  (cd "$DL" && [[ $(md5sum < base.tar.gz.part | cut -d' ' -f1) == "$(cut -d' ' -f1 base.tar.gz.md5)" ]]) \
    || { echo "The Arch Linux ARM download is damaged (checksum mismatch). Run again."; exit 1; }
  mv "$DL/base.tar.gz.part" "$DL/base.tar.gz"
fi
echo "== Unpacking =="
bsdtar -xpf "$DL/base.tar.gz" -C "$ROOT"
# arch-chroot wants the new root to be a mount point
mount --bind "$ROOT" "$ROOT"
mkdir -p "$ROOT/kirk-src"
cp -r "$HERE/overlay" "$HERE/image" "$ROOT/kirk-src/"

# ---------------------------------------------------------------------------------------- set up
echo "== Setting up kirki in the image (this is the long part) =="
arch-chroot "$ROOT" env VERSION="$VERSION" ROOT_UUID="$ROOT_UUID" EFI_UUID="$EFI_UUID" \
  /bin/bash /kirk-src/image/setup.sh
# setup.sh leaves this as its very last step: anything less is a failed setup, whatever the exit status
[[ -e $ROOT/kirk-src/setup-complete ]] || { echo "Setting up the image didn't finish (see the errors above)."; exit 1; }
rm -rf "$ROOT/kirk-src"
cleanup

# ---------------------------------------------------------------------------------------- root.img
echo "== Making the root filesystem =="
size=$(du -B M -s -x "$ROOT" | cut -dM -f1)
size=$((size + size / 8 + 512))       # room for the first start; it grows to fill its partition then
echo "Contents: $(du -sh -x "$ROOT" | cut -f1); image: ${size} MiB"
truncate -s "${size}M" "$STAGE/root.img"     # whole MiB, so a multiple of 4 KiB, as the installer needs
mkfs.btrfs -q -U "$ROOT_UUID" -L kirki "$STAGE/root.img"
mount -o loop "$STAGE/root.img" "$IMG"
for sv in @ @home @log @cache; do btrfs subvolume create "$IMG/$sv" >/dev/null; done
umount "$IMG"
# Mounted the way the installed system mounts it, so each part lands in its own subvolume.
# zstd:9 here only makes the image smaller; the installed system writes with zstd:1.
O=compress=zstd:9,noatime
# One loop device for all four: a second one on the same file would look like a duplicate filesystem.
loopdev=$(losetup --find --show "$STAGE/root.img")
mount -o "$O,subvol=@" "$loopdev" "$IMG"
mkdir -p "$IMG/home" "$IMG/var/log" "$IMG/var/cache/pacman/pkg"
mount -o "$O,subvol=@home" "$loopdev" "$IMG/home"
mount -o "$O,subvol=@log" "$loopdev" "$IMG/var/log"
mount -o "$O,subvol=@cache" "$loopdev" "$IMG/var/cache/pacman/pkg"
rsync -aHAX --info=stats1 --exclude '/boot/efi/*' "$ROOT/" "$IMG/"
mkdir -p "$IMG/boot/efi"

echo "== Boot menu =="
# Generated on the mounted image, so GRUB finds the root filesystem by the UUID the Mac will have.
if ! arch-chroot "$IMG" grub-mkconfig -o /boot/grub/grub.cfg; then
  echo "grub-mkconfig failed; trying again without the snapshots submenu"
  chmod -x "$IMG/etc/grub.d/41_snapshots-btrfs" 2>/dev/null || true
  arch-chroot "$IMG" grub-mkconfig -o /boot/grub/grub.cfg
  chmod +x "$IMG/etc/grub.d/41_snapshots-btrfs" 2>/dev/null || true
fi
grep -q "vmlinuz-linux-asahi" "$IMG/boot/grub/grub.cfg" || { echo "grub.cfg has no kirki entry."; exit 1; }
cleanup
losetup -d "$loopdev"

# ---------------------------------------------------------------------------------------- package
echo "== EFI partition =="
mkdir -p "$STAGE/esp/EFI/BOOT"
cp "$ROOT/boot/grub/arm64-efi/core.efi" "$STAGE/esp/EFI/BOOT/BOOTAA64.EFI"
[[ -f $ROOT/boot/efi/m1n1/boot.bin ]] || { echo "No m1n1/boot.bin: update-m1n1 didn't run in the image."; exit 1; }
cp -r "$ROOT/boot/efi/m1n1" "$STAGE/esp/"
cp "$HERE/asahi/kirki.icns" "$STAGE/kirki.icns"

echo "== Compressing (several minutes) =="
rm -f "$OUT/$NAME.zip"
(cd "$STAGE" && zip -q -r "$OUT/$NAME.zip" root.img esp kirki.icns)
zip_size=$(stat -c %s "$OUT/$NAME.zip")
(cd "$OUT" && sha256sum "$NAME.zip" > "$NAME.zip.sha256")
sha=$(cut -d' ' -f1 "$OUT/$NAME.zip.sha256")

python3 "$HERE/asahi/make-installer-data.py" \
  --version "$VERSION" --repo "$REPO" --package "$NAME.zip" --sha256 "$sha" --package-size "$zip_size" \
  --root-size "$(stat -c %s "$STAGE/root.img")" --efi-uuid "$EFI_UUID" > "$OUT/installer_data.json"
sed "s|^REPO=.*|REPO=$REPO|" "$HERE/asahi/install.sh" > "$OUT/install.sh"
chmod 644 "$OUT"/*
rm -rf "$STAGE" "$ROOT"

echo
echo "Done: kirki $VERSION for Apple Silicon is in $OUT/"
ls -l "$OUT"
if ((zip_size >= 2 * 1024 * 1024 * 1024)); then
  echo
  echo "WARNING: $NAME.zip is 2 GiB or larger, over GitHub's limit for a release file."
fi
echo
echo "To publish: make a GitHub release tagged $VERSION in $REPO with every file in out/."
echo "To install it from a local copy, see DEVELOPMENT.md, \"Testing an image\"."
