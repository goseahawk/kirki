# kirkus for Apple Silicon

**kirkus is a simple, easy-to-use Arch Linux system**, and this is kirkus for **Apple Silicon Macs**
(M1 and M2). You get the same complete, good-looking KDE Plasma desktop as kirkus on PCs, installed
next to macOS, with the Mac's hardware support from [Asahi Linux](https://asahilinux.org/) as
packaged for Arch by [Asahi ALARM](https://asahi-alarm.org/).

- **Easy to install.** One command in macOS's Terminal. macOS stays, and you pick which one to start.
- **Your Mac just works.** Wi-Fi, graphics, sound, keyboard backlight, the Touch Bar and battery
  are set up by Asahi Linux.
- **Mistakes can be undone.** Snapshots are taken before risky updates, and you can start your Mac
  from one right from the boot menu.
- **Updates take care of themselves.** Every week kirkus updates the system, your apps and itself.

It's still Arch underneath (Arch Linux ARM, to be exact), so nothing is hidden or locked down: pacman
and the [Arch wiki](https://wiki.archlinux.org/) work as usual whenever you want to go further.

Website: **[goseahawk.github.io/kirki](https://goseahawk.github.io/kirki/)**

kirkus is an independent project. It is not affiliated with or endorsed by Arch Linux, Arch Linux
ARM, Asahi Linux, Asahi ALARM or Apple.

## What you need

- A Mac with **M1 or M2** (MacBook Air, MacBook Pro, Mac mini, iMac, Mac Studio or Mac Pro). Macs
  with M3 or later can't run Linux yet. For PCs and Intel Macs, use
  [kirkus](https://github.com/goseahawk/kirkus).
- **macOS 13.5 or later**, fully updated, and your Mac's administrator password.
- At least **25 GB of free space** in macOS: about 2 GB while kirkus downloads, and 20 GB or more
  for kirkus itself. You choose how much to give it.
- An **internet connection**, ideally a cable or fast Wi-Fi. The download is about 2 GB.
- **A backup of your Mac.** The installer is careful with macOS, but it does change how the disk is
  divided up. Use Time Machine first.

## 1. Install

1. In macOS, open **Terminal** (Applications → Utilities), paste this and press Return:

       curl -fsSL https://github.com/goseahawk/kirki/releases/latest/download/install.sh | sh

   It downloads kirkus and checks it, then starts the **Asahi Linux installer**. Enter your Mac
   password when asked.
2. **Follow the installer's instructions exactly.** It asks:
   - which system to install: choose **kirkus**
   - how much space to give kirkus (it shrinks macOS to make room; macOS and your files stay)
   - a name for kirkus in the Mac's startup list: **kirkus** is fine
3. At the end it asks you to **shut down** the Mac and finish setting it up from the startup screen.
   Read those steps through before you shut down: wait 15 seconds after the Mac is off, then **press
   and hold the power button** until "Loading startup options" appears, choose **kirkus**, and follow
   what's on screen (it asks for your Mac password once more).

## 2. Starting kirkus for the first time

A setup window opens. It asks, one page at a time:

- your **language** and **time zone** (suggested for you when you're online)
- your **keyboard** (picked to match your Mac's keyboard)
- **your name, username and password**, and a name for the computer

Click **Done** at the end and the login screen appears. Log in with the password you chose.

## 3. Choosing macOS or kirkus

- **To choose each time:** press and hold the power button when you turn the Mac on, then pick
  **kirkus** or **Macintosh HD**.
- **To change which one starts by itself:** in kirkus, open **Startup Disk** from the app menu; in
  macOS, System Settings → General → **Startup Disk**.
- **The boot menu is hidden.** To see it (for example to start from a snapshot), tap **Esc** while the
  kirkus logo is on screen at power-on.

## 4. First steps

- **Wi-Fi:** click the network icon in the panel and pick your network.
- **Apps:** install apps from **Discover**, in the app menu. Most apps on Flathub run on Apple
  Silicon; a few are only made for Intel and AMD computers.
- **Light or dark:** kirkus starts dark. For the light version, open System Settings → **Global
  Theme** and choose **kirkus Light**, or turn on **Switch to Dark Mode at Night** to have both.
- **Firewall:** on from the start. It blocks other computers from connecting in, without getting in
  the way of anything you do. Change it in System Settings → **Firewall**.
- **Your Mac's details:** System Settings → **About this System** shows the model, battery health,
  storage and when kirkus was installed.

## Updates

kirkus updates itself once a week: the system (including the Mac support from Asahi), your Flatpak
apps and kirkus itself. It waits until you're plugged in and not on a metered connection, and a
notification tells you when it's done and whether to restart.

- **To turn this off:** System Settings → **System Update**.
- **To update Flatpak apps right now:** System Settings → **Flatpak Update**, or Discover → Updates.
- **To update the system right now:** open Konsole and run `sudo pacman -Syu`.

If Arch announces something that needs your attention, kirkus doesn't update on its own. A
notification asks you to read the news at [archlinux.org/news](https://archlinux.org/news/) and then
run `sudo pacman -Syu` yourself.

See [UPDATING.md](UPDATING.md) for the details.

## Undoing a bad update

kirkus keeps **snapshots** of the system: one right after setup, daily and weekly ones, and one just
before any important update. They cover the system, not your personal files in your home folder (you
can add those in Timeshift → Settings → Users).

If something stops working after an update:

1. Restart, and tap **Esc** while the kirkus logo is on screen to show the boot menu.
2. Choose the **snapshots** entry, then the snapshot from just before the update. Your Mac starts as
   it was then. Changes you make while it's running are temporary.
3. If everything works, open the **Timeshift** app, select that snapshot and click **Restore** to
   make it permanent. Then restart.

Snapshots are stored on the same disk, so they protect against a bad update, not a broken disk. Keep
real backups of your files.

## Troubleshooting

**The install command says GitHub can't be reached.** Check your internet connection. Some networks
block GitHub; try another network.

**The download stopped.** Run the same command again. It carries on where it left off.

**The setup window didn't finish, or closed.** Restart the Mac (hold the power button until it turns
off, then start kirkus again). Setup opens again until it's been completed.

**The desktop doesn't look like kirkus.** Open System Settings → **Global Theme**, choose **kirkus**
and click Apply. If it still looks wrong, run `kirk-theme-check` in Konsole and
[open an issue](https://github.com/goseahawk/kirki/issues) with what it shows.

**The login screen is blank.** Press Control+Option+F2 (hold Fn too if F2 changes the brightness), log in with your
username and password, and run `sudo kirk-login-theme breeze` and then `sudo systemctl restart sddm`.
That switches to KDE's standard login screen.

**I want to see what's happening while it starts.** Press Esc while the kirkus logo is on screen.

**Something about the hardware doesn't work** (sound, the camera, sleep, an external display). Check
Asahi Linux's [feature support](https://asahilinux.org/docs/platform/feature-support/overview/)
list first: not everything works on every Mac yet. Then
[open an issue](https://github.com/goseahawk/kirki/issues) with the output of `kirk-detect --summary`.

**I want to remove kirkus.** Asahi Linux's documentation explains how to remove a Linux install and
give the space back to macOS.

## Building the image yourself

Most people should just use the install command above. To build your own image, for example with
your own changes:

- **On ARM Linux** (including Asahi on a Mac): `sudo ./build.sh`.
- **On a Mac with Docker or Podman, or any other computer:** `./build-docker.sh`. On an Apple Silicon
  Mac it runs at full speed; on an Intel or AMD computer it takes hours.

The image lands in `out/`, named for today's date (set `KIRK_VERSION=26.11.18` to choose the
version). See [DEVELOPMENT.md](DEVELOPMENT.md) for how it's put together and how to install your
own build.

## License

The code is under the MIT License (see `LICENSE`). The kirkus logo and the files in `branding/` are
**not** covered by it; they may not be reused without permission. Parts of the macOS install script
and the first-start setup are based on Asahi ALARM's installer bootstrap and Calamares setup (MIT
License). Arch Linux, Arch Linux ARM and Asahi Linux are trademarks of their respective owners;
Apple, Mac and macOS are trademarks of Apple Inc.
