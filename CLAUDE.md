# CLAUDE.md — Blick (excelano/checkin)

Project-specific guidance for Blick. General working style, writing standards,
language preferences, and Mac/Xcode notes live in the home-root `~/CLAUDE.md`,
which loads alongside this file.

---

Microsoft 365 app for iOS — meetings, mail, Teams chats, and presence on iPhone, iPad, and Apple Watch. Repo at `~/checkin/` (local dir stays `checkin`; the GitHub repo is `excelano/blick`).

## Status

Repo's canonical docs are `FEATURES.md` (shipped functionality), `POTENTIAL-FEATURES.md` (the feature backlog — ideas under consideration, not yet committed), `RELEASING.md` (the App Store cut runbook), `PRIVACY.md`, `SELF-HOSTING.md`, and `IT-APPROVAL.md`. Current task comes from conversation, not from this file.

## Tech Stack

- Swift + SwiftUI, iOS 17+.
- Microsoft Graph for mail / Teams / calendar; MSAL for Swift / Apple's auth.

## Privacy posture (non-negotiable)

No analytics SDK, no off-device logger, no telemetry. The only network destinations permitted are Microsoft Graph and Microsoft identity endpoints. The operative rule is that Microsoft tokens are never moved, copied, or synced between devices. Each device that talks to Microsoft authenticates itself directly and holds only its own token, and the only thing that crosses between a user's devices is non-credential status data over Apple's on-device transports such as WatchConnectivity. First-party Blick code on a device where the user has authenticated, whether the app process or an app extension such as the widget, may call the permitted endpoints, because nothing new leaves that device. What remains a hard stop, requiring you to pause and confirm, is introducing a backend, a third-party SDK, a new external destination, or any movement of a token off the device that obtained it, which includes exporting it to a watch, syncing it to a server, or letting iCloud Keychain sync the token cache across devices.

The Apple Watch ships in two tiers. The default tier is read-only: the phone fetches and pushes non-credential status data to the watch over WatchConnectivity, and the watch relays any actions back to the phone. The watch holds no token and makes no Graph calls in this tier, so no tenant can block it, and it is the core watch functionality we build first. An opt-in second tier lets the watch authenticate on its own and store its own device-bound token on the watch, never the phone's token copied over, which unlocks standalone interactivity on cellular. That tier is gated behind a user setting, defaults off, requires an on-device spike to confirm the watchOS interactive sign-in path before we build on it, and falls back silently to the read-only tier when a tenant's Conditional Access blocks the watch.

## Azure / identity

Azure app registration is named `Blick`.

## Brand

Tatsiana palette — navy `#0D2D5B` + cyan `#00ADEE`. App icons (light, dark, tinted) live at `~/checkin/CheckIn/Assets.xcassets/AppIcon.appiconset/`. The shipped radiant-orb source PNGs are mirrored in `~/checkin/branding/` (1024×1024, no vector master yet).
