#!/usr/bin/env bash
# Update Omarchy on the uConsole. See docs/updating.md.
#
# /usr/share/omarchy is a git checkout here, not the omarchy package, so:
#   1. pull the checkout and relink its commands (omarchy update does not);
#   2. install Omarchy's systemd user units where the package would;
#   3. skip the Snapper migration, which cannot work on an ext4 root;
#   4. run `omarchy update` for packages ([omarchy] has aarch64 builds) and
#      migrations.
# Run it on the uConsole from the desktop session. It asks for sudo.
#   --no-update   do steps 1-3 only
set -euo pipefail

OMARCHY_PATH=${OMARCHY_PATH:-/usr/share/omarchy}
STATE_DIR=${OMARCHY_MIGRATION_STATE:-$HOME/.local/state/omarchy/migrations}
SNAPPER_MIGRATION=1781984677.sh

echo "==> Omarchy checkout"
if [ -d "$OMARCHY_PATH/.git" ]; then
  git=(sudo git -c "safe.directory=$OMARCHY_PATH" -C "$OMARCHY_PATH")
  before=$("${git[@]}" rev-parse --short HEAD)
  "${git[@]}" pull --ff-only
  after=$("${git[@]}" rev-parse --short HEAD)
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

echo "==> Installing Omarchy's systemd user units into /usr/lib/systemd/user"
if [ -d "$OMARCHY_PATH/default/systemd/user" ]; then
  sudo cp -r "$OMARCHY_PATH/default/systemd/user/." /usr/lib/systemd/user/
  systemctl --user daemon-reload || true
fi

if ! command -v snapper >/dev/null && [ ! -e "$STATE_DIR/$SNAPPER_MIGRATION" ]; then
  echo "==> No Snapper: marking migration $SNAPPER_MIGRATION done (omacom/omarchy#6683)"
  mkdir -p "$STATE_DIR"
  touch "$STATE_DIR/$SNAPPER_MIGRATION"
fi

if [[ ${1:-} == --no-update ]]; then
  echo "==> Skipping omarchy update (--no-update)"
  exit 0
fi

echo "==> omarchy update"
omarchy update

echo "==> Checks"
echo "    pending migrations: $(omarchy-migrate --pending 2>/dev/null | wc -l)"
systemctl --user --failed --no-legend || true
systemctl --failed --no-legend || true
if rfkill list bluetooth 2>/dev/null | grep -q 'Soft blocked: yes'; then
  echo "    Bluetooth is soft-blocked (migration 1786380259). To fix:"
  echo "      sudo omarchy-bluetooth-power on && sudo systemctl restart bt-set-address.service"
fi
echo "==> Done. Check the kernel overlay before rebooting if the kernel changed (docs/updating.md)."
