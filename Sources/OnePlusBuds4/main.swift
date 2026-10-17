// The whole executable. The app lives in the `BudsBarKit` library so the protocol and the
// views can be exercised by `swift test`; all that is left for the binary to do is start it.
//
// `BudsBar.launch()` also intercepts `--selfcheck` here, before NSApplication exists, so a
// protocol check never runs inside a live app — which is what made the original crash take
// the running app down with it.
import BudsBarKit

BudsBar.launch()
