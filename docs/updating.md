# Updating Omarchy on the uConsole

Tested on a uConsole CM4 with the AIO V2, built with [`sdcard/`](../sdcard),
Omarchy `quattro` branch at `e6d5a17` (2026-11-07; `/usr/share/omarchy/version`
says `4.0.0.alpha`), updated with `omarchy update` on 2026-11-08.

## How this install differs from a normal Omarchy

- **Omarchy itself is a git checkout** in `/usr/share/omarchy`, with its
  commands linked into `/usr/bin` and `/usr/local/bin`. It is not the `omarchy`
  pacman package, so `pacman -Qo /usr/share/omarchy` finds no owner.
- **Omarchy's own packages** (`herdr`, `aether`, `ttfx`, `omasnap`, ...) come
  prebuilt for aarch64 from `[omarchy]` at `https://pkgs.omarchy.org/edge/aarch64`.
  Omarchy did not publish ARM builds when this guide was first written; it does
  now. [`scripts/build-omarchy-pkgs.sh`](../scripts/build-omarchy-pkgs.sh) is
  only a fallback.
- **Root is ext4** and the uConsole boots through the Raspberry Pi firmware
  (`/boot/config.txt`). There is no btrfs, Snapper or Limine.

Each of these trips up `omarchy update` once. The fixes are below.

## What `omarchy update` does here

It works, with the preparation below. In order, it:

1. installs `omarchy-keyring` and runs `pacman -Syu --overwrite '/usr/share/omarchy/*'`,
   which updates Arch Linux ARM, the uConsole kernel repo and `[omarchy]`;
2. runs pending migrations from `/usr/share/omarchy/migrations` (about 240 on a
   fresh card), recording each in `~/.local/state/omarchy/migrations/`;
3. removes orphans, restarts services, and updates mise and AUR packages.

It does **not** update the git checkout: `omarchy-update-dev` skips
`/usr/share/omarchy`. Pull it yourself first (step 1 below).

## Update procedure

Run on the uConsole, from the desktop session (some migrations talk to the
running shell). It needs your sudo password.

```bash
cd ~/omarchy-uconsole            # this repository
./scripts/update-omarchy.sh      # steps 1-3, then runs `omarchy update`
```

Or by hand:

```bash
# 1. Update Omarchy itself, and relink its commands (new ones appear between releases)
sudo git -C /usr/share/omarchy pull --ff-only
for f in /usr/share/omarchy/bin/*; do
  sudo ln -sf "$f" /usr/bin/; sudo ln -sf "$f" /usr/local/bin/
done

# 2. Install Omarchy's systemd user units where the package would (blocker 2)
sudo cp -r /usr/share/omarchy/default/systemd/user/. /usr/lib/systemd/user/
systemctl --user daemon-reload

# 3. Skip the Snapper migration on ext4 (blocker 1)
command -v snapper >/dev/null || touch ~/.local/state/omarchy/migrations/1781984677.sh

# 4. Update
omarchy update

# 5. Check (below), then reboot
```

Repeat step 2 after every pull: nothing else keeps those copies current.

## Known blockers

### 1. Migration `1781984677` "Normalize Snapper snapshot services"

The update stops with `snapper: command not found` (exit code 127) right after
`Running migration (1781984677)`.

The migration decides Snapper needs repair because `/etc/snapper/configs/root`
is missing, then runs `install/config/snapper.sh`, which needs Snapper and a
btrfs root. It stops the update, and every later migration with it.

**Fix:** mark it done, then run `omarchy update` again:

```bash
touch ~/.local/state/omarchy/migrations/1781984677.sh
```

The other ~30 migrations that mention Snapper, Limine or btrfs check for them
and exit cleanly. Upstream: [omacom/omarchy#6683](https://github.com/omacom/omarchy/issues/6683)
(ext4/XFS roots; Omarchy only supports btrfs installs from its ISO).

### 2. Migration `1785608166` "Repair the pre-suspend lock monitor"

The update stops because `omarchy-sleep-lock.service` does not exist. Earlier in
the same run there is a warning with the same cause:

```
Could not start omarchy-fcitx5.service: Failed to start omarchy-fcitx5.service: Unit omarchy-fcitx5.service not found.
```
 The `omarchy` package installs `default/systemd/user/*` into
`/usr/lib/systemd/user/`; a git checkout never does, so units such as
`omarchy-sleep-lock`, `omarchy-fcitx5`, `bt-agent` and `omarchy-crash-watch`
do not exist.

**Fix:** step 2 of the procedure, then `omarchy update` again. Cards built
with the current `sdcard/chroot-setup.sh` already have them. Leave out
`default/systemd/system/` and `system-sleep/`: they are for hardware the
uConsole does not have (fingerprint readers, Cam Link, hybrid GPUs).

Once installed, `omarchy-sleep-lock` logs
`dbus-monitor: unable to enable new-style monitoring ... Falling back to eavesdropping`.
It keeps running.

### 3. Bluetooth is off after the update

Migration `1786380259` "Remember Bluetooth on and off through the rfkill soft
block" reads whether the adapter is powered and turns Bluetooth off with rfkill
if it is not. On the uConsole the adapter can read as unpowered at that
moment, and the block survives reboots. `bt-set-address.service`
([config/aio-v2](../config/aio-v2)) then fails with `OSError: [Errno 100] Network is down`.

**Fix:**

```bash
sudo omarchy-bluetooth-power on        # or: sudo rfkill unblock bluetooth
sudo systemctl restart bt-set-address.service
```

### Harmless

- `warning: limesuite: local (…) is newer than alarm (…)` and the same for
  `soapyrtlsdr`: these are local builds
  ([docs/sdr-and-aio-integration.md, section 3](sdr-and-aio-integration.md#3-broken-aarch64-packages-and-how-to-find-them)).
  Keep them.
- If the update stops, the full log is `/tmp/omarchy-update.log` (gone after a
  reboot). Find the failing migration in it, read it in
  `/usr/share/omarchy/migrations/`, fix the cause, and run `omarchy update`
  again; it continues from the first pending migration.

## What changes after the first update

- **Repository order:** migration `1790917620` moves `[omarchy]` ahead of
  `[core]`/`[extra]`/`[alarm]` in `/etc/pacman.conf`. From then on Omarchy's
  aarch64 builds of `hyprland`, `quickshell`, `aquamarine`, `ffmpeg` and
  `alsa-ucm-conf` replace Arch Linux ARM's. That is Omarchy's supported layout;
  leave it.
- **Package swaps by migrations:** `omasnap` replaces `tensaku`,
  `omarchy-power-profiles-daemon` replaces `power-profiles-daemon`,
  `disktree-bin` replaces `dua-cli` (which an earlier migration in the same run installs), and `quickshell` may be swapped for
  `quickshell-git` and back. New: `owe`, `owe-lockfeed`, `hype`, `monologue`,
  `gliff`, `signed`, `omarchy-screensaver`, `omarchy-local-ai`,
  `omarchy-hyprland-titlebars`, `ddcutil`, `rtkit`, and the fcitx5 input methods.
- **First-run steps** that failed before (`enable user systemd units` in
  `~/.local/state/omarchy/first-run.log`) succeed at the next login.

## Check after updating

```bash
omarchy-migrate --pending | wc -l        # 0
systemctl --user --failed                # nothing
systemctl --failed                       # nothing (bt-set-address: see blocker 3)
rfkill list bluetooth                    # Soft blocked: no
grep -n '^\[' /etc/pacman.conf           # [omarchy] before [core]
```

Then reboot. Check the kernel and overlay before rebooting if the kernel was
updated (next section).

## Kernel updates

The uConsole kernel comes from its own repository (`[uconsole-arch]`), and
`pacman -Syu` (inside `omarchy update`) updates it. After a kernel update,
check that the display overlay named in `config.txt` still exists before you
reboot. The rename from `clockworkpi-uconsole` to `clockworkpi-uconsole-cm4`
is exactly the kind of change that blanks the panel:

```bash
grep clockworkpi /boot/config.txt
ls /boot/overlays/ | grep clockworkpi
```

If the name in `config.txt` is not in `/boot/overlays/`, fix it first. Back up
`/boot/config.txt` and `/boot/cmdline.txt` before any update that touches the
bootloader; no migration in the tested run did.

## Bar plugins

After updating a plugin in `~/.config/omarchy/plugins/`, run
`omarchy restart shell`. See [desktop-fixes.md](desktop-fixes.md#4-bar-plugins-restart-the-shell-after-an-update).
