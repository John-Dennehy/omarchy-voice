import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Ui

Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property var activeScreen: {
    var mon = Hyprland.focusedMonitor
    if (mon && mon.name && Quickshell.screens) {
      for (var i = 0; i < Quickshell.screens.length; i++) {
        var sc = Quickshell.screens[i]
        if (sc && String(sc.name || "") === String(mon.name || "")) {
          return sc
        }
      }
    }
    return Quickshell.screens && Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
  }

  property bool opened: false
  property string viewMode: "pill" // "pill" or "expanded"
  property string statusTitle: "Connecting..."
  property string statusSub: "Initiating native Gemini Live session..."
  property string sessionState: "connecting" // connecting, listening, speaking, tool, muted, error
  property string activeProject: "main"
  property string githubUser: ""
  property bool isMuted: false
  property string currentTab: "transcript" // "transcript" or "parking_lot" or "repos"
  property bool inAgentWorkspace: false
  property bool followAgentWorkspace: true
  property bool autoOpenedByWorkspace: false

  FileView {
    id: configWatcher
    path: (Quickshell.env("HOME") || "") + "/.config/omarchy/voice/config.json"
    watchChanges: true
    printErrors: false
    onLoaded: {
      try {
        var raw = text()
        if (raw && raw.trim()) {
          var cfg = JSON.parse(raw.trim())
          if (cfg.workspace && cfg.workspace.followAgentWorkspace !== undefined) {
            root.followAgentWorkspace = cfg.workspace.followAgentWorkspace
          }
        }
      } catch (err) {}
    }
  }

  Process {
    id: initialWorkspaceCheck
    command: ["sh", "-c", "hyprctl monitors -j | jq -r '.[0].specialWorkspace.name'"]
    running: true
    stdout: SplitParser {
      onRead: function(line) {
        if (!line) return
        var name = line.trim()
        if (name === "special:agent" || name.indexOf("special:") === 0) {
          root.inAgentWorkspace = true
          if (root.followAgentWorkspace && !root.opened) {
            root.autoOpenedByWorkspace = true
            root.open(JSON.stringify({ mode: "pill" }))
          }
        }
      }
    }
  }

  Process {
    id: hyprSocketListener
    command: [
      "python3", "-u", "-c",
      "import socket, os, sys\n" +
      "sig = os.environ.get('HYPRLAND_INSTANCE_SIGNATURE', '')\n" +
      "runtime = os.environ.get('XDG_RUNTIME_DIR', f'/run/user/{os.getuid()}')\n" +
      "sock = f'{runtime}/hypr/{sig}/.socket2.sock'\n" +
      "if os.path.exists(sock):\n" +
      "    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)\n" +
      "    s.connect(sock)\n" +
      "    while True:\n" +
      "        data = s.recv(1024)\n" +
      "        if not data: break\n" +
      "        for line in data.decode('utf-8', errors='ignore').splitlines():\n" +
      "            if line:\n" +
      "                sys.stdout.write(line + '\\n')\n" +
      "                sys.stdout.flush()\n"
    ]
    running: true
    stdout: SplitParser {
      onRead: function(line) {
        if (!line) return
        var clean = line.trim()
        if (clean.indexOf("activespecial>>special:agent") === 0 || clean.indexOf("activespecialv2>>-98") === 0) {
          root.inAgentWorkspace = true
          if (root.followAgentWorkspace && !root.opened) {
            root.autoOpenedByWorkspace = true
            root.open(JSON.stringify({ mode: "pill" }))
          }
        } else if (clean.indexOf("activespecial>>,") === 0 || clean.indexOf("activespecialv2>>,,") === 0) {
          root.inAgentWorkspace = false
          if (root.followAgentWorkspace && root.autoOpenedByWorkspace && root.opened) {
            root.autoOpenedByWorkspace = false
            root.dismiss()
          }
        }
      }
    }
    onExited: function() {
      restartSocketTimer.start()
    }
  }

  Timer {
    id: restartSocketTimer
    interval: 2000
    repeat: false
    onTriggered: {
      if (!hyprSocketListener.running) hyprSocketListener.running = true
    }
  }

  ListModel {
    id: transcriptModel
  }

  ListModel {
    id: parkingLotModel
  }

  ListModel {
    id: reposModel
  }

  function open(payloadJson) {
    root.opened = true
    if (payloadJson) {
      try {
        var p = JSON.parse(payloadJson)
        if (p.mode) root.viewMode = p.mode
      } catch (err) {}
    }
    if (!daemonProcess.running) {
      daemonProcess.running = true
    }
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function") {
      root.shell.hide(manifest ? manifest.id : "jd.voice")
    }
  }

  function togglePill() {
    if (root.opened && root.viewMode === "pill") {
      root.dismiss()
    } else {
      root.viewMode = "pill"
      root.opened = true
      if (!daemonProcess.running) daemonProcess.running = true
    }
  }

  function toggleExpanded() {
    if (root.opened && root.viewMode === "expanded") {
      root.dismiss()
    } else {
      root.viewMode = "expanded"
      root.opened = true
      if (!daemonProcess.running) daemonProcess.running = true
    }
  }

  function toggle(payloadJson) {
    if (root.opened) {
      if (payloadJson) {
        try {
          var p = JSON.parse(payloadJson)
          if (p.mode && p.mode !== root.viewMode) {
            root.viewMode = p.mode
            return
          }
        } catch (err) {}
      }
      root.dismiss()
    } else {
      root.open(payloadJson)
    }
  }

  IpcHandler {
    target: "voice"
    function open(): void { root.open("{}") }
    function close(): void { root.close() }
    function dismiss(): void { root.dismiss() }
    function toggle(): void { root.toggle("{}") }
    function togglePill(): void { root.togglePill() }
    function toggleExpanded(): void { root.toggleExpanded() }
    function toggleMute(): void { root.toggleMute() }
    function toggleAgentWorkspace(): void {
      Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.workspace.toggle_special(\"agent\")"])
    }
  }

  function sendCmd(cmd) {
    var runtimeDir = Quickshell.env("XDG_RUNTIME_DIR") || "/run/user/1000"
    Quickshell.execDetached(["sh", "-c", "echo " + JSON.stringify(cmd) + " > " + runtimeDir + "/voice-assistant.cmd"])
  }

  function toggleMute() {
    root.sendCmd("toggle_mute")
  }

  function switchProject(repo) {
    root.activeProject = repo
    root.sendCmd("switch_project " + repo)
  }

  function parkIdea(thought) {
    if (!thought || !thought.trim()) return
    root.sendCmd("park_idea " + thought.trim())
  }

  function pushParkedToGithub(item) {
    var repo = item.repo || root.activeProject
    var fullRepo = repo.indexOf("/") >= 0 ? repo : (root.githubUser ? (root.githubUser + "/" + repo) : repo)
    var title = item.thought
    var cmd = "gh issue create --repo '" + fullRepo + "' --title " + JSON.stringify(title) + " --body 'Pushed from Voice Assistant Parking Lot'"
    Quickshell.execDetached(["sh", "-c", cmd])
    root.statusSub = "Pushed issue to GitHub: " + repo
    transcriptModel.append({
      role: "tool",
      text: "Pushed parked thought to GitHub issue in " + fullRepo + ": \"" + title + "\"",
      time: Qt.formatTime(new Date(), "hh:mm:ss")
    })
  }

  // Native Headless Daemon Process
  Process {
    id: daemonProcess
    command: [
      "/home/jd/.local/share/mise/installs/uv/latest/.mise-bins/uv",
      "run",
      Quickshell.env("HOME") + "/Projects/omarchy-voice/daemon.py"
    ]
    running: root.opened
    onExited: function(code, status) {
      if (root.opened) {
        root.sessionState = "error"
        root.statusTitle = "Disconnected"
        root.statusSub = "Voice daemon stopped"
      }
    }
    stdout: SplitParser {
      onRead: function(line) {
        if (!line || !line.trim()) return
        try {
          var data = JSON.parse(line.trim())
          if (data.event === "ready") {
            root.sessionState = data.state || "listening"
            root.statusTitle = data.title || "Listening"
            root.statusSub = data.sub || "Speak freely anytime"
            if (data.activeProject) root.activeProject = data.activeProject
            if (data.user) root.githubUser = data.user
          } else if (data.event === "status") {
            if (data.state) root.sessionState = data.state
            if (data.title) root.statusTitle = data.title
            if (data.sub) root.statusSub = data.sub
          } else if (data.event === "project") {
            if (data.active) root.activeProject = data.active
            if (data.user) root.githubUser = data.user
            if (data.repos && Array.isArray(data.repos)) {
              reposModel.clear()
              for (var i = 0; i < data.repos.length; i++) {
                reposModel.append(data.repos[i])
              }
            }
          } else if (data.event === "muted") {
            root.isMuted = data.isMuted
            root.sessionState = root.isMuted ? "muted" : "listening"
            root.statusTitle = root.isMuted ? "Muted" : "Listening"
          } else if (data.event === "transcript") {
            transcriptModel.append({
              role: data.role,
              text: data.text,
              time: Qt.formatTime(new Date(), "hh:mm:ss")
            })
            if (data.role === "assistant") {
              root.statusSub = data.text.length > 55 ? data.text.slice(0, 52) + "..." : data.text
            }
          } else if (data.event === "tool") {
            if (data.status === "running") {
              root.sessionState = "tool"
              root.statusTitle = "Tool: " + data.name
              root.statusSub = "Executing action..."
            } else if (data.status === "done") {
              root.sessionState = "listening"
              root.statusTitle = "Listening"
              root.statusSub = "Tool completed: " + data.name
            }
          } else if (data.event === "tool_delegated") {
            transcriptModel.append({
              role: "tool",
              text: "Delegated to " + (data.agent || "agent") + " (" + (data.mode || "workspace") + "): \"" + (data.task || "") + "\"",
              time: Qt.formatTime(new Date(), "hh:mm:ss")
            })
            root.statusSub = "Delegated to " + (data.agent || "agent")
          } else if (data.event === "tool_activated_skill") {
            transcriptModel.append({
              role: "tool",
              text: "Activated skill [" + (data.skill || "") + "] via " + (data.agent || "agent") + " (" + (data.mode || "workspace") + "): \"" + (data.prompt || "") + "\"",
              time: Qt.formatTime(new Date(), "hh:mm:ss")
            })
            root.statusSub = "Skill: " + (data.skill || "")
          } else if (data.event === "parking_lot") {
            parkingLotModel.clear()
            if (data.items) {
              for (var j = 0; j < data.items.length; j++) {
                parkingLotModel.append(data.items[j])
              }
            }
          } else if (data.event === "error") {
            root.sessionState = "error"
            root.statusTitle = "Error"
            root.statusSub = data.message || "An error occurred"
          }
        } catch (err) {
          console.warn("VoicePill: JSON parse error:", err)
        }
      }
    }
  }

  // ==========================================
  // VIEW 1: Mini Floating Pill Overlay
  // ==========================================
  PanelWindow {
    id: pillWindow
    screen: root.activeScreen
    visible: root.opened && root.viewMode === "pill"
    anchors {
      top: true
      right: true
    }
    margins {
      top: Style.space(20)
      right: Style.space(24)
    }
    implicitWidth: pillCard.width
    implicitHeight: pillCard.height
    color: "transparent"
    WlrLayershell.namespace: "omarchy-voice-pill"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    BorderSurface {
      id: pillCard
      width: Style.space(460)
      height: Style.space(66)
      radius: Style.cornerRadius > 0 ? Style.cornerRadius : Style.space(16)
      color: Util.alpha(Color.popups.background, 0.94)
      borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(1)))
      opacity: pillWindow.visible ? 1.0 : 0.0
      scale: pillWindow.visible ? 1.0 : 0.94
      Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
      Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }

      Row {
        anchors.fill: parent
        anchors.leftMargin: Style.space(14)
        anchors.rightMargin: Style.space(12)
        spacing: Style.space(12)

        Item {
          id: orbContainer
          width: Style.space(36)
          height: Style.space(36)
          anchors.verticalCenter: parent.verticalCenter

          Rectangle {
            id: pulseRing
            anchors.centerIn: parent
            width: parent.width
            height: parent.height
            radius: width / 2
            color: orbCore.color
            opacity: 0.35

            SequentialAnimation on scale {
              running: root.opened && (root.sessionState === "listening" || root.sessionState === "speaking")
              loops: Animation.Infinite
              NumberAnimation { to: root.sessionState === "speaking" ? 1.45 : 1.25; duration: root.sessionState === "speaking" ? 450 : 1200; easing.type: Easing.InOutQuad }
              NumberAnimation { to: 1.0; duration: root.sessionState === "speaking" ? 450 : 1200; easing.type: Easing.InOutQuad }
            }
          }

          Rectangle {
            id: orbCore
            anchors.centerIn: parent
            width: Style.space(22)
            height: Style.space(22)
            radius: width / 2
            color: {
              if (root.sessionState === "listening") return Color.accent
              if (root.sessionState === "speaking") return Color.success
              if (root.sessionState === "tool") return Color.warning
              if (root.sessionState === "muted") return Color.urgent
              if (root.sessionState === "error") return Color.urgent
              return Color.muted
            }
          }
        }

        Column {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - orbContainer.width - pillButtons.width - Style.space(36)
          spacing: Style.space(2)

          Row {
            spacing: Style.space(8)
            Text {
              text: root.statusTitle
              color: Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.font.title
              font.weight: Font.DemiBold
            }
            Rectangle {
              height: Style.space(18)
              width: repoTagText.contentWidth + Style.space(10)
              radius: Style.space(4)
              color: Util.alpha(Color.accent, 0.15)
              anchors.verticalCenter: parent.verticalCenter
              Text {
                id: repoTagText
                anchors.centerIn: parent
                text: root.activeProject
                color: Color.accent
                font.pixelSize: Style.font.caption - 1
                font.bold: true
              }
            }
            Rectangle {
              visible: root.inAgentWorkspace
              height: Style.space(18)
              width: copilotTagText.contentWidth + Style.space(10)
              radius: Style.space(4)
              color: Util.alpha(Color.success, 0.18)
              anchors.verticalCenter: parent.verticalCenter
              Text {
                id: copilotTagText
                anchors.centerIn: parent
                text: "Co-Pilot"
                color: Color.success
                font.pixelSize: Style.font.caption - 1
                font.bold: true
              }
            }
          }

          Text {
            text: root.statusSub
            color: Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
            width: parent.width
          }
        }

        Row {
          id: pillButtons
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(6)

          Rectangle {
            width: Style.space(32)
            height: Style.space(32)
            radius: Style.space(8)
            color: root.inAgentWorkspace ? Util.alpha(Color.accent, 0.25) : (agentHover.containsMouse ? Util.alpha(Color.foreground, 0.12) : "transparent")
            Text {
              anchors.centerIn: parent
              text: "󰚩"
              color: root.inAgentWorkspace ? Color.accent : (agentHover.containsMouse ? Color.popups.text : Color.muted)
              font.pixelSize: Style.space(16)
            }
            MouseArea {
              id: agentHover
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.workspace.toggle_special(\"agent\")"])
            }
          }

          Rectangle {
            width: Style.space(32)
            height: Style.space(32)
            radius: Style.space(8)
            color: muteHover.containsMouse ? Util.alpha(Color.foreground, 0.12) : "transparent"
            Text {
              anchors.centerIn: parent
              text: root.isMuted ? "󰍭" : "󰍬"
              color: root.isMuted ? Color.urgent : Color.popups.text
              font.pixelSize: Style.space(16)
            }
            MouseArea {
              id: muteHover
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.toggleMute()
            }
          }

          Rectangle {
            width: Style.space(32)
            height: Style.space(32)
            radius: Style.space(8)
            color: expandHover.containsMouse ? Util.alpha(Color.accent, 0.20) : "transparent"
            Text {
              anchors.centerIn: parent
              text: "󰁌"
              color: expandHover.containsMouse ? Color.accent : Color.popups.text
              font.pixelSize: Style.space(16)
            }
            MouseArea {
              id: expandHover
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.viewMode = "expanded"
            }
          }

          Rectangle {
            width: Style.space(32)
            height: Style.space(32)
            radius: Style.space(8)
            color: closeHover.containsMouse ? Util.alpha(Color.urgent, 0.20) : "transparent"
            Text {
              anchors.centerIn: parent
              text: "󰅖"
              color: closeHover.containsMouse ? Color.urgent : Color.muted
              font.pixelSize: Style.space(16)
            }
            MouseArea {
              id: closeHover
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.dismiss()
            }
          }
        }
      }
    }
  }

  // ==========================================
  // VIEW 2: Full Native Drawer Modal
  // ==========================================
  PanelWindow {
    id: expandedWindow
    screen: root.activeScreen
    visible: root.opened && root.viewMode === "expanded"
    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-voice-expanded"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened && root.viewMode === "expanded" ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: Util.alpha("#000000", 0.55)
      opacity: expandedWindow.visible ? 1.0 : 0.0
      Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
      MouseArea {
        anchors.fill: parent
        onClicked: root.viewMode = "pill"
      }
    }

    BorderSurface {
      id: expandedCard
      width: Math.max(Style.space(580), Math.min(Style.space(780), parent.width * 0.55))
      height: Math.max(Style.space(560), Math.min(Style.space(780), parent.height * 0.85))
      radius: Style.cornerRadius > 0 ? Style.cornerRadius : Style.space(18)
      anchors.centerIn: parent
      color: Color.menu.background
      borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(1)))
      padding: Style.space(20)
      opacity: root.viewMode === "expanded" ? 1.0 : 0.0
      scale: root.viewMode === "expanded" ? 1.0 : 0.95
      Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
      Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }

      MouseArea {
        anchors.fill: parent
        onClicked: {}
      }

      Item {
        id: keyHandler
        anchors.fill: parent
        focus: true
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            root.viewMode = "pill"
            event.accepted = true
          }
        }

        ColumnLayout {
          anchors.fill: parent
          spacing: Style.space(14)

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(12)

            Row {
              spacing: Style.space(10)
              Layout.fillWidth: true

              Text {
                text: "󰍬 Voice Assistant"
                color: Color.accent
                font.family: Style.font.family
                font.pixelSize: Style.font.title + 2
                font.bold: true
              }

              Rectangle {
                height: Style.space(24)
                width: projectText.contentWidth + Style.space(16)
                radius: Style.space(6)
                color: Util.alpha(Color.accent, 0.20)
                anchors.verticalCenter: parent.verticalCenter
                Text {
                  id: projectText
                  anchors.centerIn: parent
                  text: "repo: " + root.activeProject
                  color: Color.accent
                  font.bold: true
                  font.pixelSize: Style.font.caption
                }
              }

              Rectangle {
                visible: root.inAgentWorkspace
                height: Style.space(24)
                width: expCopilotTag.contentWidth + Style.space(16)
                radius: Style.space(6)
                color: Util.alpha(Color.success, 0.18)
                anchors.verticalCenter: parent.verticalCenter
                Text {
                  id: expCopilotTag
                  anchors.centerIn: parent
                  text: "special:agent co-pilot"
                  color: Color.success
                  font.bold: true
                  font.pixelSize: Style.font.caption
                }
              }
            }

            Rectangle {
              width: Style.space(32)
              height: Style.space(32)
              radius: Style.space(8)
              color: root.inAgentWorkspace ? Util.alpha(Color.accent, 0.25) : (expAgentHover.containsMouse ? Util.alpha(Color.foreground, 0.12) : "transparent")
              Text {
                anchors.centerIn: parent
                text: "󰚩"
                color: root.inAgentWorkspace ? Color.accent : (expAgentHover.containsMouse ? Color.menu.text : Color.muted)
                font.pixelSize: Style.space(16)
              }
              MouseArea {
                id: expAgentHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.workspace.toggle_special(\"agent\")"])
              }
            }

            Rectangle {
              width: Style.space(32)
              height: Style.space(32)
              radius: Style.space(8)
              color: minHover.containsMouse ? Util.alpha(Color.foreground, 0.12) : "transparent"
              Text {
                anchors.centerIn: parent
                text: "󰁍"
                color: Color.menu.text
                font.pixelSize: Style.space(16)
              }
              MouseArea {
                id: minHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.viewMode = "pill"
              }
            }

            Rectangle {
              width: Style.space(32)
              height: Style.space(32)
              radius: Style.space(8)
              color: expCloseHover.containsMouse ? Util.alpha(Color.urgent, 0.20) : "transparent"
              Text {
                anchors.centerIn: parent
                text: "󰅖"
                color: expCloseHover.containsMouse ? Color.urgent : Color.muted
                font.pixelSize: Style.space(16)
              }
              MouseArea {
                id: expCloseHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.dismiss()
              }
            }
          }

          Rectangle {
            Layout.fillWidth: true
            height: Style.space(52)
            radius: Style.space(10)
            color: Util.alpha(Color.menu.selectedBackground, 0.35)

            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: Style.space(12)
              anchors.rightMargin: Style.space(12)
              spacing: Style.space(12)

              Rectangle {
                width: Style.space(14)
                height: Style.space(14)
                radius: 7
                color: orbCore.color
              }

              Column {
                Layout.fillWidth: true
                spacing: Style.space(1)
                Text {
                  text: root.statusTitle + (root.isMuted ? " (Muted)" : "")
                  color: Color.menu.text
                  font.bold: true
                  font.pixelSize: Style.font.body
                }
                Text {
                  text: root.statusSub
                  color: Color.muted
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                  width: Style.space(460)
                }
              }

              Button {
                text: root.isMuted ? "Unmute" : "Mute"
                onClicked: root.toggleMute()
              }
            }
          }

          Row {
            spacing: Style.space(8)
            Layout.fillWidth: true

            Rectangle {
              height: Style.space(28)
              width: Style.space(110)
              radius: Style.space(6)
              color: root.currentTab === "transcript" ? Color.accent : Util.alpha(Color.foreground, 0.08)
              Text {
                anchors.centerIn: parent
                text: "󰑈 Transcript"
                color: root.currentTab === "transcript" ? Color.popups.background : Color.menu.text
                font.bold: true
                font.pixelSize: Style.font.caption
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.currentTab = "transcript"
              }
            }

            Rectangle {
              height: Style.space(28)
              width: Style.space(120)
              radius: Style.space(6)
              color: root.currentTab === "parking_lot" ? Color.accent : Util.alpha(Color.foreground, 0.08)
              Text {
                anchors.centerIn: parent
                text: "󰠮 Parking Lot (" + parkingLotModel.count + ")"
                color: root.currentTab === "parking_lot" ? Color.popups.background : Color.menu.text
                font.bold: true
                font.pixelSize: Style.font.caption
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.currentTab = "parking_lot"
              }
            }

            Rectangle {
              height: Style.space(28)
              width: Style.space(110)
              radius: Style.space(6)
              color: root.currentTab === "repos" ? Color.accent : Util.alpha(Color.foreground, 0.08)
              Text {
                anchors.centerIn: parent
                text: "󰘬 Switch Repo"
                color: root.currentTab === "repos" ? Color.popups.background : Color.menu.text
                font.bold: true
                font.pixelSize: Style.font.caption
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.currentTab = "repos"
              }
            }
          }

          StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: root.currentTab === "transcript" ? 0 : (root.currentTab === "parking_lot" ? 1 : 2)

            Item {
              ListView {
                id: transcriptList
                anchors.fill: parent
                clip: true
                model: transcriptModel
                spacing: Style.space(10)
                onCountChanged: Qt.callLater(function() { transcriptList.positionViewAtEnd() })

                delegate: Rectangle {
                  width: transcriptList.width
                  height: bubbleCol.height + Style.space(24)
                  radius: Style.space(8)
                  color: {
                    if (model.role === "assistant") return Util.alpha(Color.accent, 0.12)
                    if (model.role === "tool") return Util.alpha(Color.warning, 0.15)
                    return Util.alpha(Color.foreground, 0.08)
                  }

                  Column {
                    id: bubbleCol
                    anchors.fill: parent
                    anchors.margins: Style.space(12)
                    spacing: Style.space(6)

                    Row {
                      spacing: Style.space(8)
                      Text {
                        text: model.role === "assistant" ? "Assistant" : (model.role === "tool" ? "Action Execution" : (root.githubUser || "User"))
                        font.bold: true
                        font.pixelSize: Style.font.caption
                        color: model.role === "assistant" ? Color.accent : (model.role === "tool" ? Color.warning : Color.menu.text)
                      }
                      Text {
                        text: model.time || ""
                        font.pixelSize: Style.font.caption - 2
                        color: Color.muted
                      }
                    }

                    Text {
                      text: model.text || ""
                      width: parent.width
                      wrapMode: Text.Wrap
                      color: Color.menu.text
                      font.pixelSize: Style.font.body
                      lineHeight: 1.35
                      lineHeightMode: Text.ProportionalHeight
                    }
                  }
                }

                Text {
                  anchors.centerIn: parent
                  visible: transcriptModel.count === 0
                  text: "Start speaking naturally anytime.\nDialogue and actions will stream here live."
                  horizontalAlignment: Text.AlignHCenter
                  color: Color.muted
                  font.pixelSize: Style.font.body
                  lineHeight: 1.35
                  lineHeightMode: Text.ProportionalHeight
                }
              }
            }

            Item {
              ColumnLayout {
                anchors.fill: parent
                spacing: Style.space(10)

                RowLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(8)

                  TextField {
                    id: parkInput
                    Layout.fillWidth: true
                    placeholderText: "Quickly stash an idea or tangent..."
                    onAccepted: {
                      root.parkIdea(text)
                      text = ""
                    }
                  }

                  Button {
                    text: "Park Idea"
                    onClicked: {
                      root.parkIdea(parkInput.text)
                      parkInput.text = ""
                    }
                  }
                }

                ListView {
                  id: parkingList
                  Layout.fillWidth: true
                  Layout.fillHeight: true
                  clip: true
                  model: parkingLotModel
                  spacing: Style.space(8)

                  delegate: Rectangle {
                    width: parkingList.width
                    height: Math.max(Style.space(60), thoughtCol.height + Style.space(18))
                    radius: Style.space(8)
                    color: Util.alpha(Color.foreground, 0.08)

                    RowLayout {
                      anchors.fill: parent
                      anchors.margins: Style.space(10)
                      spacing: Style.space(8)

                      Column {
                        id: thoughtCol
                        Layout.fillWidth: true
                        spacing: Style.space(3)
                        Text {
                          text: model.thought || ""
                          font.bold: true
                          font.pixelSize: Style.font.body
                          color: Color.menu.text
                          lineHeight: 1.25
                          lineHeightMode: Text.ProportionalHeight
                          elide: Text.ElideRight
                          width: Style.space(380)
                        }
                        Text {
                          text: "Target repo: " + (model.repo || root.activeProject)
                          font.pixelSize: Style.font.caption
                          color: Color.muted
                        }
                      }

                      Button {
                        text: "󰁝 Push Issue"
                        onClicked: root.pushParkedToGithub(model)
                      }
                    }
                  }

                  Text {
                    anchors.centerIn: parent
                    visible: parkingLotModel.count === 0
                    text: "No parked thoughts yet.\nTangents during dialogue are safely captured here."
                    horizontalAlignment: Text.AlignHCenter
                    color: Color.muted
                    font.pixelSize: Style.font.body
                    lineHeight: 1.35
                    lineHeightMode: Text.ProportionalHeight
                  }
                }
              }
            }

            Item {
              ListView {
                id: repoList
                anchors.fill: parent
                clip: true
                model: reposModel
                spacing: Style.space(8)

                delegate: Rectangle {
                  width: repoList.width
                  height: Math.max(Style.space(60), repoCol.height + Style.space(20))
                  radius: Style.space(8)
                  color: model.name === root.activeProject ? Util.alpha(Color.accent, 0.22) : Util.alpha(Color.foreground, 0.08)

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true
                    onClicked: root.switchProject(model.name)
                  }

                  RowLayout {
                    anchors.fill: parent
                    anchors.margins: Style.space(10)
                    spacing: Style.space(12)

                    Text {
                      text: model.name === root.activeProject ? "󰄲" : "󰄱"
                      color: model.name === root.activeProject ? Color.accent : Color.muted
                      font.pixelSize: Style.space(18)
                    }

                    Column {
                      id: repoCol
                      Layout.fillWidth: true
                      spacing: Style.space(3)
                      Text {
                        text: model.name
                        font.bold: true
                        font.pixelSize: Style.font.body
                        color: model.name === root.activeProject ? Color.accent : Color.menu.text
                      }
                      Text {
                        text: model.desc || ""
                        font.pixelSize: Style.font.caption
                        color: Color.muted
                        lineHeight: 1.25
                        lineHeightMode: Text.ProportionalHeight
                        elide: Text.ElideRight
                        width: Style.space(450)
                      }
                    }
                  }
                }
              }
            }
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(8)

            Button {
              text: "Clear Dialogue"
              onClicked: transcriptModel.clear()
            }

            Item { Layout.fillWidth: true }

            Text {
              text: "Press Esc to minimize"
              color: Color.muted
              font.pixelSize: Style.font.caption
            }

            Button {
              text: "Minimize to Pill"
              onClicked: root.viewMode = "pill"
            }
          }
        }
      }
    }
  }
}
