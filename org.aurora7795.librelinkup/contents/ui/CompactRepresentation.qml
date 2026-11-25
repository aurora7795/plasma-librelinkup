import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

MouseArea {
    id: compact

    required property var backend

    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
    hoverEnabled: true

    Layout.minimumWidth: label.implicitWidth + Kirigami.Units.smallSpacing * 2
    Layout.preferredWidth: Layout.minimumWidth

    onClicked: function(mouse) {
        if (mouse.button === Qt.MiddleButton) backend.refresh()
        else backend.expanded = !backend.expanded
    }

    PlasmaComponents.Label {
        id: label
        anchors.centerIn: parent
        text: backend.label
        font.bold: true
        // Fall back to the panel height so the text stays inside the panel.
        fontSizeMode: Text.VerticalFit
        height: Math.min(parent.height, implicitHeight)
        color: backend.urgentReading ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
    }
}
