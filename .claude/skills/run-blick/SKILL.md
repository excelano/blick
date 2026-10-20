---
name: run-blick
description: Build, install, launch, and stream debug output for the Blick iOS app on David's paired iPhone 15, from the Debian box through the Mac Mini.
---

# Running Blick on the device

Xcode lives on the Mac Mini, so everything here runs there. `xcremote` (in
`~/bin`, run from the repo root) rsyncs `~/blick` to `~/.cache/xcremote/blick`
on the Mac and runs `xcodebuild` against that copy. Edits are made on the
Debian box; the Mac's `~/email/blick` is not used.

## Build, install, launch

```bash
xcremote phone
```

It builds Debug for the paired iPhone, installs, and launches `com.excelano.checkin`.
The watch app is embedded, so the phone install carries it; the watch updates
after a minute or two. Run it as `! xcremote phone` from a session: it asks for
the Mac login password to unlock the login keychain, prints nothing while it
waits, and echoes nothing as you type.

The simulator paths need no password: `xcremote build` builds the app scheme for
the iPhone 17 Pro Max simulator, and `xcremote shot [file]` pulls a screenshot of
the booted simulator.

## Devices

Two identifiers exist for the same phone and are not interchangeable.

| Use with | Identifier |
|---|---|
| `xcodebuild -destination` | `00008120-001019EA18834032` (hardware UDID) |
| `xcrun devicectl device ...` | `8BE2DDC5-4B5A-5ECF-BD04-3549096ADABC` (CoreDevice id) |

`xcremote phone` finds both itself. If either is missing it stops with "no
connected iPhone": wake and unlock the phone. The Series 9 watch shows as
unavailable to `devicectl` from the Mac; watch behaviour is checked on the wrist.

## Capturing debug output

Launch with the console attached on the Mac, writing to a file, and read the file
from Debian:

```bash
ssh macmini 'xcrun devicectl device process launch --console \
  --device 8BE2DDC5-4B5A-5ECF-BD04-3549096ADABC com.excelano.checkin' > /tmp/blick.out 2>&1 &
tail -f /tmp/blick.out | grep --line-buffered "CHECKIN-DEBUG"
```

`os.Logger` does not flow through `--console`, which carries only stdout and
stderr. For ad-hoc diagnostics use a temporary `#if DEBUG` `print()` with a
unique prefix such as `CHECKIN-DEBUG`, and always grep with `--line-buffered`;
without it the pipe holds short bursts back.

Existing `#if DEBUG` print hooks, usable without changing code:

| Location | What it prints |
|---|---|
| `Blick/Views/MessagePreviewSheet.swift` → `loadBodyIfNeeded()` | Email body HTML length, `cid:` image-reference count, and per-part inline/Content-ID/byte-count |
| `Blick/Services/GraphClient.swift` → `fetchEmailContent(id:)` | A non-fatal `fetchAttachmentParts failed` with the Graph error body |
| `Blick/Services/GraphClient.swift` → `fetchMailFolders()` | Elapsed seconds for the folder fetch behind Move to…, plus folder counts |
| `Blick/Services/Inbox.swift` → `disposeEmail(_:to:verb:)` | The Graph status and body behind a "Couldn't archive/move/delete that message" banner |

## Tests

The unit tests live in the `BlickKit` package, not an app target:

```bash
xcremote test BlickKit
```

`swift test` on the Mac host fails because `Brand` uses SwiftUI `Color` with no
macOS platform declared, so the tests run on the simulator. For widget-only
changes, build with `XCREMOTE_SCHEME=BlickWidgetExtension xcremote build`.
