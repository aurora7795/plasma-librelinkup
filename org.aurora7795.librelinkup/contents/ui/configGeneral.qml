import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    property alias cfg_intervalSec: intervalSpin.value
    property string cfg_unit
    property int cfg_intervalSecDefault
    property string cfg_unitDefault

    Kirigami.FormLayout {
        QQC2.SpinBox {
            id: intervalSpin
            Kirigami.FormData.label: i18n("Refresh every (seconds):")
            from: 60
            to: 600
            stepSize: 30
        }
        QQC2.ComboBox {
            Kirigami.FormData.label: i18n("Unit:")
            textRole: "text"
            valueRole: "value"
            model: [
                { text: "mg/dL", value: "mgdl" },
                { text: "mmol/L", value: "mmol" }
            ]
            currentIndex: cfg_unit === "mmol" ? 1 : 0
            onActivated: cfg_unit = currentValue
        }
        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 20
            wrapMode: Text.Wrap
            opacity: 0.75
            text: i18n("The unit can also be switched from the popup. LibreView limits how often it can be queried, so the refresh interval cannot go below 60 seconds.")
        }
    }
}
