# OnePlus Buds 4 for macOS

Native (SwiftUI) controller for **OnePlus Buds 4** on macOS — a real app window plus a
menu-bar item, in the style of a modern control panel.

## What it does
- Shows per-earbud and case battery levels, with a headline reading for the weaker bud.
- Switches noise control: Off, Transparency, ANC (Mild / Moderate / Max).
- Shows an AirPods-style floating battery popup when the buds connect.
- Connects/disconnects the buds directly.
- Ships two surfaces sharing one connection:
  - a **main window** — resizable, with the full controls, reachable from the Dock;
  - a **menu-bar item** — the compact version, for a quick glance.

  The menu-bar item disappears along with the buds when they are away; the window and
  Dock icon stay, so the app is never unreachable.

## Requirements
- macOS 26+
- Xcode installed (Command Line Tools are enough to build)
- Earbuds already paired with the Mac

## Build
```sh
./build.sh
open "OnePlus Buds 4.app"
```

## Install (disk image)
Builds the app and packages it into a drag-to-Applications DMG:
```sh
./make-dmg.sh
open "dist/OnePlus Buds 4.dmg"
```
The image opens with the app beside an Applications shortcut, a styled background and
the app icon as the volume icon.

## Generated artwork
The icon and the disk-image background are generated, not hand-drawn, so they can be
regenerated after a design change:
```sh
swift Tools/make-icon.swift             # -> Resources/AppIcon.icns
swift Tools/make-dmg-background.swift   # -> Resources/dmg-background{,@2x}.png
```
Both are committed, so `./build.sh` and `./make-dmg.sh` work without running them.

## Privacy
Bluetooth is used only to talk to paired OnePlus Buds 4. No network or analytics calls are made.

## Layout
| Path | |
| --- | --- |
| `Sources/BudsBar/App.swift` | App scenes, the menu-bar item, the window bridge |
| `Sources/BudsBar/Buds.swift` | Bluetooth state and the vendor control channel |
| `Sources/BudsBar/Protocol.swift` | `oppointeraction` wire format |
| `Sources/BudsBar/Theme.swift` | Colours and the shared surface styling |
| `Sources/BudsBar/Controls.swift` | Reusable controls shared by the window and popover |
| `Sources/BudsBar/MainWindowView.swift` | The main window |
| `Sources/BudsBar/PanelView.swift` | The menu-bar popover |

## License
MIT (see [LICENSE](./LICENSE)).

Based on the open-source "Realme TWS Mac Controller" project (MIT).
