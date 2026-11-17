# SoundBar

A native macOS menu bar app (Swift + SwiftUI) to control sound: pick the output device, set the master volume,
and set **volume and output device per app**.

> 🇧🇷 [Leia em português](README.pt-BR.md)

## Features
- Master volume and mute for the current output
- Switch the default output device and the system-sounds device
- Per-app volume slider and per-app output device (e.g. Spotify on speakers, Chrome on AirPods)
- Helper processes grouped under their parent app (Chrome Helper → Google Chrome)
- Per-app settings persisted between launches
- No kernel extension or virtual driver — uses Core Audio process taps

## Requirements
macOS 14.2 or later, Xcode command line tools (Swift 5.9+).

## Build & run
```bash
git clone https://github.com/<you>/soundbar.git
cd soundbar
./build.sh
open build/SoundBar.app
```
On first per-app change, macOS asks for **audio capture** permission (System Settings → Privacy & Security).

## How it works
For an app with a non-default volume/device, SoundBar creates a muted-when-tapped
[`CATapDescription`](https://developer.apple.com/documentation/coreaudio/catapdescription) on its processes, wraps the tap and the
chosen output in a private aggregate device, and an IOProc copies the tap audio to the output scaled by the gain.
Apps left at 100% / default output are never touched.

## Known limitations
- Aggregate device also exposes the output's input side; with Bluetooth headsets this may show the mic indicator.
- Apps whose audio runs in a separate system process (e.g. Safari/WebKit) may not be attributed correctly.
- System sounds only have a device picker, no slider.
- UI strings are currently in Portuguese; localization PRs welcome.

## License
[MIT](LICENSE)
