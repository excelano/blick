# CLAUDE.md — Blick (excelano/blick)

Project-specific guidance for Blick. Global working style, writing standards, and
language preferences live in `~/.claude/CLAUDE.md` (loads in every session); the
Apple-apps notes (Xcode, signing, Swift attribution header) live in the
email-family `~/email/CLAUDE.md`. Both load alongside this file.

---

Microsoft 365 app for iOS — meetings, mail, Teams chats, and presence on iPhone, iPad, and Apple Watch. Repo at `~/email/blick/`, GitHub repo `excelano/blick`. Every path, target, package, scheme, and Swift symbol carries the Blick name; the identifiers that deliberately still say `checkin` are listed below.

## Identifiers that stay `checkin` (do not rename)

The rename on 2026-09-02 took the whole codebase from CheckIn to Blick and deliberately left every *persisted* identifier alone. These are stored outside the app — by the App Store, by Entra, by WidgetKit, by Control Center — so renaming one silently breaks something a user has already set up. The rule is: rename symbols and paths freely, never a string literal.

- `com.excelano.checkin` and every bundle ID derived from it (`.CheckInWidget`, `.watchkitapp`, `.watchkitapp.widgets`). Changing it creates a new App Store record and orphans every install.
- `group.com.excelano.checkin` and `group.com.excelano.checkin.watch`, plus the keychain access group. These carry the widget/watch snapshot and the MSAL token cache; changing one forces every device to sign in again.
- `msauth.com.excelano.checkin://auth` and the widget's `msauth.com.excelano.checkin.CheckInWidget://auth`, both registered in the Azure `blick` app registration.
- `com.excelano.checkin.refresh`, the `BGTaskScheduler` identifier, which must match `BGTaskSchedulerPermittedIdentifiers` in Info.plist.
- The WidgetKit `kind` strings: `"CheckInWidget"` in `BlickWidget/BlickWidget.swift` and `"CheckInWatchCorner"`, `"CheckInWatchRectangular"`, `"CheckInWatchCircular"`, `"CheckInWatchInline"` in `BlickWatchWidget/BlickWatchWidget.swift`. Rename one and the widget or complication vanishes from every home screen and watch face that already has it.
- The eight `ControlKind` values (`com.excelano.checkin.control.*`), for the same reason — a renamed control disappears from Control Center.

The trap worth remembering: `CheckInWidget` was both a Swift type name and the widget's `kind` string, spelled identically. A blanket find-and-replace renames both.

One identifier did slip through that rename and had to be repaired: the local-notification prefix `checkin.meeting.`. Pending notifications live in iOS's store rather than in the app, and `MeetingNotifications.clearAll` cancels by prefix, so the renamed build could no longer see what the previous build had scheduled and every meeting reminder fired twice. It is now `blick.meeting.`, with the old prefix swept via `legacyIdentifierPrefixes`. The lesson generalises past the `com.excelano.*` shape: **anything the app writes into an OS-owned store keyed by a string** — notification identifiers, widget kinds, control kinds, App Group and UserDefaults keys, keychain items — is a persisted identifier even when it looks like an ordinary internal constant. Audit changed *string literals*, not just identifiers matching the bundle ID.

## Swift traps paid for once

`summary?.x = f(summary?.x)` crashes at run time. With optional chaining on the left, Swift opens the write access to `summary` before evaluating the right side, which reads `summary` again, and the exclusivity checker kills the app ("Simultaneous accesses ... modification requires exclusive access"). It only fires on the branch that actually runs the line, which is how four of them hid until an archive of an unread message hit one. Read into a local first, then assign; `Inbox.adjustUnreadEmails(by:)` is the pattern.

Graph's `/move` re-creates the message under a new id, including the move back on undo. Any row restored after an undo must carry the id the move returned, or every later action on it targets an id that no longer resolves.

## Status

Repo's canonical docs are `FEATURES.md` (shipped functionality), `POTENTIAL-FEATURES.md` (the feature backlog — ideas under consideration, not yet committed), `RELEASING.md` (the App Store cut runbook), `PRIVACY.md`, `SELF-HOSTING.md`, and `IT-APPROVAL.md`. Current task comes from conversation, not from this file.

## Tech Stack

- Swift + SwiftUI, iOS 18+.
- Microsoft Graph for mail / Teams / calendar; MSAL for Swift / Apple's auth.

## Privacy posture (non-negotiable)

No analytics SDK, no off-device logger, no telemetry. The only network destinations permitted are Microsoft Graph and Microsoft identity endpoints. The operative rule is that Microsoft tokens are never moved, copied, or synced between devices. Each device that talks to Microsoft authenticates itself directly and holds only its own token, and the only thing that crosses between a user's devices is non-credential data over Apple's on-device transports such as WatchConnectivity. First-party Blick code on a device where the user has authenticated, whether the app process or an app extension such as the widget, may call the permitted endpoints, because nothing new leaves that device. What remains a hard stop, requiring you to pause and confirm, is introducing a backend, a third-party SDK, a new external destination, or any movement of a token off the device that obtained it, which includes exporting it to a watch, syncing it to a server, or letting iCloud Keychain sync the token cache across devices.

The Apple Watch ships in two tiers. The default tier holds no token and makes no Graph calls: the phone fetches and pushes data to the watch over WatchConnectivity, and the watch relays any actions back to the phone, so no tenant can block it, and it is the core watch functionality we build first. An opt-in second tier lets the watch authenticate on its own and store its own device-bound token on the watch, never the phone's token copied over, which unlocks standalone interactivity on cellular. That tier is gated behind a user setting, defaults off, requires an on-device spike to confirm the watchOS interactive sign-in path before we build on it, and falls back silently to the read-only tier when a tenant's Conditional Access blocks the watch.

## Azure / identity

Azure app registration is named `blick`.

## Brand

Tatsiana palette — navy `#0D2D5B` + cyan `#00ADEE`. App icons (light, dark, tinted) live at `~/email/blick/Blick/Assets.xcassets/AppIcon.appiconset/`.
