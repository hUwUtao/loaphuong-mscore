# Loaphuong MuseScore Plugin

QML plugin to render vocal tracks via the gen backend.

## Install

1. Copy `loaphuong.qml` to MuseScore plugins folder:
   - Linux:   `~/Documents/MuseScore4/Plugins/loaphuong/loaphuong.qml`
   - macOS:   `~/Documents/MuseScore4/Plugins/loaphuong/loaphuong.qml`
   - Windows: `%USERPROFILE%\Documents\MuseScore4\Plugins\loaphuong\loaphuong.qml`

2. Enable plugin in MuseScore:
   - `Plugins → Manage Plugins…`
   - Find "loaphuong" → Enable

3. Start gen backend:
   ```bash
   bun run backend/index.ts
   ```

4. Open a score with lyrics, run plugin:
   - `Plugins → loaphuong → Render Vocal`

## Output Contract

See `AGENTS.md` for the full `render.json` spec.
