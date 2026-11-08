#!/usr/bin/env bash
# Copy this machine's active Wi-Fi network onto the uConsole SD card as a
# NetworkManager profile. The passphrase is never printed.
#
# usage: sudo ./add-wifi.sh /dev/mmcblk0 [SSID]
set -euo pipefail

DEV="${1:-}"
MNT=/mnt/uconsole-sd
die() { echo "ERROR: $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "run with sudo"
[[ -n "${DEV}" && -b "${DEV}" ]] || die "usage: sudo $0 /dev/mmcblkN [SSID]"
p() { [[ "${DEV}" =~ [0-9]$ ]] && echo "${DEV}p$1" || echo "${DEV}$1"; }

# ---- find the host connection -----------------------------------------------
con="${2:-}"
if [[ -z "${con}" ]]; then
  con="$(nmcli -t -f NAME,TYPE connection show --active | awk -F: '$2=="802-11-wireless"{print $1; exit}')"
fi
[[ -n "${con}" ]] || die "no active Wi-Fi connection on this machine; pass the SSID"

ssid="$(nmcli -g 802-11-wireless.ssid connection show "${con}")"
keymgmt="$(nmcli -g 802-11-wireless-security.key-mgmt connection show "${con}" 2>/dev/null || true)"
psk="$(nmcli -s -g 802-11-wireless-security.psk connection show "${con}" 2>/dev/null || true)"
if [[ -z "${psk}" && -n "${SUDO_USER:-}" ]]; then
  # password stored in the user's keyring rather than system-wide
  psk="$(runuser -u "${SUDO_USER}" -- nmcli -s -g 802-11-wireless-security.psk connection show "${con}" 2>/dev/null || true)"
fi
if [[ -z "${psk}" && -n "${keymgmt}" && "${keymgmt}" != none ]]; then
  read -r -s -p "Passphrase for '${ssid}' (not echoed): " psk; echo
fi
[[ -n "${keymgmt}" && "${keymgmt}" != none && -z "${psk}" ]] && die "no passphrase available"
echo "Network: ${ssid}  security: ${keymgmt:-open}  passphrase: $([[ -n ${psk} ]] && echo found || echo none)"

# ---- mount the card root ----------------------------------------------------
for part in $(lsblk -lnpo NAME "${DEV}" | tail -n +2); do umount "${part}" 2>/dev/null || true; done
mkdir -p "${MNT}"
mount "$(p 2)" "${MNT}"
trap 'umount "${MNT}"; sync' EXIT
[[ -d "${MNT}/etc/NetworkManager" ]] || die "$(p 2) does not look like the uConsole root"

dir="${MNT}/etc/NetworkManager/system-connections"
mkdir -p "${dir}"

# remove any earlier (incomplete) profiles for the same SSID
shopt -s nullglob
for f in "${dir}"/*.nmconnection; do
  if grep -qxF "ssid=${ssid}" "${f}"; then echo "removing old profile ${f##*/}"; rm -f "${f}"; fi
done

out="${dir}/${ssid//\//_}.nmconnection"
umask 077
{
  echo "[connection]"
  echo "id=${ssid}"
  echo "uuid=$(cat /proc/sys/kernel/random/uuid)"
  echo "type=wifi"
  echo "autoconnect=true"
  echo
  echo "[wifi]"
  echo "mode=infrastructure"
  echo "ssid=${ssid}"
  if [[ -n "${keymgmt}" && "${keymgmt}" != none ]]; then
    echo
    echo "[wifi-security]"
    echo "key-mgmt=${keymgmt}"
    echo "psk=${psk}"
  fi
  echo
  echo "[ipv4]"
  echo "method=auto"
  echo
  echo "[ipv6]"
  echo "method=auto"
} > "${out}"
chown root:root "${out}"
chmod 600 "${out}"
echo "wrote /etc/NetworkManager/system-connections/${out##*/} on the card"

# make sure NetworkManager starts on boot and nothing else fights it
ls "${MNT}/etc/systemd/system/multi-user.target.wants/NetworkManager.service" >/dev/null 2>&1 \
  && echo "NetworkManager is enabled on the card" \
  || { ln -sf /usr/lib/systemd/system/NetworkManager.service \
         "${MNT}/etc/systemd/system/multi-user.target.wants/NetworkManager.service"
       echo "enabled NetworkManager on the card"; }
for svc in iwd wpa_supplicant@wlan0; do
  [[ -e "${MNT}/etc/systemd/system/multi-user.target.wants/${svc}.service" ]] \
    && echo "note: ${svc} is also enabled on the card"
done
echo "Done. Card unmounted; put it back in the uConsole."
