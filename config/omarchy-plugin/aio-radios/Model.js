.pragma library
// Pure helpers for Widget.qml, kept here so they can be tested without a shell.

var NAMES = {
  "SDR": "SDR", "GPS": "GPS", "LORA": "LoRa", "USB": "USB"
}

var APPS = {
  "sdrpp": "SDR++", "gqrx": "Gqrx", "SigDigger": "SigDigger", "urh": "Universal Radio Hacker",
  "gnuradio-companion": "GNU Radio", "satdump-ui": "SatDump", "adsb-map": "ADS-B map",
  "ais-map": "AIS map", "gps-map": "GPS map", "xgps": "xgps", "xgpsspeed": "xgpsspeed",
  "viking": "Viking", "cgps": "GPS status", "pygpsclient": "PyGPSClient",
  "meshtasticd": "Meshtastic node", "sdr-tool fm": "FM radio", "sdr-tool noaa": "NOAA radio",
  "sdr-tool adsb": "ADS-B (text)", "sdr-tool aprs": "APRS", "sdr-tool ism": "ISM sensors",
  "sdr-tool pager": "Pagers", "sdr-tool scan": "Band scan", "sdr-tool share": "SDR sharing",
  "sdr-tool test": "SDR test"
}

// Command output is untrusted: keep it short and free of markup.
function clean(s) {
  return String(s).replace(/[<>&"'\u0000-\u001f]/g, "").slice(0, 40)
}

function appName(raw) {
  var s = clean(raw)
  return APPS.hasOwnProperty(s) ? APPS[s] : s
}

function parse(text) {
  try {
    var d = JSON.parse(String(text).trim())
    if (!d || !Array.isArray(d.rails)) return null
    var rails = []
    for (var i = 0; i < d.rails.length && i < 8; i++) {
      var r = d.rails[i]
      if (!r || !NAMES.hasOwnProperty(r.name)) continue
      var apps = Array.isArray(r.apps) ? r.apps.slice(0, 6).map(appName) : []
      rails.push({ name: r.name, label: NAMES[r.name], on: r.on === true, apps: apps })
    }
    return {
      rails: rails,
      watts: typeof d.watts === "number" ? d.watts : null,
      charging: d.charging === true,
      battery: typeof d.battery === "number" ? d.battery : null
    }
  } catch (e) {
    return null
  }
}

// Font Awesome glyphs, as in the Alt + R SDR menu.
var GLYPHS = { "SDR": "\uf012", "GPS": "\uf124", "LORA": "\uf1e0" }

// The powered radios to show in the bar, in a fixed order. USB is the AIO's
// hub, normally on, so it is left to the tooltip.
function litRails(state) {
  if (!state) return []
  return state.rails.filter(function(r) { return r.on && GLYPHS.hasOwnProperty(r.name) })
    .map(function(r) { return { name: r.name, glyph: GLYPHS[r.name] } })
}

function tooltip(state) {
  if (!state) return "AIO radios: status unavailable"
  var lines = state.rails.map(function(r) {
    return r.label + ": " + (r.on ? "on" : "off") + (r.apps.length ? " (" + r.apps.join(", ") + ")" : "")
  })
  if (state.watts !== null) {
    lines.push((state.charging ? "Charging, " : "Battery draw ") + state.watts.toFixed(2) + " W"
      + (state.battery !== null ? ", " + state.battery + "%" : ""))
  }
  lines.push("Click: radio power · Right: SDR menu · Middle: power monitor")
  return lines.join("\n")
}
