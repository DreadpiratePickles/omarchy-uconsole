#!/usr/bin/env bash
# Runs INSIDE the uConsole root filesystem (aarch64, via qemu binfmt).
# Implements the README's steps 3 and 5-17, docs/aio-v2.md and
# docs/sdr-toolkit.md, plus extra SDR applications. Step numbers refer to the
# README. Steps that need the real hardware (RTC write, Wi-Fi) are left for
# first boot.
set -euo pipefail

SRC=/root/sdcard-src
TZ_NAME="${TZ_NAME:-America/New_York}"
USER_NAME=alarm
UHOME=/home/${USER_NAME}
OMARCHY_KEY=40DFB630FF42BCFFB047046CF0134EE680CAC571
AIO_COMMIT=c21ca742775b32ecea30b334e15a2d7f003e511a
FAILED=()

log()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m!!  %s\033[0m\n' "$*"; }
as_user() { runuser -u "${USER_NAME}" -- env HOME="${UHOME}" USER="${USER_NAME}" "$@"; }
pac() { pacman --noconfirm "$@"; }

# --------------------------------------------------------------------------
log "Step 5: disable pacman's Landlock sandbox (uConsole kernel lacks Landlock)"
grep -q '^DisableSandbox' /etc/pacman.conf || sed -i '/^\[options\]/a DisableSandbox' /etc/pacman.conf
grep -q '^ParallelDownloads' /etc/pacman.conf || sed -i '/^\[options\]/a ParallelDownloads = 5' /etc/pacman.conf

log "Step 6: pin known-good Arch Linux ARM mirrors"
cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.orig 2>/dev/null || true
cat > /etc/pacman.d/mirrorlist <<'EOF'
Server = http://fl.us.mirror.archlinuxarm.org/$arch/$repo
Server = http://nj.us.mirror.archlinuxarm.org/$arch/$repo
Server = http://ca.us.mirror.archlinuxarm.org/$arch/$repo
EOF
ln -sf "/usr/share/zoneinfo/${TZ_NAME}" /etc/localtime

if [[ ! -s /etc/pacman.d/gnupg/pubring.gpg && ! -s /etc/pacman.d/gnupg/pubring.kbx ]]; then
  pacman-key --init
  pacman-key --populate archlinuxarm
fi

log "Step 7: remove the stock linux-aarch64 kernel, then full upgrade"
if pacman -Qq linux-aarch64 >/dev/null 2>&1; then
  pac -R linux-aarch64        # plain -R: -s would cascade into linux-firmware
fi
pac -Syu

log "Step 8: point config.txt at the renamed CM4 overlay"
if [[ -e /boot/overlays/clockworkpi-uconsole-cm4.dtbo ]]; then
  sed -i 's/^dtoverlay=clockworkpi-uconsole$/dtoverlay=clockworkpi-uconsole-cm4/' /boot/config.txt
else
  warn "clockworkpi-uconsole-cm4.dtbo not present; leaving overlay name unchanged"
fi
ls /boot/overlays | grep -i clockwork || true
grep -n 'clockworkpi' /boot/config.txt

log "Step 3: give ${USER_NAME} sudo"
pac -S --needed sudo
usermod -aG wheel "${USER_NAME}"
install -Dm0440 /dev/stdin /etc/sudoers.d/10-wheel <<'EOF'
%wheel ALL=(ALL:ALL) ALL
EOF

log "Step 9: compressed swap"
pac -S --needed zram-generator
cat > /etc/systemd/zram-generator.conf <<'EOF'
[zram0]
zram-size = ram
compression-algorithm = zstd
EOF

log "Step 10: desktop packages (all prebuilt)"
mapfile -t DESKTOP < <(grep -v '^\s*#' "${SRC}/desktop-packages.txt" | sed '/^\s*$/d')
pac -S --needed "${DESKTOP[@]}"

log "Step 11: deploy Omarchy to /usr/share/omarchy"
DEST=/usr/share/omarchy
rm -rf "${DEST}"
git clone --depth 1 https://github.com/basecamp/omarchy.git "${DEST}"
git -C "${DEST}" log -1 --format='    omarchy @ %h %cd' --date=short
mkdir -p /usr/local/bin
for f in "${DEST}"/bin/*; do
  [[ -f "$f" ]] || continue
  ln -sf "$f" "/usr/local/bin/$(basename "$f")"
  # Several Omarchy scripts call siblings by absolute /usr/bin path.
  [[ -e "/usr/bin/$(basename "$f")" ]] || ln -sf "$f" "/usr/bin/$(basename "$f")"
done
install -Dm644 "${DEST}/etc/profile.d/omarchy.sh" /etc/profile.d/omarchy.sh 2>/dev/null || warn "no etc/profile.d/omarchy.sh upstream"
install -Dm644 "${DEST}/default/uwsm/env.d/10-omarchy" /usr/share/uwsm/env.d/10-omarchy 2>/dev/null || warn "no uwsm env.d upstream"
mkdir -p /usr/share/wayland-sessions
cp "${DEST}"/default/wayland-sessions/*.desktop /usr/share/wayland-sessions/ 2>/dev/null || true
# The omarchy package installs default/systemd/user/* into /usr/lib/systemd/user/.
# A git checkout does not, and later `omarchy update` migrations fail when they
# restart these units (omarchy-sleep-lock, omarchy-fcitx5, ...). See
# docs/updating.md. The system/ and system-sleep/ files are for hardware the
# uConsole does not have, so they are left out.
if [[ -d "${DEST}/default/systemd/user" ]]; then
  cp -r "${DEST}/default/systemd/user/." /usr/lib/systemd/user/
fi

mkdir -p "${UHOME}/.config"
cp -rn "${DEST}"/config/* "${UHOME}/.config/" 2>/dev/null || true
touch "${UHOME}/.bashrc"
if ! grep -q 'omarchy/default/bash/env-bootstrap' "${UHOME}/.bashrc"; then
  cat >> "${UHOME}/.bashrc" <<'EOF'

# Omarchy environment
[[ -r /usr/share/omarchy/default/bash/env-bootstrap ]] && source /usr/share/omarchy/default/bash/env-bootstrap
[[ $- == *i* && -r "$OMARCHY_PATH/default/bash/rc" ]] && source "$OMARCHY_PATH/default/bash/rc"
EOF
fi

# xdg-terminal-exec: now packaged for aarch64, no AUR build needed.
pac -S --needed xdg-terminal-exec chromium
[[ -f "${DEST}/default/xdg-terminal-exec/hyprland-xdg-terminals.list" ]] && \
  cp "${DEST}/default/xdg-terminal-exec/hyprland-xdg-terminals.list" "${UHOME}/.config/xdg-terminals.list"
mkdir -p "${UHOME}/.config"
cat > "${UHOME}/.config/mimeapps.list" <<'EOF'
[Default Applications]
x-scheme-handler/http=chromium.desktop
x-scheme-handler/https=chromium.desktop
text/html=chromium.desktop
EOF

log "Step 12: panel rotation"
install -Dm644 "${SRC}/files/monitors.lua" "${UHOME}/.config/hypr/monitors.lua"

log "Step 13: Left Alt -> Super with keyd"
pac -S --needed keyd
install -Dm644 "${SRC}/files/keyd-default.conf" /etc/keyd/default.conf
systemctl enable keyd.service

log "Step 14: autologin on tty1 and start Hyprland"
install -Dm644 /dev/stdin /etc/systemd/system/getty@tty1.service.d/autologin.conf <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o "-p -f -- \\\\u" --noclear --autologin ${USER_NAME} %I \$TERM
EOF
cat > "${UHOME}/.bash_profile" <<'EOF'
[[ -f ~/.bashrc ]] && . ~/.bashrc
if [[ -z $WAYLAND_DISPLAY && $XDG_VTNR == 1 ]]; then
  mkdir -p ~/.local/share
  exec Hyprland &> ~/.local/share/hyprland-session.log
fi
EOF

log "Step 16: Omarchy's own packages (prebuilt aarch64 from pkgs.omarchy.org)"
# Omarchy publishes aarch64 builds of its packages at pkgs.omarchy.org, so they
# no longer need compiling (scripts/build-omarchy-pkgs.sh is the fallback).
# The repo is appended LAST here, so Hyprland and Quickshell come from ALARM
# [extra]. The first `omarchy update` then runs migration 1790917620, which
# moves [omarchy] ahead of ALARM's repos, and Omarchy's own aarch64 builds of
# hyprland, quickshell, aquamarine, ffmpeg and alsa-ucm-conf replace ALARM's.
# That is the layout Omarchy supports; see docs/updating.md.
curl -fsSL -o /tmp/omarchy.asc "https://keys.openpgp.org/vks/v1/by-fingerprint/${OMARCHY_KEY}"
pacman-key --add /tmp/omarchy.asc
pacman-key --lsign-key "${OMARCHY_KEY}"
if ! grep -q '^\[omarchy\]' /etc/pacman.conf; then
  cat >> /etc/pacman.conf <<'EOF'

[omarchy]
SigLevel = Required DatabaseOptional
Server = https://pkgs.omarchy.org/edge/aarch64
EOF
fi
pac -Sy
OMA_PKGS=(ttf-ia-writer yaru-icon-theme tobi-try omarchy-nvim yay ttfx tzupdate
          herdr cliamp omacalc omawrite omacut tensaku mise-bin aether)
for p in "${OMA_PKGS[@]}"; do
  pac -S --needed "$p" || { warn "omarchy package $p failed"; FAILED+=("$p"); }
done

log "Step 15: theme"
as_user env OMARCHY_PATH="${DEST}" PATH="${DEST}/bin:${PATH}" \
  timeout 120 omarchy-theme-set "Tokyo Night" || warn "theme set deferred to first login"

log "Step 17: screensaver branding"
mkdir -p "${UHOME}/.config/omarchy/branding"
[[ -f "${DEST}/logo.txt" ]] && cp "${DEST}/logo.txt" "${UHOME}/.config/omarchy/branding/screensaver.txt"

# --------------------------------------------------------------------------
log "AIO V2: boot overlays in [cm4] (I2C RTC, SPI1 for LoRa)"
cp /boot/config.txt /boot/config.txt.pre-aio
if ! grep -q 'AIO V2 expansion board' /boot/config.txt; then
  python3 - <<'PY'
import re
p = "/boot/config.txt"
s = open(p).read()
block = ("\n# --- AIO V2 expansion board ---\n"
         "dtparam=i2c_arm=on\n"
         "dtoverlay=i2c-rtc,pcf85063a\n"
         "dtoverlay=spi1-1cs\n")
# insert at the end of the [cm4] section (just before the next [section])
m = re.search(r"^\[cm4\]\s*$", s, re.M)
assert m, "no [cm4] section in config.txt"
n = re.search(r"^\[", s[m.end():], re.M)
pos = m.end() + n.start() if n else len(s)
s = s[:pos].rstrip("\n") + "\n" + block + "\n" + s[pos:]
open(p, "w").write(s)
PY
fi
for o in i2c-rtc spi1-1cs; do
  [[ -e "/boot/overlays/${o}.dtbo" ]] || warn "overlay ${o}.dtbo missing from /boot/overlays"
done

log "AIO V2: tools and control utility"
pac -S --needed rtl-sdr soapysdr soapyrtlsdr gpsd i2c-tools libgpiod \
  raspberrypi-utils python-pyserial minicom usbutils python-pyqt6
rm -rf /opt/aiov2_ctl
git clone https://github.com/hackergadgets/aiov2_ctl.git /opt/aiov2_ctl
git -C /opt/aiov2_ctl checkout -q "${AIO_COMMIT}"
mkdir -p /etc/bash_completion.d     # installer hard-codes this path
( cd /opt/aiov2_ctl && python3 ./aiov2_ctl.py --install ) || warn "aiov2_ctl --install reported an error"
systemctl enable aiov2-rails-boot.service || warn "aiov2-rails-boot.service not enabled"
# Boot defaults from docs/aio-v2.md: USB hub on, radios off (battery).
aiov2_ctl --boot-rail USB on
for f in GPS LORA SDR; do aiov2_ctl --boot-rail "$f" off; done
aiov2_ctl --boot-rails-status || true

log "AIO V2: non-root access"
getent group rtlsdr >/dev/null || groupadd -r rtlsdr
usermod -aG uucp,rtlsdr,video,audio,input "${USER_NAME}"

log "AIO V2: gpsd on the GPS UART"
if [[ -f /etc/default/gpsd ]]; then
  sed -i -e 's|^DEVICES=.*|DEVICES="/dev/ttyS0"|' -e 's|^GPSD_OPTIONS=.*|GPSD_OPTIONS="-n -s 9600"|' /etc/default/gpsd
else
  printf 'START_DAEMON="true"\nUSBAUTO="true"\nDEVICES="/dev/ttyS0"\nGPSD_OPTIONS="-n -s 9600"\n' > /etc/default/gpsd
fi
systemctl enable gpsd.socket

# --------------------------------------------------------------------------
log "SDR toolkit (docs/sdr-toolkit.md) plus the rest of the prebuilt SDR stack"
SDR_PKGS=(
  # from the guide
  rtl_433 multimon-ng inspectrum urh sox viking gqrx python-pipx soapysdr
  soapyrtlsdr soapyairspy soapyaudio soapyplutosdr hackrf airspy limesuite
  # extra receivers, decoders and analysis
  sdrangel gnuradio gnuradio-companion gnuradio-osmosdr sigdigger suscan
  dump1090_rs soapyhackrf soapyremote soapybladerf bladerf rtl-sdr
  hamlib codec2 picocom kismet wireshark-qt
)
for p in "${SDR_PKGS[@]}"; do
  pac -S --needed "$p" || { warn "SDR package $p failed"; FAILED+=("$p"); }
done
getent group wireshark >/dev/null && usermod -aG wireshark "${USER_NAME}"
getent group kismet >/dev/null && usermod -aG kismet "${USER_NAME}"

log "SDR: LoRa/GPS Python tools via pipx (as ${USER_NAME})"
chown -R "${USER_NAME}:${USER_NAME}" "${UHOME}"
for p in meshtastic PyGPSClient; do
  as_user pipx install "$p" || { warn "pipx $p failed"; FAILED+=("pipx:$p"); }
done

log "SDR: AUR-recipe builds (SDR++, gpredict, direwolf, meshtasticd)"
pac -S --needed base-devel cmake git fftw glew glfw libvolk zstd libiio \
  libad9361 rtaudio portaudio autoconf automake intltool gtk3 curl \
  alsa-lib i2c-tools ulfius yaml-cpp
BUILD=/var/tmp/sdr-build
rm -rf "${BUILD}"; mkdir -p "${BUILD}"
cp -a "${SRC}/pkgs/." "${BUILD}/"
chown -R "${USER_NAME}:${USER_NAME}" "${BUILD}"
for p in meshtasticd-bin direwolf gpredict sdrpp-git; do
  log "  building ${p}"
  if as_user bash -c "cd '${BUILD}/${p}' && MAKEFLAGS=-j$(nproc) makepkg --noconfirm --nocheck --skippgpcheck -f" ; then
    pkgfile=$(find "${BUILD}/${p}" -maxdepth 1 -name '*.pkg.tar.*' ! -name '*-debug-*' | head -1)
    pac -U "${pkgfile}" || { warn "install ${p} failed"; FAILED+=("$p"); }
  else
    warn "build ${p} failed"; FAILED+=("$p")
  fi
done
rm -rf "${BUILD}"

log "SDR: meshtasticd for the AIO V2 SX1262 (installed, NOT enabled)"
if [[ -d /etc/meshtasticd ]]; then
  install -Dm644 "${SRC}/files/meshtasticd/aio-v2-lora.yaml" /etc/meshtasticd/config.d/aio-v2-lora.yaml
  install -Dm644 "${SRC}/files/meshtasticd/meshtasticd-lora-power.conf" \
    /etc/systemd/system/meshtasticd.service.d/lora-power.conf
  if command -v meshtasticd >/dev/null; then
    ldd /usr/bin/meshtasticd | grep 'not found' && warn "meshtasticd has missing libraries" || true
  fi
fi

# --------------------------------------------------------------------------
log "Optional Wi-Fi profile"
if [[ -n "${WIFI_SSID:-}" ]]; then
  f="/etc/NetworkManager/system-connections/${WIFI_SSID}.nmconnection"
  install -Dm600 /dev/stdin "$f" <<EOF
[connection]
id=${WIFI_SSID}
type=wifi
autoconnect=true

[wifi]
mode=infrastructure
ssid=${WIFI_SSID}

[wifi-security]
key-mgmt=wpa-psk
psk=${WIFI_PSK}

[ipv4]
method=auto

[ipv6]
method=auto
EOF
  echo "    wrote ${f}"
fi

log "Finalize"
chown -R "${USER_NAME}:${USER_NAME}" "${UHOME}"
pac -Scc >/dev/null 2>&1 || true
rm -f /tmp/omarchy.asc

echo
if ((${#FAILED[@]})); then
  warn "Non-fatal failures: ${FAILED[*]}"
else
  echo "All steps succeeded."
fi
printf '%s\n' "${FAILED[@]:-}" > /root/sdcard-build-failures.txt
