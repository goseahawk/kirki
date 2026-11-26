#!/usr/bin/env bash
# Updates an installed kirkus for Apple Silicon to this version of the project, without reinstalling.
#
# Run it from the project folder on the installed Mac:
#     sudo ./apply-to-installed.sh
#
# kirk-update runs it automatically for each new release (see UPDATING.md). The version it records
# is today's date, or set KIRK_VERSION=26.11.18 to choose it.
#
# It installs the same files and settings as the image: branding, boot splash, GRUB theme, login
# screen, Plasma splash, About page, update hooks and firewall. It never touches the EFI partition
# (m1n1, U-Boot, the Mac's firmware) or the GRUB image there, so the way your Mac boots stays as it
# is. The Asahi packages keep those up to date themselves. Safe to run again.
set -euo pipefail
[[ $EUID -eq 0 ]] || exec sudo KIRK_VERSION="${KIRK_VERSION:-}" KIRK_FORCE="${KIRK_FORCE:-}" "$0" "$@"

VERSION=${KIRK_VERSION:-$(date +%y.%m.%d)}
[[ $VERSION =~ ^[0-9]{2}\.[0-9]{2}\.[0-9]{2}(\.[0-9]+)?$ ]] || { echo "Bad version '$VERSION': use YY.MM.DD or YY.MM.DD.N, e.g. 26.11.18 or 26.11.18.1"; exit 1; }
BRAND="kirkus $VERSION"
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$HERE/overlay/installed
[[ -d $SRC ]] || { echo "Run this from inside the project folder."; exit 1; }

# ---------------------------------------------------------------------------------------- hardware
eval "$(sh "$SRC"/usr/local/bin/kirk-detect)"
echo "This computer: $(sh "$SRC"/usr/local/bin/kirk-detect --summary)"
if [[ $KIRK_APPLE_SILICON != yes && ${KIRK_FORCE:-} != yes ]]; then
  echo "This is kirkus for Apple Silicon Macs, and this computer isn't one, so nothing was changed."
  echo "PCs and Intel Macs use the regular kirkus (github.com/goseahawk/kirkus): set REPO in"
  echo "/etc/kirk-update.conf to goseahawk/kirkus. (KIRK_FORCE=yes overrides this check.)"
  exit 1
fi

# Copy a tree onto /, file by file, owned by root. Programs (usr/local/bin, etc/grub.d) get 755,
# everything else 644. Directories that already exist keep their permissions. Files listed in KEEP
# are only installed if missing, so your own settings in them survive updates.
KEEP=(etc/kirk-update.conf)
copy_tree() {
  local from=$1 rel mode k skip
  while IFS= read -r -d '' rel; do
    rel=${rel#./}
    skip=no
    for k in "${KEEP[@]}"; do [[ $rel == "$k" && -e /$rel ]] && skip=yes; done
    [[ $skip == yes ]] && continue
    case $rel in
      usr/local/bin/*|etc/grub.d/*) mode=755 ;;
      *) mode=644 ;;
    esac
    install -D -o root -g root -m "$mode" "$from/$rel" "/$rel"
  done < <(cd "$from" && find . -type f -print0)
}

# ---------------------------------------------------------------------------------------- packages
echo "== packages =="
PKGS=(kinfocenter discover flatpak kdialog xf86-input-libinput plymouth power-profiles-daemon
      zram-generator calamares cage xorg-server-xwayland)
pacman -S --needed --noconfirm "${PKGS[@]}"
# wanted, but not fatal if Arch Linux ARM doesn't have them
for p in fastfetch ufw plasma-firewall; do
  pacman -S --needed --noconfirm "$p" || echo "($p isn't available; skipped)"
done

# ------------------------------------------------------------------------------------------- files
echo "== kirkus files =="
# Theme folders belong to kirkus entirely: replace them, so files a newer version dropped go too.
rm -rf /usr/share/plymouth/themes/kirkus /boot/grub/themes/kirkus /usr/share/sddm/themes/kirkus \
       /usr/share/plasma/look-and-feel/org.kirkus.splash /usr/share/plasma/look-and-feel/org.kirkus.light \
       /usr/share/plasma/desktoptheme/kirkus /usr/share/icons/kirkus /usr/share/icons/kirkus-light \
       /usr/share/wallpapers/kirkus /usr/share/kirkus /usr/share/calamares-kirkus
copy_tree "$SRC"
systemctl daemon-reload

# version, read by kirk-branding, the About page and kirk-update
touch /etc/kirk-release
set_release_key() {
  if grep -q "^$1=" /etc/kirk-release; then sed -i "s|^$1=.*|$1=$2|" /etc/kirk-release
  else echo "$1=$2" >> /etc/kirk-release; fi
}
set_release_key VERSION "$VERSION"
set_release_key HW_APPLE_SILICON "$KIRK_APPLE_SILICON"
/usr/local/bin/kirk-branding

# ---------------------------------------------------------------------------------------- services
systemctl enable power-profiles-daemon.service || true
systemctl enable speakersafetyd.service 2>/dev/null || true
# firewall: turned on once (see kirk-firewall-setup); after that it's left as you set it
command -v ufw >/dev/null && { systemctl enable --now kirk-firewall-setup.service || true; }
# grub-btrfsd picks up its Timeshift settings on restart
systemctl try-restart grub-btrfsd.service 2>/dev/null || true
# weekly automatic updates, unless you've turned them off
if grep -q '^AUTO_SYSTEM_UPDATE=no' /etc/kirk-update.conf 2>/dev/null; then
  systemctl disable --now kirk-auto-update.timer 2>/dev/null || true
else
  systemctl enable --now kirk-auto-update.timer || true
fi
# First-start setup: only ever on a fresh install. This system is already set up.
mkdir -p /var/lib/kirkus
[[ -e /var/lib/kirkus/setup-done ]] || touch /var/lib/kirkus/setup-done
systemctl disable kirk-setup.service 2>/dev/null || true

# ----------------------------------------------------------------------------------- desktop & apps
echo "== desktop =="
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo \
  || echo "Could not add Flathub (offline?). Run this again later to add it."
/usr/local/bin/kirk-install-fonts || true
/usr/local/bin/kirk-login-theme kirkus
for d in hicolor kirkus kirkus-light; do gtk-update-icon-cache -q -t -f /usr/share/icons/$d 2>/dev/null || true; done
# The Plasma splash is the default for everyone via /etc/xdg/ksplashrc; set it for you as well, in
# case you picked a different one before.
if [[ -n ${SUDO_USER:-} ]] && command -v kwriteconfig6 >/dev/null; then
  sudo -H -u "$SUDO_USER" kwriteconfig6 --file ksplashrc --group KSplash --key Engine KSplashQML || true
  sudo -H -u "$SUDO_USER" kwriteconfig6 --file ksplashrc --group KSplash --key Theme org.kirkus.splash || true
fi

# ------------------------------------------------------------------------------------- boot splash
echo "== boot splash =="
# Rebuilding the boot image on a system that boots fine today: snapshot first (Btrfs), keep a copy
# of mkinitcpio.conf, and put it back automatically if the rebuild fails.
SPLASH_OK=no
if [[ $(findmnt -no FSTYPE /) == btrfs && -f /etc/timeshift/timeshift.json ]] && command -v timeshift >/dev/null; then
  timeshift --create --comments "kirkus $VERSION: before update" --scripted >/dev/null 2>&1 \
    && echo "Timeshift snapshot taken." || echo "(snapshot skipped)"
fi
cp /etc/mkinitcpio.conf /etc/mkinitcpio.conf.kirkus-backup
# plymouth right after udev; Asahi's own hook (asahi) stays first, before udev
sed -i -E '/^HOOKS=/{/[( ]plymouth[ )]/!s/([( ])(udev|systemd)([ )])/\1\2 plymouth\3/}' /etc/mkinitcpio.conf
if ! grep -qE '^HOOKS=.*[( ]plymouth[ )]' /etc/mkinitcpio.conf; then
  echo "WARNING: couldn't find udev or systemd in HOOKS, so the boot splash was not enabled."
  cp /etc/mkinitcpio.conf.kirkus-backup /etc/mkinitcpio.conf
elif ! grep -qE '^HOOKS=.*[( ]asahi[ )]' /etc/mkinitcpio.conf; then
  echo "WARNING: the asahi hook is missing from HOOKS in /etc/mkinitcpio.conf. Not rebuilding the"
  echo "         boot image; add 'asahi' right after 'base' first, or the Mac's firmware won't load."
  cp /etc/mkinitcpio.conf.kirkus-backup /etc/mkinitcpio.conf
else
  plymouth-set-default-theme kirkus
  if mkinitcpio -P; then
    SPLASH_OK=yes
  else
    echo "WARNING: rebuilding the boot image failed. Restoring the previous setup..."
    cp /etc/mkinitcpio.conf.kirkus-backup /etc/mkinitcpio.conf
    mkinitcpio -P && echo "Restored. Your system boots exactly as before." \
      || echo "!! Restore also failed. Do NOT restart; paste this output to get help."
  fi
fi

# -------------------------------------------------------------------------------------------- GRUB
echo "== GRUB menu =="
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
set_var GRUB_GFXPAYLOAD_LINUX keep $G      # no flicker between GRUB and the boot splash
if [[ $SPLASH_OK == yes ]]; then
  sed -i -E '/^GRUB_CMDLINE_LINUX_DEFAULT=/{/splash/!s/"$/ splash"/}' $G
fi
if [[ -f /etc/default/grub-btrfs/config ]]; then
  set_var GRUB_BTRFS_SUBMENUNAME "\"$BRAND snapshots\"" /etc/default/grub-btrfs/config
fi
/usr/local/bin/kirk-grub-theme-font || true
# grub-mkconfig only replaces grub.cfg if the new one passes its syntax check, so a failure here
# leaves your current, working boot menu in place.
grub-mkconfig -o /boot/grub/grub.cfg \
  || echo "WARNING: grub-mkconfig failed; your existing boot menu was left as it was and still works."

echo
echo "kirkus $VERSION is installed. Restart to see everything."
