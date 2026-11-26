#!/usr/bin/env python3
"""Writes installer_data.json, which tells the Asahi installer how to install kirki.

Called by build.sh. The format is the Asahi installer's (see AsahiLinux/asahi-installer-data), with
one extra top-level "kirki" block that install.sh reads: where to download the image and its
checksum. install.sh downloads and checks the image itself and hands the installer a local copy,
because the installer can't follow GitHub's download links (it drops the signed query string when it
follows a redirect).

The partition layout matches Asahi ALARM's: a 500 MB EFI partition (m1n1 stage 2, U-Boot, GRUB and
the Mac's firmware, which the installer copies in) and the Btrfs root, which takes whatever space
you give kirki in the installer.
"""
import argparse, json, re, sys

# macOS versions whose system firmware the installer may pair kirki with (as Asahi's own images).
SUPPORTED_FW = ["12.3", "12.3.1", "13.5", "14.8.3"]
EFI_SIZE = 500 * 1024 * 1024


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--version", required=True)
    ap.add_argument("--repo", required=True, help="owner/name of the GitHub repository")
    ap.add_argument("--package", required=True, help="the zip's file name")
    ap.add_argument("--sha256", required=True)
    ap.add_argument("--package-size", type=int, required=True)
    ap.add_argument("--root-size", type=int, required=True, help="size of root.img in bytes")
    ap.add_argument("--efi-uuid", required=True, help="FAT volume ID as XXXX-XXXX")
    a = ap.parse_args()

    if not re.fullmatch(r"[0-9]{2}\.[0-9]{2}\.[0-9]{2}(\.[0-9]+)?", a.version):
        sys.exit(f"bad version {a.version!r}")
    if not re.fullmatch(r"[0-9a-f]{64}", a.sha256):
        sys.exit("bad sha256")
    if not re.fullmatch(r"[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}", a.efi_uuid):
        sys.exit("bad EFI volume ID")
    if a.root_size % 4096:
        sys.exit("root.img must be a multiple of 4 KiB")

    data = {
        "kirki": {
            "kirki_version": a.version,
            "kirki_package": a.package,
            "kirki_url": f"https://github.com/{a.repo}/releases/download/{a.version}/{a.package}",
            "kirki_sha256": a.sha256,
            "kirki_size": a.package_size,
        },
        "os_list": [
            {
                "name": f"kirki {a.version} (KDE Plasma)",
                "default_os_name": "kirki",
                "boot_object": "m1n1.bin",
                "next_object": "m1n1/boot.bin",
                # relative: install.sh points REPO_BASE at its local copy (REPO_BASE/os/<package>)
                "package": a.package,
                "icon": "kirki.icns",
                "supported_fw": SUPPORTED_FW,
                "partitions": [
                    {
                        "name": "EFI",
                        "type": "EFI",
                        "size": f"{EFI_SIZE}B",
                        "format": "fat",
                        "volume_id": "0x" + a.efi_uuid.replace("-", "").lower(),
                        "copy_firmware": True,
                        "copy_installer_data": True,
                        "source": "esp",
                    },
                    {
                        "name": "Root",
                        "type": "Linux",
                        "size": f"{a.root_size}B",
                        "expand": True,
                        "image": "root.img",
                    },
                ],
            }
        ],
    }
    # One key per line: install.sh reads the "kirki_*" values with sed (macOS has no jq or python
    # by default).
    json.dump(data, sys.stdout, indent=1)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
