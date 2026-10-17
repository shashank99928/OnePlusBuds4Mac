// The whole executable. The app lives in the `BudsBarKit` library so the protocol and the
// views can be exercised by `swift test`; all that is left for the binary to do is start it.
//
// `BudsBar.launch()` also intercepts `--selfcheck` and `--render-snapshots` here, before
// NSApplication exists, so neither job runs inside a live app — which is what made the
// original self-check crash take the running app down with it.
//
// The `assumeIsolated` is honest rather than a workaround: a process's top-level code runs on
// the main thread before any concurrency exists, and the compiler cannot see that from here.
import BudsBarKit

MainActor.assumeIsolated {
    BudsBar.launch()
}
