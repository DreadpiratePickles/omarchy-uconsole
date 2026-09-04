#!/bin/bash
set -euo pipefail
DEST=/usr/share/omarchy
echo "==> Installing Omarchy tree to $DEST"
if [ -d "$DEST/.git" ]; then
  sudo git -C "$DEST" fetch --depth 1 origin && sudo git -C "$DEST" reset --hard origin/HEAD
else
  sudo rm -rf "$DEST"
  sudo git clone --depth 1 https://github.com/basecamp/omarchy.git "$DEST"
fi

echo "==> Linking omarchy-* commands onto PATH"
sudo mkdir -p /usr/local/bin
for f in "$DEST"/bin/*; do
  [ -f "$f" ] && sudo ln -sf "$f" "/usr/local/bin/$(basename "$f")"
done

echo "==> Installing system profile + session files"
sudo install -Dm644 "$DEST/etc/profile.d/omarchy.sh" /etc/profile.d/omarchy.sh
sudo install -Dm644 "$DEST/default/uwsm/env.d/10-omarchy" /usr/share/uwsm/env.d/10-omarchy
sudo mkdir -p /usr/share/wayland-sessions
sudo cp "$DEST"/default/wayland-sessions/*.desktop /usr/share/wayland-sessions/ 2>/dev/null || true

echo "==> Seeding user configs (existing files preserved)"
mkdir -p "$HOME/.config"
cp -rn "$DEST"/config/* "$HOME/.config/" 2>/dev/null || true

echo "==> Hooking bashrc"
if ! grep -q 'omarchy/default/bash/env-bootstrap' "$HOME/.bashrc"; then
  cat >> "$HOME/.bashrc" <<'EOF'

# Omarchy environment
[[ -r /usr/share/omarchy/default/bash/env-bootstrap ]] && source /usr/share/omarchy/default/bash/env-bootstrap
[[ $- == *i* && -r "$OMARCHY_PATH/default/bash/rc" ]] && source "$OMARCHY_PATH/default/bash/rc"
EOF
fi

echo "==> Writing uConsole monitor config"
mkdir -p "$HOME/.config/hypr"
cat > "$HOME/.config/hypr/monitors.lua" <<'EOF'
-- ClockworkPi uConsole CM4.
-- The 5" DSI panel is natively 720x1280 (portrait) but physically mounted
-- landscape, so the output needs a rotation transform. transform 3 = 270 deg.
-- If the image comes up upside down, change this to 1 (90 deg).
hl.monitor({
  output = "DSI-1",
  mode = "720x1280@60",
  position = "0x0",
  scale = 1,
  transform = 3,
})

-- Panel is small; keep XWayland apps unscaled.
hl.env("GDK_SCALE", "1")
EOF

echo "==> Done"
