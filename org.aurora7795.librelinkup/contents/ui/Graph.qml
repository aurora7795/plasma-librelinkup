import QtQuick
import org.kde.kirigami as Kirigami

// 12-hour glucose graph with the target range shaded. Values are always
// mg/dL internally; only the axis labels follow the chosen unit.
Canvas {
    id: graph

    property var report: null
    property bool mmol: false
    property bool outline: false          // no widget background: add contrast
    property color outlineColor: "black"
    readonly property color fg: Kirigami.Theme.textColor

    implicitHeight: Kirigami.Units.gridUnit * 9

    onReportChanged: requestPaint()
    onMmolChanged: requestPaint()
    onFgChanged: requestPaint()
    onOutlineChanged: requestPaint()
    onOutlineColorChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        var r = report
        if (!r || !r.history || r.history.length < 2) return
        var pts = r.history
        var now = Date.now() / 1000
        var t0 = now - 12 * 3600
        var peak = 0, trough = 1000
        for (var j = 0; j < pts.length; j++) {
            if (pts[j].t < t0) continue
            peak = Math.max(peak, pts[j].mgdl)
            trough = Math.min(trough, pts[j].mgdl)
        }
        // Scale to the data so highs and lows are never clipped.
        var lo = Math.min(40, r.targetLow - 10, trough - 10)
        var hi = Math.max(300, r.targetHigh + 40, peak + 10)
        var padL = Kirigami.Units.gridUnit * 2.2
        function X(t) { return padL + Math.max(0, Math.min(1, (t - t0) / (now - t0))) * (width - padL) }
        function Y(v) { return height - (Math.max(lo, Math.min(hi, v)) - lo) / (hi - lo) * height }
        var c = fg
        ctx.fillStyle = Qt.rgba(c.r, c.g, c.b, outline ? 0.18 : 0.10)
        ctx.fillRect(padL, Y(r.targetHigh), width - padL, Y(r.targetLow) - Y(r.targetHigh))
        var ticks = mmol ? [4, 7, 10, 14, 20, 25] : [70, 120, 180, 250, 350, 450]
        ctx.font = Math.round(Kirigami.Theme.smallFont.pointSize * 4 / 3) + "px " + Kirigami.Theme.smallFont.family
        ctx.textBaseline = "middle"
        ctx.lineWidth = 1
        for (var k = 0; k < ticks.length; k++) {
            var mg = mmol ? ticks[k] * 18.0182 : ticks[k]
            if (mg < lo || mg > hi) continue
            var y = Math.round(Y(mg)) + 0.5
            ctx.strokeStyle = Qt.rgba(c.r, c.g, c.b, 0.18)
            ctx.beginPath(); ctx.moveTo(padL, y); ctx.lineTo(width, y); ctx.stroke()
            if (outline) {
                ctx.lineWidth = 3
                ctx.strokeStyle = outlineColor
                ctx.strokeText(String(ticks[k]), 0, y)
                ctx.lineWidth = 1
            }
            ctx.fillStyle = Qt.rgba(c.r, c.g, c.b, 0.8)
            ctx.fillText(String(ticks[k]), 0, y)
        }
        // Draw the line twice with no background: a wider halo, then the line.
        var passes = outline ? [[5, outlineColor], [2, c]] : [[2, c]]
        for (var n = 0; n < passes.length; n++) {
            ctx.strokeStyle = passes[n][1]
            ctx.lineWidth = passes[n][0]
            ctx.lineJoin = "round"
            ctx.beginPath()
            var started = false
            for (var i = 0; i < pts.length; i++) {
                if (pts[i].t < t0) continue
                if (!started) { ctx.moveTo(X(pts[i].t), Y(pts[i].mgdl)); started = true }
                else ctx.lineTo(X(pts[i].t), Y(pts[i].mgdl))
            }
            ctx.stroke()
        }
    }
}
