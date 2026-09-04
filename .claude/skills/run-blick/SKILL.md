---
name: run-blick
description: Build, install, launch, and stream debug output for the Blick iOS app on David's paired iPhone 15.
---

# Running Blick on the device

This is the verified flow for building Blick, installing it on David's
paired iPhone 15, launching it, and capturing debug output. Use this
instead of rediscovering — the device identifiers, log-capture gotchas,
and buffering pitfalls are baked in.

## Devices

Two different identifiers exist for the same phone. They are NOT
interchangeable.

| Use with | Identifier | Source |
|---|---|---|
| `xcodebuild -destination` | `00008120-001019EA18834032` (hardware UDID) | `xcodebuild -showdestinations` |
| `xcrun devicectl device ...` | `8BE2DDC5-4B5A-5ECF-BD04-3549096ADABC` (devicectl id) | `xcrun devicectl list devices` |

If you get `Unable to find a device matching the provided destination
specifier`, you've used the devicectl id where xcodebuild expected the
hardware UDID.

## Build

BlickKit and BlickGraph are local Swift Packages, so the iOS
scheme builds them per-consumer-platform in one pass. No pre-build
step is needed.

```bash
xcodebuild -project /Users/anderix/email/blick/Blick.xcodeproj \
  -scheme Blick -configuration Debug \
  -destination "platform=iOS,id=00008120-001019EA18834032" \
  -allowProvisioningUpdates build
```

`-allowProvisioningUpdates` lets Xcode refresh the provisioning profile
if needed. Without it you'll hit signing errors after profile renewals.

The DerivedData hash changes whenever the project path changes (it did
after the move to `~/email/blick`), so the install step resolves it at
run time rather than hardcoding it. Resolve it by newest match, never
with a bare `Blick-*` glob — see the warning under Install.

## Install

```bash
APP=$(ls -dt ~/Library/Developer/Xcode/DerivedData/Blick-*/Build/Products/Debug-iphoneos/Blick.app | head -1)
xcrun devicectl device install app \
  --device 8BE2DDC5-4B5A-5ECF-BD04-3549096ADABC "$APP"
```

**Never pass the bare `Blick-*` glob to `devicectl`.** Xcode keeps a
separate DerivedData directory per project *path*, and stale ones from
earlier paths survive a move. When more than one matches, the glob expands
to multiple arguments and devicectl fails with `Unexpected argument`.

This failure is worse than it looks, and it cost a false verification once.
A failed install does not stop a subsequent `process launch` — the launch
succeeds against the **previously installed** build, so the phone comes up
looking healthy while running old code. Always confirm the install printed
`App installed:` before launching, and treat a launch that follows a failed
install as testing nothing.

`ls -dt ... | head -1` picks the most recently built product, which is
correct even when several directories legitimately exist. If a stale
directory is just dead weight, check what project path it belongs to and
delete it:

```bash
for d in ~/Library/Developer/Xcode/DerivedData/Blick-*/; do
  echo "$d"; /usr/libexec/PlistBuddy -c "Print :WorkspacePath" "$d/info.plist" 2>/dev/null
done
```

## Launch

Plain launch (no log capture, returns immediately):

```bash
xcrun devicectl device process launch \
  --device 8BE2DDC5-4B5A-5ECF-BD04-3549096ADABC \
  com.excelano.checkin
```

Launch with stdout/stderr attached (devicectl waits for the app to
terminate):

```bash
xcrun devicectl device process launch \
  --device 8BE2DDC5-4B5A-5ECF-BD04-3549096ADABC \
  --console com.excelano.checkin
```

## Capturing debug output

**`os.Logger` does NOT flow through `--console`.** os.Logger writes to
the device's unified system log, which is a separate channel from
stdout/stderr. `--console` captures only the standard streams.

Two paths to capture os.Logger output:

1. Xcode > Window > Devices and Simulators > select device > Open Console.
   Filters on the unified log from the device. Reliable, but interactive.
2. For automated capture from a script, switch to `print()` temporarily.
   `print()` writes to stdout, which `--console` captures.

For ad-hoc diagnostics from a script, the `print()` path is much
faster than wiring up the unified log:

```swift
#if DEBUG
print("CHECKIN-DEBUG body bytes: \(rawBytes)")
#endif
```

Prefix with a unique token like `CHECKIN-DEBUG` so you can grep
cleanly out of the full console stream.

### Pre-wired hooks

Existing `#if DEBUG` print hooks already in the codebase, ready to
use without modifying code:

| Location | What it prints |
|---|---|
| `Blick/Views/MessagePreviewSheet.swift` → `loadBodyIfNeeded()` | Email body HTML length, `cid:` image-reference count, and per-part inline/Content-ID/byte-count — for the "renders as text not HTML" and "inline image didn't paint" classes of bug |
| `Blick/Services/GraphClient.swift` → `fetchEmailContent(id:)` | Logs a non-fatal `fetchAttachmentParts failed` with the Graph error body when the best-effort attachment call throws |
| `Blick/Services/GraphClient.swift` → `fetchMailFolders()` | Elapsed seconds for the folder fetch behind Move to…, plus top-level and child folder counts — separates a slow Graph call from a slow token refresh when the picker spins |
| `Blick/Services/Inbox.swift` → `disposeEmail(_:to:verb:)` | The Graph status and body behind a "Couldn't archive/move/delete that message" banner, which otherwise only reaches `os.Logger` |

Add more here as they get added. Removing them is cheap; re-adding
under deadline pressure is not.

## Streaming captured logs

When piping the `--console` output through `grep`, **always use
`grep --line-buffered`**. Without it, the pipe buffers and the file
fills only when many KB accumulate — which means short bursts of
debug output never appear.

Wrong (silent):

```bash
xcrun devicectl device process launch --console ... | grep "CHECKIN-DEBUG"
```

Right:

```bash
xcrun devicectl device process launch --console ... > /tmp/blick.out 2>&1 &
tail -f /tmp/blick.out | grep --line-buffered "CHECKIN-DEBUG"
```

The two-step approach (let the launcher write everything to a file,
then `tail -f | grep --line-buffered` on the file) avoids the inline
pipe buffering entirely.

## Verifying device readiness

Before any of the above, confirm the phone is paired and reachable:

```bash
xcrun devicectl list devices
```

If the phone shows as `unavailable`, prompt David to wake it and
unlock. devicectl needs the device unlocked to install apps.

## End-to-end one-liner

For the common "build, install, launch, get out" pattern:

```bash
xcodebuild -project /Users/anderix/email/blick/Blick.xcodeproj \
  -scheme Blick -configuration Debug \
  -destination "platform=iOS,id=00008120-001019EA18834032" \
  -allowProvisioningUpdates build 2>&1 | tail -3 \
&& APP=$(ls -dt ~/Library/Developer/Xcode/DerivedData/Blick-*/Build/Products/Debug-iphoneos/Blick.app | head -1) \
&& xcrun devicectl device install app \
     --device 8BE2DDC5-4B5A-5ECF-BD04-3549096ADABC "$APP" 2>&1 | tail -3 \
&& xcrun devicectl device process launch \
     --device 8BE2DDC5-4B5A-5ECF-BD04-3549096ADABC \
     com.excelano.checkin 2>&1 | tail -2
```

About 30 seconds end-to-end on a warm DerivedData cache.

## Tests

The unit tests live in the `BlickKit` package (`BlickKit/Tests/BlickKitTests`),
not in an app test target — there is no `BlickTests` scheme. Run them from the
package directory against a simulator; `swift test` on the Mac host fails
because `Brand` uses SwiftUI `Color` with no macOS platform declared:

```bash
cd /Users/anderix/email/blick/BlickKit
xcodebuild test -scheme BlickKit \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" 2>&1 \
  | grep -E "error:|Suite .* (passed|failed)|Test run with|\*\* TEST"
```

For widget-only changes, build with `-scheme BlickWidgetExtension`.
