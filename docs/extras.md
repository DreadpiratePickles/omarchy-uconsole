# Extras that work on ARM

Applications people usually assume are unavailable on aarch64, and how to get them.

## Obsidian

Obsidian **does** publish ARM64 Linux builds, but only on its GitHub releases,
not in any Arch repository, which is why package audits report it missing.

One catch: the *latest* release tag is often Android-only. Walk back to the most
recent tag that carries desktop assets.

```bash
curl -s "https://api.github.com/repos/obsidianmd/obsidian-releases/releases?per_page=8" \
  | grep -o '"name": "obsidian-[0-9.]*-arm64.tar.gz"'
```

Then install the tarball (preferred over the AppImage, which needs FUSE):

```bash
curl -fsSLO https://github.com/obsidianmd/obsidian-releases/releases/download/v1.13.7/obsidian-1.13.7-arm64.tar.gz
sudo mkdir -p /opt/obsidian
sudo tar xzf obsidian-1.13.7-arm64.tar.gz -C /opt/obsidian --strip-components=1
sudo chmod 4755 /opt/obsidian/chrome-sandbox
sudo ln -sf /opt/obsidian/obsidian /usr/local/bin/obsidian
sudo install -Dm644 /opt/obsidian/resources/icon.png \
  /usr/share/icons/hicolor/512x512/apps/obsidian.png
```

Run it natively on Wayland rather than through XWayland, which matters for text
sharpness on the DSI panel:

```
Exec=/opt/obsidian/obsidian --enable-features=UseOzonePlatform --ozone-platform=wayland %u
```

**Cost:** roughly 700 MB resident, 337 MB on disk. It runs on a 4 GB CM4, but
Obsidian plus a browser plus a compile will push you into swap. If Electron ever
refuses to start after a kernel change, add `--no-sandbox`.

## lla

A Rust `ls` replacement. Not in the repos or the AUR, so build it:

```bash
cargo install lla
```

Add `~/.cargo/bin` to your PATH.

## bat

Already in the official repos as a prebuilt aarch64 package — no cargo needed:

```bash
sudo pacman -S bat
```

## keyd

The right way to remap keys system-wide. See Step 13 in the main README.

## Not available for aarch64

No official ARM packages, and worth knowing before you go looking:

- **Security:** `ffuf`, `dirb`, `john`, `seclists`
- **Radio:** `chirp`, `fldigi`, `wsjtx`, `js8call`, `gpredict`, `welle.io`, `csdr`
- **Other:** `dotnet-runtime` and anything depending on it, `obs-studio`

Some of these have AUR recipes that build fine; they simply have no binary.
