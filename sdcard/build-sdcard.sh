#!/usr/bin/env bash
# Build a ready-to-boot uConsole (CM4 Lite + HackerGadgets AIO V2) SD card
# running Omarchy plus an SDR toolkit, following this repository's README and
# docs. See sdcard/README.md.
#
# usage: sudo ./sdcard/build-sdcard.sh /dev/mmcblk0
#   SKIP_FLASH=1   reuse an already-flashed card (re-run the setup stage)
#   CHROOT_SCRIPT=fixup-chroot.sh  with SKIP_FLASH=1: run only the fix-up pass
#   YES=1          skip the confirmation prompt
#   WIFI_SSID=... WIFI_PSK=...   optional: preload a Wi-Fi profile
#   CACHE=dir      where uconsole-arch-cm4.img.zst(.sha256) are (default: ../cache)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE="${CACHE:-${HERE}/../cache}"
IMG="${CACHE}/uconsole-arch-cm4.img.zst"
GUIDE="${HERE}/.."          # repository root
DEV="${1:-}"
MNT=/mnt/uconsole-sd
LOG="${HERE}/build.log"
FW_BASE=https://raw.githubusercontent.com/raspberrypi/firmware/stable/boot
FW_FILES=(start4.elf fixup4.dat start4x.elf fixup4x.dat start4cd.elf fixup4cd.dat bootcode.bin)

die() { echo "ERROR: $*" >&2; exit 1; }
log() { printf '\n\033[1;32m### %s\033[0m\n' "$*"; }

[[ $EUID -eq 0 ]] || die "run with sudo"
[[ -n "${DEV}" && -b "${DEV}" ]] || die "usage: sudo $0 /dev/mmcblkN"
[[ "$(lsblk -dno TYPE "${DEV}")" == disk ]] || die "${DEV} is not a whole disk"
[[ -x /usr/bin/qemu-aarch64-static && -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ]] \
  || die "qemu-aarch64 binfmt is not registered"

exec > >(tee -a "${LOG}") 2>&1
echo "==== build started $(date) ===="

# ---- safety checks on the target ------------------------------------------
root_src="$(findmnt -no SOURCE / || true)"
for part in $(lsblk -lnpo NAME "${DEV}"); do
  [[ "${root_src}" != "${part}"* ]] || die "${DEV} holds the running root filesystem"
done
size=$(blockdev --getsize64 "${DEV}")
(( size >= 15000000000 && size <= 600000000000 )) || die "unexpected size ${size} bytes for ${DEV}"
p() { [[ "${DEV}" =~ [0-9]$ ]] && echo "${DEV}p$1" || echo "${DEV}$1"; }

lsblk -o NAME,SIZE,TYPE,TRAN,MODEL,LABEL,MOUNTPOINTS "${DEV}"
if [[ "${SKIP_FLASH:-0}" != 1 && "${YES:-0}" != 1 ]]; then
  read -r -p "ERASE ${DEV} and write the uConsole image? type 'yes': " ans
  [[ "${ans}" == yes ]] || die "aborted"
fi

unmount_card() {
  local part
  for part in $(lsblk -lnpo NAME "${DEV}" | tail -n +2); do
    umount "${part}" 2>/dev/null || true
  done
  udevadm settle
}

cleanup() {
  set +e
  if mountpoint -q "${MNT}"; then
    if [[ -e "${MNT}/etc/resolv.conf.sdbuild" || -L "${MNT}/etc/resolv.conf.sdbuild" ]]; then
      mv -f "${MNT}/etc/resolv.conf.sdbuild" "${MNT}/etc/resolv.conf"
    elif [[ -f "${MNT}/root/sdcard-src/.resolv-added" ]]; then
      rm -f "${MNT}/etc/resolv.conf"
    fi
    rm -rf "${MNT}/root/sdcard-src"
    umount -R "${MNT}"
  fi
  sync
}
trap cleanup EXIT

# ---- step 1: flash ---------------------------------------------------------
unmount_card
if [[ "${SKIP_FLASH:-0}" != 1 ]]; then
  log "Step 1: verify and flash wdkdot/uconsole-arch CM4 image"
  [[ -f "${IMG}" ]] || die "missing ${IMG}"
  want="$(awk '{print $1}' "${IMG}.sha256")"
  got="$(sha256sum "${IMG}" | awk '{print $1}')"
  [[ "${want}" == "${got}" ]] || die "checksum mismatch for ${IMG}"
  echo "    sha256 ok ${got}"
  wipefs -a "${DEV}"
  zstd -dc "${IMG}" | dd of="${DEV}" bs=4M conv=fsync status=progress
  sync; partprobe "${DEV}"; udevadm settle
  sleep 2; unmount_card

  log "Step 4: expand root partition to the whole card"
  echo ", +" | sfdisk -N 2 --force --no-reread "${DEV}"
  partprobe "${DEV}"; udevadm settle; sleep 2; unmount_card
  findmnt -rno SOURCE | grep -q "^$(p 2)$" && die "$(p 2) is still mounted"
  e2fsck -fy "$(p 2)" || [[ $? -le 1 ]]
  resize2fs "$(p 2)"
fi

# ---- mount -----------------------------------------------------------------
mkdir -p "${MNT}"
sleep 2; unmount_card
mount "$(p 2)" "${MNT}"
mount "$(p 1)" "${MNT}/boot"
[[ -f "${MNT}/boot/config.txt" ]] || die "boot partition has no config.txt"

log "Step 2: add missing Raspberry Pi VideoCore firmware"
for f in "${FW_FILES[@]}"; do
  curl -fsSL -o "${MNT}/boot/${f}" "${FW_BASE}/${f}"
  echo "    ${f} $(stat -c %s "${MNT}/boot/${f}") bytes"
done

# ---- chroot stage ----------------------------------------------------------
log "Steps 3,5-17 + AIO V2 + SDR inside the aarch64 root (qemu)"
mkdir -p "${MNT}/root/sdcard-src"
cp -a "${HERE}"/*-chroot.sh "${HERE}/chroot-setup.sh" "${MNT}/root/sdcard-src/"
cp -a "${GUIDE}/scripts/sdr/pkgs" "${MNT}/root/sdcard-src/pkgs"
cp "${GUIDE}/scripts/desktop-packages.txt" "${MNT}/root/sdcard-src/"
# files/ as chroot-setup.sh expects it, taken from the repository's config/
F="${MNT}/root/sdcard-src/files"
install -Dm644 "${GUIDE}/config/monitors.lua" "${F}/monitors.lua"
install -Dm644 "${GUIDE}/config/keyd-default.conf" "${F}/keyd-default.conf"
install -Dm644 "${GUIDE}/config/aio-v2/aio-v2-lora.yaml" "${F}/meshtasticd/aio-v2-lora.yaml"
install -Dm644 "${GUIDE}/config/aio-v2/meshtasticd-lora-power.conf" "${F}/meshtasticd/meshtasticd-lora-power.conf"
mount -t proc proc "${MNT}/proc"
mount --rbind /sys "${MNT}/sys";  mount --make-rslave "${MNT}/sys"
mount --rbind /dev "${MNT}/dev";  mount --make-rslave "${MNT}/dev"
mount -t tmpfs tmpfs "${MNT}/tmp"
if [[ -e "${MNT}/etc/resolv.conf" || -L "${MNT}/etc/resolv.conf" ]]; then
  mv -f "${MNT}/etc/resolv.conf" "${MNT}/etc/resolv.conf.sdbuild"
else
  touch "${MNT}/root/sdcard-src/.resolv-added"
fi
cp -L /etc/resolv.conf "${MNT}/etc/resolv.conf"

host_tz="$(readlink /etc/localtime | sed 's|.*/zoneinfo/||')"
chroot "${MNT}" /usr/bin/env -i PATH=/usr/local/sbin:/usr/local/bin:/usr/bin HOME=/root TERM=xterm \
  LANG=C.UTF-8 TZ_NAME="${host_tz:-America/New_York}" \
  WIFI_SSID="${WIFI_SSID:-}" WIFI_PSK="${WIFI_PSK:-}" \
  /bin/bash "/root/sdcard-src/${CHROOT_SCRIPT:-chroot-setup.sh}"

# kill anything (gpg-agent, dirmngr) still running inside the chroot
for proc in /proc/[0-9]*; do
  r="$(readlink "${proc}/root" 2>/dev/null || true)"
  [[ "${r}" == "${MNT}" ]] && kill "${proc##*/}" 2>/dev/null || true
done
sleep 1

# ---- verify ----------------------------------------------------------------
log "Verify boot partition and root"
ok=1
chk() { if eval "$2"; then echo "  ok   $1"; else echo "  FAIL $1"; ok=0; fi; }
chk "start4.elf present"                  "[[ -s '${MNT}/boot/start4.elf' ]]"
chk "kernel named in config.txt exists"   "k=\$(awk '/^\[cm4\]/{f=1} f&&/^kernel=/{sub(/kernel=/,\"\");print;exit}' '${MNT}/boot/config.txt'); [[ -s '${MNT}/boot/'\$k ]]"
chk "initramfs present"                   "ls '${MNT}'/boot/initramfs-linux-uconsole-cm4*.img >/dev/null 2>&1"
chk "uConsole overlay in config exists"   "o=\$(awk '/^\[cm4\]/{f=1} f&&/^dtoverlay=clockworkpi/{sub(/dtoverlay=/,\"\");print;exit}' '${MNT}/boot/config.txt'); [[ -s '${MNT}/boot/overlays/'\$o.dtbo ]]"
chk "AIO overlays configured"             "grep -q '^dtoverlay=spi1-1cs' '${MNT}/boot/config.txt'"
chk "hyprland installed"                  "[[ -x '${MNT}/usr/bin/Hyprland' ]]"
chk "omarchy deployed"                    "[[ -d '${MNT}/usr/share/omarchy/bin' ]]"
chk "panel rotation config"               "grep -q DSI-1 '${MNT}/home/alarm/.config/hypr/monitors.lua'"
chk "keyd Alt->Super"                     "[[ -f '${MNT}/etc/keyd/default.conf' ]]"
chk "tty1 autologin"                      "[[ -f '${MNT}/etc/systemd/system/getty@tty1.service.d/autologin.conf' ]]"
chk "aiov2_ctl installed"                 "[[ -x '${MNT}/usr/local/bin/aiov2_ctl' ]]"
for b in gqrx sdrpp sdrangel gnuradio-companion urh rtl_433 inspectrum gpredict direwolf meshtasticd; do
  chk "app: ${b}" "[[ -x '${MNT}/usr/bin/${b}' ]]"
done
echo; echo "--- /boot/config.txt [cm4] ---"
awk '/^\[cm4\]/{f=1;print;next} /^\[/{f=0} f' "${MNT}/boot/config.txt"
df -h "${MNT}" "${MNT}/boot"
[[ -s "${MNT}/root/sdcard-build-failures.txt" ]] && { echo "--- non-fatal failures ---"; cat "${MNT}/root/sdcard-build-failures.txt"; }

cleanup
trap - EXIT
echo "==== build finished $(date) ===="
(( ok )) && echo "Card is ready. Remove it and boot the uConsole." || echo "Some checks failed; see above."
