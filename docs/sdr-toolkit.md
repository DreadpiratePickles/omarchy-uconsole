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

## SDR++, CHIRP, gpredict, direwolf and meshtasticd

These do build on aarch64. The AUR `sdrpp-git` recipe only *declares* `x86_64`.
See [sdr-and-aio-integration.md](sdr-and-aio-integration.md#3-sdr-apps-that-do-build-on-aarch64)
for an aarch64 SDR++ PKGBUILD, the AUR recipes that work as-is, and the yaml-cpp
shim `meshtasticd-bin` needs. `dump1090_rs` is in the ALARM repos.

Still without an ARM build: `fldigi`, `wsjtx`, `js8call`, `welle.io`, `csdr`,
and SDRangel (its dependencies `log4cpp` and `qt5-websockets` are not packaged).

## Remember the rails are off at boot

The AIO V2 radios are GPIO-gated. Power the SDR before any tool will see it:

```bash
sudo aiov2_ctl SDR on
rtl_test -t
```
