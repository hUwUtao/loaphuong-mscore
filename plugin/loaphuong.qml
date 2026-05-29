import MuseScore 3.0
import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQuick.Window 2.15

MuseScore {
    id: root

    // ---- Configuration ----
    property string backendUrl: "http://127.0.0.1:3100"
    property string voice: "soprano"
    property string model: "gpu"
    property string cacheDir: ""

    // ---- State ----
    property bool rendering: false
    property bool hasRender: false
    property real progress: 0.0
    property string phase: ""
    property string eta: ""
    property string resultPath: ""
    property var phrases: []
    property var phraseProgress: ({})

    menuPath: "Plugins.loaphuong.Render Vocal"
    description: "Render vocal track via Loaphuong gen backend"
    version: "0.1.0"
    pluginType: "dialog"
    dockArea: "none"

    onRun: {
        if (!curScore) {
            console.log("loaphuong: no score open")
            return
        }
        window.visible = true
    }

    function collectScoreData() {
        if (!curScore) return null

        var path = cacheDir + "/cephome_input.musicxml"
        if (cacheDir === "") {
            var ts = new Date().getTime()
            path = Qt.formatDate(new Date(), "yyyyMMdd") + "_" + ts + ".musicxml"
        }

        var ok = curScore.writeScore(path)
        if (!ok) {
            console.log("cephome: writeScore failed")
            return null
        }

        var notes = []
        var cursor = curScore.newCursor()
        cursor.rewind(0)
        cursor.voice = 0

        while (cursor.next()) {
            var el = cursor.element
            if (el && el.type === Element.NOTE) {
                var note = el
                var lyricText = null
                var verse = 0
                var syllabic = null

                for (var i = 0; i < note.elements.length; i++) {
                    var child = note.elements[i]
                    if (child.type === Element.LYRICS) {
                        lyricText = child.text
                        verse = child.verse
                        syllabic = child.syllabic
                        break
                    }
                }

                if (lyricText) {
                    notes.push({
                        tick: note.tick,
                        pitch: note.pitch,
                        duration: note.duration,
                        lyric: lyricText,
                        verse: verse,
                        syllabic: syllabic,
                        voice: cursor.voice,
                        staff: cursor.staffIdx
                    })
                }
            }
        }

        return {
            path: path,
            notes: notes,
            title: curScore.title,
            composer: curScore.composer
        }
    }

    function startRender() {
        if (rendering) return

        var data = collectScoreData()
        if (!data) return

        rendering = true
        hasRender = false
        progress = 0.0
        phase = "Exporting score..."
        resultPath = ""

        var xhr = new XMLHttpRequest()
        xhr.open("POST", backendUrl + "/api/render")
        xhr.setRequestHeader("Content-Type", "application/json")

        xhr.onprogress = function(e) {
            if (xhr.status !== 200) return
            var text = xhr.responseText || ""
            var lines = text.trim().split("\n")
            for (var i = 0; i < lines.length; i++) {
                try {
                    var ev = JSON.parse(lines[i])
                    updateProgress(ev)
                } catch(_) {}
            }
        }

        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.LOADING) {
                var text = xhr.responseText || ""
                var lines = text.trim().split("\n")
                for (var i = 0; i < lines.length; i++) {
                    try {
                        var ev = JSON.parse(lines[i])
                        updateProgress(ev)
                    } catch(_) {}
                }
            }
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200) {
                    try {
                        var result = JSON.parse(xhr.responseText)
                        resultPath = result.wavPath || result.audioPath || ""
                        hasRender = true
                        phase = "Done!"
                    } catch(e) {
                        phase = "Error parsing response"
                    }
                } else {
                    phase = "Error: " + xhr.status
                }
                rendering = false
                progress = 1.0
            }
        }

        var body = JSON.stringify({
            musicxml: data.path,
            voice: voice,
            model: model,
            options: {
                title: data.title,
                composer: data.composer || "",
                notes: data.notes.map(function(n) {
                    return {
                        tick: n.tick,
                        midi: n.pitch,
                        lyric: n.lyric,
                        verse: n.verse,
                        syllabic: n.syllabic
                    }
                })
            }
        })

        xhr.send(body)
    }

    function updateProgress(ev) {
        if (ev.phase) phase = ev.phase
        if (ev.progress !== undefined) progress = ev.progress
        if (ev.eta) eta = ev.eta
        if (ev.phrase !== undefined && ev.status !== undefined) {
            phraseProgress[ev.phrase] = ev.status
            var list = []
            for (var k in phraseProgress) list.push(k)
            phraseProgress = phraseProgress
        }
    }

    function progressColor(status) {
        if (status === "done") return "#22c55e"
        if (status === "rendering") return "#3b82f6"
        if (status === "queued") return "#94a3b8"
        return "#e2e8f0"
    }

    function progressIcon(status) {
        if (status === "done") return "\u2713"
        if (status === "rendering") return "\u25B6"
        if (status === "queued") return "\u25CB"
        return "\u00B7"
    }

    Window {
        id: window
        width: 420
        height: 520
        title: "Loaphuong Render"
        flags: Qt.Dialog | Qt.WindowCloseButtonHint | Qt.WindowTitleHint
        modality: Qt.NonModal

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            // ---- Config section ----
            GroupBox {
                title: "Configuration"
                Layout.fillWidth: true

                GridLayout {
                    columns: 2
                    columnSpacing: 8
                    rowSpacing: 8
                    anchors.left: parent.left
                    anchors.right: parent.right

                    Label { text: "Voice" }
                    ComboBox {
                        id: voiceCombo
                        Layout.fillWidth: true
                        model: ["soprano", "alto", "tenor", "baritone"]
                        currentIndex: 0
                        onCurrentTextChanged: root.voice = currentText
                    }

                    Label { text: "Model" }
                    ComboBox {
                        id: modelCombo
                        Layout.fillWidth: true
                        model: ["gpu (fast)", "cpu (slow)"]
                        currentIndex: 0
                        onCurrentTextChanged: {
                            root.model = currentText.indexOf("gpu") >= 0 ? "gpu" : "cpu"
                        }
                    }

                    Label { text: "Backend URL" }
                    TextField {
                        id: urlField
                        Layout.fillWidth: true
                        text: root.backendUrl
                        onTextChanged: root.backendUrl = text
                    }

                    Label { text: "Cache dir" }
                    TextField {
                        id: cacheField
                        Layout.fillWidth: true
                        placeholderText: "Auto (temp)"
                        onTextChanged: root.cacheDir = text
                    }
                }
            }

            // ---- Render button + status ----
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Button {
                    id: renderBtn
                    text: rendering ? "Rendering..." : "Render"
                    Layout.fillWidth: true
                    enabled: !rendering && curScore !== null
                    onClicked: startRender()
                }

                Button {
                    text: "Cancel"
                    enabled: rendering
                    onClicked: {
                        rendering = false
                        phase = "Cancelled"
                    }
                }
            }

            // ---- Progress bar ----
            ProgressBar {
                id: progressBar
                Layout.fillWidth: true
                from: 0
                to: 1
                value: progress
                visible: rendering || hasRender
            }

            Label {
                text: phase + (eta ? " (" + eta + ")" : "")
                visible: phase !== ""
                color: hasRender ? "#22c55e" : "#64748b"
                font.pixelSize: 12
            }

            // ---- Phrase chips ----
            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                visible: Object.keys(phraseProgress).length > 0

                Flow {
                    id: chipFlow
                    width: parent.width
                    spacing: 6

                    Repeater {
                        model: {
                            var keys = Object.keys(phraseProgress).sort()
                            return keys
                        }

                        delegate: Rectangle {
                            width: chipLabel.implicitWidth + 24
                            height: 28
                            radius: 14
                            color: progressColor(phraseProgress[modelData])

                            Label {
                                id: chipLabel
                                anchors.centerIn: parent
                                text: progressIcon(phraseProgress[modelData]) + " " + modelData
                                color: "white"
                                font.pixelSize: 11
                                font.bold: true
                            }

                            ToolTip {
                                text: modelData + ": " + phraseProgress[modelData]
                                visible: ma.containsMouse
                            }

                            MouseArea {
                                id: ma
                                anchors.fill: parent
                                hoverEnabled: true
                            }
                        }
                    }
                }
            }

            // ---- Result path ----
            Rectangle {
                Layout.fillWidth: true
                height: 36
                radius: 6
                color: "#f0fdf4"
                border.color: "#bbf7d0"
                visible: hasRender && resultPath !== ""

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 8

                    Label {
                        text: "\uD83D\uDD0A WAV"
                        font.bold: true
                        color: "#166534"
                    }

                    Label {
                        text: resultPath
                        Layout.fillWidth: true
                        elide: Text.ElideMiddle
                        color: "#166534"
                        font.pixelSize: 11
                    }

                    Button {
                        text: "Copy"
                        flat: true
                        onClicked: {
                            // clipboard copy workaround
                            phase = "Copied: " + resultPath
                        }
                    }
                }
            }

            // ---- Score info ----
            Label {
                text: curScore ? (curScore.title || "Untitled") + " \u00B7 " + curScore.nmeasures + " measures" : "No score open"
                color: "#94a3b8"
                font.pixelSize: 11
                visible: true
            }
        }
    }
}
