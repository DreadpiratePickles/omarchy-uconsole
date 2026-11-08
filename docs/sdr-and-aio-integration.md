# A complete SDR uConsole: AIO V2, SDR apps, and Omarchy integration

Follow-on notes from building a uConsole that boots into Omarchy with the AIO V2
board fully working. Every SDR app runs on the CM4, and each one powers the radio
it needs only while it is open. Everything is one key away: **Alt + R** opens an
SDR menu.

This picks up after the main README. It also corrects a few things in
[aio-v2.md](aio-v2.md) and [sdr-toolkit.md](sdr-toolkit.md) that turned out to
be fixable.

**Verified on:** uConsole, CM4 Lite Rev 1.1 (4 GB), AIO V2, kernel
`7.1.13-uconsole-cm4+`, Hyprland 0.57.1 (Lua config), Quickshell 0.3.2, Omarchy
`quattro` branch at `e6d5a17` (git deploy per Step 11).

---

## Contents

1. [Clock: two problems that keep it wrong](#1-clock-two-problems-that-keep-it-wrong)
2. [GPIO without root](#2-gpio-without-root)
3. [Broken aarch64 packages, and how to find them](#3-broken-aarch64-packages-and-how-to-find-them)
4. [SDR apps that do build on aarch64](#4-sdr-apps-that-do-build-on-aarch64)
5. [Meshtastic on the AIO V2 LoRa radio](#5-meshtastic-on-the-aio-v2-lora-radio)
6. [Power: radios on only while an app needs them](#6-power-radios-on-only-while-an-app-needs-them)
7. [Omarchy integration: one key for everything](#7-omarchy-integration-one-key-for-everything)
8. [What was tested](#8-what-was-tested)
9. [Agent CLIs (Claude Code, Codex, gh) via mise](#9-agent-clis-claude-code-codex-gh-via-mise)
10. [Renaming the default `alarm` user](#10-renaming-the-default-alarm-user)
11. [Building the card offline from an x86 machine](#11-building-the-card-offline-from-an-x86-machine)

Supporting files are in [`config/aio-v2/`](../config/aio-v2) and
[`scripts/sdr/`](../scripts/sdr).

---

## 1. Clock: two problems that keep it wrong

Setting the RTC once ([aio-v2.md](aio-v2.md#set-the-clock)) is necessary but not
sufficient. Two separate faults kept the clock wrong. A wrong clock is what makes
`pacman -Syu` fail with signature and TLS errors on first boot.

### The RTC can lose the race at boot

The `pcf85063` driver can probe before the chip answers:

```
rtc-pcf85063 1-0051: error -EREMOTEIO: RTC chip is not present
rtc-pcf85063 1-0051: probe with driver rtc-pcf85063 failed with error -121
```

When that happens there is no `/dev/rtc0`, and `hwclock` reports *cannot access the
hardware clock*. A few seconds later `i2cdetect -y 1` shows the chip answering
at `0x51`, and binding by hand works:

```bash
echo 1-0051 | sudo tee /sys/bus/i2c/drivers/rtc-pcf85063/bind
```

On a chip that has never been set, the first successful bind logs `POR issue
detected, sending a SW reset`. That is expected. A small oneshot service retries
the bind when `/dev/rtc0` is missing, then sets the system clock from the RTC
before `time-set.target`. It is an early-boot unit, so it needs
`DefaultDependencies=no`. Without that, it creates an ordering cycle, and systemd
quietly drops `systemd-timesyncd` from the boot to break it. If you see
`Job systemd-timesyncd.service/start deleted to break ordering cycle`, this is
the cause.


```bash
sudo install -m755 config/aio-v2/aio-rtc-fix /usr/local/bin/
sudo install -m644 config/aio-v2/aio-rtc-fix.service /etc/systemd/system/
sudo systemctl enable aio-rtc-fix
```

### systemd-networkd stops NTP from ever running

The base image enables **both** `systemd-networkd` (for Ethernet) and
NetworkManager (Wi-Fi). `systemd-timesyncd` asks networkd whether the machine is
online. networkd does not manage `wlan0`, so it answers `ONLINE_STATE=offline`
and timesyncd never sends a packet (`timedatectl timesync-status` shows
`Packet count: 0`). NetworkManager can handle everything, so turn networkd off,
including its socket units, and reboot:

```bash
sudo systemctl disable --now systemd-networkd.service systemd-networkd.socket \
  systemd-networkd-varlink.socket systemd-networkd-varlink-metrics.socket \
  systemd-networkd-resolve-hook.socket systemd-networkd-wait-online.service
sudo reboot
```

---

## 2. GPIO without root

Without root, `aiov2_ctl` reports every rail as `OFF`, even when one is on. That
makes the boot-rails service look broken when it is not. Create a `gpio` group
and give it the devices:

```bash
sudo groupadd -r gpio
sudo usermod -aG gpio $USER
sudo install -m644 config/aio-v2/60-gpio.rules /etc/udev/rules.d/
sudo udevadm control --reload && sudo udevadm trigger
```

After logging in again, `aiov2_ctl` shows the real state and
`aiov2_ctl SDR on` works without sudo. Everything in sections 6 and 7 depends on
this.

---

## 3. Broken aarch64 packages, and how to find them

An app that installs is not necessarily an app that runs. On the CM4, these
needed fixing.

### LimeSuite crashes every SoapySDR app (SIGILL)

The Arch Linux ARM `limesuite` package (23.11.0-9) contains `ldapr`, an
**ARMv8.3** instruction. The CM4's Cortex-A72 is ARMv8.0 (`/proc/cpuinfo`
features: `fp asimd evtstrm crc32 cpuid`). SoapySDR loads every installed module
when it looks for devices, LimeSuite's included. So Gqrx, SigDigger, GNU Radio,
dump1090_rs and SDR++ all die with an illegal instruction the moment they open a
device, even with no LimeSDR attached:

```
Signal: 4 (ILL)
#0 libLimeSuite.so.23.11-1 + 0x8bd14      ldapr x0, [x19]
```

To scan for this class of problem:

```bash
for f in $(pacman -Qlq limesuite soapysdr gqrx sdrpp-git | grep -E '(/bin/|\.so)'); do
  [ -f "$f" ] && file -b "$f" | grep -q ELF &&
  n=$(objdump -d "$f" | grep -cwE 'ldapr|ldaprb|ldaprh|ldapur') && [ "$n" -gt 0 ] && echo "$f $n"
done
```

Look only for `ldapr*`. The LSE atomics (`cas`, `ldadd`, `swp`...) also appear
throughout normal GCC output, but only inside `-moutline-atomics` helpers that
check the CPU at runtime, so they are harmless. In the whole SDR stack, only
LimeSuite was affected.

The fix is to rebuild LimeSuite on the device with the normal `-march=armv8-a`.
[`scripts/sdr/pkgs/limesuite`](../scripts/sdr/pkgs/limesuite/PKGBUILD) is Arch's
recipe with the GUI, the Octave plugin, the docs and LimeQuickTest turned off,
which keeps the build short:

```bash
cd scripts/sdr/pkgs/limesuite && makepkg -si
LimeUtil --find        # must not crash
```

### SoapySDR cannot see the RTL-SDR

The ALARM `soapyrtlsdr` module was linked against `librtlsdr.so.2`. The current
`rtl-sdr` (2.0.3) ships with SONAME `librtlsdr.so.0`, so the module fails to load
and every SoapySDR client reports *no match*. Rebuild it
([`scripts/sdr/pkgs/soapyrtlsdr`](../scripts/sdr/pkgs/soapyrtlsdr/PKGBUILD); it
needs `-DCMAKE_POLICY_VERSION_MINIMUM=3.5`):

```bash
cd scripts/sdr/pkgs/soapyrtlsdr && makepkg -si
SoapySDRUtil --find=driver=rtlsdr     # with the SDR rail on
```

### Viking hangs before its window appears

Viking 1.11 loads a pixbuf inside a GObject `class_init`. With gdk-pixbuf 2.44,
every decode goes through glycin, and glycin's worker threads need GLib's
type-init lock, which the main thread is holding. The result is a deadlock
(`gly_loader_load` ← `gdk_pixbuf_new_from_resource` ← `g_type_class_get`). This
is not glycin's bwrap sandbox, which works fine here, and
`GLYCIN_DISABLE_SANDBOX` does not help.

[`scripts/sdr/glycin-warmup.c`](../scripts/sdr/glycin-warmup.c) is a small
`LD_PRELOAD` shim. It wraps `gtk_init*()` and decodes one 1×1 PNG straight after
it, so glycin finishes its own setup before the app's `class_init` runs. It cannot
do this from a constructor, because the dynamic loader's lock is held there.

```bash
gcc -O2 -shared -fPIC -o libglycin-warmup.so scripts/sdr/glycin-warmup.c \
  $(pkg-config --cflags --libs gtk+-3.0) -ldl
sudo install -m755 libglycin-warmup.so /usr/local/lib/
printf '#!/bin/sh\nexec env LD_PRELOAD=/usr/local/lib/libglycin-warmup.so /usr/bin/viking "$@"\n' \
  | sudo install -m755 /dev/stdin /usr/local/bin/viking
```

### No sound from the speaker

The uConsole's speaker amplifier is enabled by **GPIO11**, and the base image
ships with that line commented out in `/boot/config.txt`. Audio plays happily into
PipeWire (bcm2835 analog, routed to GPIO 12/13 by `audremap`), but nothing comes
out. GPIO10 is the headphone-detect input.

```bash
sudo pinctrl set 11 op dh                                     # now
sudo sed -i 's/^# gpio=11=op,dh$/gpio=11=op,dh/' /boot/config.txt   # every boot
```

The ALSA `PCM` control on card 0 also defaults to about −20 dB under PipeWire's
own volume. Set it to 0 dB and save it with `amixer -c 0 sset PCM 0dB` and
`sudo alsactl store`.

### SDR++ hangs on its splash screen ("Application Not Responding")

SDR++'s default audio sink (`audio_sink`, RtAudio over ALSA) deadlocks at start-up
on PipeWire's ALSA plugin. It calls `AudioSink::doStop()` → `snd_pcm_drain` on a
stream that never started, and never returns. Switch the radio stream to the
PortAudio sink ("New Audio") and disable the RtAudio one. While you are in
`~/.config/sdrpp/`, also make it CM4-sized:

| File | Setting |
|---|---|
| `config.json` | `moduleInstances."Audio Sink".enabled = false`; add `"New Audio Sink": {"enabled": true, "module": "new_portaudio_sink"}`; `streams.Radio.sink = "New Audio"` |
| `config.json` | `fftSize` 65536 → 8192; `source = "RTL-SDR"`; disable source modules for hardware you do not have (about 20 of them), which cuts start-up time |
| `rtl_sdr_config.json` | `sampleRate` 1024000, fixed `gain` |
| `radio_config.json` | `selectedDemodId` 1 (WFM), `WFM.deempMode` `75us` in the Americas (the default `50us` is Europe) |

Two copies of SDR++ wait on each other's config lock (`ConfigManager locked,
waiting...`) and fight over the radio. The launchers therefore go through
[`sdr-launch`](../scripts/sdr/sdr-launch), which focuses the running copy
instead of starting another. Launch with `--autostart` to start receiving
without pressing play.

### Smaller ones

| Symptom | Fix |
|---|---|
| PyGPSClient: `ImportError: libtk8.6.so` | `sudo pacman -S tk` |
| `modeslive` gone (pyModeS 3 removed it) | `pipx install "pyModeS<3"` |
| direwolf exits: *could not open direwolf.conf* | a receive-only config with `ADEVICE stdin null` (written by `sdr-tool`) |
| `hamlibtcl` links a missing `libtcl8.6.so` | harmless unless you use Hamlib from Tcl |

---

## 4. SDR apps that do build on aarch64

| App | Source | Notes |
|---|---|---|
| gqrx, GNU Radio + gnuradio-osmosdr, URH, inspectrum, SigDigger, rtl_433, multimon-ng, hamlib, kismet, wireshark-qt, viking, gpsd | ALARM repos | `pacman -S` (then section 3) |
| `dump1090_rs` | ALARM repos | ADS-B decoder/server, no display; `sdr-tool adsb` adds one |
| gpredict | AUR `gpredict` | Builds as-is. Drop the `hamradio-menus` dependency |
| direwolf | AUR `direwolf` | Builds as-is |
| CHIRP | AUR `chirp-next` | `arch=any`. Build AUR `python-yattag` first |
| **SDR++** | [`scripts/sdr/pkgs/sdrpp-git`](../scripts/sdr/pkgs/sdrpp-git/PKGBUILD) | See below |
| meshtasticd | [`scripts/sdr/pkgs/meshtasticd-bin`](../scripts/sdr/pkgs/meshtasticd-bin/PKGBUILD) | Section 5 |
| SDRangel | none | ALARM build needs `log4cpp` and `qt5-websockets`, which are not packaged. Gqrx and SDR++ cover the role |

### SDR++

The AUR `sdrpp-git` recipe only *declares* `x86_64`. The PKGBUILD here sets
`arch=(aarch64)`, pins a known-good commit, and disables modules whose
libraries have no ARM package (`AIRSPYHF`, `SDRPLAY`, `DISCORD_PRESENCE`).
Do **not** enable `OPT_BUILD_WEATHER_SAT_DECODER`: it fails with
`dsp/pll.h: No such file or directory`.

```bash
cd scripts/sdr/pkgs/sdrpp-git && MAKEFLAGS=-j3 makepkg -si
```

Use `-j3` on a 4 GB CM4 so the desktop stays usable. The build takes about half
an hour.

### CHIRP

```bash
for p in python-yattag chirp-next; do
  curl -fsSL https://aur.archlinux.org/cgit/aur.git/snapshot/$p.tar.gz | tar xz
  (cd $p && makepkg -si)
done
```

---

## 5. Meshtastic on the AIO V2 LoRa radio

### Package

The AUR `meshtasticd-bin` copies only the binary and unit file out of the
upstream Debian `.deb`. That leaves a service that cannot start: the unit runs
`/usr/bin/meshtasticd-start.sh`, which is missing, as user `meshtasticd`, which
does not exist. The fixed
[PKGBUILD](../scripts/sdr/pkgs/meshtasticd-bin/PKGBUILD):

- keeps the start script, the udev rule (`spi` and `gpio` groups) and the
  **bundled Meshtastic web client** (`/usr/share/meshtasticd/web`);
- replaces the Debian postinst with `sysusers.d` (user `meshtasticd` in `spi`,
  `gpio` and `uucp`) and `tmpfiles.d` (`/var/lib/meshtasticd`, ownership of
  `/etc/meshtasticd`);
- depends on
  [`yaml-cpp08-compat`](../scripts/sdr/pkgs/yaml-cpp08-compat/PKGBUILD). The
  Debian binary needs `libyaml-cpp.so.0.8` and Arch ships 0.9. The compat package
  installs only the versioned `.so.0.8*` files, so it cannot conflict.

```bash
(cd scripts/sdr/pkgs/yaml-cpp08-compat && makepkg -si)
(cd scripts/sdr/pkgs/meshtasticd-bin && makepkg -si)
```

### Configuration

```bash
sudo install -Dm644 config/aio-v2/aio-v2-lora.yaml        /etc/meshtasticd/config.d/aio-v2-lora.yaml
sudo install -Dm644 config/aio-v2/meshtasticd-webserver.yaml /etc/meshtasticd/config.d/webserver.yaml
sudo install -Dm644 config/aio-v2/meshtasticd-mac.yaml    /etc/meshtasticd/config.d/mac.yaml
sudo install -Dm644 config/aio-v2/meshtasticd-lora-power.conf \
  /etc/systemd/system/meshtasticd.service.d/lora-power.conf
sudo install -Dm644 config/aio-v2/50-meshtasticd.rules    /etc/polkit-1/rules.d/50-meshtasticd.rules
sudo chown -R meshtasticd:meshtasticd /etc/meshtasticd
```

- **`aio-v2-lora.yaml`** describes the SX1262 wiring. It is from
  [508-dev/uconsole-scripts](https://github.com/508-dev/uconsole-scripts).
  On first start, look for `sx1262 init success` in the journal.
- **`mac.yaml`**: without a MAC source, meshtasticd falls back to node number
  `0xAAAAAAAA` (`!aaaaaaaa`), so every such node on the mesh has the same ID.
  Point it at `wlan0`, and if it already started without one, delete
  `/var/lib/meshtasticd/.portduino` so the ID is regenerated.
- **`lora-power.conf`** powers GPIO16 before start and **cuts it after stop**
  (`ExecStopPost`), so the transmitter only has power while the node runs. The
  `+` prefix runs `pinctrl` as root, because the service itself runs as
  `meshtasticd`.
- **`webserver.yaml`** serves the web client on `https://<host>:9443`.
- **`50-meshtasticd.rules`** lets `wheel` users start and stop the service
  without a password, which is what makes one-click launch possible.

The node generates a self-signed certificate for `meshtastic.local`, which the
browser rejects on `localhost`. Replace it with one for `localhost`, then trust it
in the NSS database that Chromium uses:

```bash
sudo openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout /etc/meshtasticd/ssl/private_key.pem -out /etc/meshtasticd/ssl/certificate.pem \
  -subj "/O=Meshtastic/CN=localhost" \
  -addext "subjectAltName=DNS:localhost,IP:127.0.0.1" -addext "basicConstraints=critical,CA:FALSE"
sudo chown meshtasticd:meshtasticd /etc/meshtasticd/ssl/*.pem
certutil -A -d sql:$HOME/.pki/nssdb -n meshtasticd-local -t "P,," -i /etc/meshtasticd/ssl/certificate.pem
```

Set the region once, before transmitting:

```bash
sudo systemctl start meshtasticd
meshtastic --host localhost --set lora.region US
```

---

## 6. Power: radios on only while an app needs them

The AIO V2's rails are all GPIO-switched (SDR 7, GPS 27, LoRa 16, USB 23).
Leaving them on costs battery, and leaving them off means apps cannot find their
hardware. [`scripts/sdr/aio-run`](../scripts/sdr/aio-run) wraps an app with the
rails it needs:

```bash
aio-run SDR -- gqrx
aio-run GPS -- cgps -s
```

It switches the rails on, waits for the hardware (the RTL-SDR appearing on USB),
runs the app, and switches the rails off when the app exits.

Closing a terminal window can tear down the whole app scope, which kills
`aio-run` before it finishes cleaning up and leaves the radio powered. As a safety
net, `aio-run --reap` switches off any rail that aio-run turned on and that no
running process holds. It runs at the start of every `aio-run`, and once a minute
from a user timer:

```bash
cp config/aio-v2/aio-reap.{service,timer} ~/.config/systemd/user/
systemctl --user daemon-reload && systemctl --user enable --now aio-reap.timer
``` Rails are
**reference counted** per session, so two apps sharing the SDR do not cut each
other off. A rail that was already on before the first `aio-run` claimed it
(turned on by hand, or a boot default) is left on.

Measured on the board:

- **The SDR does not need the USB rail.** The RTL-SDR sits behind the AIO's
  internal hub, which stays up with the USB rail off. The USB rail powers the
  external USB-A port. Leave it on if you plug things in (CHIRP cables, Wi-Fi
  adapters for Kismet); otherwise it can go off at boot too.
- **LoRa is handled by `meshtasticd` itself** (section 5), not by `aio-run`.
- **`gpsd` is socket-activated** with `-n`, so it simply picks up NMEA whenever
  the GPS rail comes up.

---

## 7. Omarchy integration: one key for everything

### Alt + R: the SDR menu

[`scripts/sdr/sdr-omarchy-integration.sh`](../scripts/sdr/sdr-omarchy-integration.sh)
adds an **SDR** submenu to the Omarchy menu, using
`~/.config/omarchy/extensions/omarchy-menu.jsonc`, and binds `SUPER + R` to it.
With keyd mapping Alt to Super (Step 13), that is **Alt + R** on the uConsole
keyboard.

```
SDR
├─ Receivers        SDR++ · Gqrx · SigDigger · FM radio · NOAA weather radio
├─ Decoders         ADS-B aircraft · APRS packets · ISM sensors (rtl_433) · Pagers
├─ Analyse & build  Universal Radio Hacker · GNU Radio Companion · Inspectrum
├─ Ham radio        CHIRP · Gpredict
├─ GPS              GPS map · GPS status · PyGPSClient · xgps · Viking maps
├─ Meshtastic       Open Meshtastic · Meshtastic CLI · Keep node running ✓
├─ Wireless         Kismet server · Kismet web UI · Wireshark
└─ AIO power        SDR ✓ · GPS ✓ · LORA ✓ · USB ✓ · All radios off · Power monitor · SDR self test
```

Every hardware entry goes through `sdr-launch` (single instance + `aio-run`), `sdr-tool` or `meshtastic-ui`, so
picking it powers the right radio and closing it powers the radio down. The power
rows show a check mark when a rail is on, read live from `pinctrl`. Rows for apps
that are not installed are hidden.

### The same in the app launcher

The script writes user-level copies of the system `.desktop` files for Gqrx,
SDR++, SigDigger, GNU Radio Companion, URH, xgps and Viking, with `Exec=` prefixed
by `aio-run`. A file with the same name in `~/.local/share/applications`
overrides the system one, so the launcher (Super + Space) powers radios exactly
like the menu does. Tools that ship no launcher (inspectrum, PyGPSClient, the
`sdr-tool` jobs, Meshtastic, Kismet) get new entries. Terminal tools use
Omarchy's own `xdg-terminal-exec --app-id=TUI.float|TUI.tile` convention.

### sdr-tool: the terminal decoders

[`scripts/sdr/sdr-tool`](../scripts/sdr/sdr-tool) gives each command-line job a
name and a sensible default:

```
sdr-tool fm [MHz]        broadcast FM; with no MHz, scan the band and pick a station
sdr-tool noaa [MHz]      NOAA weather radio; with no MHz, tune the strongest channel,
                         or say so if none is 10 dB above the noise
sdr-tool adsb            aircraft table (dump1090_rs + modeslive)
sdr-tool aprs [MHz]      APRS packets via direwolf, receive only (144.39)
sdr-tool ism             rtl_433
sdr-tool pager [MHz]     POCSAG/FLEX via multimon-ng
sdr-tool scan LO HI      list signals between LO and HI MHz, in dB above the noise
sdr-tool test            rtl_test
```

Each job re-runs itself under `aio-run`, so the SDR stays powered across the
scan and the playback and is switched off when the job ends. The scans use
`rtl_power` and report each peak relative to the band's median, which tells a
station from noise. Indoors, for example, FM stations measured +7 to +28 dB and
every NOAA channel stayed within 6 dB of the floor, so nothing was being
received.

### gps-map: live position on a map

Viking can follow gpsd, but only after right-clicking its GPS layer and choosing
*Start Realtime Tracking* every session, which is awkward on a 5" screen.
[`scripts/sdr/gps-map`](../scripts/sdr/gps-map) is a ~150-line Python program. It
reads gpsd, serves a Leaflet/OpenStreetMap page on `127.0.0.1`, and opens it in
its own Chromium app window. The map follows the fix and draws a trail. A panel
shows fix type, satellites used/seen, a signal-strength bar per satellite, and
accuracy, so you can watch it acquire instead of staring at a blank map. Closing
the window exits, and `sdr-launch`/`aio-run` power the GPS down. Tiles need a
network; position does not. Indoors, the AIO V2 GPS typically hears 0–3
satellites and gets no fix. It needs a window or open sky.

### meshtastic-ui: one-click Meshtastic

[`scripts/sdr/meshtastic-ui`](../scripts/sdr/meshtastic-ui) starts
`meshtasticd`, which powers the LoRa radio, waits for the node API, and opens the
node's own web client in a dedicated Chromium app window. Closing the window stops
the node and cuts LoRa power, unless the node was already running ("Keep node
running" in the menu). `--tui` gives a `meshtastic` CLI shell instead.

Notes:

- The dedicated `--user-data-dir` makes the window its own process, so the script
  can tell when it closes. Pass `--no-first-run`, or the first launch shows
  Chromium's terms dialog instead of the app.
- With Hyprland's Lua config, `hyprctl dispatch exec ...` no longer works.
  Scripts must use `hyprctl dispatch 'hl.dsp.exec_cmd("…")'`.

### Install

```bash
sudo install -m755 scripts/sdr/{aio-run,sdr-launch,sdr-tool,gps-map,meshtastic-ui} /usr/local/bin/
pipx install "pyModeS<3"
bash scripts/sdr/sdr-omarchy-integration.sh      # as the desktop user
```

The integration script is safe to re-run. It overwrites `omarchy-menu.jsonc`, so
merge it by hand if you have your own entries, and appends one `o.bind` line to
`~/.config/hypr/bindings.lua`.

---

## 8. What was tested

Each app was launched on the device exactly as the menu launches it, checked for
a mapped window and no core dump, then closed through Hyprland as a user would.
The rail state was read before and after.

| App | Window | Radio on while open | Radio off after close |
|---|---|---|---|
| SDR++, Gqrx, SigDigger, URH, GNU Radio Companion | yes | SDR | yes |
| Viking, xgps, PyGPSClient, cgps | yes | GPS | yes |
| Inspectrum, CHIRP, Gpredict, Wireshark | yes | none needed | n/a |
| ADS-B, APRS, rtl_433, pagers, FM, NOAA, self test | terminal | SDR | yes |
| Speaker (test tone, FM) | audible after GPIO11 fix | SDR for FM | yes |
| Meshtastic web client | yes (7 s) | LoRa (via meshtasticd) | yes, node stopped |
| Kismet | web UI on :2501 | none | n/a |

Received live during testing: ADS-B Mode S frames, GPS NMEA (3 satellites
indoors, no fix), FM audio to the speaker, and a Meshtastic node with
`sx1262 init success`.

Kismet needs a capture source added in its web UI. The CM4's own Wi-Fi
(brcmfmac) cannot do monitor mode, so plug a monitor-capable USB adapter into
the AIO's USB-A port.

---

## 9. Agent CLIs (Claude Code, Codex, gh) via mise

A packaged Omarchy install gets `claude`, `codex`, `gh`, `node` and the other
agent CLIs from mise, configured in `/etc/mise/conf.d/` by the
`omarchy-settings` package. The git deploy in Step 11 does not have those files.

`omarchy-settings` exists in the aarch64 Omarchy repo, but **do not install the
whole package** on the uConsole. It also ships mkinitcpio hooks (with Plymouth),
Limine entry config and many `/etc/skel` defaults. Extract only the mise and
shell-bootstrap files:

```bash
sudo pacman -Sw omarchy-settings
f=$(ls /var/cache/pacman/pkg/omarchy-settings-*.pkg.tar.zst | tail -1)
sudo bsdtar -xpf "$f" -C / \
  etc/mise/conf.d/omarchy-tools.toml etc/mise/conf.d/omarchy.toml \
  etc/mise/conf.d/omarchy-agent-accounts.toml etc/profile.d/omarchy.sh
bash -lc 'mise install claude codex gh node'     # ~12 min on the CM4, mostly Node
```

Then log in on the device (`gh auth login --web`, `claude` then `/login`,
`codex login`). Do this rather than copying `~/.claude/.credentials.json` or
`~/.codex/auth.json` from another machine: the refresh tokens rotate, so two
machines sharing one log each other out.

---

## 10. Renaming the default `alarm` user

A rename keeps the Omarchy setup, the groups and autologin. It must run while the
user is logged out, so run it as a detached root job, which ends with a reboot:

```bash
sudo systemd-run --unit=rename-user --collect /bin/bash -c '
  sed -i "s/--autologin alarm /--autologin NEWUSER /" \
    /etc/systemd/system/getty@tty1.service.d/autologin.conf
  systemctl daemon-reload; systemctl stop getty@tty1
  loginctl terminate-user alarm; sleep 3; pkill -KILL -u alarm; sleep 2
  usermod -l NEWUSER -d /home/NEWUSER -m alarm
  groupmod -n NEWUSER alarm
  sed -i "s/^alarm:/NEWUSER:/" /etc/subuid /etc/subgid
  echo "NEWUSER:NEWPASSWORD" | chpasswd
  systemctl reboot'
```

Afterwards, run `pipx reinstall-all` as the new user, because pipx scripts embed
the old home path. Also change root's password; the image default is
`root`/`root`.

---

## 11. Building the card offline from an x86 machine

Most of the README can be done before the card goes into the uConsole: work in an
aarch64 chroot on the card, under `qemu-user-static` with binfmt's `F` flag.

- **DNS:** `/etc/resolv.conf` is a symlink into `/run`. Move it aside, copy the
  host's in, and restore it afterwards.
- **Leftover processes:** `pacman-key` leaves `gpg-agent` and `dirmngr` running.
  Kill anything whose `/proc/*/root` is the mount point before unmounting.
- **Expected noise:** mkinitcpio warns about the `microcode` hook,
  `drm_privacy_screen` and `vconsole.conf`, and Chromium crashes under qemu when
  Omarchy sets the theme. The theme is still staged correctly.
- **pacman hooks that do not run in a chroot:** pacman skips `systemd` hooks
  there ("Skipped: Running in chroot"). `systemd-sysusers` and
  `systemd-tmpfiles` catch up on the first real boot.
- **Big C++ builds** (SDR++, LimeSuite) are faster on the CM4 itself after first
  boot than under emulation.

## Phone tethering (iPhone/Android)

The AIO V2 has no cellular modem, and ClockworkPi's 4G board needs the same
expansion slot, so mobile data comes from a phone.

- **Wi-Fi hotspot**: join it like any network. Nothing to install.
- **USB**: the uConsole kernel ships `ipheth`. Install `usbmuxd`
  (`libimobiledevice` is already there), plug the phone into a USB-A port
  (the USB-C port is charge-only), unlock it and tap *Trust*.
- **Bluetooth (automatic fallback)**: pair the phone once in `bluetui` with
  Personal Hotspot open. `config/tether/bt-tether-auto` then picks any paired
  phone offering Bluetooth NAP, creates a NetworkManager `panu` connection for
  it, and brings it up only while no Wi-Fi/Ethernet/USB connection is active.
  It drops the tether again as soon as Wi-Fi is back. It is run by a
  NetworkManager dispatcher hook (`90-bt-tether-auto`) and by
  `bt-tether-auto.timer` every minute, which catches a phone coming into range.
  Throughput is low (tens of KB/s to a few Mbit/s), because the CM4's single
  Wi-Fi/Bluetooth chip and the phone's cell signal both limit it.

```sh
sudo install -m755 config/tether/bt-tether-auto /usr/local/bin/
sudo install -m755 config/tether/90-bt-tether-auto /etc/NetworkManager/dispatcher.d/
sudo install -m644 config/tether/bt-tether-auto.{service,timer} /etc/systemd/system/
sudo systemctl enable --now NetworkManager-dispatcher bt-tether-auto.timer
```

Tested: with the Wi-Fi radio off, the uConsole was online through the iPhone
within about 10 s. With Wi-Fi back on, the tether was dropped within a minute.

## More SDR apps: aircraft map, ships, weather satellites, network sharing

None of these are packaged for aarch64, so they are built from source (all
four build and run on the CM4):

| App | Build | Launcher (Alt + R) |
|---|---|---|
| readsb + tar1090 | `git clone wiedehopf/readsb && make RTLSDR=yes`; copy `tar1090/html` to `/usr/local/share/tar1090/html` | **Decoders > ADS-B aircraft map** (`scripts/sdr/adsb-map`) |
| AIS-catcher 0.70 | cmake, no extra deps | **Decoders > AIS ships map** (`scripts/sdr/ais-map`) |
| SatDump 1.2.2 | cmake `-DBUILD_GUI=ON`, deps `libvolk fftw glfw jemalloc nng zstd portaudio boost lua54 ocl-icd hdf5`; about 3 h with `make -j2` (`-j3` risks running out of RAM on a 4 GB CM4) | **Decoders > SatDump weather satellites** |
| rtl_tcp (in `rtl-sdr`) | already installed | **Receivers > Share SDR over network** (`sdr-tool share`) |

- `adsb-map` runs readsb, writing JSON to a private runtime directory, and
  serves tar1090 plus that JSON on 127.0.0.1 from a small Python server, so no
  lighttpd or nginx is needed. It opens in its own Chromium app window and uses
  the GPS position if gpsd already has a fix. Closing the window stops readsb,
  and `aio-run` powers the SDR off. The AUR `readsb-git` is the
  Mictronics/protobuf fork, which pulls in bladeRF, libiio and rrdtool, and
  `tar1090-git` expects a dump1090 package; neither is needed here.
- `ais-map` runs AIS-catcher's built-in web map with `IP_BIND 127.0.0.1` (by
  default it listens on all interfaces) and `-X off`: **AIS-catcher shares
  received data with aiscatcher.org by default.**
- `sdr-tool share` runs `rtl_tcp -a 0.0.0.0 -p 1234` and prints the LAN and
  Tailscale addresses to use with SDR++'s RTL-TCP source. It is unauthenticated,
  so only run it on networks you trust.

Tested: the aircraft map showed traffic over New York within 25 s; AIS-catcher
started and served its map; an rtl_tcp client on another machine received the
`RTL0` header (R820T, 29 gains) and a live sample stream. Each one powered the
SDR on while running and off again afterwards.

The uConsole's Omarchy git checkout does not install
`/usr/share/omarchy/etc/sudoers.d/*` the way the `omarchy-settings` package
does on x86. Without `omarchy-theme-browser`, every theme change asks for a
password via pkexec (for `omarchy-theme-set-browser-policy`). Install those
narrowly scoped rules with `sudo install -m440 /usr/share/omarchy/etc/sudoers.d/* /etc/sudoers.d/`.
