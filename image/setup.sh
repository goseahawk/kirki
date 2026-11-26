#!/bin/bash
# Turns an Arch Linux ARM root filesystem into kirki for Apple Silicon. Runs INSIDE the image's
# chroot, started by build.sh, which sets:
#   VERSION     kirki version, YY.MM.DD
#   ROOT_UUID   the root filesystem's UUID (fixed per image; the Asahi installer copies it as is)
#   EFI_UUID    the EFI partition's FAT volume ID, as XXXX-XXXX
# and copies the project to /kirk-src (left out of the finished image).
#
# What it does, in the order the Asahi ALARM image builder (asahi-alarm/asahi-alarm-builder) does it:
# Asahi ALARM repository and kernel, Apple Silicon support, GRUB as an EFI image for U-Boot; then the
# kirki desktop, branding, services and the first-start setup.
set -euo pipefail
: "${VERSION:?}" "${ROOT_UUID:?}" "${EFI_UUID:?}"
SRC=/kirk-src
BRAND="kirki $VERSION"
say() { echo; echo "### $*"; }

# ------------------------------------------------------------------------------------- pacman
say "pacman: Asahi ALARM repository and keys"
sed -i -e 's/^#\?ParallelDownloads.*/ParallelDownloads = 5/' /etc/pacman.conf
grep -q '^\[asahi-alarm\]' /etc/pacman.conf ||
  sed -i -e '/^\[core\]/i [asahi-alarm]\nInclude = /etc/pacman.d/mirrorlist.asahi-alarm\n' /etc/pacman.conf
install -m644 "$SRC/image/mirrorlist.asahi-alarm" /etc/pacman.d/mirrorlist.asahi-alarm
# pacman downloads as the 'alpm' user, which has to exist first
systemd-sysusers
pacman-key --init
pacman-key --populate archlinuxarm
# The Asahi ALARM signing key isn't known yet, so its keyring package is the one thing installed
# without a signature check (over HTTPS, from Asahi ALARM's GitHub releases). Every package after it
# is checked against the keys it brings.
sed -e '/^\[asahi-alarm\]/a SigLevel = Never' /etc/pacman.conf > /tmp/pacman-keyring.conf
pacman --config /tmp/pacman-keyring.conf -Sy --noconfirm asahi-alarm-keyring
rm -f /tmp/pacman-keyring.conf
pacman-key --populate asahi-alarm

# ------------------------------------------------------------------------------------- base
say "Base system and the Asahi kernel"
# where update-m1n1 puts m1n1 + U-Boot + device trees; build.sh copies it to the EFI partition
mkdir -p /boot/efi/EFI/BOOT /boot/efi/m1n1
touch /boot/efi/.builder
# Arch Linux ARM's generic kernel doesn't run on Apple Silicon
pacman -Q linux-aarch64 >/dev/null 2>&1 && pacman -Rdd --noconfirm linux-aarch64
pacman -Syu --noconfirm

# Required: without any of these there's no point carrying on.
PKGS=(
  # Apple Silicon (as Asahi ALARM's own desktop image)
  linux-asahi asahi-meta asahi-desktop-meta asahi-scripts asahi-fwextract m1n1 uboot-asahi
  mkinitcpio grub btrfs-progs
  # the desktop (kirkus's package set for PCs, minus the PC-only drivers)
  base-devel git sudo nano vim man-db cronie
  networkmanager wpa_supplicant
  pipewire pipewire-alsa pipewire-pulse wireplumber
  plasma-desktop plasma-nm plasma-pa powerdevil bluedevil kscreen kwallet-pam
  kde-gtk-config breeze-gtk sddm sddm-kcm xdg-desktop-portal-kde xdg-user-dirs
  konsole dolphin kate ark gwenview okular spectacle
  power-profiles-daemon upower zram-generator bluez bluez-utils
  firefox noto-fonts noto-fonts-emoji
  kinfocenter discover flatpak kdialog xf86-input-libinput plymouth
  # the first-start setup
  calamares cage xorg-server-xwayland
)
# Wanted, but kirki still works without them: a missing one is reported and skipped, so a package
# that Arch Linux ARM hasn't built (yet) for aarch64 doesn't stop the build.
OPTIONAL=(fastfetch ufw plasma-firewall timeshift grub-btrfs inotify-tools)

say "Installing kirki packages"
pacman -S --needed --noconfirm "${PKGS[@]}"
MISSING=()
for p in "${OPTIONAL[@]}"; do
  pacman -S --needed --noconfirm "$p" || MISSING+=("$p")
done
((${#MISSING[@]} == 0)) || echo "WARNING: not available, left out: ${MISSING[*]}"

# ------------------------------------------------------------------------------------- GRUB
say "GRUB (started by U-Boot from the EFI partition)"
# GRUB can't be installed the usual way here (grub-install wants a mounted, real EFI partition), so
# build a GRUB image that finds the root filesystem by UUID and reads everything else from
# /@/boot/grub. build.sh copies it to EFI/BOOT/BOOTAA64.EFI, where U-Boot looks.
cat > /tmp/grub-core.cfg <<EOF
search.fs_uuid $ROOT_UUID root
set prefix=(\$root)'/@/boot/grub'
EOF
sed -i '/efi_uga/d' /etc/grub.d/00_header           # no such module on arm64
rm -f /etc/grub.d/30_uefi-firmware                   # broken under U-Boot
mkdir -p /boot/grub/fonts /boot/grub/locale
touch /boot/grub/device.map
dd if=/dev/zero of=/boot/grub/grubenv bs=1024 count=1 status=none
rm -rf /boot/grub/arm64-efi
cp -r /usr/lib/grub/arm64-efi /boot/grub/
rm -f /boot/grub/arm64-efi/*.module
cp /usr/share/grub/unicode.pf2 /boot/grub/fonts/
for i in /usr/share/locale/*/LC_MESSAGES/grub.mo; do
  [[ -f $i ]] && cp "$i" "/boot/grub/locale/$(echo "$i" | cut -d/ -f5).mo"
done
grub-mkimage --directory /usr/lib/grub/arm64-efi -c /tmp/grub-core.cfg --prefix /boot/grub \
  --output /boot/grub/arm64-efi/core.efi --format arm64-efi --compression auto \
  ext2 part_gpt search btrfs
rm -f /tmp/grub-core.cfg

# ------------------------------------------------------------------------------------- fstab
say "fstab"
# The kirki Btrfs layout: @ (/), @home, and @log and @cache kept out of snapshots. The root
# filesystem is grown to fill its partition on the first start (x-systemd.growfs). No subvolid:
# Timeshift restores replace @.
O=noatime,compress=zstd:1,space_cache=v2,discard=async
cat > /etc/fstab <<EOF
# kirki for Apple Silicon
UUID=$ROOT_UUID  /                      btrfs  $O,subvol=@,x-systemd.growfs  0 0
UUID=$ROOT_UUID  /home                  btrfs  $O,subvol=@home      0 0
UUID=$ROOT_UUID  /var/log               btrfs  $O,subvol=@log       0 0
UUID=$ROOT_UUID  /var/cache/pacman/pkg  btrfs  $O,subvol=@cache     0 0
UUID=$EFI_UUID   /boot/efi  vfat  rw,relatime,fmask=0022,dmask=0022,codepage=437,iocharset=iso8859-1,shortname=mixed,errors=remount-ro  0 2
EOF

# ------------------------------------------------------------------------------------- accounts
say "Accounts"
# Arch Linux ARM ships an 'alarm' account (password alarm) and root with password root.
userdel -r alarm 2>/dev/null || true
passwd -l root >/dev/null
# systemd-firstboot would stop the first start to ask questions; the kirki setup asks them instead
mkdir -p /etc/systemd/system/systemd-firstboot.service.d
cat > /etc/systemd/system/systemd-firstboot.service.d/no-prompt.conf <<'EOF'
[Service]
ExecStart=
ExecStart=systemd-firstboot
EOF
# a working language until setup sets yours
sed -i 's/^#\(en_US.UTF-8 UTF-8\)/\1/' /etc/locale.gen
locale-gen
echo LANG=en_US.UTF-8 > /etc/locale.conf
echo kirki > /etc/hostname

# ------------------------------------------------------------------------------------- kirki
say "kirki files"
# File by file, owned by root: programs (usr/local/bin, etc/grub.d) 755, everything else 644. The
# same rule as apply-to-installed.sh, so an update installs exactly what a fresh image has.
(cd "$SRC/overlay/installed" && find . -type f -printf '%P\0') |
  while IFS= read -r -d '' rel; do
    case $rel in usr/local/bin/*|etc/grub.d/*) mode=755 ;; *) mode=644 ;; esac
    install -D -o root -g root -m "$mode" "$SRC/overlay/installed/$rel" "/$rel"
  done
cat > /etc/kirk-release <<EOF
VERSION=$VERSION
INSTALL_DATE=$(date -I)
INSTALL_MODE=asahi
INSTALL_FS=btrfs
INSTALL_ENGINE=image
HW_APPLE_SILICON=yes
SOURCE=release $VERSION
EOF
echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/10-wheel
chmod 440 /etc/sudoers.d/10-wheel
/usr/local/bin/kirk-branding
/usr/local/bin/kirk-install-fonts
/usr/local/bin/kirk-login-theme kirkus
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo ||
  echo "WARNING: couldn't add Flathub; kirk-update adds it later."
for d in hicolor kirkus kirkus-light; do gtk-update-icon-cache -q -t -f "/usr/share/icons/$d" 2>/dev/null || true; done

if command -v timeshift >/dev/null; then
  mkdir -p /etc/timeshift
  cat > /etc/timeshift/timeshift.json <<EOF
{
  "backup_device_uuid" : "$ROOT_UUID",
  "parent_device_uuid" : "",
  "do_first_run" : "false",
  "btrfs_mode" : "true",
  "include_btrfs_home_for_backup" : "false",
  "include_btrfs_home_for_restore" : "false",
  "stop_cron_emails" : "true",
  "schedule_monthly" : "false",
  "schedule_weekly" : "true",
  "schedule_daily" : "true",
  "schedule_hourly" : "false",
  "schedule_boot" : "false",
  "count_monthly" : "2",
  "count_weekly" : "3",
  "count_daily" : "5",
  "count_hourly" : "6",
  "count_boot" : "5",
  "snapshot_size" : "0",
  "snapshot_count" : "0",
  "date_format" : "%Y-%m-%d %H:%M:%S",
  "exclude" : [],
  "exclude-apps" : []
}
EOF
fi

# ------------------------------------------------------------------------------------- boot
say "Boot splash and boot menu"
# The initramfs: Asahi's hook first (it unpacks the Mac's firmware from the EFI partition), the boot
# splash right after udev, and grub-btrfs's overlay last, so read-only snapshots boot. Btrfs is
# built in, since autodetect only sees the build machine, not a Mac. Set now that every hook exists.
HOOKS="base asahi udev plymouth autodetect microcode modconf kms keyboard keymap consolefont block filesystems fsck"
[[ -f /usr/lib/initcpio/install/grub-btrfs-overlayfs ]] && HOOKS+=" grub-btrfs-overlayfs"
sed -i -E "s/^HOOKS=\(.*/HOOKS=($HOOKS)/" /etc/mkinitcpio.conf
sed -i -E 's/^MODULES=\(\)/MODULES=(btrfs)/' /etc/mkinitcpio.conf
grep -E '^(MODULES|HOOKS)=' /etc/mkinitcpio.conf
plymouth-set-default-theme kirkus
mkinitcpio -P

# Set KEY=VALUE in a defaults file: replace the first (possibly commented-out) line, else append.
set_var() {
  local key=$1 val=$2 f=$3
  if grep -qE "^#?[[:space:]]*$key=" "$f"; then
    sed -i -E "0,/^#?[[:space:]]*$key=/s|^#?[[:space:]]*$key=.*|$key=$val|" "$f"
  else
    echo "$key=$val" >> "$f"
  fi
}
G=/etc/default/grub
set_var GRUB_DISTRIBUTOR "\"$BRAND\"" $G
set_var GRUB_TIMEOUT 2 $G
set_var GRUB_TIMEOUT_STYLE hidden $G
set_var GRUB_THEME '"/boot/grub/themes/kirkus/theme.txt"' $G
set_var GRUB_TERMINAL_OUTPUT gfxterm $G
set_var GRUB_GFXMODE auto $G
set_var GRUB_GFXPAYLOAD_LINUX keep $G
sed -i -E '/^GRUB_CMDLINE_LINUX_DEFAULT=/{/splash/!s/"$/ splash"/}' $G
if [[ -d /etc/default/grub-btrfs || -f /usr/bin/grub-btrfsd ]]; then
  mkdir -p /etc/default/grub-btrfs
  touch /etc/default/grub-btrfs/config
  set_var GRUB_BTRFS_SUBMENUNAME "\"$BRAND snapshots\"" /etc/default/grub-btrfs/config
fi
/usr/local/bin/kirk-grub-theme-font || true
# grub.cfg itself is written by build.sh, once the image is mounted where GRUB will find it

# ------------------------------------------------------------------------------------- services
say "Services"
systemctl enable NetworkManager.service sddm.service bluetooth.service power-profiles-daemon.service \
  fstrim.timer systemd-timesyncd.service cronie.service kirk-auto-update.timer kirk-setup.service
# Asahi: speakers are only unlocked while speakersafetyd watches them
systemctl enable speakersafetyd.service 2>/dev/null || echo "(no speakersafetyd.service)"
command -v ufw >/dev/null && systemctl enable kirk-firewall-setup.service
command -v timeshift >/dev/null && systemctl enable kirk-first-snapshot.service
command -v grub-btrfsd >/dev/null && systemctl enable grub-btrfsd.service

# ------------------------------------------------------------------------------------- tidy up
say "Tidying up"
pacman -Scc --noconfirm >/dev/null 2>&1 || true
rm -rf /var/cache/pacman/pkg/* /tmp/* /root/.cache
# each install gets its own machine ID on its first start
: > /etc/machine-id
touch /kirk-src/setup-complete       # build.sh checks for it
echo "kirki $VERSION is set up in the image."
