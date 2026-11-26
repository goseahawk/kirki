#!/usr/bin/env bash
# Builds kirki for Apple Silicon on a computer that isn't 64-bit ARM Linux, in a container:
# macOS on an Apple Silicon Mac (Docker Desktop or Podman), or Linux / Windows+WSL2 on anything.
#
#     ./build-docker.sh
#
# The whole build runs in a throwaway privileged Ubuntu container; only the finished files are
# copied back to ./out/. On an Apple Silicon Mac or an ARM machine it runs natively; on an Intel or
# AMD computer every program in the image runs under emulation and it takes hours.
#
# Written to run under bash 3.2 (the /bin/bash that ships with macOS).
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
IMAGE=docker.io/library/ubuntu:24.04

[ -f "$HERE/build.sh" ] || { echo "Put build-docker.sh in the project folder, next to build.sh."; exit 1; }

if command -v podman >/dev/null 2>&1; then
  ENGINE=podman
elif command -v docker >/dev/null 2>&1; then
  ENGINE=docker
else
  cat <<'MSG'
Neither podman nor docker was found. Install one:
  macOS:    brew install --cask docker        (or: brew install podman && podman machine init --rootful && podman machine start)
  Fedora:   sudo dnf install podman
  Debian:   sudo apt install podman           (or docker.io)
  Windows:  Docker Desktop with the WSL2 backend; run this script from inside WSL
MSG
  exit 1
fi
echo "Using $ENGINE."

RUN_ARGS="run --rm --privileged --platform linux/arm64"
if [ -t 0 ] && [ -t 1 ]; then RUN_ARGS="$RUN_ARGS -it"; fi

case "$(uname -m)" in
  arm64|aarch64) ;;
  *)
    cat <<MSG

NOTE: this computer is $(uname -m), and kirki for Apple Silicon is 64-bit ARM, so the build runs
under emulation (qemu). Expect several hours. An Apple Silicon Mac, an ARM cloud machine or GitHub's
"Build image" workflow is much faster.
If $ENGINE can't run ARM containers yet, set that up first:
    sudo $ENGINE run --rm --privileged docker.io/tonistiigi/binfmt --install arm64

MSG
    ;;
esac

echo "Note: the build needs about 20 GB of free space in your $ENGINE storage."
mkdir -p "$HERE/out"

# The project is mounted read-only and copied in: a macOS or Windows folder can't hold the Linux
# file ownership and permissions the build depends on.
set +e
# shellcheck disable=SC2086  # RUN_ARGS is a deliberate list of whitespace-free flags
"$ENGINE" $RUN_ARGS \
  -e KIRK_VERSION="${KIRK_VERSION:-$(date +%y.%m.%d)}" \
  -e KIRK_REPO="${KIRK_REPO:-}" \
  -v "$HERE:/src:ro" \
  -v "$HERE/out:/out" \
  "$IMAGE" bash -euo pipefail -c '
    echo "== installing the build tools =="
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -q
    apt-get install -y -q --no-install-recommends libarchive-tools arch-install-scripts btrfs-progs \
      zip rsync curl ca-certificates python3 util-linux mount
    mkdir -p /work
    cp -a /src/. /work/
    rm -rf /work/build /work/out
    cd /work
    ./build.sh
    echo "== copying the results out =="
    cp -v /work/out/* /out/
  '
RC=$?
set -e
if [ "$RC" -ne 0 ]; then
  echo
  echo "The build failed (exit $RC). Scroll up: the last pacman or build.sh error is the real one."
  echo "If it mentions loop devices or mounting, the container isn't privileged enough: on Linux, run"
  echo "this script with sudo; with Podman on a Mac, use a rootful machine (podman machine set --rootful)."
  exit "$RC"
fi
if [ -n "${SUDO_USER:-}" ] && [ "$(id -u)" -eq 0 ]; then
  chown -R "$SUDO_USER" "$HERE/out" 2>/dev/null || true
fi
echo
echo "Done. The image is in $HERE/out/"
