import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as P5Support

PlasmoidItem {
    id: root

    // ---- data -------------------------------------------------------------
    property var report: null          // last good helper result
    property string error: ""
    property bool needsSetup: false
    property bool busy: false
    property int tick: 0               // bumps every 30 s so ages re-evaluate
    property var alertState: ({})      // kind -> time of last notification
    property int seq: 0

    readonly property var cfg: Plasmoid.configuration

    // Desktop: let the user switch the widget background off (edit mode,
    // "Show Background"). With it off, text and graph get an outline so they
    // stay readable on any wallpaper.
    Plasmoid.backgroundHints: PlasmaCore.Types.StandardBackground | PlasmaCore.Types.ConfigurableBackground
    readonly property bool onPanel: Plasmoid.formFactor === PlasmaCore.Types.Horizontal
                                    || Plasmoid.formFactor === PlasmaCore.Types.Vertical
    readonly property bool noBackground: !onPanel
        && (Plasmoid.effectiveBackgroundHints
            & (PlasmaCore.Types.StandardBackground | PlasmaCore.Types.TranslucentBackground)) === 0
    readonly property bool mmol: String(cfg.unit).toLowerCase() === "mmol"
    readonly property var arrows: ["", "↓", "↘", "→", "↗", "↑"]
    readonly property int signalLostMinutes: 30
    readonly property string helperPath:
        decodeURIComponent(String(Qt.resolvedUrl("../code/llu.py")).replace(/^file:\/\//, ""))

    function fmt(mgdl) {
        if (mgdl === null || mgdl === undefined) return "—"
        return mmol ? (mgdl / 18.0182).toFixed(1) : String(Math.round(mgdl))
    }
    function arrow(t) { return arrows[Math.max(1, Math.min(5, Number(t) || 3))] }
    function ageMinutes() {
        tick  // re-evaluate bindings as time passes
        if (!report || !report.t) return -1
        return Math.max(0, Math.round((Date.now() / 1000 - report.t) / 60))
    }
    readonly property bool stale: report !== null && ageMinutes() > 15
    readonly property bool urgentReading: report !== null && (report.isHigh || report.isLow
        || report.mgdl <= cfg.lowAt || report.mgdl >= cfg.highAt)

    readonly property string label: {
        if (report) return fmt(report.mgdl) + " " + arrow(report.trend) + (stale ? " ?" : "")
        return error ? "⚠ glucose" : "…"
    }

    toolTipMainText: report ? fmt(report.mgdl) + " " + (mmol ? "mmol/L" : "mg/dL") + " " + arrow(report.trend)
                            : i18n("LibreLinkUp")
    toolTipSubText: report ? (ageMinutes() <= 0 ? i18n("just now") : i18n("%1 min ago", ageMinutes()))
                           : error

    function toggleUnit() { Plasmoid.configuration.unit = mmol ? "mgdl" : "mmol" }

    // ---- running the helper and notify-send ---------------------------------
    function q(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }

    P5Support.DataSource {
        id: runner
        engine: "executable"
        connectedSources: []
        onNewData: function(source, data) {
            disconnectSource(source)
            if (source.indexOf("notify-send") === 0) return
            root.handle(String(data["stdout"] || "").trim())
        }
    }

    function runHelper(extra) {
        if (busy) return
        busy = true
        // The trailing comment makes each source string unique so it can rerun.
        runner.connectSource("python3 -I " + q(helperPath) + (extra ? " " + extra : "") + " # " + (seq++))
    }
    function refresh() { runHelper("") }
    // Credentials are collected by the helper itself (kdialog), never passed
    // through the command line or environment.
    function signIn() { error = ""; runHelper("--signin") }

    function handle(text) {
        busy = false
        try {
            var r = JSON.parse(text)
            if (r.ok) {
                report = r; error = ""; needsSetup = false
            } else if (!r.cancelled) {
                error = String(r.error || "unknown error")
                needsSetup = r.setup === true
            }
        } catch (e) {
            error = "no response from helper"
        }
        checkAlert()
    }

    Timer {
        interval: Math.max(60, root.cfg.intervalSec) * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    // Keeps ages current and lets "signal lost" fire even when fetches fail.
    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: { root.tick++; root.checkAlert() }
    }

    onExpandedChanged: function() { if (root.expanded) root.refresh() }

    // ---- notifications ------------------------------------------------------
    // Thresholds are stored in mg/dL whatever unit is displayed.
    // Fire `kind` when `active` turns on, and again every `repeat` minutes while
    // it stays on (0 = once per episode). Turning off resets it.
    function evaluate(kind, active, headline, body, urgency, icon) {
        var st = Object.assign({}, alertState)
        if (!active) {
            if (kind in st) { delete st[kind]; alertState = st }
            return
        }
        var now = Date.now()
        var last = st[kind]
        var every = cfg.repeatMin * 60000
        if (last !== undefined && (every <= 0 || now - last < every)) return
        st[kind] = now
        alertState = st
        sendAlert(headline, body, urgency, icon)
    }

    function sendAlert(headline, body, urgency, icon) {
        runner.connectSource("notify-send -a LibreLinkUp -u " + urgency + " -i " + (icon || "dialog-warning") + " "
            + q(headline) + " " + q(body) + " # " + (seq++))
    }

    // Breeze has no diagonal arrows, so the diagonals use plain up/down.
    function alertIcon(trend) {
        return ["", "arrow-down-double", "arrow-down", "arrow-right", "arrow-up", "arrow-up-double"][Math.max(1, Math.min(5, Number(trend) || 3))]
    }

    function checkAlert() {
        if (!report) return
        if (!cfg.alertsEnabled) { if (Object.keys(alertState).length) alertState = ({}); return }
        var age = ageMinutes()
        // No fresh data: only the signal-lost alert can apply.
        evaluate("signal", cfg.signalOn && age >= signalLostMinutes,
            "No glucose data", "Last reading " + age + " min ago", "normal")
        if (stale) {
            evaluate("low", false); evaluate("high", false)
            evaluate("fastDown", false); evaluate("fastUp", false)
            return
        }
        var v = report.mgdl
        var body = fmt(v) + " " + (mmol ? "mmol/L" : "mg/dL") + " " + arrow(report.trend)
        var a = arrow(report.trend)
        var ic = alertIcon(report.trend)
        evaluate("low", cfg.lowOn && v <= cfg.lowAt, "Low glucose " + a, body, "critical", ic)
        evaluate("high", cfg.highOn && v >= cfg.highAt, "High glucose " + a, body, "normal", ic)
        evaluate("fastDown", cfg.fastOn && report.trend === 1, "Falling fast ↓↓", body, "normal", "arrow-down-double")
        evaluate("fastUp", cfg.fastOn && report.trend === 5, "Rising fast ↑↑", body, "normal", "arrow-up-double")
    }

    // Right-click menu: works at every size, including the tiny desktop view.
    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18n("Refresh now")
            icon.name: "view-refresh"
            enabled: !root.busy
            onTriggered: root.refresh()
        },
        PlasmaCore.Action {
            text: root.mmol ? i18n("Show mg/dL") : i18n("Show mmol/L")
            icon.name: "exchange-positions"
            onTriggered: root.toggleUnit()
        },
        PlasmaCore.Action {
            text: root.report ? i18n("Account…") : i18n("Sign in…")
            icon.name: "user-identity"
            enabled: !root.busy
            onTriggered: root.signIn()
        }
    ]

    // ---- representations ------------------------------------------------------
    // In a panel: a compact label that opens a popup. On the desktop: the full
    // view itself, which adapts to however big the widget is made.
    preferredRepresentation: onPanel ? compactRepresentation : fullRepresentation
    compactRepresentation: CompactRepresentation { backend: root }
    fullRepresentation: FullRepresentation { backend: root }
}
