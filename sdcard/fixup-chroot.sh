#!/usr/bin/env bash
# Second pass, inside the card's root: rebuild SDR++ (without the broken
# weather-sat decoder) and give meshtasticd its yaml-cpp 0.8 runtime.
set -euo pipefail
SRC=/root/sdcard-src
FAILED=()
log()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m!!  %s\033[0m\n' "$*"; }

BUILD=/var/tmp/sdr-build
rm -rf "${BUILD}"; mkdir -p "${BUILD}"
cp -a "${SRC}/pkgs/yaml-cpp08-compat" "${SRC}/pkgs/sdrpp-git" "${BUILD}/"
chown -R alarm:alarm "${BUILD}"
for p in yaml-cpp08-compat sdrpp-git; do
  log "building ${p}"
  if runuser -u alarm -- env HOME=/home/alarm bash -c \
      "cd '${BUILD}/${p}' && MAKEFLAGS=-j$(nproc) makepkg --noconfirm --nocheck -f"; then
    f=$(find "${BUILD}/${p}" -maxdepth 1 -name '*.pkg.tar.*' ! -name '*-debug-*' | head -1)
    pacman --noconfirm -U "$f" || { warn "install ${p} failed"; FAILED+=("$p"); }
  else
    warn "build ${p} failed"; FAILED+=("$p")
  fi
done
rm -rf "${BUILD}"

log "meshtasticd library check"
if ldd /usr/bin/meshtasticd | grep 'not found'; then
  warn "meshtasticd still has missing libraries"; FAILED+=(meshtasticd-libs)
else
  echo "    all meshtasticd libraries resolve"
fi

pacman -Scc --noconfirm >/dev/null 2>&1 || true
# The verify step reads this file; sdrangel has no installable aarch64 package.
printf '%s\n' "${FAILED[@]}" sdrangel-unavailable > /root/sdcard-build-failures.txt
((${#FAILED[@]})) && warn "Non-fatal failures: ${FAILED[*]}" || echo "Fix-up pass succeeded."
