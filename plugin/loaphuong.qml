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
		var measureLen = div * sigN * 4 / sigD

		// Scan all tracks to find chords
		var info = "scanning all tracks:\n"
		var nstaves = curScore.nstaves || 1
		var allNotes = []

		for (var t = 0; t < nstaves * 4; t++) {
			var cursor = curScore.newCursor()
			cursor.track = t
			cursor.rewind(Cursor.SCORE_START)
			var segs = 0, found = 0
			while (cursor.segment && ++segs < 100) {
				var e = cursor.element
				if (e && e.type === Element.CHORD && e.notes && e.notes.length > 0) {
					found++
					var lrc = null
					if (e.lyrics && e.lyrics.length > 0 && e.lyrics[0].text)
						lrc = e.lyrics[0]
					allNotes.push({
						tick: cursor.tick, track: t,
						note: e.notes[0],
						dur: e.duration ? e.duration.ticks : 1,
						lyric: lrc
					})
					if (segs <= 5)
						info += "  track" + t + " seg" + segs + " t=" + cursor.tick
							+ " pitch=" + e.notes[0].pitch
							+ (lrc ? " lyric=" + lrc.text : "") + "\n"
				}
				cursor.next()
			}
			if (found > 0)
				info += "track" + t + ": " + found + " chords\n"
		}

		// Sort all notes by tick
		allNotes.sort(function(a, b) { return a.tick - b.tick })

		// Determine total ticks
		var totalTicks = 0
		var ec = curScore.newCursor()
		ec.rewind(Cursor.SCORE_END)
		if (ec.segment)
			totalTicks = ec.tick
		if (totalTicks <= 0 && allNotes.length > 0)
			totalTicks = allNotes[allNotes.length - 1].tick + measureLen
		if (totalTicks <= 0)
			totalTicks = measureLen * 10

		var numMeasures = Math.ceil(totalTicks / measureLen)
		info += "\nmeasures=" + numMeasures + " totalTicks=" + totalTicks
			+ " measureLen=" + measureLen

		// Generate MusicXML with proper measure boundaries
		var xml = '<?xml version="1.0" encoding="UTF-8"?>\n'
		xml += '<!DOCTYPE score-partwise PUBLIC "-//Recordare//DTD MusicXML 4.0 Partwise//EN"'
			+ ' "http://www.musicxml.org/dtds/partwise.dtd">\n'
		xml += '<score-partwise version="4.0">\n'
		xml += '<part-list>\n'
		xml += '<score-part id="P1"><part-name>Voice</part-name></score-part>\n'
		xml += '</part-list>\n'
		xml += '<part id="P1">\n'

		var noteIdx = 0
		for (var m = 1; m <= numMeasures; m++) {
			xml += '<measure number="' + m + '">\n'
			if (m === 1) {
				xml += '<attributes>\n'
				xml += '<divisions>' + div + '</divisions>\n'
				xml += '<time>\n'
				xml += '<beats>' + sigN + '</beats>\n'
				xml += '<beat-type>' + sigD + '</beat-type>\n'
				xml += '</time>\n'
				xml += '<clef>\n'
				xml += '<sign>G</sign>\n'
				xml += '<line>2</line>\n'
				xml += '</clef>\n'
				xml += '</attributes>\n'
			}

			var mStart = (m - 1) * measureLen
			var mEnd = m * measureLen
			while (noteIdx < allNotes.length && allNotes[noteIdx].tick < mEnd) {
				var an = allNotes[noteIdx]
				xml += '<note>\n'
				xml += '<pitch>\n'
				xml += '<step>' + pitchToStep(an.note.pitch) + '</step>\n'
				xml += '<octave>' + pitchToOctave(an.note.pitch) + '</octave>\n'
				xml += '</pitch>\n'
				xml += '<duration>' + an.dur + '</duration>\n'
				xml += '<type>quarter</type>\n'
				if (an.lyric) {
					var syl = ["single","begin","end","middle"][an.lyric.syllabic] || "single"
					xml += '<lyric>\n'
					xml += '<syllabic>' + syl + '</syllabic>\n'
					xml += '<text>' + escapeXml(an.lyric.text) + '</text>\n'
					xml += '</lyric>\n'
				}
				xml += '</note>\n'
				noteIdx++
			}

			xml += '</measure>\n'
		}

		xml += '</part>\n'
		xml += '</score-partwise>\n'

		lastXml = info + "\n\n---\n\nMusicXML:\n" + xml.slice(0, 1500)
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
