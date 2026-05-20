# CheckIn: Privacy Statement

CheckIn is a voice-first iOS app that talks to your Microsoft 365 account on your behalf. Voice apps that touch work email, calendars, and chats raise privacy expectations beyond ordinary apps, and rightly so. This document is the canonical statement of what CheckIn does and does not do with your data. The companion repository is open source so that every claim here is independently verifiable.

## What stays on your device

**Audio.** Microphone audio captured for voice queries is processed only on your device. CheckIn sets `requiresOnDeviceRecognition = true` on every recognition request. Apple's `SFSpeechRecognizer` honors that flag by performing recognition entirely on-device for supported locales. If your locale does not support on-device recognition, CheckIn refuses to start the voice surface rather than falling back to server recognition. There is no in-app override and no code path for server-side recognition.

**Transcripts.** The text produced by speech recognition is held in memory while the voice session is active, used to compute intent and entity matches, and is never written to disk. It is never sent to any server, including Apple's.

**Conversation context.** The dialog state machine tracks what you most recently asked and what CheckIn most recently said in order to handle follow-ups, disambiguation, and barge-in. This conversation context lives in memory only. When you close the app from the app switcher, or when iOS reclaims the app's memory, the context is gone. There is no persistence layer and no timer; the natural in-memory lifetime is the boundary.

**Microsoft 365 data.** When you ask for your summary, CheckIn fetches calendar events, unread emails, and Teams chats from the Microsoft Graph API using your account's own credentials. The fetched data is held in memory long enough to render the summary on screen and speak it aloud. Nothing is persisted to disk, including caches. Closing or backgrounding the app discards the data.

## What leaves your device

**Microsoft Graph API calls.** When you ask for your summary, CheckIn issues HTTPS requests to your Microsoft 365 service. These calls go to `graph.microsoft.com` (and regional equivalents) and `login.microsoftonline.com`. They carry your access token, which Microsoft uses to identify you, and they return the calendar, mail, and chat data your account has access to. This is the same traffic that any Microsoft Graph client makes; CheckIn does not add headers, identifiers, or analytics to it.

**Nothing else.** CheckIn makes no other network requests. No analytics, no crash reporting, no telemetry, no usage logging that leaves the device, no third-party SDKs that would. The Xcode project deliberately imports nothing of the sort, which is the point: this is enforced by the absence of code, not by a policy that depends on the developer behaving well.

## What CheckIn does not collect

CheckIn does not collect microphone audio, transcripts, Microsoft 365 content, conversation context, query history, usage events, screen views, button taps, feature counts, crash reports, performance metrics, diagnostic logs, device identifiers, advertising identifiers, installation identifiers, or anything else. When CheckIn ships to the App Store, its App Privacy declaration will be "Data Not Collected." This document and the open-source repository are the substance behind that label.

## One thing outside the app's control

Apple aggregates anonymous crash logs at the iOS level from devices that have **Share With App Developers** turned on, and surfaces those aggregates to developers in App Store Connect. CheckIn neither collects this data nor processes it; the repository contains no code that touches it. But Apple may still surface aggregate, anonymized crash signatures to the developer account regardless of what the app itself does. If you do not want any of your device's anonymous crash data shared with any developer, including this one, the iOS-level control lives at **Settings > Privacy & Security > Analytics & Improvements > Share With App Developers**. Turning it off applies to all apps on your phone.

## How to verify the claims yourself

The full source is at [github.com/excelano/checkin](https://github.com/excelano/checkin). To check the claims here independently:

1. Search the project for `URLSession`. Every network call should target `graph.microsoft.com`, `login.microsoftonline.com`, or one of their regional equivalents.
2. Search for analytics and crash-reporter SDK names: Firebase, Sentry, Crashlytics, Mixpanel, Amplitude, Segment, GoogleAnalytics. None should appear.
3. Search for `requiresOnDeviceRecognition` and confirm it is set unconditionally to `true`.
4. Search for `print(` and `os_log(` and confirm there are no statements that emit user content.

If you would rather not depend on Excelano's published Azure App Registration at all, see `SELF-HOSTING.md` for two paths: a runtime override that points CheckIn at your own Azure App Registration without rebuilding the app, and a full fork-and-build path that puts every piece of infrastructure in your own hands.

## Updates to this document

This document changes as the design changes. The change history is the git log of `PRIVACY.md`. Substantive changes to the privacy posture (a new data flow, a new dependency that touches data, a relaxation of the on-device recognition requirement) require a corresponding update here in the same commit.
