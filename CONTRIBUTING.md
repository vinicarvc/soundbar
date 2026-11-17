# Contributing

Thanks for helping out! 

1. Fork and create a branch (`feat/...` or `fix/...`).
2. Build with `./build.sh` and run `open build/SoundBar.app`.
3. Keep changes focused; describe how you tested them (devices, apps, macOS version).
4. Open a pull request.

Code layout: `CoreAudioHelpers.swift` (thin Core Audio wrappers), `AppTap.swift` (per-app process tap + gain),
`AudioModel.swift` (state, polling, settings), `ContentView.swift` (SwiftUI UI).

Ideas welcome: localization, per-app mute, volume above 100%, launch at login, keyboard shortcuts.
