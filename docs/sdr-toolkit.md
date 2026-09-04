# SDR toolkit

A software-defined radio kit for the uConsole, sized for a CM4 rather than a
desktop. Pairs with the AIO V2's RTL-SDR (see [aio-v2.md](aio-v2.md)).

```bash
sudo pacman -S --needed rtl_433 multimon-ng inspectrum urh sox viking gqrx \
  python-pipx soapysdr soapyrtlsdr soapyairspy soapyaudio soapyplutosdr \
  hackrf airspy limesuite
pipx install meshtastic
pipx install PyGPSClient
```

## What each tool does

| Tool | Purpose |
|---|---|
| `gqrx` | Graphical receiver — waterfall, demodulation, listening |
| **`urh`** | Universal Radio Hacker — reverse-engineer unknown RF protocols to bits |
| `inspectrum` | Visual analysis of captured signal files |
| `rtl_433` | Decode 433 MHz sensors: weather, tyre pressure, doors |
| `multimon-ng` | Decode POCSAG pagers, APRS, DTMF |
| `sox` | Audio piping between tools |
| `viking` | GPS track / GPX viewer |
| `meshtastic` | LoRa mesh for the board's SX1262 |
| `PyGPSClient` | GPS diagnostics — position, satellites, NMEA |
| SoapySDR + backends | Hardware abstraction for RTL, Airspy, PlutoSDR, HackRF, LimeSDR |

`urh` is the centrepiece for security work: it demodulates an unknown signal,
shows you the bitstream, and helps you work out the encoding — the job you would
otherwise take to a much bigger machine.

## SDR++ does not build on ARM

The obvious choice, and the one the AIO vendor forks as `sdrpp-brown`, is not
installable here. The AUR `sdrpp-git` PKGBUILD declares `x86_64` only:

```
==> ERROR: sdrpp-git is not available for the 'aarch64' architecture.
```

`gqrx` covers the same receiver role. If you specifically want SDR++, you would
have to patch the PKGBUILD's `arch` array and fix whatever the build then hits,
which upstream has not done for a reason.

## Not available for aarch64

No official ARM packages: `chirp`, `fldigi`, `wsjtx`, `js8call`, `gpredict`,
`welle.io`, `csdr`, `dump1090`. Some have AUR recipes that build; none ship a
binary.

## Remember the rails are off at boot

The AIO V2 radios are GPIO-gated. Power the SDR before any tool will see it:

```bash
sudo aiov2_ctl SDR on
rtl_test -t
```
