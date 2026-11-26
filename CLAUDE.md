# kirki: notes for Claude

This repo (github.com/goseahawk/kirki) is kirki, the Apple Silicon (M1/M2) port of kirkus
(github.com/goseahawk/kirkus), a simple, easy-to-use Arch Linux distribution with KDE Plasma. Here
it's built on Arch Linux ARM with Asahi ALARM's kernel and Mac support: a disk image the Asahi
installer writes from macOS, a setup window (Calamares) on the first start, and the same desktop,
branding and self-updating as kirkus. How it works inside is in `DEVELOPMENT.md`; read that before
changing anything.

- `overlay/installed` started as a copy of kirkus's. Desktop and branding changes made in kirkus
  should usually be brought over here too (and the other way round); hardware, boot and update
  scripts differ on purpose.
- The name shown to people is **kirki** everywhere (os-release, boot menu, setup window, theme names,
  website, release files). Internal IDs keep kirkus's names so changes carry over between the two:
  theme package IDs (`org.kirkus.splash`, icon/Plasma/SDDM/Plymouth theme folders and `Id`s,
  `KirkusDark`), folders like `/usr/share/kirkus` and `calamares-kirkus`, the `kirk-*` commands. Never
  rename an ID to kirki; change display names (`Name=`, `"Name"`) only.

## Working with the owner

- The owner usually wants each change committed and pushed to `main` when it's done, with a clear
  commit message. Commits use the owner's GitHub noreply address. Never put the owner's personal
  email address in the repo, commits or anything sent to an outside service.
- For appearance and branding changes (logo, colours, splash, login screen, wallpaper, themes), keep
  commit messages vague, e.g. "Update branding" or "Appearance tweaks". Don't describe the details.
- Keep replies short and plain: what changed, anything to watch out for, and what the owner needs to
  do (usually: publish a release, or run `sudo kirk-update --main` on the Mac).
- For visual changes (logo, splash, login screen), render previews and offer a few options to choose
  from before applying.
- The owner's own kirkus computer is a 2015 MacBook Air (Intel), which runs kirkus, not
  this port.

## Docs

- `README.md` and `UPDATING.md` are for **users**: plain steps, no internals, no maintainer notes.
  Don't add lines about small internal features.
- `DEVELOPMENT.md` is for maintainers: internals, the release process and the project layout.
- License stays the last section of the README, after "Building the image yourself".

## Rules that matter

- **Versions** are `YY.MM.DD`, or `YY.MM.DD.N` for later builds the same day. Release tags are the
  bare version (no `v`). `kirk-update` compares versions with `sort -V`.
- **Published releases go to every installed system automatically** (after its next `pacman -Syu`),
  and to every new install (the install command follows the latest release). Test with a draft
  release or "Just build" in the Build image workflow first.
- A release needs all of `out/`: `install.sh`, `installer_data.json`, the zip and its checksum. The
  zip must stay under 2 GiB (GitHub's limit).
- Never write a Mac's EFI variables, and never touch the EFI partition or the macOS-side stub from
  `apply-to-installed.sh`. Keep the `asahi` mkinitcpio hook first after `base`.
- The Asahi installer can't follow GitHub's redirects (it drops the query string), which is why
  `asahi/install.sh` downloads the image first. Don't point `installer_data.json` at a GitHub URL.
- `apply-to-installed.sh` copies the whole `overlay/installed` tree (files in its `KEEP` list, like
  `/etc/kirk-update.conf`, are only installed when missing). It has no migration code for old names;
  keep it that way.
- Packages go in `image/setup.sh`: `PKGS` (required) or `OPTIONAL` (skipped with a warning if Arch
  Linux ARM lacks them). Check a package exists for aarch64 before adding it.
- System Settings entries are `.desktop` files in
  `overlay/installed/usr/share/plasma/systemsettings/externalmodules/` (plus a copy in
  `usr/share/applications/`). Discover's "Software Update" page is hidden in `/etc/xdg/kdeglobals`.

## Branding

- The mark is a vulture (the bird) with a Marigold head. The logo files are in `branding/build/`:
  `logo.svg` (lockup on light), `logo-dark.svg` (on dark), `logo-one-color.svg`, `icon.svg` (app
  icon: the bird on a Marigold rounded square), `mark.svg` (one-colour bird), `mark-color.svg` and
  `mark-dark.svg` (the bird cut out of the two lockups). The wordmark is DM Sans Bold, always
  lowercase; DM Sans is bundled in `overlay/installed/usr/share/fonts/kirkus/`.
- `branding/tools/make-screens.py` builds every screen image, the wallpaper and the app icon from
  those files; `make-fastfetch-logo.py` and `make-live-icons.py` do the rest. Rerun them after any
  logo change, and check that the login and splash bird are pixel-identical.
- The desktop theme is called kirki everywhere System Settings shows one: Global Theme (`org.kirkus.splash`,
  the default), Colors, Plasma Style, Icons (Breeze with the bird as KDE's start icon, so the launcher
  shows it with no setting), wallpaper and splash; kirki Light is the twin, paired for "Switch to
  Dark Mode at Night". A new account needs no scripts. DEVELOPMENT.md → "Desktop theme" has the
  details, including the login scripts that bring existing accounts over.
- Don't ship a panel layout in the Global Theme: with a copy of KDE's in it, new accounts on Arch's
  newer Plasma got no panel (it worked on Plasma 6.7). KDE's own layout always matches the installed
  Plasma.
- KDE's `plasma-apply-*` tools change nothing, and still exit 0, when they think a theme is already
  set; `/etc/xdg` makes them think so. Check the result and write the settings directly if needed
  (`kirk-set-theme` does). `kirk-theme-check` shows an account's real theme state; ask for its output.
- The colour schemes, `/etc/xdg/kdeglobals` and Konsole's profile come from
  `branding/tools/make-color-schemes.py`.
- The wallpaper is "Quiet": flat Ink with a large bird one shade lighter (flat Bone and one shade
  darker for kirki Light), as the package `/usr/share/wallpapers/kirkus`. No gradients (the owner
  found the old one cheap; they band on real screens).
- The Global Theme previews are real screenshots of a fresh account in that theme (Dolphin at Home,
  Konsole running fastfetch), so they match what people get. Retake them after any look change.
- SVGs Plasma loads must suit Qt's strict SVG reader: self-closing elements, nothing nested oddly,
  no filters. A file Qt rejects shows nothing at all.
- Every screen is Ink and centres its image at `x = W/2`, `y = H/2 - 50`, with even image sizes:
  GRUB background = the bird; boot splash (Plymouth) = the word "kirki", fading in; login screen
  (SDDM) = the bird at 30% opacity; Plasma splash = the same bird brightening from 30% to full.
- Palette: Ink `#16171b`, Bone `#f3efe6`, Marigold `#f2a93b`. Text on Marigold is Ink.

## Testing

There's no way to boot kirki or build the image from here (no ARM machine, and Arch Linux ARM's
servers are blocked), so:

- Syntax-check every script (`bash -n`, `sh -n`, `python3 -m py_compile`) and validate XML/JSON.
- Test scripts against mocks of the commands they call (pacman, nmcli, gdbus, curl, kdialog), with
  paths redirected to a temporary folder, covering each case. `kirk-detect`, `kirk-about-*` take
  `KIRK_DT` / `KIRK_SYS` for a fake device tree and sysfs.
- `asahi/install.sh` can be run on Linux with mocks of curl, uname, shasum, df, sudo and caffeinate,
  after replacing its `/System` check and its `PATH` line in a copy.
- The Asahi ALARM repository's package and file lists can be downloaded from
  github.com/asahi-alarm/asahi-alarm/releases/download/aarch64/ (`asahi-alarm.db`, `.files`).
- Say clearly what has only been tested that way.
- Desktop look and theme logic can be checked in a real Plasma 6 session: debootstrap the newest
  Ubuntu release from archive.ubuntu.com (Arch and Debian mirrors are blocked here) into a chroot,
  install `plasma-desktop kwin-x11 xvfb`, run `kwin_x11` and `plasmashell` on Xvfb as a test user
  with `XDG_CONFIG_DIRS=$HOME/.config/kdedefaults:/etc/xdg` (as startplasma sets it), and screenshot
  with `import -window root`. Still say it was Ubuntu's Plasma under X11, not kirki on hardware.

Not yet confirmed on real hardware: everything specific to this port (see the end of
DEVELOPMENT.md), plus, as on kirkus, tap to click and weekly automatic updates.
