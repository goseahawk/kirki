#!/bin/sh
# Installs kirkus on an Apple Silicon Mac. Run it in macOS's Terminal:
#
#     curl -fsSL https://github.com/goseahawk/kirki/releases/latest/download/install.sh | sh
#
# It downloads the newest kirkus release and checks it, then starts the Asahi Linux installer (the
# version Asahi ALARM uses), which makes room next to macOS and installs kirkus there. macOS is kept.
#
# The installer can't follow GitHub's download links itself, so this script downloads the image
# first and gives the installer that local copy. The download is kept in /tmp/kirkus-download until
# you restart the Mac, so running this again doesn't download it again.
#
# For testing (see DEVELOPMENT.md):
#   KIRK_INSTALLER_DATA=URL   another installer_data.json (https:// or file://)
#   KIRK_PACKAGE=FILE         use this image zip instead of downloading the one installer_data.json names
#
# Based on Asahi ALARM's installer-bootstrap.sh (MIT licence).

# Truncation guard: nothing runs unless the whole script arrived
if true; then
    set -e

    REPO=goseahawk/kirki

    if [ ! -e /System ]; then
        echo "This runs in macOS, on an Apple Silicon Mac (M1 or M2)."
        echo "kirkus is installed from macOS, next to it. You appear to be running another system."
        exit 1
    fi
    if [ "$(uname -m)" != arm64 ]; then
        echo "This Mac has an Intel processor. This version of kirkus is for Apple Silicon Macs."
        echo "Intel Macs use the regular kirkus: https://github.com/goseahawk/kirkus"
        exit 1
    fi

    export LC_ALL=en_US.UTF-8
    export LANG=en_US.UTF-8
    export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

    if ! curl --no-progress-meter file:/// >/dev/null 2>&1; then
        echo "Your version of curl is too old, which usually means macOS is out of date."
        echo "Installing kirkus needs macOS 13.5 or later: update macOS first."
        exit 1
    fi

    # The Asahi installer, as Asahi ALARM publishes it
    VERSION_FLAG="https://asahi-alarm.org/latest"
    INSTALLER_BASE="https://asahi-alarm.org"
    DATA_URL="${KIRK_INSTALLER_DATA:-https://github.com/$REPO/releases/latest/download/installer_data.json}"
    TMP=/tmp/asahi-install
    DL=/tmp/kirkus-download

    echo
    echo "Getting ready to install kirkus:"

    if [ -e "$TMP" ]; then
        mv "$TMP" "$TMP-$(date +%Y%m%d-%H%M%S)-$$"
    fi
    mkdir -p "$TMP" "$DL"
    cd "$TMP"

    echo "  Finding the newest kirkus..."
    if ! curl --no-progress-meter -fL -o installer_data.json "$DATA_URL"; then
        echo "  Couldn't download kirkus's installer information from GitHub."
        echo "  Check your internet connection (GitHub may be blocked on this network) and try again."
        exit 1
    fi
    value() { sed -n "s/.*\"$1\": *\"\{0,1\}\([^\",]*\)\"\{0,1\},\{0,1\}\$/\1/p" installer_data.json | head -1; }
    KVER=$(value kirkus_version)
    PKG=$(value kirkus_package)
    URL=$(value kirkus_url)
    SHA=$(value kirkus_sha256)
    SIZE=$(value kirkus_size)
    case "$PKG" in
        kirkus-*.zip) ;;
        *) echo "  That installer information doesn't look like kirkus's. Nothing was changed."; exit 1 ;;
    esac
    echo "  kirkus $KVER"

    if [ -n "$KIRK_PACKAGE" ]; then
        echo "  Using $KIRK_PACKAGE"
        ZIP="$KIRK_PACKAGE"
    else
        ZIP="$DL/$PKG"
        MB=$(( ${SIZE:-0} / 1000000 ))
        FREE_MB=$(( $(df -k /tmp | awk 'NR==2 {print $4}') / 1000 ))
        if [ "$FREE_MB" -lt $(( MB + 500 )) ]; then
            echo "  The download needs about $MB MB free in macOS, and there's only $FREE_MB MB."
            echo "  Free up some space and try again."
            exit 1
        fi
        echo "  Downloading kirkus ($MB MB; it can be resumed if it's interrupted)..."
        curl -fL --retry 5 -C - -o "$ZIP" "$URL" || {
            echo "  The download stopped. Run the same command again to carry on where it left off."
            exit 1
        }
    fi

    echo "  Checking the download..."
    GOT=$(shasum -a 256 "$ZIP" | cut -d' ' -f1)
    if [ "$GOT" != "$SHA" ]; then
        if [ -n "$KIRK_PACKAGE" ]; then
            echo "  $KIRK_PACKAGE doesn't match this release's checksum. Nothing was changed."
        else
            rm -f "$ZIP"
            echo "  The download is damaged (its checksum doesn't match). It has been deleted;"
            echo "  run the same command again to download it again."
        fi
        exit 1
    fi
    echo "  OK."

    # The installer finds a relative package at $REPO_BASE/os/<package>
    mkdir -p "$TMP/os"
    ln -sf "$ZIP" "$TMP/os/$PKG"
    export REPO_BASE="$TMP"
    export INSTALLER_DATA="$DATA_URL"

    echo "  Downloading the Asahi installer..."
    PKG_VER="$(curl --no-progress-meter -fL "$VERSION_FLAG")"
    curl --no-progress-meter -fL -o "installer-$PKG_VER.tar.gz" "$INSTALLER_BASE/installer-$PKG_VER.tar.gz"
    tar xf "installer-$PKG_VER.tar.gz"

    echo
    echo "Starting the Asahi installer. When it asks which system to install, choose kirkus."
    echo "It runs as root, so enter your Mac password if you're asked for it."
    echo
    if [ "$USER" != "root" ]; then
        exec caffeinate -dis sudo -E ./install.sh "$@"
    else
        exec caffeinate -dis ./install.sh "$@"
    fi
fi
