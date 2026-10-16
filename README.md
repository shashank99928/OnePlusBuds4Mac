# OnePlus Buds 4 for macOS

Native (SwiftUI) menu-bar controller for **OnePlus Buds 4** on macOS.

## What it does
- Shows per-earbud and case battery levels.
- Switches noise control: Off, Transparency, ANC (Mild / Moderate / Max).
- Shows an AirPods-style floating battery popup when the buds connect.
- Connects/disconnects the buds directly.
- Menu-bar only app (no Dock icon).

## Requirements
- macOS 26+
- Xcode installed (Command Line Tools are enough to build)
- Earbuds already paired with the Mac

## Build
```sh
./build.sh
open "OnePlus Buds 4.app"
```

## Privacy
Bluetooth is used only to talk to paired OnePlus Buds 4. No network or analytics calls are made.

## License
MIT (see [LICENSE](./LICENSE)).

Based on the open-source "Realme TWS Mac Controller" project (MIT).
