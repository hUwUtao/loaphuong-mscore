import MuseScore 3.0
import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

MuseScore {
	id: root
	width: 440
	height: 520

	property string backendUrl: "http://127.0.0.1:3100"
	property string voice: "MERROW"
	property string model: "gpu"

	property bool rendering: false
	property bool hasRender: false
	property real progress: 0.0
	property string phase: "Ready"
	property string resultPath: ""
	property string lastXml: ""
	property string lastError: ""
	property int lyricNoteCount: 0

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

	function pitchToStep(p) {
		var steps = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
		return steps[p % 12]
	}

	function pitchToOctave(p) {
		return Math.floor(p / 12) - 1
	}

	function findVocalTrack() {
		var nstaves = curScore.nstaves || 1
		for (var t = 0; t < nstaves * 4; t++) {
			var cursor = curScore.newCursor()
			cursor.track = t
			cursor.rewind(Cursor.SCORE_START)
			var safety = 0
			while (cursor.segment && ++safety < 500) {
				var e = cursor.element
				if (e && e.type === Element.CHORD && e.lyrics && e.lyrics.length > 0) {
					return t
				}
				cursor.next()
			}
		}
		return 0
	}


	// Write phonemes as Lyric Line 2 — match by sequential position
	function writePhonemesToScore(exportData) {
		var target = findVocalTrack()
		var keys = Object.keys(exportData)
		if (keys.length === 0) return
		var cursor = curScore.newCursor()
		cursor.track = target
		cursor.rewind(Cursor.SCORE_START)
		var ki = 0, written = 0, safety = 0
		curScore.startCmd()
		while (cursor.segment && ++safety < 500) {
			var e = cursor.element
			if (e && e.type === Element.CHORD && e.notes && e.notes.length > 0
				&& e.lyrics && e.lyrics.length > 0 && e.lyrics[0].text && ki < keys.length) {
				var phones = exportData[keys[ki]]
				ki++
				if (!phones || phones.length === 0) continue
				// Skip if Lyric 2 already has user override text
				if (e.lyrics.length > 1 && e.lyrics[1] && e.lyrics[1].text && e.lyrics[1].text.length > 0)
					continue
				var txt = phones.join(" ")
				try {
					if (e.lyrics.length > 1 && e.lyrics[1]) {
						e.lyrics[1].text = txt
					} else {
						var ly = newElement(Element.LYRICS)
						ly.text = txt
						ly.verse = 1
						cursor.add(ly)
					}
					written++
				} catch (_) {}
			}
			cursor.next()
		}
		curScore.endCmd()
		lyricNoteCount = written
	}

	function escapeXml(s) {
		return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&apos;")
	}

	function doRequest(endpoint, bodyObj, cb) {
		var xhr = new XMLHttpRequest()
		xhr.open("POST", backendUrl + endpoint)
		xhr.setRequestHeader("Content-Type", "application/json")
		xhr.onreadystatechange = function() {
			try {
				if (xhr.readyState === 4) {
					if (xhr.status === 200) cb(null, JSON.parse(xhr.responseText))
					else cb(xhr.responseText, null)
				}
			} catch (e) { cb(String(e), null) }
		}
		xhr.send(JSON.stringify(bodyObj))
	}


	function startRender(withOverrides) {
		if (rendering || !curScore) return
		rendering = true
		hasRender = false
		progress = 0.0
		phase = "Generating MusicXML..."
		resultPath = ""

		try {
			var bodyObj = { voice: voice, model: model }

			// Read Lyric Line 2 as overrides when re-rendering
			if (withOverrides)
				bodyObj.phonemeOverrides = readPhonemesFromScore()

			var musicXml = generateMusicXml()
			bodyObj.musicxml = musicXml

			lastXml = musicXml.length > 2000 ? musicXml.slice(0, 2000) + "..." : musicXml
			lastError = ""
			phase = "Rendering..."

			doRequest("/api/render", bodyObj, function(err, res) {
				if (err) {
					lastError = err
					phase = "Error"
				} else {
					resultPath = res.wavPath || ""
					hasRender = true
					phase = "Done! " + ((res.output && res.output.phonemeExport) ? Object.keys(res.output.phonemeExport).length + " notes" : "")
				}
				rendering = false
				progress = 1.0
			})
		} catch (e) {
			phase = "Error: " + e
			rendering = false
		}
	}

	function showPhonemes() {
		if (rendering || !curScore) return
		rendering = true
		progress = 0.0
		phase = "Analyzing..."
		lastError = ""

		try {
			var musicXml = generateMusicXml()
			var bodyObj = { musicxml: musicXml }
			doRequest("/api/phonemes", bodyObj, function(err, res) {
				if (err) {
					lastError = err
					phase = "Error"
				} else {
					var pExport = res.phonemeExport || {}
					writePhonemesToScore(pExport)
					phase = Object.keys(pExport).length + " notes written to Lyric 2"
				}
				rendering = false
				progress = 1.0
			})
		} catch (e) {
			phase = "Error: " + e
			rendering = false
		}
	}

	ColumnLayout {
		anchors.fill: parent
		anchors.margins: 12
		spacing: 8

		GroupBox {
			title: "Voice"
			Layout.fillWidth: true

			GridLayout {
				columns: 2
				columnSpacing: 8
				rowSpacing: 6
				anchors.left: parent.left
				anchors.right: parent.right

				Label { text: "Model" }
				ComboBox {
					Layout.fillWidth: true
					model: ["MERROW", "NAKUMO", "REINA", "RUNO", "SOMA", "ZUNKO"]
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
			spacing: 6

			Button {
				text: "Show Phonemes"
				enabled: !rendering && curScore != null
				onClicked: showPhonemes()
			}

			Button {
				text: rendering ? "Rendering..." : "Render"
				enabled: !rendering && curScore != null
				Layout.fillWidth: true
				onClicked: startRender(false)
			}

			Button {
				text: "Re-render"
				enabled: !rendering && hasRender
				highlighted: lyricNoteCount > 0
				onClicked: startRender(true)
			}

			Button {
				text: "Play"
				enabled: hasRender && resultPath !== ""
				onClicked: { if (resultPath) Qt.openUrlExternally("file://" + resultPath) }
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

		Label {
			text: lyricNoteCount > 0
				? lyricNoteCount + " notes have Lyric 2 phonemes — edit them in the score, then Re-render"
				: ""
			visible: lyricNoteCount > 0
			color: "#a78bfa"
			font.pixelSize: 10
			wrapMode: Text.Wrap
		}

		Item { Layout.fillHeight: true }

		Rectangle {
			Layout.fillWidth: true
			Layout.maximumHeight: 80
			visible: lastError !== ""
			color: "#1e1e2e"
			radius: 4
			clip: true

			ScrollView {
				anchors.fill: parent
				anchors.margins: 4
				Label {
					text: "Error:\n" + lastError
					color: "#cdd6f4"
					font.pixelSize: 9
					font.family: "monospace"
					textFormat: Text.PlainText
					wrapMode: Text.Wrap
				}
			}
		}

		Label {
			text: curScore ? (curScore.title || "Untitled") + " \u00B7 " + curScore.nmeasures + " measures" : "No score open"
			color: "#94a3b8"
			font.pixelSize: 10
		}
	}
}
