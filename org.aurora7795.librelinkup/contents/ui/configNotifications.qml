import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    property alias cfg_alertsEnabled: enabledBox.checked
    property alias cfg_lowOn: lowBox.checked
    property alias cfg_lowAt: lowSpin.value
    property alias cfg_highOn: highBox.checked
    property alias cfg_highAt: highSpin.value
    property alias cfg_fastOn: fastBox.checked
    property alias cfg_signalOn: signalBox.checked
    property alias cfg_repeatMin: repeatSpin.value
    property bool cfg_alertsEnabledDefault
    property bool cfg_lowOnDefault
    property int cfg_lowAtDefault
    property bool cfg_highOnDefault
    property int cfg_highAtDefault
    property bool cfg_fastOnDefault
    property bool cfg_signalOnDefault
    property int cfg_repeatMinDefault

    // Thresholds are stored in mg/dL; show the mmol/L equivalent beside them.
    function mmolText(mgdl) { return "≈ " + (mgdl / 18.0182).toFixed(1) + " mmol/L" }

    Kirigami.FormLayout {
        QQC2.CheckBox {
            id: enabledBox
            Kirigami.FormData.label: i18n("Notifications:")
            text: i18n("Enabled")
        }

        Item { Kirigami.FormData.isSection: true }

        QQC2.CheckBox {
            id: lowBox
            enabled: enabledBox.checked
            Kirigami.FormData.label: i18n("Low glucose:")
            text: i18n("Critical notification at or below")
        }
        RowLayout {
            enabled: enabledBox.checked && lowBox.checked
            QQC2.SpinBox { id: lowSpin; from: 40; to: 120 }
            QQC2.Label { text: "mg/dL   " + mmolText(lowSpin.value); opacity: 0.75 }
        }

        QQC2.CheckBox {
            id: highBox
            enabled: enabledBox.checked
            Kirigami.FormData.label: i18n("High glucose:")
            text: i18n("Notification at or above")
        }
        RowLayout {
            enabled: enabledBox.checked && highBox.checked
            QQC2.SpinBox { id: highSpin; from: 140; to: 400 }
            QQC2.Label { text: "mg/dL   " + mmolText(highSpin.value); opacity: 0.75 }
        }

        QQC2.CheckBox {
            id: fastBox
            enabled: enabledBox.checked
            Kirigami.FormData.label: i18n("Trend:")
            text: i18n("Rising / falling fast (double arrow)")
        }
        QQC2.CheckBox {
            id: signalBox
            enabled: enabledBox.checked
            Kirigami.FormData.label: i18n("Signal:")
            text: i18n("No new reading for 30 minutes")
        }

        RowLayout {
            enabled: enabledBox.checked
            Kirigami.FormData.label: i18n("Repeat every:")
            QQC2.SpinBox { id: repeatSpin; from: 0; to: 240 }
            QQC2.Label { text: i18n("min (0 = once)"); opacity: 0.75 }
        }

        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            wrapMode: Text.Wrap
            opacity: 0.75
            text: i18n("Notifications are sent with notify-send. They depend on this widget, the unofficial API and your connection, so do not rely on them as a safety alarm.")
        }
    }
}
