# Omarchy package availability on aarch64

Of the 147 packages in Omarchy's `install/omarchy-base.packages`, **120 are
available** in the Arch Linux ARM repositories and install directly. `quickshell`,
which drives Omarchy's entire bar and shell, is among them.

## The 27 that are not

### Omarchy's own tools — all buildable

Not on the AUR, but **all published as PKGBUILDs** at
[omacom/omarchy-pkgs](https://github.com/omacom/omarchy-pkgs), and every one
declares `aarch64`. Upstream just does not publish ARM binaries.

`aether`, `cliamp`, `herdr`, `omacalc`, `omacut`, `omawrite`, `omarchy-nvim`,
`tensaku`, `tobi-try`, `ttfx`

Sources live on the same GitHub account: `omacom/ttfx` (Rust), `omacom/aether`
(Go, ships an ARM64 release binary), `omacom/herdr` (Rust), `omacom/omacalc`,
`omacom/omacut`, `omacom/omawrite` (C++/Qt6).

`ttfx` is the important one — it drives the screensaver, and without it the
console fills with `command not found`.

### Also in omarchy-pkgs

`ttf-ia-writer`, `yaru-icon-theme`, `yay`, `tzupdate`, `mise-bin`, `localsend`,
`asdcontrol`, `hyprland-preview-share-picker`, `ufw-docker`,
`ttf-jetbrains-mono-nerd-basic`

Use the official `ttf-jetbrains-mono-nerd` rather than the `-basic` variant, and
skip `ufw-docker` unless you want Docker.

### From the AUR
`xdg-terminal-exec` — needed, architecture independent, builds in seconds.
Omarchy's terminal shortcut does not work without it.

### Genuinely x86-bound or not worth it
`dotnet-runtime` and `pinta` (depends on it), `obs-studio`,
`qemu-user-static-binfmt`

### Naming quirk
`nvim` is Omarchy's own alias package. Install `neovim` from the official repos.

## What this build deliberately skips

Present for x86 Omarchy, omitted here as wrong for a 4 GB handheld with a 5 inch
screen:

`libreoffice-fresh`, `kdenlive`, `obs-studio`, `obsidian`, `moonlight-qt`,
`docker` and friends, the `cups` printing stack, `nautilus` and the `gvfs`
backends, `xournalpp`, `tesseract`, `plymouth`, `sddm`

Add any of them back with `pacman -S` if you disagree; nothing depends on their
absence.

## GPU

The uConsole's Compute Module uses Broadcom VideoCore, so the driver stack is
`mesa` plus `vulkan-broadcom`, driven by the `v3d` kernel driver. Do **not**
install `freedreno` or `turnip`; those target Qualcomm Adreno and are irrelevant
here. Hardware acceleration works out of the box once `v3d` is bound.
