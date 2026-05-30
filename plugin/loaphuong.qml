import MuseScore 3.0
import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

MuseScore {
	id: root
	width: 420
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

	function generateMusicXml() {
		var sigN = curScore.timesigNumerator || 4
		var sigD = curScore.timesigDenominator || 4
		var div = curScore.division || 480

		// DEBUG: just dump segment info
		var info = "track0 scan:\n"
		var cursor = curScore.newCursor()
		cursor.rewind(Cursor.SCORE_START)
		var segs = 0, chords = 0, lyrics = 0
		while (cursor.segment && ++segs < 100) {
			var e = cursor.element
			if (e) {
				info += "seg" + segs + " t=" + cursor.tick + " type=" + e.type
				if (e.type === Element.CHORD) {
					chords++
					info += " notes=" + (e.notes ? e.notes.length : 0)
					if (e.lyrics) {
						lyrics += e.lyrics.length
						info += " lyrics=" + e.lyrics.length + "[" + e.lyrics[0].text + "]"
					}
				}
				info += "\n"
			}
			cursor.next()
		}
		info += "total: segs=" + segs + " chords=" + chords + " lyrics=" + lyrics

		// Wrap in minimal MusicXML so backend can report parse error
		var xml = '<?xml version="1.0" encoding="UTF-8"?>\n'
		xml += '<score-partwise version="4.0">\n'
		xml += '<part-list><score-part id="P1"><part-name>Voice</part-name></score-part></part-list>\n'
		xml += '<part id="P1"><measure number="1">\n'
		xml += '<attributes><divisions>' + div + '</divisions>'
		xml += '<time><beats>' + sigN + '</beats><beat-type>' + sigD + '</beat-type></time>'
		xml += '<clef><sign>G</sign><line>2</line></clef>'
		xml += '</attributes>\n'

		// Emit notes from track0 chords
		var cursor2 = curScore.newCursor()
		cursor2.rewind(Cursor.SCORE_START)
		var safety = 0
		while (cursor2.segment && ++safety < 5000) {
			var e = cursor2.element
			if (e && e.type === Element.CHORD && e.notes && e.notes.length > 0) {
				var n = e.notes[0]
				xml += '<note><pitch><step>' + pitchToStep(n.pitch) + '</step>'
				xml += '<octave>' + pitchToOctave(n.pitch) + '</octave></pitch>'
				xml += '<duration>' + (e.duration ? e.duration.ticks : 1) + '</duration>'
				xml += '<type>quarter</type>'
				if (e.lyrics && e.lyrics.length > 0 && e.lyrics[0].text) {
					var syl = ["single","begin","end","middle"][e.lyrics[0].syllabic] || "single"
					xml += '<lyric><syllabic>' + syl + '</syllabic><text>' + escapeXml(e.lyrics[0].text) + '</text></lyric>'
				}
				xml += '</note>\n'
			}
			cursor2.next()
		}

		xml += '</measure></part></score-partwise>\n'

		lastXml = info + "\n\n---\n\nMusicXML:\n" + xml.slice(0, 1000)
		return xml
	}

	function escapeXml(s) {
		return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&apos;")
	}

	function startRender() {
		if (rendering || !curScore) return

		rendering = true
		hasRender = false
		progress = 0.0
		phase = "Generating MusicXML..."
		resultPath = ""

		try {
			var musicXml = generateMusicXml()
			lastXml = musicXml.length > 2000 ? musicXml.slice(0, 2000) + "..." : musicXml
			lastError = ""
			phase = "Sending request..."

			var xhr = new XMLHttpRequest()
			xhr.open("POST", backendUrl + "/api/render")
			xhr.setRequestHeader("Content-Type", "application/json")

			xhr.onreadystatechange = function() {
				try {
					if (xhr.readyState === 3) {
						phase = "Processing..."
					}
					if (xhr.readyState === 4) {
						if (xhr.status === 200) {
							var result = JSON.parse(xhr.responseText)
							resultPath = result.wavPath || ""
							hasRender = true
							phase = "Done!"
						} else {
							lastError = xhr.responseText
							phase = "Error: " + xhr.status
						}
						rendering = false
						progress = 1.0
					}
				} catch (e) {
					console.log("loaphuong: xhr cb error: " + e)
				}
			}

			var body = JSON.stringify({
				musicxml: musicXml,
				voice: voice,
				model: model,
			})

			xhr.send(body)
		} catch (e) {
			console.log("loaphuong: render error: " + e)
			phase = "Error: " + e
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

		// Debug panel — show on error or after render
		Rectangle {
			Layout.fillWidth: true
			Layout.maximumHeight: 150
			visible: lastError !== "" || lastXml !== ""
			color: "#1e1e2e"
			radius: 4
			clip: true

			ScrollView {
				anchors.fill: parent
				anchors.margins: 4

				Label {
					text: lastError !== ""
						? "Server:\n" + lastError
						: "MusicXML:\n" + lastXml
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
			font.pixelSize: 11
		}
	}
}
