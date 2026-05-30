loaphuong — Vietnamese singing synthesis for MuseScore
====================================================

Files:
  loaphuong.exe          Backend server (standalone, no runtime deps)
  loaphuong.qml          MuseScore QML plugin
  loaphuong.vst3/        VST3 audio plugin (optional)
  deploy.bat             One-click installer

Install:
  1. Run deploy.bat (copies QML to MuseScore Plugins, VST3 to Documents\VST3)
  2. In MuseScore: Plugins → Manage Plugins → enable loaphuong
  3. Set NEUTRINO_ROOT environment variable, or put NEUTRINO/ folder next to .exe
  4. Run loaphuong.exe (starts backend on :3100)
  5. In MuseScore: Plugins → loaphuong → Render

NEUTRINO setup:
  Download from: https://studio-neutrino.com/download/
  Expected structure:
    NEUTRINO/
    ├── bin/neutrino.exe
    └── model/<voice_name>/

Troubleshooting:
  - VST3 not detected? Install to C:\Program Files\Common Files\VST3\ instead
  - Backend won't start? Set NEUTRINO_ROOT=C:\path\to\NEUTRINO
