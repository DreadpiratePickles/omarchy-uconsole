# Build the SD card offline

These scripts build a ready-to-boot card for a uConsole **CM4 Lite** with the
**HackerGadgets AIO V2**, from an x86_64 Linux machine. They do the README's
steps 1 to 17, the AIO V2 setup ([docs/aio-v2.md](../docs/aio-v2.md)) and the
SDR toolkit ([docs/sdr-toolkit.md](../docs/sdr-toolkit.md)) in an aarch64
chroot under qemu, so the first boot lands in Omarchy.

This is how the reference device was built (November 2026). What is not
automated yet comes after first boot: see [After first boot](#after-first-boot).

| Script | What it does |
| --- | --- |
| `build-sdcard.sh` | Flashes the base image, expands the root, adds the Pi firmware (step 2), then runs `chroot-setup.sh` inside the card and checks the result |
| `chroot-setup.sh` | Steps 3 and 5-17, the AIO V2 boot overlays, `aiov2_ctl`, gpsd, the SDR packages, and the SDR++ / gpredict / direwolf / meshtasticd builds |
| `fixup-chroot.sh` | Second pass: rebuilds SDR++ and installs `yaml-cpp08-compat` for meshtasticd (both failed in the first pass) |
| `add-wifi.sh` | Copies this machine's current Wi-Fi network onto the card as a NetworkManager profile. The passphrase is never printed |

## Requirements (on the build machine)

- x86_64 Linux with `qemu-user-static` and binfmt registered for aarch64 with
  the `F` flag (`/proc/sys/fs/binfmt_misc/qemu-aarch64` must exist). On Arch:
  `pacman -S qemu-user-static qemu-user-static-binfmt`.
- `zstd`, `sfdisk`, `e2fsprogs`, `curl`, `git`, and about 20 GB free.
- A microSD card of 16 GB or more (32 GB recommended) in a reader.
- The base image, from [wdkdot/uconsole-arch](https://github.com/wdkdot/uconsole-arch)
  release **v2026.07.04**, in `cache/` at the repository root:

```bash
mkdir -p cache && cd cache
curl -LO https://github.com/wdkdot/uconsole-arch/releases/download/v2026.07.04/uconsole-arch-cm4.img.zst
curl -LO https://github.com/wdkdot/uconsole-arch/releases/download/v2026.07.04/uconsole-arch-cm4.img.zst.sha256
cd ..
```

The script checks the image against the `.sha256` file before writing.

## Build

```bash
lsblk                                   # find the card, e.g. /dev/sdX or /dev/mmcblk0
sudo ./sdcard/build-sdcard.sh /dev/sdX  # asks you to type "yes" before erasing it
```

It takes about an hour on a fast machine, most of it in emulated `makepkg`
builds. The log goes to `sdcard/build.log`.

Options (environment variables):

- `WIFI_SSID=... WIFI_PSK=...`: write a Wi-Fi profile onto the card. Or run
  `sudo ./sdcard/add-wifi.sh /dev/sdX` afterwards, which takes the network this
  machine is on. Never commit either; `build.log` does not record the passphrase.
- `SKIP_FLASH=1`: reuse an already-flashed card and re-run the setup stage.
- `SKIP_FLASH=1 CHROOT_SCRIPT=fixup-chroot.sh`: run only the fix-up pass.
- `YES=1`: skip the confirmation prompt.
- `CACHE=dir`: look for the image somewhere else.

Then run the fix-up pass, which the first pass needs for SDR++ and meshtasticd:

```bash
sudo SKIP_FLASH=1 CHROOT_SCRIPT=fixup-chroot.sh ./sdcard/build-sdcard.sh /dev/sdX
```

### Expected results

The verify step prints `ok`/`FAIL` per check. On the reference build:

- **`FAIL app: sdrangel`**: SDRangel has no installable aarch64 package. Expected.
- **`FAIL app: sdrpp`** and **"meshtasticd has missing libraries"** after the
  first pass only. `fixup-chroot.sh` fixes both.
- The noise listed in
  [docs/sdr-and-aio-integration.md section 11](../docs/sdr-and-aio-integration.md#11-building-the-card-offline-from-an-x86-machine)
  (mkinitcpio warnings, Chromium crashing under qemu while the theme is set,
  skipped systemd hooks) is harmless.

### Choices the scripts make

- **User `alarm`**, the base image's account, with sudo through `wheel`, and
  autologin on tty1 into Hyprland. Change both passwords on first boot
  (README step 3). To rename the user, see
  [section 10](../docs/sdr-and-aio-integration.md#10-renaming-the-default-alarm-user).
- **Omarchy** is a shallow `git clone` of `basecamp/omarchy` (its default
  branch) into `/usr/share/omarchy`, with its commands linked into `/usr/bin`
  and `/usr/local/bin`. It is not the `omarchy` pacman package. Omarchy's
  systemd user units are copied into `/usr/lib/systemd/user/`, as the package
  would.
- **Omarchy's own packages** (`herdr`, `aether`, `ttfx`, ...) come prebuilt from
  `https://pkgs.omarchy.org/edge/aarch64`, signed with Omarchy's key
  (`40DFB630FF42BCFFB047046CF0134EE680CAC571`). The repo is added last; the first
  `omarchy update` moves it first (see [docs/updating.md](../docs/updating.md)).
- **Time zone** is copied from the build machine.
- **AIO V2 boot rails:** USB hub on, SDR/GPS/LoRa off, to save battery.
- **meshtasticd** is installed and configured but not enabled.

## After first boot

On the uConsole, in order:

1. Change the passwords (`passwd` and `sudo passwd`), and connect to Wi-Fi if
   you did not preload it (`nmcli device wifi connect "<SSID>" --ask`).
   Use `--ask` rather than putting the password on the command line, where it
   ends up in your shell history.
2. Fix the clock and write it to the AIO's RTC:
   [section 1](../docs/sdr-and-aio-integration.md#1-clock-two-problems-that-keep-it-wrong).
3. GPIO without root, the Omarchy SDR menu, Meshtastic and the rest of
   [docs/sdr-and-aio-integration.md](../docs/sdr-and-aio-integration.md).
4. Run the first Omarchy update as described in
   [docs/updating.md](../docs/updating.md). It has two known blockers on this
   install, both with workarounds.
5. Desktop fixes (keyring, remote access):
   [docs/desktop-fixes.md](../docs/desktop-fixes.md).
