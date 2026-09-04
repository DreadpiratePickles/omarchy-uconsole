#!/bin/bash
# Build Omarchy's own packages from their published PKGBUILDs.
# They all declare aarch64; upstream simply does not publish ARM binaries.
LOG=/tmp/omapkgs.log
: > "$LOG"

echo "==> waiting for any running pacman to finish" | tee -a "$LOG"
while pgrep -x pacman >/dev/null || pgrep -x cargo >/dev/null; do sleep 15; done

cd ~ || exit 1
rm -rf omarchy-pkgs
git clone --depth 1 https://github.com/omacom/omarchy-pkgs.git >>"$LOG" 2>&1 || exit 1

# Ordered: cheap/no-compile first, then toolchain-heavy.
PKGS=(
  ttf-ia-writer
  ttf-jetbrains-mono-nerd-basic
  yaru-icon-theme
  tobi-try
  omarchy-nvim
  yay
  ttfx
  tzupdate
  herdr
  cliamp
  omacalc
  omawrite
  omacut
  tensaku
  mise-bin
)

OK=(); FAIL=()
for p in "${PKGS[@]}"; do
  d=~/omarchy-pkgs/pkgbuilds/$p
  [ -d "$d" ] || { FAIL+=("$p(no pkgbuild)"); continue; }
  echo "=================== BUILD $p ===================" >>"$LOG"
  if ( cd "$d" && makepkg -si --noconfirm --needed >>"$LOG" 2>&1 ); then
    OK+=("$p"); echo "OK   $p" | tee -a "$LOG"
  else
    FAIL+=("$p"); echo "FAIL $p" | tee -a "$LOG"
  fi
done

echo "" | tee -a "$LOG"
echo "BUILT:  ${OK[*]}" | tee -a "$LOG"
echo "FAILED: ${FAIL[*]}" | tee -a "$LOG"
echo "EXIT=0" >> "$LOG"
