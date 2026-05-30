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

	function findNoteIdxByTick(tick) {
		for (var i = 0; i < notes.length; i++)
			if (notes[i].tick === tick) return i
		return -1
	}

	// Write phonemes as Lyric Line 2 — match by tick
	function writePhonemesToScore(exportData) {
		var target = findVocalTrack()
		var cursor = curScore.newCursor()
		cursor.track = target
		cursor.rewind(Cursor.SCORE_START)
		var written = 0
		var safety = 0
		curScore.startCmd()
		while (cursor.segment && ++safety < 500) {
			var e = cursor.element
			if (e && e.type === Element.CHORD && e.notes && e.notes.length > 0) {
				var ni = findNoteIdxByTick(cursor.tick)
				if (ni >= 0) {
					var nid = notes[ni].id
					var phones = exportData[nid]
					if (phones && phones.length > 0) {
						var txt = phones.join(" ")
						try {
							if (e.lyrics && e.lyrics.length > 1 && e.lyrics[1]) {
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
				}
			}
			cursor.next()
		}
		curScore.endCmd()
		lyricNoteCount = written
	}

	// Read Lyric Line 2 — iterate ALL chords to align with MusicXML order
	function readPhonemesFromScore() {
		var target = findVocalTrack()
		var overrides = []
		var cursor = curScore.newCursor()
		cursor.track = target
		cursor.rewind(Cursor.SCORE_START)
		var safety = 0
		while (cursor.segment && ++safety < 500) {
			var e = cursor.element
			if (e && e.type === Element.CHORD && e.notes && e.notes.length > 0) {
				var txt = ""
				try {
					if (e.lyrics && e.lyrics.length > 1 && e.lyrics[1] && e.lyrics[1].text)
						txt = e.lyrics[1].text
				} catch (_) {}
				overrides.push(txt.length > 0 ? txt.split(" ") : [])
			}
			cursor.next()
		}
		return overrides
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

	function analyzePhonemes() {
		if (rendering || !curScore) return
		rendering = true
		progress = 0.0
		phase = "Analyzing phonemes..."
		lastError = ""

		try {
			var result = generateMusicXml()
			var bodyObj = { musicxml: result.xml || undefined, scorePath: result.path || undefined }
			doRequest("/api/phonemes", bodyObj, function(err, res) {
				if (err) {
					lastError = err
					phase = "Error"
				} else {
					var exportData = res.phonemeExport || {}
					writePhonemesToScore(exportData)
					phase = Object.keys(exportData).length + " notes written as Lyric 2"
				}
				rendering = false
				progress = 1.0
			})
		} catch (e) {
			phase = "Error: " + e
			rendering = false
		}
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

			var result = generateMusicXml()
			if (result.path) bodyObj.scorePath = result.path
			else bodyObj.musicxml = result.xml

			lastXml = result.xml ? (result.xml.length > 2000 ? result.xml.slice(0, 2000) + "..." : result.xml) : result.path
			lastError = ""
			phase = "Rendering..."

			doRequest("/api/render", bodyObj, function(err, res) {
				if (err) {
					lastError = err
					phase = "Error"
				} else {
					resultPath = res.wavPath || ""
					hasRender = true
					// Re-write phonemes from fresh export
					if (res.output && res.output.phonemeExport)
						writePhonemesToScore(res.output.phonemeExport)
					phase = "Done! " + (res.output ? Object.keys(res.output.phonemeExport || {}).length + " notes" : "")
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
				text: "Analyze"
				enabled: !rendering && curScore != null
				onClicked: analyzePhonemes()
			}

			Button {
				text: "Render"
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
