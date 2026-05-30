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
	property string phase: "Ready"
	property string resultPath: ""

	menuPath: "Plugins.loaphuong.Render Vocal"
	description: "Render vocal track via Loaphuong gen backend"
	version: "0.1.0"
	pluginType: "dialog"
	dockArea: "none"

	onRun: {
		try {
			console.log("loaphuong: onRun, score=" + (curScore ? curScore.title : "none"))
			phase = curScore ? "Ready — " + curScore.title : "No score open"
		} catch (e) {
			console.log("loaphuong: onRun error: " + e)
			phase = "Init error: " + e
		}
	}

	function startRender() {
		if (rendering || !curScore) return

		var ts = new Date().getTime()
		var tmp = Qt.formatDate(new Date(), "yyyyMMdd") + "_" + ts

		// Try to write to a temp location the backend can reach
		var path = "/tmp/loaphuong_" + tmp + ".musicxml"

		try {
			var ok = curScore.writeScore(path)
			console.log("loaphuong: writeScore(" + path + ") = " + ok)
			if (!ok) {
				// Fallback: try without leading slash, some MS versions
				path = "loaphuong_" + tmp + ".musicxml"
				ok = curScore.writeScore(path)
				console.log("loaphuong: writeScore fallback = " + ok)
				if (!ok) {
					phase = "Export failed (check console)"
					return
				}
			}
		} catch (e) {
			console.log("loaphuong: writeScore threw: " + e)
			phase = "Export error: " + e
			return
		}

		rendering = true
		hasRender = false
		progress = 0.0
		phase = "Sending request..."
		resultPath = ""

		try {
			var xhr = new XMLHttpRequest()
			xhr.open("POST", backendUrl + "/api/render")
			xhr.setRequestHeader("Content-Type", "application/json")

			xhr.onreadystatechange = function() {
				try {
					if (xhr.readyState === 3) { // LOADING
						var text = xhr.responseText || ""
						if (text.length > 0) phase = "Processing..."
					}
					if (xhr.readyState === 4) { // DONE
						if (xhr.status === 200) {
							var result = JSON.parse(xhr.responseText)
							resultPath = result.wavPath || ""
							hasRender = true
							phase = "Done!"
						} else {
							phase = "Server: " + xhr.status + " " + xhr.statusText
						}
						rendering = false
						progress = 1.0
					}
				} catch (e) {
					console.log("loaphuong: xhr error: " + e)
				}
			}

			var body = JSON.stringify({
				musicxml: path,
				voice: voice,
				model: model,
			})

			console.log("loaphuong: sending POST to " + backendUrl + "/api/render")
			xhr.send(body)
			console.log("loaphuong: request sent")
		} catch (e) {
			console.log("loaphuong: XHR failed: " + e)
			phase = "XHR failed: " + e
			rendering = false
		}
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
				enabled: !rendering && curScore != null
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

		ProgressBar {
			Layout.fillWidth: true
			from: 0; to: 1
			value: progress
			visible: rendering || hasRender
		}

		Label {
			text: phase
			visible: phase !== ""
			color: hasRender ? "#22c55e" : "#64748b"
			font.pixelSize: 12
		}

		Item { Layout.fillHeight: true }

		Label {
			text: curScore ? (curScore.title || "Untitled") + " \u00B7 " + curScore.nmeasures + " measures" : "No score open"
			color: "#94a3b8"
			font.pixelSize: 11
		}
	}
}
