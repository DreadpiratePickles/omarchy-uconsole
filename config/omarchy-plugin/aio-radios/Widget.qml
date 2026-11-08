import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// AIO V2 radio power for the uConsole. One standard bar icon per powered radio
// (SDR, GPS, LoRa), or a single dimmed icon when they are all off; the tooltip
// says which app holds each radio and the power draw. Data comes from
// /usr/local/bin/aio-status, polled every few seconds.
BarWidget {
  id: root
  moduleName: "aio.radios"

  property var radios: null
  readonly property var lit: Model.litRails(radios)
  readonly property bool anyOn: lit.length > 0
  readonly property bool hideWhenOff: setting("hideWhenOff", false) === true
  readonly property int intervalMs: Math.max(1, Math.min(30, Number(setting("interval", 3)))) * 1000
  readonly property string tip: Model.tooltip(radios)

  visible: anyOn || !hideWhenOff
  implicitWidth: icons.implicitWidth
  implicitHeight: icons.implicitHeight

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function press(b) {
    if (!root.bar) return
    if (b === Qt.RightButton) root.bar.run("omarchy-menu toggle sdr")
    else if (b === Qt.MiddleButton) root.bar.run("omarchy-launch-tui aiov2_ctl --watch")
    else root.bar.run("omarchy-menu toggle sdr.power")
    refreshSoon.restart()
  }

  Process {
    id: statusProc
    command: ["/usr/local/bin/aio-status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.radios = Model.parse(text)
    }
  }

  Timer {
    interval: root.intervalMs
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  // Catch a toggle made from the menu without waiting a full interval.
  Timer {
    id: refreshSoon
    interval: 1500
    onTriggered: root.refresh()
  }

  Grid {
    id: icons
    rows: root.vertical ? -1 : 1
    columns: root.vertical ? 1 : -1
    spacing: 0

    Repeater {
      model: root.anyOn ? root.lit : [{ name: "OFF", glyph: "" }]

      BarIconButton {
        required property var modelData
        bar: root.bar
        text: modelData.glyph
        slotSize: Style.bar.statusSlot
        dimmed: !root.anyOn
        tooltipText: root.tip
        onPressed: function(b) { root.press(b) }
      }
    }
  }
}
