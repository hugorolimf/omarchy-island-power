import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Commons
import qs.Commons as Commons
import "../io.github.hugorolimf.kit/ui"
import "Model.js" as Model
import "Strings.js" as Strings

Panel {
  id: root
  moduleName: "io.github.hugorolimf.power"
  ipcTarget: "omarchy.power"
  // manageIpc: false so this panel can own the single IpcHandler the target
  // permits — needed for the togglePercentage method below.
  manageIpc: false
  property var batteryInfo: ({})
  property var systemInfo: ({})
  property var profiles: []
  property string activeProfile: ""
  property int profileIndex: 0
  property bool cursorActive: false
  readonly property bool showPercentage: setting("showPercentage", false) === true
  // With the percentage shown the button paints a text block wider than an
  // icon, so the open-panel mark takes the painted width instead of the
  // icon-sized fraction of the slot the fallback assumes.
  readonly property real openPanelIndicatorWidth: showPercentage && !button.vertical ? button.glyphPaintedWidth : 0
  readonly property bool batteryPresent: {
    var device = UPower.displayDevice
    return !!(device && device.isPresent)
  }

  function upowerStates() {
    return {
      Charging: UPowerDeviceState.Charging,
      Discharging: UPowerDeviceState.Discharging,
      FullyCharged: UPowerDeviceState.FullyCharged,
      PendingCharge: UPowerDeviceState.PendingCharge
    }
  }

  function selectProfileByDelta(delta) {
    profileIndex = Model.selectProfileIndex(profileIndex, delta, profiles)
  }

  function activateSelectedProfile() {
    if (profileIndex < 0 || profileIndex >= profiles.length) return
    setProfile(profiles[profileIndex])
  }

  function batteryIcon() {
    var device = UPower.displayDevice
    return Model.batteryIcon(device, root.discharging, upowerStates())
  }

  function modeLabel() {
    var device = UPower.displayDevice
    return Model.modeLabel(device, root.discharging, upowerStates())
  }

  function profileIcon(name) {
    return Model.profileIcon(name)
  }

  // Bundled wrappers that add the firmware's max-power (Extreme) profile.
  function scriptPath(name) {
    return decodeURIComponent(Qt.resolvedUrl("scripts/" + name).toString().replace(/^file:\/\//, ""))
  }

  readonly property bool fullyCharged: {
    var device = UPower.displayDevice
    return device && device.isPresent && device.state === UPowerDeviceState.FullyCharged && !root.chargeThresholdActive
  }
  readonly property bool discharging: {
    var device = UPower.displayDevice
    return !!(device && device.isPresent && UPower.onBattery)
  }
  readonly property bool chargeThresholdActive: {
    var device = UPower.displayDevice
    return Model.chargeThresholdActive(device, root.discharging, upowerStates())
  }
  readonly property bool batteryFull: fullyCharged || (!root.discharging && batteryFraction >= 1)
  readonly property bool batteryFlowIdle: batteryFull || chargeThresholdActive

  // 0..1 charge level, used by the visual progress bar.
  readonly property real batteryFraction: {
    var d = UPower.displayDevice
    return Model.batteryFraction(d)
  }

  readonly property bool charging: {
    var d = UPower.displayDevice
    return d && d.isPresent && !UPower.onBattery && !root.batteryFlowIdle
  }

  // anatomy: colour only for state. Green while charging, amber under 20%
  // and red under 10% on battery, plain stroke tone otherwise.
  readonly property string batteryTone: {
    if (root.charging) return "green"
    if (root.discharging && root.batteryFraction < 0.1) return "red"
    if (root.discharging && root.batteryFraction < 0.2) return "amber"
    return ""
  }
  readonly property color batteryFillColor: batteryTone === "" ? Anatomy.hi : Anatomy.tone(batteryTone)
  readonly property color batteryStateColor: batteryTone === "" ? Anatomy.muted : Anatomy.tone(batteryTone)

  // Cute agent-flavored phrases shown in the hero status line, rotated on a
  // timer so the panel feels alive when current is flowing (either direction).
  // Stay awake (was a bar indicator), through the idle service's IPC since
  // widgets get no first-party services; read again on every open.
  property bool stayAwake: false
  function setStayAwake(on) {
    stayAwake = on
    Quickshell.execDetached(["omarchy-shell", "idle", on ? "disable" : "enable"])
  }
  Process {
    id: idleProc
    command: ["omarchy-shell", "idle", "status"]
    stdout: StdioCollector {
      onStreamFinished: { try { root.stayAwake = JSON.parse(text).stayAwake === true } catch (e) {} }
    }
  }
  readonly property var chargingPhrases: [
    Strings.T("Bombeando energia"),
    Strings.T("Injetando elétrons"),
    Strings.T("Enchendo o tanque"),
    Strings.T("Juntando watts"),
    Strings.T("Guardando joules"),
    Strings.T("Puxando volts"),
    Strings.T("Completando a reserva"),
    Strings.T("Absorvendo ampères"),
    Strings.T("Inalando quilowatts")
  ]
  readonly property var onBatteryPhrases: [
    Strings.T("Bebericando energia"),
    Strings.T("Gastando joules"),
    Strings.T("Drenando watts"),
    Strings.T("Queimando elétrons"),
    Strings.T("Saboreando a carga"),
    Strings.T("Gastando coulombs"),
    Strings.T("Sangrando ampères"),
    Strings.T("Devorando volts"),
    Strings.T("Beliscando a reserva")
  ]
  property int phraseIndex: 0

  // Whichever list is "active" given the current power state.
  readonly property var activePhrases: {
    if (fullyCharged) return []
    if (charging) return chargingPhrases
    if (discharging) return onBatteryPhrases
    return []
  }
  readonly property bool rotatingPhrases: activePhrases.length > 0

  readonly property string heroStatusText: {
    if (fullyCharged) return Strings.T("Carga completa")
    if (rotatingPhrases) return activePhrases[phraseIndex % activePhrases.length]
    return modeLabel()
  }

  function refresh() {
    if (!batteryPresent) return

    if (!batteryProc.running) batteryProc.running = true
    if (!profilesProc.running) profilesProc.running = true
    if (!systemProc.running) systemProc.running = true
  }

  function updateKeyValue(raw, targetName) {
    var next = Model.parseKeyValue(raw)
    // Keep last known good data if a refresh briefly returns nothing — happens
    // around AC plug/unplug events. Avoids the section collapsing mid-transition.
    if (Object.keys(next).length === 0) return
    if (targetName === "battery") batteryInfo = next
    else systemInfo = next
  }

  function updateProfiles(raw) {
    var parsed = Model.parseProfiles(raw, profileIndex)
    // Same guard as battery: preserve the last known profile list across
    // transient empty payloads so the buttons don't blink out.
    if (parsed.profiles.length === 0) return
    profiles = parsed.profiles
    activeProfile = parsed.activeProfile
    profileIndex = parsed.profileIndex
    if (opened && !cursorActive) {
      var idx = profiles.indexOf(activeProfile)
      if (idx >= 0) profileIndex = idx
    }
  }

  function setProfile(profile) {
    if (!profile || actionProc.running) return
    actionProc.command = [root.scriptPath("profiles-set"), root.discharging ? "battery" : "ac", profile]
    actionProc.running = true
  }

  function togglePercentage() {
    root.settings = Object.assign({}, root.settings, { showPercentage: !root.showPercentage })
    if (root.bar && root.bar.shell) root.bar.shell.updateEntryInline(root.moduleName, root.settings)
  }

  IpcHandler {
    target: "omarchy.power"

    function open() { root.open() }
    function close() { root.close() }
    function show() { root.open() }
    function hide() { root.close() }
    function toggle() { root.toggle() }
    function togglePercentage() { root.togglePercentage() }
  }

  onOpenedChanged: {
    if (opened) {
      idleProc.running = true
      if (!batteryPresent) {
        close()
        return
      }

      refresh()
      var idx = profiles.indexOf(activeProfile)
      profileIndex = idx >= 0 ? idx : 0
      cursorActive = false
    }
  }

  onBatteryPresentChanged: if (!batteryPresent) close()

  visible: batteryPresent
  implicitWidth: batteryPresent ? button.implicitWidth : 0
  implicitHeight: batteryPresent ? button.implicitHeight : 0

  Process {
    id: batteryProc
    command: ["omarchy-battery-status", "--shell"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateKeyValue(text, "battery") }
  }

  Process {
    id: profilesProc
    command: [root.scriptPath("profiles-list"), "--active-state"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateProfiles(text) }
  }

  Process {
    id: systemProc
    command: ["omarchy-system-stats"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateKeyValue(text, "system") }
  }

  Process {
    id: actionProc
    onExited: root.refresh()
  }

  Timer { interval: 5000; running: root.opened; repeat: true; onTriggered: root.refresh() }

  // Rotate the status phrase while the panel is open and we're in a
  // rotating state (charging or on battery). The text swap is wrapped in a
  // fade so the changeover reads as one organism rather than a hard cut.
  Timer {
    id: phraseTimer
    interval: 2800
    running: root.opened && root.rotatingPhrases
    repeat: true
    triggeredOnStart: false
    onTriggered: phraseSwap.restart()
  }

  SequentialAnimation {
    id: phraseSwap
    PropertyAnimation {
      target: heroStatus; property: "opacity"
      to: 0.0; duration: 180; easing.type: Easing.OutQuad
    }
    ScriptAction {
      script: {
        var n = root.activePhrases.length
        if (n > 0) root.phraseIndex = (root.phraseIndex + 1) % n
      }
    }
    PropertyAnimation {
      target: heroStatus; property: "opacity"
      to: 1.0; duration: 260; easing.type: Easing.InQuad
    }
  }

  // If we leave a rotating state mid-swap, halt the animation and snap back
  // to full opacity so "FULLY CHARGED" is legible immediately rather than
  // appearing dimmed.
  Connections {
    target: root
    function onRotatingPhrasesChanged() {
      if (!root.rotatingPhrases) {
        phraseSwap.stop()
        heroStatus.opacity = 1.0
      }
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.showPercentage && !vertical
      ? Math.round(root.batteryFraction * 100) + "% " + root.batteryIcon()
      : root.batteryIcon()
    slotSize: Style.bar.iconSlot * (root.showPercentage && !vertical ? 2 : 1)
    tooltipText: ""
    onPressed: function(b) {
      if (!root.batteryPresent) return
      if (b === Qt.RightButton) root.togglePercentage()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened && root.batteryPresent
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dx !== 0) root.selectProfileByDelta(dx)
        else if (dy !== 0) root.selectProfileByDelta(dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateSelectedProfile()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        // ---------- Hero: battery icon · title/status · percentage ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, heroPercent.implicitHeight)

          // Stroke battery with the charge drawn inside it, bolt while charging.
          AnatomyIcon {
            id: heroIcon
            path: Anatomy.icons.battery
            size: Style.font.display
            strokeWidth: 1.3
            color: Anatomy.hi
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter

            readonly property real unit: size / 24

            Rectangle {
              x: 5 * heroIcon.unit
              y: 9.5 * heroIcon.unit
              height: 5 * heroIcon.unit
              width: Math.max(heroIcon.unit, 12 * heroIcon.unit * root.batteryFraction)
              radius: heroIcon.unit
              color: root.batteryFillColor
              opacity: root.charging ? 0.35 : 0.85

              Behavior on width { NumberAnimation { duration: Anatomy.base; easing.type: Easing.Bezier; easing.bezierCurve: Anatomy.ease } }
              Behavior on color { ColorAnimation { duration: Anatomy.fast } }
            }

            AnatomyIcon {
              visible: root.charging
              anchors.fill: parent
              path: Anatomy.icons.bolt
              size: heroIcon.size
              strokeWidth: 1.5
              color: Anatomy.strong
            }
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: heroPercent.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              text: Strings.T("Bateria")
              color: Anatomy.strong
              font.family: Anatomy.sans
              font.pixelSize: Style.font.title
              font.weight: Font.DemiBold
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              id: heroStatus
              textFormat: Text.PlainText
              text: root.heroStatusText.toUpperCase()
              color: root.batteryStateColor
              font.family: Anatomy.mono
              font.pixelSize: Style.font.caption
              font.weight: Font.DemiBold
              font.letterSpacing: Anatomy.labelSpacing
              elide: Text.ElideRight
              width: parent.width

              Behavior on color { ColorAnimation { duration: Anatomy.fast } }
            }
          }

          Text {
            id: heroPercent
            textFormat: Text.PlainText
            text: root.batteryInfo.percentage || "—"
            color: Anatomy.strong
            font.family: Anatomy.sans
            font.pixelSize: Style.font.displayLarge
            font.weight: Font.Light
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        // ---------- Battery meter ----------
        Item {
          width: parent.width
          implicitHeight: Anatomy.trackHeight

          Rectangle {
            id: barTrack
            anchors.fill: parent
            radius: height / 2
            color: Anatomy.faint
          }

          Rectangle {
            id: barFill
            anchors.left: barTrack.left
            anchors.verticalCenter: barTrack.verticalCenter
            height: barTrack.height
            radius: barTrack.radius
            color: root.batteryFillColor
            width: Math.max(barTrack.height, barTrack.width * root.batteryFraction)

            Behavior on width { NumberAnimation { duration: Anatomy.base; easing.type: Easing.Bezier; easing.bezierCurve: Anatomy.ease } }
            Behavior on color { ColorAnimation { duration: Anatomy.fast } }

            // Subtle pulse while charging — visible signal that energy is flowing in.
            SequentialAnimation on opacity {
              running: root.charging && !root.fullyCharged && root.opened
              loops: Animation.Infinite
              alwaysRunToEnd: true
              NumberAnimation { from: 1.0; to: 0.55; duration: 950; easing.type: Easing.InOutSine }
              NumberAnimation { from: 0.55; to: 1.0; duration: 950; easing.type: Easing.InOutSine }
            }
          }
        }

        // ---------- Stats ----------
        // Visibility is intentionally only gated by "we've ever loaded data" so
        // the section never collapses mid-transition. fullyCharged is *not* part
        // of the condition: UPower briefly reports FullyCharged on plug-in when
        // the battery sits above the charge-control start threshold, and we
        // refuse to flicker the whole panel for that ~1s window.
        Row {
          visible: root.batteryInfo.percentage !== undefined
          width: parent.width
          spacing: Style.space(20)

          Column {
            width: (parent.width - parent.spacing) / 2
            spacing: Style.spacing.labelGap
            InfoPair { label: Strings.T("Capacidade"); value: root.batteryInfo.size || "" }
            InfoPair { label: Strings.T("Ciclos de carga"); value: root.batteryInfo.cycles || "—" }
          }

          Column {
            width: (parent.width - parent.spacing) / 2
            spacing: Style.spacing.labelGap
            InfoPair {
              label: root.chargeThresholdActive ? Strings.T("Limite de carga") : (root.discharging ? Strings.T("Tempo restante") : Strings.T("Até encher"))
              value: root.chargeThresholdActive ? (root.batteryInfo.threshold || "-") : (root.batteryFlowIdle ? "-" : (root.batteryInfo.time || "—"))
            }
            InfoPair {
              label: root.chargeThresholdActive ? Strings.T("Estado") : (root.discharging ? Strings.T("Consumo") : Strings.T("Carga"))
              value: root.chargeThresholdActive ? Strings.T("Mantendo") : (root.batteryFull ? "-" : (root.batteryInfo.rate || ""))
            }
          }
        }

        // ---------- Power profile picker ----------
        PanelSeparator {
        }

        Column {
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: Strings.T("MODO DE ENERGIA")
          }

          // anatomy segmented control (.seg): one faint rail, equal chips,
          // the active profile lifted as a card.
          Rectangle {
            width: parent.width
            implicitHeight: profileRow.implicitHeight + 4
            radius: Anatomy.rowRadius
            color: Anatomy.faint

            Row {
              id: profileRow
              x: 2
              y: 2
              width: parent.width - 4
              spacing: 2

              readonly property real cellWidth: root.profiles.length > 0
                ? (width - spacing * (root.profiles.length - 1)) / root.profiles.length
                : 0

              Repeater {
                model: root.profiles

                BorderSurface {
                  id: chip
                  required property var modelData
                  required property int index

                  readonly property string profile: String(modelData)
                  readonly property bool isActive: root.activeProfile === profile
                  readonly property bool hasCursor: root.cursorActive && root.profileIndex === index

                  width: profileRow.cellWidth
                  implicitHeight: chipLabel.implicitHeight + Style.space(12)
                  radius: Anatomy.chipRadius
                  color: isActive ? Anatomy.card : (hasCursor ? Anatomy.hover : "transparent")
                  borderSpec: Border.none()
                  border.width: hasCursor && isActive ? Anatomy.hairline : 0
                  border.color: Anatomy.selectedRim

                  Behavior on color { ColorAnimation { duration: Anatomy.fast; easing.type: Easing.Bezier; easing.bezierCurve: Anatomy.ease } }

                  AnatomyLift { visible: chip.isActive; radius: chip.radius; depth: 3 }
                  AnatomyLift { visible: chip.isActive; radius: chip.radius; inner: true }

                  Text {
                    id: chipLabel
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    width: parent.width - Style.space(6)
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: Model.profileLabel(chip.profile)
                    color: chip.isActive || chip.hasCursor ? Anatomy.strong : Anatomy.muted
                    font.family: Anatomy.mono
                    font.pixelSize: Math.max(9, Style.font.caption)
                    font.weight: Font.Medium
                    font.letterSpacing: 0.5
                    font.capitalization: Font.AllUppercase

                    Behavior on color { ColorAnimation { duration: Anatomy.fast } }
                  }

                  MouseArea {
                    id: chipMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.setProfile(chip.profile)
                    onContainsMouseChanged: if (containsMouse) {
                      root.cursorActive = true
                      root.profileIndex = chip.index
                    }
                  }

                  PanelToolTip {
                    visible: chipMouse.containsMouse && text !== ""
                    text: Model.profileHint(chip.profile)
                  }
                }
              }
            }
          }
        }

        // ---------- Stay awake (was a bar indicator) ----------
        PanelSeparator {
        }

        Toggle {
          width: parent.width
          label: Strings.T("Manter acordado")
          description: Strings.T("Sem bloqueio nem proteção de tela")
          checked: root.stayAwake
          onClicked: root.setStayAwake(!checked)
        }
      }
    }
  }

  component InfoPair: Row {
    property string label: ""
    property string value: ""

    width: parent.width
    spacing: Style.space(8)

    InfoLabel { text: label }
    Item { width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth - parent.spacing * 2); height: 1 }
    InfoValue { text: value }
  }

  component InfoLabel: Text {
    textFormat: Text.PlainText
    color: Anatomy.muted
    font.family: Anatomy.sans
    font.pixelSize: Style.font.bodySmall
  }

  component InfoValue: Text {
    textFormat: Text.PlainText
    color: Anatomy.strong
    font.family: Anatomy.mono
    font.pixelSize: Style.font.bodySmall
    font.weight: Font.Medium
  }
}
