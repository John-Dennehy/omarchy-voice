import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "jd.voice"

  readonly property string statusPath: (Quickshell.env("HOME") || "") + "/.local/state/omarchy/voice/status.json"

  property string voiceState: "idle" // idle, connecting, listening, speaking, tool, muted, error
  property string activeProject: ""
  property bool isMuted: false

  FileView {
    id: statusWatcher
    path: root.statusPath
    watchChanges: true
    printErrors: false
    onLoaded: {
      try {
        var raw = text()
        if (raw && raw.trim()) {
          var data = JSON.parse(raw.trim())
          if (data.updatedAt) {
            var diffMs = Date.now() - Date.parse(data.updatedAt)
            if (!isNaN(diffMs) && diffMs > 15000) {
              root.voiceState = "idle"
              return
            }
          }
          if (data.state) root.voiceState = data.state
          if (data.project) root.activeProject = data.project
          if (data.isMuted !== undefined) root.isMuted = data.isMuted
        }
      } catch (err) {}
    }
  }

  Timer {
    interval: 2500
    running: true
    repeat: true
    onTriggered: statusWatcher.reload()
  }

  readonly property color iconColor: {
    if (root.voiceState === "listening") return Color.accent
    if (root.voiceState === "speaking") return Color.success
    if (root.voiceState === "tool") return Color.warning
    if (root.voiceState === "muted" || root.isMuted) return Color.urgent
    if (root.voiceState === "connecting") return "#fab387"
    return root.bar ? root.bar.barForeground : Color.foreground
  }

  readonly property string iconText: {
    if (root.voiceState === "speaking") return "󰕾"
    if (root.voiceState === "muted" || root.isMuted) return "󰍭"
    if (root.voiceState === "tool") return "󱚣"
    return "󰍬"
  }

  readonly property string tip: {
    if (root.voiceState === "listening") return "Voice: Listening [" + (root.activeProject || "ready") + "]\nLeft-click: Pill | Right-click: Mute | Middle-click: Drawer"
    if (root.voiceState === "speaking") return "Voice: Speaking...\nLeft-click: Pill | Right-click: Mute"
    if (root.voiceState === "muted") return "Voice: Muted\nClick to unmute"
    if (root.voiceState === "tool") return "Voice: Running action..."
    return "Voice Assistant (Idle)\nClick to summon"
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.iconText
    foreground: root.iconColor
    slotSize: Style.bar.statusSlot
    tooltipText: root.tip

    onPressed: function(b) {
      if (b === Qt.RightButton) {
        Quickshell.execDetached(["omarchy-shell", "voice", "toggleMute"])
      } else if (b === Qt.MiddleButton) {
        Quickshell.execDetached(["omarchy-shell", "voice", "toggleExpanded"])
      } else {
        Quickshell.execDetached(["omarchy-shell", "voice", "togglePill"])
      }
    }
  }
}
