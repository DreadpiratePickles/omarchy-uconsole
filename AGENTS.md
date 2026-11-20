# AGENTS.md

Instructions for AI agents installing, upgrading or fixing Omarchy on a
ClockworkPi uConsole (CM4) with the HackerGadgets AIO V2, using this
repository. Humans: the same steps are explained in the [README](README.md)
and [docs/](docs).

## The configuration

| Part | What it is |
| --- | --- |
| Hardware | uConsole, Raspberry Pi CM4 **Lite** (boots from microSD), AIO V2 (RTL-SDR, GPS on `/dev/ttyS0`, SX1262 LoRa on SPI1, USB hub, RTC). Each AIO radio has a power rail on a GPIO: SDR 7, GPS 27, LoRa 16, USB 23 |
| Base OS | Arch Linux ARM from [wdkdot/uconsole-arch](https://github.com/wdkdot/uconsole-arch) v2026.07.04, kernel `linux-uconsole-cm4` from the `[uconsole-arch]` repo. ext4 root. Boots via Raspberry Pi firmware and `/boot/config.txt`: no Limine, no Snapper, no btrfs |
| Omarchy | A **git checkout** of `basecamp/omarchy` in `/usr/share/omarchy` (tested: `quattro` at `e6d5a17`), commands linked into `/usr/bin` and `/usr/local/bin`. **Not** the `omarchy` pacman package |
| Omarchy packages | Prebuilt aarch64 from `[omarchy]` = `https://pkgs.omarchy.org/edge/aarch64`, key `40DFB630FF42BCFFB047046CF0134EE680CAC571` |
| Session | Autologin on tty1 into Hyprland (user `alarm` on a fresh card); Left Alt is Super via keyd |
| AIO and SDR | `aiov2_ctl`, `aio-run` (powers rails per app), gpsd on `/dev/ttyS0`, meshtasticd (not enabled at boot), SDR apps, Omarchy SDR menu on Alt + R |

## Repository map

- `sdcard/`: build a complete card offline on x86 Linux. **Start here for a new install.** [sdcard/README.md](sdcard/README.md)
- `docs/updating.md`: the upgrade procedure and known blockers. **Read before any `omarchy update`.**
- `docs/sdr-and-aio-integration.md`: clock, GPIO without root, aarch64 package fixes, Meshtastic, power management, Omarchy SDR integration, agent CLIs.
- `docs/aio-v2.md`, `docs/sdr-toolkit.md`: AIO V2 bring-up and SDR packages.
- `docs/desktop-fixes.md`: keyring, gnome-keyring daemon race, running Omarchy commands over SSH, Tailscale.
- `scripts/`: `update-omarchy.sh`, `deploy-omarchy.sh`, `build-omarchy-pkgs.sh` (fallback only), `keyring-passwordless`, `sdr/` tools and PKGBUILDs.
- `config/`: files the docs install (`aio-v2/`, `meshtastic/`, `keyring/`, `tether/`, monitors, keyd).

## New install

1. Build the card: [sdcard/README.md](sdcard/README.md) (`sudo ./sdcard/build-sdcard.sh /dev/sdX`,
   then the `fixup-chroot.sh` pass). It runs for about an hour.
2. On the uConsole, follow [sdcard/README.md, After first boot](sdcard/README.md#after-first-boot):
   passwords and Wi-Fi, clock/RTC, GPIO group, SDR integration, then the first update.

Without an x86 build machine, follow README steps 1-17 on the device. Step 11
must include installing `default/systemd/user/*`, and step 16 should use the
`[omarchy]` repository.

## Upgrade

On the uConsole, from the desktop session:

```bash
./scripts/update-omarchy.sh
```

This pulls `/usr/share/omarchy` (`omarchy update` does not), relinks commands,
copies `default/systemd/user/*` to `/usr/lib/systemd/user/`, marks migration
`1781984677` done when Snapper is absent, then runs `omarchy update`. If the
update stops, read `/tmp/omarchy-update.log`, find the last
`Running migration (…)`, read that file in `/usr/share/omarchy/migrations/`,
fix the cause, and run `omarchy update` again. Known blockers and fixes:
[docs/updating.md](docs/updating.md#known-blockers).

Verify:

```bash
omarchy-migrate --pending | wc -l   # 0
systemctl --user --failed; systemctl --failed
rfkill list bluetooth               # not soft-blocked
grep clockworkpi /boot/config.txt; ls /boot/overlays | grep clockworkpi   # names match
```

## Rules

- **Privilege:** `sudo` needs the user's password. When you have no terminal
  for it, give the user the exact command to run (in Claude Code: `! sudo …`).
  Do not try to work around sudo.
- **Never change `/boot` without a backup** (`config.txt`, `cmdline.txt`), and
  never reboot after a kernel update until the overlay named in `config.txt`
  exists in `/boot/overlays/`. A wrong overlay name blanks the panel.
- **Do not edit files in `/usr/share/omarchy`**; `git pull` there must stay a
  fast-forward. Put changes in `~/.config`, `/usr/local`, or this repository.
- **Do not skip migrations blindly.** Only `1781984677` is known to need
  skipping on this install. For any other failure, read the migration and fix
  its precondition. A migration is marked done with
  `touch ~/.local/state/omarchy/migrations/<name>.sh`.
- **Leave `[omarchy]` first in `/etc/pacman.conf`** after the first update
  (migration `1790917620` puts it there).
- **After changing a bar plugin**, run `omarchy restart shell`.
- **Over SSH**, set the session environment first:
  [docs/desktop-fixes.md section 3](docs/desktop-fixes.md#3-running-omarchy-commands-over-ssh).
- **Privacy:** never write Wi-Fi names or passwords, MAC or Bluetooth
  addresses, Tailscale names or IPs, usernames, home paths, GPS coordinates,
  tokens or keys into this repository, its commit messages, or shell history.
  Use `nmcli … --ask` instead of `password …` on the command line. Before
  committing, search the diff for these.
- **Shell safety:** when writing files from a shell, never wrap document text in
  a heredoc whose delimiter (such as `EOF`) can appear in the text. Use a file
  editing tool, or a unique delimiter.

## Hardware facts agents get wrong

- The CM4's Bluetooth needs `bt-set-address.service` (`config/aio-v2`) for a
  unique address and headset audio. It fails if Bluetooth is rfkill-blocked.
- GPS (`/dev/ttyS0`) is shared by gpsd and, when Meshtastic uses GPS,
  meshtasticd. Only one should read it at a time.
- Without the GPIO setup in docs/sdr-and-aio-integration.md section 2,
  `aiov2_ctl` reports every rail as off even when it is on.
- The clock is wrong at boot until the RTC and NTP fixes in section 1 are applied.
