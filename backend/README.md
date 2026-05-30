# loaphuong Backend

The backend lives at `../loaphuong/` — a standalone NEUTRINO SVS wrapper
that embeds cephome directly (MusicXML→phonemes→WAV).

## Run

```bash
# Development (Bun)
cd ../loaphuong && NEUTRINO_ROOT=/path/to/NEUTRINO bun src/main.ts

# Production (compiled binary)
cd ../loaphuong && NEUTRINO_ROOT=/path/to/NEUTRINO ./loaphuong-linux
```

Serves on `http://127.0.0.1:3100`.

## API

| Endpoint | Method | Description |
|---|---|---|
| `/api/render` | POST | MusicXML → WAV pipeline |
| `/api/render-stream` | POST | SSE progress events |
| `/api/status` | GET | Health + daemon status |
| `/api/voices` | GET | Available NEUTRINO voice models |
