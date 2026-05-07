# CheckIn

A voice-first iOS app for hands-free Microsoft 365 status. Your next meeting, unread emails, pending Teams chats. Eyes-off. Local. Private.

CheckIn augments Outlook and Teams; it does not replace them. Tap any item to deep-link into the canonical app for the full content.

## What it does

You ask, CheckIn answers. The voice surface starts narrow on purpose: at-a-glance summary, sender or topic filter, refresh, repeat, stop, help, open by name. Anything richer (replying, marking read, joining meetings by voice) ships in later releases. The full scope is captured in `PLAN.md`.

The interaction model is multi-modal. Voice handles the hands-off path; touch and screen handle everything voice is bad at (browsing, comparison, precise editing). Either is enough on its own.

## How it works

CheckIn talks directly to your Microsoft 365 tenant via the Microsoft Graph API. There is no backend. There is no analytics. There is no logging that leaves the device, including to the developer.

Speech recognition runs on-device using `SFSpeechRecognizer` with `requiresOnDeviceRecognition = true`. The microphone audio and the resulting transcripts never leave the phone. M365 data is fetched on demand, surfaced to the screen and to text-to-speech, and is not persisted to disk.

`PRIVACY.md` is the canonical statement. `SELF-HOSTING.md` walks through the fork-and-rebuild path with your own Azure App Registration if you want full custody.

## Status

Early. The design audit is complete (see `DESIGN.md`, 33 numbered decisions). The architecture build (`StateMachine`, `DialogContext`, intent classifier, response template registry, deep-link service, audio session, earcons) is the next piece of work. See `PLAN.md` for the Day 1 build sequence.

The keeper code in this repo (MSAL auth wrapper, Microsoft Graph data layer, models, brand, utilities) carries over from an earlier iteration of the project that lives at the archived [excelano/checkin-voice](https://github.com/excelano/checkin-voice) repo. The voice prototype that preceded the iOS app lives at the archived [excelano/checkin-web-prototype](https://github.com/excelano/checkin-web-prototype) repo.

## Repo layout

```
DESIGN.md          33 design decisions; the source of truth
PERSONA.md         voice persona reference for TTS strings
STATES.md          application state machine
PLAN.md            scope and sequencing
CAPABILITIES.md    Apple voice/audio API capability scan
PHASE3-NOTES.md    patterns extracted from the archived web prototype
PRIVACY.md         privacy statement (forthcoming)
SELF-HOSTING.md    self-hosting walkthrough (forthcoming)

CheckIn/
    CheckInApp.swift
    Info.plist
    Assets.xcassets/
    Models/        plain Codable structs for Graph responses
    Services/      MSAL auth, Graph client
    Utilities/     brand, time formatting, constants
    Views/         ContentView placeholder (Phase 4 fleshes this out)
```

## Getting set up (macOS)

The Xcode project file is intentionally not in this repo. Create one fresh:

1. Open Xcode, File → New → Project, iOS App template.
2. Product Name: `CheckIn`. Bundle Identifier: `com.excelano.checkin`. Interface: SwiftUI. Language: Swift.
3. Save the project at the root of this repo (`~/checkin/`). Xcode will create `CheckIn.xcodeproj` next to the existing `CheckIn/` directory.
4. Delete the auto-generated `CheckInApp.swift` and `ContentView.swift` Xcode created. Add the existing `CheckIn/` files to the project (right-click the project navigator → "Add Files to CheckIn", select the directory, check "Create groups").
5. In project settings, replace the auto-generated `Info.plist` with the one in this repo, or merge the keys (URL schemes, query schemes, microphone and speech-recognition usage descriptions).
6. Add MSAL via Swift Package Manager: File → Add Package Dependencies, URL `https://github.com/AzureAD/microsoft-authentication-library-for-objc`.
7. Set deployment target to iOS 17.0.
8. Build. The placeholder `ContentView` should sign in with your M365 account and show "Signed in."

If you want to use your own Azure App Registration instead of mine, see `SELF-HOSTING.md` (forthcoming).

## License

MIT. See `LICENSE`.
