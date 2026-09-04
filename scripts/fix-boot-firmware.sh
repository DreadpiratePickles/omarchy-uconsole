#!/usr/bin/env bash
# Add the Raspberry Pi VideoCore firmware that the uconsole-arch image omits.
# Without start4.elf the CM4 cannot start its ARM cores: green LED, black screen.
#
# Usage: ./fix-boot-firmware.sh /path/to/mounted/BOOT
set -euo pipefail

BOOT="${1:-}"
if [[ -z $BOOT || ! -d $BOOT ]]; then
  echo "Usage: $0 /path/to/mounted/BOOT partition" >&2
  exit 1
fi
if [[ ! -f "$BOOT/config.txt" ]]; then
  echo "No config.txt in $BOOT - is that really the boot partition?" >&2
  exit 1
fi

BASE=https://raw.githubusercontent.com/raspberrypi/firmware/stable/boot
FILES=(start4.elf fixup4.dat start4x.elf fixup4x.dat start4cd.elf fixup4cd.dat bootcode.bin)

for f in "${FILES[@]}"; do
  echo "==> $f"
  curl -fsSL -o "$BOOT/$f" "$BASE/$f"
done

# macOS sprinkles AppleDouble files on FAT; harmless but untidy.
command -v dot_clean >/dev/null && dot_clean -m "$BOOT" || true
sync
echo "==> Done. Firmware installed:"
ls -la "$BOOT" | grep -E 'start4|fixup4|bootcode'
