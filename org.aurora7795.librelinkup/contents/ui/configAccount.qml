import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.plasma.plasma5support as P5Support

KCM.SimpleKCM {
    id: page

    property string email: ""
    property string storage: "none"
    property string message: ""
    property bool failed: false
    property bool busy: false
    property int seq: 0

    readonly property string helperPath:
        decodeURIComponent(String(Qt.resolvedUrl("../code/llu.py")).replace(/^file:\/\//, ""))

    function q(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }
    function run(arg) {
        busy = true
        runner.connectSource("python3 -I " + q(helperPath) + " " + arg + " # " + (seq++))
    }

    P5Support.DataSource {
        id: runner
        engine: "executable"
        connectedSources: []
        onNewData: function(source, data) {
            disconnectSource(source)
            page.busy = false
            var r
            try { r = JSON.parse(String(data["stdout"] || "").trim()) } catch (e) { r = null }
            if (!r) { page.failed = true; page.message = i18n("No response from the helper."); return }
            if (source.indexOf("--status") >= 0 || source.indexOf("--signout") >= 0) {
                page.email = r.email || ""
                page.storage = r.storage || "none"
                if (source.indexOf("--signout") >= 0) { page.failed = false; page.message = i18n("Signed out. The saved password was removed.") }
                return
            }
            // --signin: the helper also fetched a reading, so r.ok means it worked.
            if (r.cancelled) { page.message = ""; page.run("--status"); return }
            page.failed = !r.ok
            page.message = r.ok ? i18n("Signed in. The widget updates at its next refresh.") : String(r.error || "")
            page.run("--status")
        }
    }

    Component.onCompleted: run("--status")

    Kirigami.FormLayout {
        QQC2.Label {
            Kirigami.FormData.label: i18n("Signed in as:")
            text: page.email !== "" ? page.email : i18n("not signed in")
            opacity: page.email !== "" ? 1 : 0.6
        }
        QQC2.Label {
            Kirigami.FormData.label: i18n("Password stored in:")
            text: page.storage === "keyring" ? i18n("system keyring")
                : page.storage === "file" ? i18n("a private file (no keyring found)")
                : i18n("nowhere")
            opacity: page.storage === "none" ? 0.6 : 1
        }
        QQC2.Label {
            visible: page.storage === "file"
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            wrapMode: Text.Wrap
            opacity: 0.75
            text: i18n("~/.config/librelinkup-plasma/config.json (mode 600). Install libsecret-tools and it moves into the keyring automatically.")
        }

        Item { Kirigami.FormData.isSection: true }

        RowLayout {
            QQC2.Button {
                icon.name: "user-identity"
                text: page.email !== "" ? i18n("Change account…") : i18n("Sign in…")
                enabled: !page.busy
                onClicked: page.run("--signin")
            }
            QQC2.Button {
                icon.name: "edit-delete"
                text: i18n("Sign out and forget password")
                enabled: !page.busy && page.email !== ""
                onClicked: page.run("--signout")
            }
        }

        QQC2.Label {
            visible: page.message !== ""
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            wrapMode: Text.Wrap
            text: page.message
            color: page.failed ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
        }
        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            wrapMode: Text.Wrap
            opacity: 0.75
            text: i18n("Use the LibreLinkUp follower account that your Libre app shares with, not the sensor owner's login. Sign-in opens a KDE dialog so your password never passes through the widget.")
        }
    }
}
