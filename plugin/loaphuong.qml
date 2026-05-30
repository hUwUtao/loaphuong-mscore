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
		var div = typeof curScore.division !== "undefined" ? curScore.division
			: typeof division !== "undefined" ? division : 480

		var xml = '<?xml version="1.0" encoding="UTF-8"?>\n'
		xml += '<!DOCTYPE score-partwise PUBLIC "-//Recordare//DTD MusicXML 4.0 Partwise//EN" "http://www.musicxml.org/dtds/partwise.dtd">\n'
		xml += '<score-partwise version="4.0">\n'
		xml += '  <part-list>\n'
		xml += '    <score-part id="P1">\n'
		xml += '      <part-name>Voice</part-name>\n'
		xml += '    </score-part>\n'
		xml += '  </part-list>\n'
		xml += '  <part id="P1">\n'

		var cursor = curScore.newCursor()
		cursor.rewind(0)
		var measureNum = 0

		// Prepend a silence measure so NEUTRINO gets an initial pau
		var restDur = div * sigN * (4 / sigD)

		while (cursor.segment) {
			var el = cursor.element
			if (el && el.type === Element.MEASURE) {
				measureNum++
				xml += '    <measure number="' + measureNum + '">\n'

				if (measureNum === 1) {
					xml += '      <attributes>\n'
					xml += '        <divisions>' + div + '</divisions>\n'
					xml += '        <time>\n'
					xml += '          <beats>' + sigN + '</beats>\n'
					xml += '          <beat-type>' + sigD + '</beat-type>\n'
					xml += '        </time>\n'
					xml += '        <clef>\n'
					xml += '          <sign>G</sign>\n'
					xml += '          <line>2</line>\n'
					xml += '        </clef>\n'
					xml += '      </attributes>\n'
					// Lead-in silence: whole rest
					xml += '      <note>\n'
					xml += '        <rest/>\n'
					xml += '        <duration>' + restDur + '</duration>\n'
					xml += '        <type>whole</type>\n'
					xml += '      </note>\n'
				}

				cursor.next()

				while (cursor.segment && cursor.element && cursor.element.type !== Element.MEASURE) {
					var e = cursor.element

					if (e.type === Element.CHORD) {
						var chord = e
						if (chord.notes && chord.notes.length > 0) {
							var note = chord.notes[0]
							var dur = chord.duration ? chord.duration.ticks : 1
							var step = pitchToStep(note.pitch)
							var oct = pitchToOctave(note.pitch)

							xml += '      <note>\n'
							if (note.pitch !== undefined && note.pitch !== null) {
								xml += '        <pitch>\n'
								xml += '          <step>' + step + '</step>\n'
								xml += '          <octave>' + oct + '</octave>\n'
								xml += '        </pitch>\n'
							} else {
								xml += '        <rest/>\n'
							}
							xml += '        <duration>' + dur + '</duration>\n'
							xml += '        <type>quarter</type>\n'

							if (chord.lyrics && chord.lyrics.length > 0) {
								var l = chord.lyrics[0]
								var txt = l.text || ""
								if (txt.length > 0) {
									var syl = "single"
									if (l.syllabic === 0) syl = "single"
									else if (l.syllabic === 1) syl = "begin"
									else if (l.syllabic === 2) syl = "end"
									else if (l.syllabic === 3) syl = "middle"
									xml += '        <lyric>\n'
									xml += '          <syllabic>' + syl + '</syllabic>\n'
									xml += '          <text>' + escapeXml(txt) + '</text>\n'
									xml += '        </lyric>\n'
								}
							}

							xml += '      </note>\n'
						}
					} else if (e.type === Element.REST) {
						var rest = e
						var dur = rest.duration ? rest.duration.ticks : 1
						xml += '      <note>\n'
						xml += '        <rest/>\n'
						xml += '        <duration>' + dur + '</duration>\n'
						xml += '        <type>quarter</type>\n'
						xml += '      </note>\n'
					}

					cursor.next()
				}

				xml += '    </measure>\n'
			} else {
				cursor.next()
			}
		}

		xml += '  </part>\n'
		xml += '</score-partwise>\n'
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

		Label {
			text: curScore ? (curScore.title || "Untitled") + " \u00B7 " + curScore.nmeasures + " measures" : "No score open"
			color: "#94a3b8"
			font.pixelSize: 11
		}
	}
}
