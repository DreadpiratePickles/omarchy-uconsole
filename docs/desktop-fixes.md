# Desktop fixes: keyring, shell and remote admin

Fixes for problems that show up once the desktop is running, after the steps in
the [README](../README.md). None of them is specific to the AIO V2.

## Contents

1. [The keyring asks for a password after every boot](#1-the-keyring-asks-for-a-password-after-every-boot)
2. [Two gnome-keyring daemons at login](#2-two-gnome-keyring-daemons-at-login)
3. [Running Omarchy commands over SSH](#3-running-omarchy-commands-over-ssh)
4. [Bar plugins: restart the shell after an update](#4-bar-plugins-restart-the-shell-after-an-update)
5. [Remote access with Tailscale](#5-remote-access-with-tailscale)

---

## 1. The keyring asks for a password after every boot

The uConsole logs in automatically on tty1 (Step 14), so PAM never sees a
password and cannot unlock the GNOME keyring. If the keyring was created with a
password, for example the first time Chromium or `gh auth login` asked for one,
every boot brings an unlock prompt. There is no default password to type: it is
whatever was entered when the keyring was made. (`cpi`/`cpi` is the login on
ClockworkPi's own OS image, not on this one.)

The fix that matches autologin is a keyring with no password. The trade-off:
anyone who can read your home directory can read the stored secrets. With
autologin, a login password did not protect them at rest either.

**If you still know the password, or the keyring is unlocked right now,** keep
its contents. [`scripts/keyring-passwordless`](../scripts/keyring-passwordless)
copies every item (Chromium's Safe Storage key, `gh` tokens and so on) into a
new password-less keyring called `Login`, checks each copy, and makes it the
default:

```bash
cp -a ~/.local/share/keyrings ~/.local/share/keyrings.bak
python3 scripts/keyring-passwordless              # from the desktop session
python3 scripts/keyring-passwordless --delete-old # or delete the old one later
```

Keeping Chromium's Safe Storage key matters: without it Chromium cannot decrypt
its saved passwords and cookies.

**If the password is lost,** the contents are lost too. Start over:

```bash
rm ~/.local/share/keyrings/*.keyring
```

Log out and in. The next app that needs the keyring asks you to create one:
leave the password empty and accept the warning.

Check: `head -c 9 ~/.local/share/keyrings/Login.keyring` prints `[keyring]`
for a password-less keyring. An encrypted one starts with `GnomeKeyring`.

## 2. Two gnome-keyring daemons at login

`pgrep -a gnome-keyring` can show two daemons started in the same second:

```
gnome-keyring-daemon --start --foreground --components=secrets
gnome-keyring-daemon --foreground --components=pkcs11,secrets --control-directory=/run/user/1000/keyring
```

The second is `gnome-keyring-daemon.service` (socket-activated by systemd). The
first is D-Bus starting its own copy on the first request for
`org.freedesktop.secrets`, because the package's D-Bus service file has no
`SystemdService=` line. They race for the same bus name; one wins and the other
sits idle, and an early request can reach the wrong one. That shows up as
unlock prompts and secrets that seem to go missing.

Make D-Bus use the systemd unit instead:

```bash
install -Dm644 config/keyring/org.freedesktop.secrets.service \
  ~/.local/share/dbus-1/services/org.freedesktop.secrets.service
```

It takes effect at the next login. To clean up now without logging out:

```bash
busctl --user status org.freedesktop.secrets | grep -E '^(PID|Unit)'   # the one in use
systemctl --user list-units 'dbus-*org.freedesktop.secrets*'           # the extra one
systemctl --user stop 'dbus-:1.2-org.freedesktop.secrets@0.service'    # name from the line above
```

## 3. Running Omarchy commands over SSH

An SSH login does not have the desktop session's environment, so `omarchy`
commands fail with errors such as `OMARCHY_PATH: unbound variable`, and
`hyprctl` cannot find Hyprland. Set the variables first:

```bash
export OMARCHY_PATH=/usr/share/omarchy PATH=/usr/share/omarchy/bin:$PATH
export XDG_RUNTIME_DIR=/run/user/$(id -u) WAYLAND_DISPLAY=wayland-1
export DBUS_SESSION_BUS_ADDRESS=unix:path=$XDG_RUNTIME_DIR/bus
export HYPRLAND_INSTANCE_SIGNATURE=$(ls $XDG_RUNTIME_DIR/hypr | head -1)

omarchy bar set aio.radios barRadios "SDR, LoRa"
omarchy restart shell
grim /tmp/screen.png        # a screenshot of the uConsole's screen
```

`rsync` is not installed on the base image; use `scp` to copy files over, or
install it on both ends with `pacman -S rsync`.

## 4. Bar plugins: restart the shell after an update

The Omarchy shell reloads a plugin in `~/.config/omarchy/plugins/` when its files
change, but a JavaScript file imported with `.pragma library` (such as the AIO
radios widget's `Model.js`) can stay in memory in its old version. The widget then
runs new QML against old helpers, and new settings seem to do nothing. Run
`omarchy restart shell` after updating a plugin.

## 5. Remote access with Tailscale

Tailscale gives the uConsole a stable name on your own devices, wherever it is
connected (Wi-Fi, phone tethering), so you can SSH in to fix things without
using the small keyboard:

```bash
sudo pacman -S tailscale
sudo systemctl enable --now tailscaled
sudo tailscale up                 # prints a login URL; open it on another device
```

Then, from any of your other machines on the tailnet, `ssh <user>@uconsole`
(the default device name is the hostname). Use SSH keys rather than a
password: add your public key to `~/.ssh/authorized_keys` on the uConsole.
