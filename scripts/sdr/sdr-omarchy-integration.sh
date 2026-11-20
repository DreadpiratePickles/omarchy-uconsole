#!/bin/bash
# Integrate the SDR / AIO V2 toolkit into Omarchy on a uConsole.
#   - every SDR app in the app launcher powers the AIO rails it needs while it
#     runs, and switches them off afterwards (aio-run / sdr-tool / meshtastic-ui)
#   - an "SDR" submenu in the Omarchy menu containing every SDR command, plus
#     AIO power-rail toggles
#   - SUPER + R (Alt + R on the uConsole keyboard) opens that menu
# Needs aio-run, sdr-launch, sdr-tool, gps-map and meshtastic-ui in /usr/local/bin
# (adsb-map, ais-map and satdump-ui are optional).
# Run as the desktop user (not root). Safe to re-run.
set -euo pipefail

APPS="$HOME/.local/share/applications"
mkdir -p "$APPS"
have() { command -v "$1" >/dev/null 2>&1 || [[ -x $1 ]]; }

# ---- 1. wrap the system launchers of hardware apps --------------------------
# A copy in ~/.local/share/applications with the same name overrides the
# system one; only the Exec lines change.
wrap() { # desktop-file PROC RAILS — single instance, rails powered while running
  local src="/usr/share/applications/$1"
  [[ -f $src ]] || return 0
  sed -E "s|^(Exec=)(.*)$|\1sdr-launch $2 $3 -- \2|; /^TryExec=/d" "$src" > "$APPS/$1"
}
wrap dk.gqrx.gqrx.desktop     gqrx            SDR
wrap sdrpp.desktop            sdrpp           SDR
# start receiving as soon as SDR++ has loaded
[[ -f $APPS/sdrpp.desktop ]] && sed -i -E "s|^(Exec=.*sdrpp)$|\1 --autostart|" "$APPS/sdrpp.desktop"
wrap SigDigger.desktop        SigDigger       SDR
wrap gnuradio-grc.desktop     gnuradio-compan SDR
wrap urh.desktop              urh             SDR
wrap xgps.desktop             xgps            GPS
wrap xgpsspeed.desktop        xgpsspeed       GPS
# Viking resolves to /usr/local/bin/viking, which preloads the glycin warm-up
# shim (see glycin-warmup.c); without it Viking 1.11 hangs before its window.
wrap viking.desktop           viking          GPS
# direwolf's own launcher starts it with no config; APRS lives in sdr-tool.
[[ -f /usr/share/applications/direwolf.desktop ]] && \
  printf '[Desktop Entry]\nType=Application\nName=direwolf\nNoDisplay=true\n' > "$APPS/direwolf.desktop"

desktop() { # file name exec icon comment [terminal-class]
  {
    printf '[Desktop Entry]\nVersion=1.0\nType=Application\nName=%s\nComment=%s\nIcon=%s\n' "$2" "$5" "$4"
    if [[ -n ${6:-} ]]; then
      printf 'Exec=xdg-terminal-exec --app-id=%s -e %s\n' "$6" "$3"
    else
      printf 'Exec=%s\n' "$3"
    fi
    printf 'Terminal=false\nCategories=HamRadio;Network;\n'
  } > "$APPS/$1.desktop"
}

# ---- 2. launchers for apps that ship none -----------------------------------
have inspectrum && desktop inspectrum "Inspectrum" "inspectrum" audio-x-generic "Analyse recorded signal files"
have "$HOME/.local/bin/pygpsclient" && desktop pygpsclient "PyGPSClient" "aio-run GPS -- $HOME/.local/bin/pygpsclient" find-location "GPS/GNSS status (powers the GPS)"
have kismet && desktop kismet-web "Kismet Web UI" "omarchy-launch-webapp http://localhost:2501" network-wireless "Kismet web interface (start Kismet Server first)"
have kismet && desktop kismet-server "Kismet Server" "kismet" network-wireless "Wireless monitor" TUI.tile
have gps-map && desktop gps-map "GPS Map" "sdr-launch gps-map GPS -- gps-map" find-location "Live position on OpenStreetMap (powers the GPS)"
have adsb-map && desktop adsb-map "ADS-B Map" "sdr-launch adsb-map SDR -- adsb-map" airplane-mode-symbolic "Live aircraft map, readsb + tar1090 (powers the SDR)"
have ais-map && desktop ais-map "AIS Ship Map" "sdr-launch ais-map SDR -- ais-map" find-location "Ships near you via AIS-catcher (powers the SDR)"
# same basename as SatDump's own launcher, so this one (which powers the SDR) wins
have satdump-ui && desktop satdump "SatDump" "sdr-launch satdump-ui SDR -- satdump-ui" weather-few-clouds "Weather satellite decoder (powers the SDR)"
have cgps && desktop gps-status "GPS Status" "aio-run GPS -- cgps -s" find-location "Live GPS fix (powers the GPS)" TUI.float
have aiov2_ctl && desktop aio-power "AIO Power Monitor" "aiov2_ctl --watch" battery "AIO V2 rails and power draw" TUI.float
if have sdr-tool; then
  desktop sdr-adsb  "ADS-B Aircraft"     "sdr-tool adsb"  airplane-mode-symbolic "Aircraft near you (powers the SDR)" TUI.tile
  desktop sdr-aprs  "APRS Decoder"       "sdr-tool aprs"  network-wireless "APRS packets on 144.39 MHz (powers the SDR)" TUI.tile
  desktop sdr-ism   "ISM Sensors"        "sdr-tool ism"   network-wireless "rtl_433: weather stations, TPMS, doorbells (powers the SDR)" TUI.tile
  desktop sdr-pager "Pager Decoder"      "sdr-tool pager" network-wireless "POCSAG/FLEX via multimon-ng (powers the SDR)" TUI.float
  desktop sdr-fm    "FM Radio"           "sdr-tool fm"    audio-x-generic "Broadcast FM (powers the SDR)" TUI.float
  desktop sdr-noaa  "NOAA Weather Radio" "sdr-tool noaa"  weather-showers "162.55 MHz weather radio (powers the SDR)" TUI.float
  desktop sdr-share "Share SDR (rtl_tcp)" "sdr-tool share" network-wireless "Let SDR++/Gqrx on another computer use this radio (powers the SDR)" TUI.float
  desktop sdr-test  "SDR Self Test"      "sdr-tool test"  utilities-system-monitor "rtl_test (powers the SDR)" TUI.float
fi
if have meshtastic-ui; then
  desktop meshtastic     "Meshtastic"     "meshtastic-ui"       network-wireless "Start the LoRa node and open its web client; closing stops it"
  desktop meshtastic-cli "Meshtastic CLI" "meshtastic-ui --tui" utilities-terminal "Start the LoRa node with a meshtastic CLI shell" TUI.tile
fi
# remove launchers from earlier versions of this script
rm -f "$APPS/rtl_433.desktop" "$APPS/GPS Status.desktop" "$APPS/Kismet Server.desktop" \
      "$APPS/AIO Power Monitor.desktop" "$APPS/Meshtastic Info.desktop"
update-desktop-database "$APPS" 2>/dev/null || true

# ---- 3. Omarchy menu: SDR submenu -------------------------------------------
# rail pins: SDR=7 GPS=27 LORA=16 USB=23 (HackerGadgets AIO V2)
q() { local s=${1//\\/\\\\}; printf '%s' "${s//\"/\\\"}"; }   # JSON-escape
row() { # id icon label action [when] [checked]
  printf '  "sdr.%s": {"icon":"%s","label":"%s","action":"%s"' "$1" "$2" "$(q "$3")" "$(q "$4")"
  [[ -n ${5:-} ]] && printf ',"when":"%s"' "$(q "$5")"
  [[ -n ${6:-} ]] && printf ',"checked":"%s"' "$(q "$6")"
  printf '},\n'
}
sub() { printf '  "sdr.%s": {"icon":"%s","label":"%s"},\n' "$1" "$2" "$(q "$3")"; }
gui() { row "$1" "$2" "$3" "uwsm-app -- $4" "command -v ${5:-${4##* }}"; }        # id icon label cmd [bin]
tui() { row "$1" "$2" "$3" "omarchy-launch-tui $4" "command -v ${5:-${4%% *}}"; } # id icon label cmd [bin]
rail() { # FEATURE PIN
  local on="pinctrl get $2 | grep -q '| hi'"
  row "power.${1,,}" "$I_PWR" "$1 radio power" \
    "aiov2_ctl $1 \$($on && echo off || echo on) && omarchy-notification-send 'AIO $1 rail toggled'" \
    "" "$on"
}
I_SDR=$'' I_PWR=$'' I_RX=$'' I_DEC=$'' I_AN=$''
I_HAM=$'' I_GPS=$'' I_NET=$'' I_MESH=$'' I_TERM=$''
I_WEB=$'' I_ON=$'' I_OFF=$'' I_TEST=$''

mkdir -p "$HOME/.config/omarchy/extensions"
{
  echo '{'
  echo '  // SDR / AIO V2 menu, generated by sdr-omarchy-integration.sh.'
  echo '  // Every app here powers the AIO rails it needs while it runs.'
  printf '  "sdr": {"icon":"%s","label":"SDR","aliases":["radio"],"description":"Radios, decoders, GPS, LoRa and AIO V2 power"},\n' "$I_SDR"

  sub receive "$I_RX" "Receivers"
  gui receive.sdrpp     "$I_RX" "SDR++"                "sdr-launch sdrpp SDR -- sdrpp --autostart" sdrpp
  gui receive.gqrx      "$I_RX" "Gqrx"                 "sdr-launch gqrx SDR -- gqrx"
  gui receive.sigdigger "$I_RX" "SigDigger"            "sdr-launch SigDigger SDR -- SigDigger"
  tui receive.fm        "$I_RX" "FM radio"             "sdr-tool fm" sdr-tool
  tui receive.noaa      "$I_RX" "NOAA weather radio"   "sdr-tool noaa" sdr-tool
  tui receive.share     "$I_RX" "Share SDR over network" "sdr-tool share" sdr-tool

  sub decode "$I_DEC" "Decoders"
  gui decode.adsbmap "$I_DEC" "ADS-B aircraft map"   "sdr-launch adsb-map SDR -- adsb-map" adsb-map
  tui decode.adsb  "$I_DEC" "ADS-B aircraft (text)"  "sdr-tool adsb" sdr-tool
  gui decode.ais   "$I_DEC" "AIS ships map"          "sdr-launch ais-map SDR -- ais-map" ais-map
  gui decode.satdump "$I_DEC" "SatDump weather satellites" "sdr-launch satdump-ui SDR -- satdump-ui" satdump-ui
  tui decode.aprs  "$I_DEC" "APRS packets"           "sdr-tool aprs" sdr-tool
  tui decode.ism   "$I_DEC" "ISM sensors (rtl_433)"  "sdr-tool ism" sdr-tool
  tui decode.pager "$I_DEC" "Pagers (POCSAG/FLEX)"   "sdr-tool pager" sdr-tool

  sub analyse "$I_AN" "Analyse & build"
  gui analyse.urh        "$I_AN" "Universal Radio Hacker" "sdr-launch urh SDR -- urh"
  gui analyse.grc        "$I_AN" "GNU Radio Companion"    "sdr-launch gnuradio-compan SDR -- gnuradio-companion"
  gui analyse.inspectrum "$I_AN" "Inspectrum (files)"     "inspectrum"

  sub ham "$I_HAM" "Ham radio"
  gui ham.chirp    "$I_HAM" "CHIRP radio programmer" "chirp"
  gui ham.gpredict "$I_HAM" "Gpredict satellites"    "gpredict"

  sub gps "$I_GPS" "GPS"
  gui gps.map         "$I_GPS" "GPS map"       "sdr-launch gps-map GPS -- gps-map" gps-map
  tui gps.cgps        "$I_GPS" "GPS status"    "aio-run GPS -- cgps -s" cgps
  gui gps.pygpsclient "$I_GPS" "PyGPSClient"   "aio-run GPS -- $HOME/.local/bin/pygpsclient" "$HOME/.local/bin/pygpsclient"
  gui gps.xgps        "$I_GPS" "xgps"          "sdr-launch xgps GPS -- xgps"
  gui gps.viking      "$I_GPS" "Viking maps"   "sdr-launch viking GPS -- viking"

  sub mesh "$I_MESH" "Meshtastic (LoRa)"
  row mesh.web  "$I_WEB"  "Open Meshtastic"     "meshtastic-ui" "command -v meshtastic-ui"
  tui mesh.cli  "$I_TERM" "Meshtastic CLI"      "meshtastic-ui --tui" meshtastic-ui
  row mesh.node "$I_ON"   "Keep node running"   \
    "systemctl \$(systemctl is-active -q meshtasticd && echo stop || echo start) meshtasticd" \
    "command -v meshtasticd" "systemctl is-active -q meshtasticd"

  sub net "$I_NET" "Wireless"
  tui net.kismet    "$I_NET" "Kismet server" "kismet"
  row net.kismetweb "$I_WEB" "Kismet web UI" "omarchy-launch-webapp http://localhost:2501" "command -v kismet"
  gui net.wireshark "$I_NET" "Wireshark"     "wireshark"

  sub power "$I_PWR" "AIO power"
  rail SDR 7; rail GPS 27; rail LORA 16; rail USB 23
  row power.alloff "$I_OFF"  "All radios off" \
    "systemctl stop meshtasticd 2>/dev/null; for r in SDR GPS LORA; do aiov2_ctl \$r off; done; omarchy-notification-send 'AIO radios off'"
  tui power.monitor "$I_PWR" "Power monitor"   "aiov2_ctl --watch" aiov2_ctl
  tui power.test    "$I_TEST" "SDR self test"  "sdr-tool test" sdr-tool
  echo '}'
} | sed -z 's/,\n}/\n}/' > "$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"

# ---- 4. keybinding ------------------------------------------------------------
B="$HOME/.config/hypr/bindings.lua"
grep -q 'omarchy-menu toggle sdr' "$B" 2>/dev/null || \
  printf '\n-- SDR / AIO V2 menu (Alt + R on the uConsole keyboard)\no.bind("SUPER + R", "SDR menu", "omarchy-menu toggle sdr")\n' >> "$B"

echo "SDR launchers, Omarchy SDR menu and SUPER+R binding installed."
