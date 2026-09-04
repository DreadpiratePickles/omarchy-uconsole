# zsh, Powerlevel10k and the Omarchy shell

Omarchy ships bash with its own prompt and a large set of `omarchy-*` helper
functions. Moving to zsh is fine, but two things will break silently if you just
run `chsh`.

## 1. Your desktop will stop starting

If you followed the console-autologin approach, the Hyprland session launches from
`~/.bash_profile`. **zsh never reads that file.** After `chsh` you autologin to a
bare console with no desktop and no obvious reason why.

Port the block to `~/.zprofile` — see [config/zprofile](../config/zprofile):

```zsh
if [[ -z $WAYLAND_DISPLAY && $XDG_VTNR == 1 ]]; then
  exec Hyprland &> ~/.local/share/hyprland-session.log
fi
```

Test the condition without launching anything:

```bash
env -u WAYLAND_DISPLAY XDG_VTNR=1 zsh -c '[[ -z $WAYLAND_DISPLAY && $XDG_VTNR == 1 ]] && echo would-start || echo BROKEN'
env -u WAYLAND_DISPLAY XDG_VTNR=3 zsh -c '[[ -z $WAYLAND_DISPLAY && $XDG_VTNR == 1 ]] && echo BROKEN || echo correctly-skips'
```

Keep `~/.bash_profile` in place as a fallback.

## 2. The omarchy-* commands stop resolving

`OMARCHY_PATH` and Omarchy's PATH additions come from a POSIX shell script that
plain zsh cannot source directly. Wrap it:

```zsh
[ -r /usr/share/omarchy/default/bash/env-bootstrap ] && \
  emulate sh -c "source /usr/share/omarchy/default/bash/env-bootstrap"
```

Put it in **both** `.zshrc` and `.zprofile`; login shells and interactive shells
take different paths. Verify with `zsh -l -c 'command -v omarchy-theme-set'`.

## Packages

Everything is in the official repos; no AUR needed:

```bash
sudo pacman -S --needed zsh git fzf zoxide ttf-jetbrains-mono-nerd
```

Omarchy already uses **JetBrains Mono Nerd Font** everywhere — its foot, Alacritty
and Ghostty configs all name it — so the font step is usually already done. Guides
written for Debian tell you to install `fonts-jetbrains-mono`, which is the plain
typeface **without** Nerd Font glyphs; Powerlevel10k icons would render as boxes.
Install the `-nerd` variant.

## The wizard does not launch on first terminal

This one is confusing. `foot` launches whatever `$SHELL` says, and a Hyprland
session that started *before* you ran `chsh` still carries `SHELL=/bin/bash`. You
get bash, no wizard, and nothing looks wrong.

Either reboot, or pin the terminal explicitly in `~/.config/foot/foot.ini`:

```ini
[main]
shell=/usr/bin/zsh
```

## Config

[config/zshrc](../config/zshrc) is a Zinit + Powerlevel10k + fzf-tab + zoxide
setup with the Omarchy bootstrap prepended. Note `HISTFILE=~/.zsh_history`, which
is the zsh convention.

On first interactive launch Zinit clones and compiles the plugins, then the
Powerlevel10k wizard runs. On a 1280x720 5-inch panel, **Transient prompt is worth
enabling** — it collapses old prompts back to a single line and reclaims a
surprising amount of vertical space.

If a plugin silently fails to download (fzf-tab did for us), install it directly:

```bash
zsh -i -c 'zinit light Aloxaf/fzf-tab'
ls ~/.local/share/zinit/plugins/     # expect six entries
```

## Validate before you switch shells

A broken zsh locks you out of SSH, because SSH uses your login shell. Check first:

```bash
zsh -n ~/.zshrc && zsh -n ~/.zprofile
zsh -i -c 'echo ok'
```

Only then `sudo chsh -s /usr/bin/zsh $USER`.
