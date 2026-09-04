#!/usr/bin/env bash
# Update Omarchy on an ARM install.
#
# Do NOT use `omarchy-update` here. It assumes Omarchy was installed as a pacman
# package that owns /usr/share/omarchy, and it pulls from Omarchy's own package
# repository, which is x86_64 only. On this install /usr/share/omarchy is a git
# checkout, so the update path is a git pull plus a normal system upgrade.
set -euo pipefail

OMARCHY_PATH=${OMARCHY_PATH:-/usr/share/omarchy}

echo "==> System packages"
sudo pacman -Syu --noconfirm

echo "==> Omarchy itself"
if [ -d "$OMARCHY_PATH/.git" ]; then
  before=$(sudo git -C "$OMARCHY_PATH" rev-parse --short HEAD)
  sudo git -C "$OMARCHY_PATH" fetch --depth 1 origin
  sudo git -C "$OMARCHY_PATH" reset --hard origin/HEAD
  after=$(sudo git -C "$OMARCHY_PATH" rev-parse --short HEAD)
  echo "    $before -> $after"
else
  echo "    $OMARCHY_PATH is not a git checkout; skipping" >&2
fi

echo "==> Relinking omarchy-* commands (new ones appear between releases)"
for f in "$OMARCHY_PATH"/bin/*; do
  [ -f "$f" ] || continue
  sudo ln -sf "$f" "/usr/bin/$(basename "$f")"
  sudo ln -sf "$f" "/usr/local/bin/$(basename "$f")"
done

echo "==> Pending migrations"
if command -v omarchy-migrate >/dev/null; then
  omarchy-migrate --pending || true
  echo "    Review the list above, then run: omarchy-migrate"
  echo "    Some migrations assume x86 packages and will fail harmlessly."
fi

echo "==> Rebuilding Omarchy's own packages (they have no ARM binaries)"
echo "    Run ./build-omarchy-pkgs.sh if ttfx, aether, herdr et al changed."

echo "==> Restarting the shell so the bar picks up changes"
if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
  omarchy-restart-shell || true
fi

echo "==> Done"
