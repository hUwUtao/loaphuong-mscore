import MuseScore 3.0
import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

MuseScore {
	id: root
	width: 500
	height: 600

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

	// Phoneme override state
	property var phonemeExport: ({})
	property var pinnedOverrides: ({})
	property var notes: []       // output.notes from last response
	property var notePairs: []   // [{id, lyric, phonemes:"s i n", pinned:bool}]

	menuPath: "Plugins.loaphuong.Render Vocal"
	description: "Render vocal track via Loaphuong gen backend"
	version: "0.1.0"
	pluginType: "dialog"
	dockArea: "none"

	function rebuildNotePairs() {
		var pairs = []
		var keys = Object.keys(phonemeExport)
		for (var i = 0; i < keys.length; i++) {
			var id = keys[i]
			var lyric = ""
			for (var j = 0; j < notes.length; j++) {
				if (notes[j].id === id) { lyric = notes[j].lyric || ""; break }
			}
			pairs.push({
				id: id,
				lyric: lyric,
				phonemes: phonemeExport[id].join(" "),
				pinned: !!pinnedOverrides[id]
			})
		}
		notePairs = pairs
	}

	function togglePin(noteId) {
		if (pinnedOverrides[noteId]) {
			var copy = {}
			var keys = Object.keys(pinnedOverrides)
			for (var i = 0; i < keys.length; i++)
				if (keys[i] !== noteId) copy[keys[i]] = pinnedOverrides[keys[i]]
			pinnedOverrides = copy
		} else {
			var copy = {}
			var keys = Object.keys(pinnedOverrides)
			for (var i = 0; i < keys.length; i++)
				copy[keys[i]] = pinnedOverrides[keys[i]]
			copy[noteId] = phonemeExport[noteId]
			pinnedOverrides = copy
		}
		rebuildNotePairs()
	}

	function pinAll() {
		var copy = {}
		var keys = Object.keys(phonemeExport)
		for (var i = 0; i < keys.length; i++)
			copy[keys[i]] = phonemeExport[keys[i]]
		pinnedOverrides = copy
		rebuildNotePairs()
	}

	function unpinAll() {
		pinnedOverrides = ({})
		rebuildNotePairs()
	}

	function hasPins() {
		return Object.keys(pinnedOverrides).length > 0
	}

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

	function getExportPath() {
		return "/tmp/loaphuong_export.musicxml"
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

	function generateMusicXml() {
		var nstaves = curScore.nstaves || 1
		var target = findVocalTrack()
		var info = "target track=" + target + " nstaves=" + nstaves + "\n"

		var exportPath = getExportPath()
		try {
			curScore.startCmd()
			for (var t = 0; t < nstaves * 4; t++) {
				if (t !== target) {
					var dc = curScore.newCursor()
					dc.track = t
					dc.rewind(Cursor.SCORE_START)
					while (dc.segment) {
						var el = dc.element
						if (el) curScore.removeElement(el)
						dc.next()
					}
				}
			}
			var ok = writeScore(curScore, exportPath, "musicxml")
			curScore.endCmd()
			cmd("undo")
			if (ok) {
				info += "writeScore -> " + exportPath
				lastXml = info
				return { path: exportPath, xml: "" }
			}
		} catch (e) {
			try { curScore.endCmd() } catch (_) {}
			try { cmd("undo") } catch (_) {}
			info += "writeScore failed: " + e + "\n"
		}

		info += "Falling back to manual generation\n"
		var sigN = curScore.timesigNumerator || 4
		var sigD = curScore.timesigDenominator || 4
		var div = curScore.division || 480
		var measureLen = div * sigN * 4 / sigD
		var allNotes = []

		var fallbackCursor = curScore.newCursor()
		fallbackCursor.track = target
		fallbackCursor.rewind(Cursor.SCORE_START)
		var segs = 0
		while (fallbackCursor.segment && ++segs < 500) {
			var e = fallbackCursor.element
			if (e && e.type === Element.CHORD && e.notes && e.notes.length > 0) {
				var lrc = e.lyrics && e.lyrics.length > 0 && e.lyrics[0].text ? e.lyrics[0] : null
				allNotes.push({
					tick: fallbackCursor.tick,
					note: e.notes[0],
					dur: e.duration ? e.duration.ticks : 1,
					lyric: lrc
				})
			}
			fallbackCursor.next()
		}
		allNotes.sort(function(a, b) { return a.tick - b.tick })

		var totalTicks = 0
		var ec = curScore.newCursor()
		ec.rewind(Cursor.SCORE_END)
		if (ec.segment) totalTicks = ec.tick
		if (totalTicks <= 0 && allNotes.length > 0)
			totalTicks = allNotes[allNotes.length - 1].tick + measureLen
		if (totalTicks <= 0) totalTicks = measureLen * 10

		var numMeasures = Math.ceil(totalTicks / measureLen)

		var xml = '<?xml version="1.0" encoding="UTF-8"?>\n'
		xml += '<!DOCTYPE score-partwise PUBLIC "-//Recordare//DTD MusicXML 4.0 Partwise//EN"'
			+ ' "http://www.musicxml.org/dtds/partwise.dtd">\n'
		xml += '<score-partwise version="4.0">\n'
		xml += '<part-list><score-part id="P1"><part-name>Voice</part-name></score-part></part-list>\n'
		xml += '<part id="P1">\n'

		var noteIdx = 0
		for (var m = 1; m <= numMeasures; m++) {
			xml += '<measure number="' + m + '">\n'
			if (m === 1) {
				xml += '<attributes>\n'
				xml += '<divisions>' + div + '</divisions>\n'
				xml += '<time><beats>' + sigN + '</beats><beat-type>' + sigD + '</beat-type></time>\n'
				xml += '<clef><sign>G</sign><line>2</line></clef>\n'
				xml += '</attributes>\n'
			}
			var mEnd = m * measureLen
			while (noteIdx < allNotes.length && allNotes[noteIdx].tick < mEnd) {
				var an = allNotes[noteIdx++]
				xml += '<note><pitch><step>' + pitchToStep(an.note.pitch) + '</step>'
					+ '<octave>' + pitchToOctave(an.note.pitch) + '</octave></pitch>'
					+ '<duration>' + an.dur + '</duration><type>quarter</type>'
				if (an.lyric) {
					var syl = ["single","begin","end","middle"][an.lyric.syllabic] || "single"
					xml += '<lyric><syllabic>' + syl + '</syllabic><text>' + escapeXml(an.lyric.text) + '</text></lyric>'
				}
				xml += '</note>\n'
			}
			xml += '</measure>\n'
		}
		xml += '</part>\n</score-partwise>\n'

		info += "measures=" + numMeasures + " notes=" + allNotes.length
		lastXml = info + "\n---\n" + xml.slice(0, 1500)
		return { path: "", xml: xml }
	}

	function escapeXml(s) {
		return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&apos;")
	}

	function startRender(withOverrides) {
		if (rendering || !curScore) return

		rendering = true
		hasRender = false
		progress = 0.0
		phase = "Generating MusicXML..."
		resultPath = ""

		try {
			var result = generateMusicXml()
			var musicXml = result.xml
			var exportPath = result.path
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
							var res = JSON.parse(xhr.responseText)
							resultPath = res.wavPath || ""
							hasRender = true

							// Load phoneme data
							if (res.output) {
								notes = res.output.notes || []
								phonemeExport = res.output.phonemeExport || {}
								if (!withOverrides) pinnedOverrides = ({})
								rebuildNotePairs()
							}

							var pc = Object.keys(phonemeExport).length
							phase = "Done! " + pc + " notes with phonemes"
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

			var bodyObj = { voice: voice, model: model }
			if (withOverrides && hasPins())
				bodyObj.phonemeOverrides = pinnedOverrides
			if (exportPath) {
				bodyObj.scorePath = exportPath
			} else {
				bodyObj.musicxml = musicXml
			}
			var body = JSON.stringify(bodyObj)

			xhr.send(body)
		} catch (e) {
			console.log("loaphuong: render error: " + e)
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
				text: rendering ? "..." : "Render"
				enabled: !rendering && curScore != null
				onClicked: startRender(false)
			}

			Button {
				text: "Re-render"
				enabled: !rendering && hasRender && hasPins()
				highlighted: hasPins()
				onClicked: startRender(true)
			}

			Button {
				text: "Play"
				enabled: hasRender && resultPath !== ""
				onClicked: { if (resultPath) Qt.openUrlExternally("file://" + resultPath) }
			}

			Item { Layout.fillWidth: true }

			Button {
				text: "Pin all"
				enabled: hasRender && !rendering
				onClicked: pinAll()
			}

			Button {
				text: "Unpin"
				enabled: hasRender && !rendering && hasPins()
				onClicked: unpinAll()
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

		// Phoneme table
		Frame {
			Layout.fillWidth: true
			Layout.fillHeight: true
			visible: hasRender && notePairs.length > 0
			clip: true
			padding: 4

			ListView {
				id: phonemeList
				anchors.fill: parent
				model: notePairs
				spacing: 2
				clip: true

				delegate: RowLayout {
					width: phonemeList.width
					spacing: 6
					height: 22

					Label {
						text: modelData.id
						color: "#64748b"
						font.pixelSize: 10
						font.family: "monospace"
						Layout.preferredWidth: 70
					}

					Label {
						text: modelData.lyric
						font.pixelSize: 11
						font.bold: true
						Layout.preferredWidth: 50
					}

					Label {
						text: modelData.phonemes
						color: "#a78bfa"
						font.pixelSize: 10
						font.family: "monospace"
						Layout.fillWidth: true
						elide: Text.ElideRight
					}

					Button {
						text: modelData.pinned ? "\u25C9" : "\u25CB"
						flat: true
						implicitWidth: 24
						implicitHeight: 20
						onClicked: togglePin(modelData.id)
					}
				}
			}
		}

		// Debug panel
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
					text: "Server:\n" + lastError
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
