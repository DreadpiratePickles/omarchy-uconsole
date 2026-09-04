# AIO V2 expansion board on Arch

Setup for the HackerGadgets / OpenSourceSDRLab uConsole AIO V2 (RTL-SDR, LoRa,
GPS, RTC, USB hub) on Arch Linux ARM. Verified working on a CM4.

## What works, and what does not

| Function | CM4 status |
|---|---|
| RTL-SDR | Works. Enumerates as `RTL2838`, R820T tuner, zero sample loss |
| GPS | Works. NMEA on `/dev/ttyS0` at 9600 baud |
| LoRa (SX1262) | Rail powers, SPI1 exposed at `/dev/spidev1.0` |
| RTC (PCF85063A) | Works. Keeps time with no network |
| USB hub | Works |
| RJ45 Ethernet | **Does not work.** Needs the separate CM5 upgrade kit |
| USB 3.0 speeds | **Not available.** Falls back to USB 2.0 |

The Ethernet limitation is hardware, not driver. It applies on any distro.

## Everything is off at boot

The board's radios are GPIO-gated and unpowered until you switch them on:

| Feature | GPIO |
|---|---|
| SDR | 7 |
| LoRa | 16 |
| USB | 23 |
| GPS | 27 |

On CM5 the SDR pin is driven high at boot; on CM4 you raise it yourself.

## Boot overlays

Add to the `[cm4]` section of `/boot/config.txt`. Back it up first — a bad
`config.txt` is a black screen.

```ini
# --- AIO V2 expansion board ---
dtparam=i2c_arm=on
dtoverlay=i2c-rtc,pcf85063a
dtoverlay=spi1-1cs
```

`spi1-1cs` puts chip select on GPIO18, which leaves GPIO16 free as the LoRa
power-enable line. Reboot, then confirm you have `/dev/i2c-1`, `/dev/rtc0` and
`/dev/spidev1.0`.

Note that GPIO7 is `SPI4_SCLK` under the uConsole overlay before the AIO tool
reclaims it as an output. Nothing appeared to break in testing, but be aware if
you use `/dev/spidev4.0`.

## Tools

```bash
sudo pacman -S --needed rtl-sdr soapysdr soapyrtlsdr gpsd i2c-tools \
                        libgpiod raspberrypi-utils python-pyserial minicom usbutils
```

`raspberrypi-utils` provides `pinctrl`, which the vendor control tool shells out to.

## Control tool

```bash
git clone https://github.com/hackergadgets/aiov2_ctl.git
cd aiov2_ctl
sudo mkdir -p /etc/bash_completion.d      # Arch lacks this; the installer hard-codes it
sudo python3 ./aiov2_ctl.py --install
```

Without that `mkdir` the installer dies partway through with a `FileNotFoundError`
after already placing the binary, leaving the systemd boot service uninstalled.

Feature names are **uppercase** (`GPS`, `LORA`, `SDR`, `USB`). The tool's own
`--help` cannot show them: it prints an unformatted f-string placeholder. Lowercase
names are accepted silently and do nothing.

```bash
sudo aiov2_ctl SDR on
sudo aiov2_ctl --status          # needs root to read pin state
```

Without root, `--status` reports boot defaults rather than reality, so it will tell
you rails are off when they are on.

## Boot defaults

Leaving all four rails powered costs meaningful battery. A reasonable default is
the USB hub on and the radios off:

```bash
sudo aiov2_ctl --boot-rail USB on
for f in GPS LORA SDR; do sudo aiov2_ctl --boot-rail $f off; done
```

## Set the clock

Do this once. It fixes the wrong-clock problem that otherwise breaks TLS and
pacman on every boot.

```bash
sudo hwclock -w --rtc=/dev/rtc0
sudo hwclock -r --rtc=/dev/rtc0
```

A first read before writing reports `Power loss detected, invalid time`, which is
normal on a clock that has never been set.

## Verifying

```bash
rtl_test                                   # SDR
sudo stty -F /dev/ttyS0 9600 raw -echo     # GPS
sudo timeout 5 cat /dev/ttyS0
```

The GPS streams NMEA immediately and reports satellites in view long before it
gets a position fix. `$GNGGA` with empty coordinates plus `$GPGSV` lines listing
satellites means the receiver is working and just needs sky.

## Non-root access

```bash
sudo usermod -aG uucp,rtlsdr alarm
```

There is no `gpio` group on Arch, so `pinctrl` still needs sudo.
