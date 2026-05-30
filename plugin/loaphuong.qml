import MuseScore 3.0
import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

MuseScore {
	id: root
	width: 420
	height: 520

	property string backendUrl: "http://127.0.0.1:3100"
	property string voice: "merrow"
	property string model: "gpu"

	property bool rendering: false
	property bool hasRender: false
	property real progress: 0.0
	property string phase: ""
	property string eta: ""
	property string resultPath: ""
	property var phraseProgress: ({})

	menuPath: "Plugins.loaphuong.Render Vocal"
	description: "Render vocal track via Loaphuong gen backend"
	version: "0.1.0"
	pluginType: "dialog"
	dockArea: "none"

	onRun: {
		try {
			console.log("loaphuong: onRun, score=" + (curScore ? curScore.title : "none"))
		} catch (e) {
			console.log("loaphuong: onRun error: " + e)
		}
	}

	function startRender() {
		if (rendering || !voice) return

		var ts = new Date().getTime()
		if (!curScore) {
			phase = "No score open"
			return
		}

		var path = Qt.formatDate(new Date(), "yyyyMMdd") + "_" + ts + ".musicxml"
		var ok = curScore.writeScore(path)
		if (!ok) {
			phase = "Export failed"
			return
		}

		rendering = true
		hasRender = false
		progress = 0.0
		phase = "Exporting..."
		resultPath = ""
		phraseProgress = ({})

		var xhr = new XMLHttpRequest()
		xhr.open("POST", backendUrl + "/api/render")
		xhr.setRequestHeader("Content-Type", "application/json")

		xhr.onreadystatechange = function() {
			if (xhr.readyState === XMLHttpRequest.LOADING) {
				try {
					var text = xhr.responseText || ""
					var lines = text.trim().split("\n")
					for (var i = 0; i < lines.length; i++) {
						var ev = JSON.parse(lines[i])
						if (ev.phase) phase = ev.phase
						if (ev.progress !== undefined) progress = ev.progress
					}
				} catch (_) {}
			}
			if (xhr.readyState === XMLHttpRequest.DONE) {
				if (xhr.status === 200) {
					try {
						var result = JSON.parse(xhr.responseText)
						resultPath = result.wavPath || ""
						hasRender = true
						phase = "Done!"
					} catch (e) {
						phase = "Parse error"
					}
				} else {
					phase = "Error: " + xhr.status
				}
				rendering = false
				progress = 1.0
			}
		}

		xhr.send(JSON.stringify({
			musicxml: path,
			voice: voice,
			model: model,
		}))
	}

	ColumnLayout {
		anchors.fill: parent
		anchors.margins: 16
		spacing: 12

		GroupBox {
			title: "Voice"
			Layout.fillWidth: true

			GridLayout {
				columns: 2
				columnSpacing: 8
				rowSpacing: 8
				anchors.left: parent.left
				anchors.right: parent.right

				Label { text: "Model" }
				ComboBox {
					id: voiceCombo
					Layout.fillWidth: true
					model: ["merrow", "nakumo", "reina", "runo", "soma", "zunko"]
					currentIndex: 0
					onCurrentTextChanged: root.voice = currentText
				}

				Label { text: "Backend" }
				TextField {
					Layout.fillWidth: true
					text: root.backendUrl
					onTextChanged: root.backendUrl = text
				}

				Label { text: "Render" }
				ComboBox {
					Layout.fillWidth: true
					model: ["gpu", "cpu"]
					currentIndex: 0
					onCurrentTextChanged: root.model = currentText
				}
			}
		}

		RowLayout {
			Layout.fillWidth: true
			spacing: 8

			Button {
				text: rendering ? "Rendering..." : "Render"
				Layout.fillWidth: true
				enabled: !rendering && curScore !== null
				onClicked: startRender()
			}

			Button {
				text: "Cancel"
				enabled: rendering
				onClicked: rendering = false
			}
		}

		ProgressBar {
			Layout.fillWidth: true
			from: 0; to: 1
			value: progress
			visible: rendering || hasRender
		}

		Label {
			text: {
				if (curScore) return (curScore.title || "Untitled") + " \u00B7 " + curScore.nmeasures + " measures"
				return "No score open"
			}
			color: "#94a3b8"
			font.pixelSize: 11
		}

		Label {
			text: phase + (eta ? " (" + eta + ")" : "")
			visible: phase !== ""
			color: hasRender ? "#22c55e" : "#64748b"
			font.pixelSize: 12
		}

		Item {
			Layout.fillHeight: true
		}
	}
}
