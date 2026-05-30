# loaphuong-mscore

Compound vocal instrument for MuseScore: QML plugin + VST3 playback + gen backend. Vietnamese singing synthesis using cephome engine.

## Architecture

```
MuseScore
├── QML plugin (plugin/loaphuong.qml)     UI: config, render button, progress chips
└── VST3 (target/release/*.vst3)          Cached WAV playback, transport-synced
        │
        ▼
  loaphuong Backend (../loaphuong/)        (:3100)
  ├── cephome submodule (cephome/engine/)  MusicXML→phoneme pipeline
  └── NEUTRINO N.Engine                    phonemes→WAV
```

**loaphuong** (`../loaphuong/`) is the full backend — NEUTRINO wrapper embedding cephome.

## Repo Structure

```
loaphuong-mscore/
├── plugin/              MuseScore QML plugin
├── vst3/                Rust VST3 (nih-plug) cached playback
├── backend/             Launcher for ../loaphuong backend
├── AGENTS.md            This file
└── ...
```

## Output Contract (`render.json`)

The gen model reads this, fills `audio` field:

```json
{
  "format": "cephome-render-v1",
  "notes": [{ "tick": 0, "midi": 60, "lyric": "Nào", "dynamic": "p" }],
  "phones": [{
    "startNs": 0, "endNs": 400000,
    "phoneme": "n", "class": "c", "role": "pre",
    "midi": 60, "lyric": "Nào", "tone": 1,
    "expression": { "energy": 70, "vibratoRateHz": 5.2, "tonalPitchOffset": -0.3 }
  }],
  "audio": null  // ← fill after gen: { "format": "wav", "sampleRate": 48000, "path": "..." }
}
```

## Dependencies

- **cephome engine** at `../cephome/` — Bun runtime, see `../cephome/AGENTS.md`
- **nih-plug** for VST3 — `crates.io/crates/nih-plug`
- **Bun** for backend server
- **Rust** for VST3 plugin

## Key Commands (TBD — fill as you build)

```bash
# Start gen backend (dev)
NEUTRINO_ROOT=/path/to/NEUTRINO bun run ../loaphuong/src/main.ts

# Start gen backend (compiled)
NEUTRINO_ROOT=/path/to/NEUTRINO ../loaphuong/loaphuong-linux

# Build VST3
cd vst3 && cargo run --package xtask -- bundle loaphuong --release

# Install QML plugin
cp plugin/loaphuong.qml ~/Documents/MuseScore4/Plugins/loaphuong/
```

## QML Plugin

See `plugin/loaphuong.qml`. Key behavior:
- Reads score via `curScore.writeScore()` → exports MusicXML
- POSTs to backend `/api/render` with file path
- Shows progress chips per phrase
- On completion, VST3 loads cached WAV from known path

## VST3

Trivial — just a cached WAV player:
- `process()` reads from preloaded ring buffer, syncs to MuseScore transport tick
- No gen, no IPC in audio thread
- Hot-reloads WAV when QML signals new render ready

## Gen Backend

Managed by `../loaphuong/` — NEUTRINO wrapper embedding cephome.
- POST `/api/render` — MusicXML → WAV pipeline
- POST `/api/render-stream` — SSE progress events
- GET `/api/status` — Health check
- GET `/api/voices` — List voice models

## Style

Match cephome conventions: tabs, double quotes, trailing semicolons, no comments unless non-obvious.
