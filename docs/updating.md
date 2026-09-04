# Updating Omarchy on ARM

**Do not run `omarchy-update`.** It will not work on this install, and the reason
is structural rather than a bug.

## Why the built-in updater does not apply

`omarchy-update` assumes Omarchy was installed as a pacman package. Two of its
steps make that explicit:

```bash
# omarchy-update-system-pkgs
sudo pacman -Syu --overwrite '/usr/share/omarchy/*'

# omarchy-update-keyring
omarchy-pkg-add omarchy-keyring
```

The first expects a package to own `/usr/share/omarchy`. On an ARM install that
directory is a git checkout, so `pacman -Syu` upgrades your system but never
touches Omarchy. The second installs Omarchy's signing keyring so it can pull
from their package repository, which publishes **x86_64 only**.

So at best it silently does nothing for Omarchy; at worst it fails on a missing
keyring package.

## What to run instead

```bash
./scripts/update-omarchy.sh
```

It does four things the built-in updater would have done differently:

1. `pacman -Syu` for the system, same as upstream.
2. `git pull` in `/usr/share/omarchy` to update Omarchy itself, which is the part
   the packaged updater would have handled.
3. **Relinks `bin/`** into `/usr/bin` and `/usr/local/bin`. Easy to forget: new
   `omarchy-*` commands appear between releases and will not exist on your PATH
   otherwise.
4. Lists pending migrations rather than running them blind.

## Migrations

Omarchy ships over 100 migration scripts in `migrations/`, timestamped and run
once each. Check what is pending before running them:

```bash
omarchy-migrate --pending
omarchy-migrate
```

Read the list first. Migrations that install packages from Omarchy's own
repository, or that touch Limine, Snapper or Plymouth, will fail on this install
because none of those apply here. A failed migration is usually harmless, but a
migration that rewrites boot configuration is not — this hardware boots through
Raspberry Pi firmware and `config.txt`, not Limine.

**Back up your boot files before any migration that mentions the bootloader:**

```bash
sudo cp /boot/config.txt /boot/config.txt.bak
sudo cp /boot/cmdline.txt /boot/cmdline.txt.bak
```

## Kernel updates are separate

The uConsole kernel comes from its own repository, not Arch's:

```bash
sudo pacman -Syu    # includes linux-uconsole-cm4-git if the repo is reachable
```

After any kernel update, verify the display overlay still exists under its
expected name before rebooting. The rename from `clockworkpi-uconsole` to
`clockworkpi-uconsole-cm4` is exactly the kind of change that blanks the panel:

```bash
grep clockworkpi /boot/config.txt
ls /boot/overlays/ | grep clockworkpi
```

If the name in `config.txt` is not in `/boot/overlays/`, fix it before you reboot.

## Omarchy's own packages

`ttfx`, `aether`, `herdr` and the rest have no ARM binaries, so a system upgrade
never updates them. Rebuild from their PKGBUILDs when they change:

```bash
./scripts/build-omarchy-pkgs.sh
```
