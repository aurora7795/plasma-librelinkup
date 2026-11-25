import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

// Used both as the popup (panel) and as the desktop widget itself. It decides
// what to show from the space it is given:
//   tiny    value + trend arrow, scaled to fill
//   small   + unit toggle and age
//   medium  + 12-hour graph
//   large   + range/average and buttons
//   xlarge  + disclaimer
ColumnLayout {
    id: full

    required property var backend
    readonly property var report: backend.report

    readonly property real gu: Kirigami.Units.gridUnit
    readonly property bool showDetails: height >= gu * 5.5 && width >= gu * 7
    readonly property bool showGraph: report !== null && height >= gu * 11 && width >= gu * 12
    readonly property bool showStats: report !== null && height >= gu * 14 && width >= gu * 14
    readonly property bool showButtons: (height >= gu * 16 && width >= gu * 16)
        || (report === null && height >= gu * 8 && width >= gu * 10)
    readonly property bool showNote: height >= gu * 19 && width >= gu * 16

    Layout.minimumWidth: gu * 4
    Layout.minimumHeight: gu * 3
    Layout.preferredWidth: gu * 22
    Layout.preferredHeight: gu * 20
    spacing: Kirigami.Units.smallSpacing

    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_R) backend.refresh()
    }

    // Value and trend arrow, scaled to the space available.
    Item {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredHeight: full.gu * 4.5
        Layout.maximumHeight: full.showGraph ? full.gu * 6 : Number.POSITIVE_INFINITY

        PlasmaComponents.Label {
            anchors.fill: parent
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            font.pixelSize: 400
            minimumPixelSize: 8
            fontSizeMode: Text.Fit
            font.bold: true
            textFormat: Text.PlainText
            opacity: backend.stale ? 0.6 : 1
            color: backend.urgentReading ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
            text: full.report ? backend.fmt(full.report.mgdl) + " " + backend.arrow(full.report.trend)
                              : (backend.error ? "⚠" : "…")
        }
    }

    // Unit toggle and age, or the error / sign-in prompt
    PlasmaComponents.Label {
        Layout.fillWidth: true
        visible: full.showDetails
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        elide: Text.ElideRight
        maximumLineCount: 3
        textFormat: Text.PlainText
        color: backend.error ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
        opacity: backend.error ? 1 : 0.75
        font: Kirigami.Theme.smallFont
        text: {
            if (backend.error) return backend.error
            if (!full.report) return i18n("loading…")
            var m = backend.ageMinutes()
            return (backend.mmol ? "mmol/L" : "mg/dL") + " ⇄   ·   "
                + (m <= 0 ? i18n("just now") : i18n("%1 min ago", m)) + (backend.stale ? i18n(" (stale)") : "")
        }
        MouseArea {
            anchors.fill: parent
            enabled: full.report !== null && !backend.error
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: backend.toggleUnit()
        }
    }

    Graph {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredHeight: full.gu * 8
        Layout.minimumHeight: full.gu * 4
        visible: full.showGraph
        report: full.report
        mmol: backend.mmol
    }

    PlasmaComponents.Label {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        visible: full.showStats && full.report.history.length > 1
        opacity: 0.75
        font: Kirigami.Theme.smallFont
        text: {
            if (!full.report) return ""
            var v = full.report.history.map(function(p) { return p.mgdl })
            var sum = 0
            for (var i = 0; i < v.length; i++) sum += v[i]
            return i18n("Range %1–%2   Avg %3   (last 12 h)",
                backend.fmt(Math.min.apply(null, v)), backend.fmt(Math.max.apply(null, v)),
                backend.fmt(sum / v.length))
        }
    }

    RowLayout {
        Layout.alignment: Qt.AlignHCenter
        visible: full.showButtons
        spacing: Kirigami.Units.smallSpacing

        PlasmaComponents.Button {
            icon.name: "user-identity"
            text: backend.needsSetup || !full.report ? i18n("Sign in…") : i18n("Account…")
            enabled: !backend.busy
            onClicked: backend.signIn()
        }
        PlasmaComponents.Button {
            icon.name: "view-refresh"
            text: i18n("Refresh")
            enabled: !backend.busy
            onClicked: backend.refresh()
        }
        PlasmaComponents.Button {
            icon.name: "configure"
            text: i18n("Settings…")
            onClicked: Plasmoid.internalAction("configure").trigger()
        }
    }

    PlasmaComponents.Label {
        Layout.fillWidth: true
        visible: full.showNote
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        opacity: 0.6
        font: Kirigami.Theme.smallFont
        text: i18n("Not a medical device. Do not use for treatment or dosing decisions. Not affiliated with or endorsed by Abbott. Uses the unofficial LibreView API.")
    }
}
