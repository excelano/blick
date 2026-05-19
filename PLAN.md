# CheckIn: Go-Forward Plan

Updated 2026-05-07.

## Status

**iOS app:** Fresh build. The earlier voice-prototype iteration lives at the archived `excelano/checkin-voice` repo. The keepers (MSAL auth wrapper, Microsoft Graph data layer, models, brand, utilities) carry over to this repo; the architectural skeleton is built fresh in Phase 2 to match `STATES.md`.

**Web prototype:** Out of scope. Lives at the archived `excelano/checkin-web-prototype` repo.

**Apple Developer enrollment:** Submitted 2026-05-06 with corrected D&B profile. Awaiting Apple verification email (1-5 business days). Once approved, TestFlight distribution becomes available.

**App icon:** Custom CheckIn icon (single bold teal check on navy) lives in `CheckIn/Assets.xcassets/AppIcon.appiconset/`. Wired in once the Xcode project is created.

## Architecture (per DESIGN.md)

The design audit (`DESIGN.md`, 33 decisions captured) sets the architecture. Highlights that shape this plan:

- **Single screen, deep-link** (D27). The app has one main screen showing the at-a-glance summary. Tap any item to deep-link to Outlook or Teams. No detail views, no reply flow, no email body display.
- **Voice as state machine** (D1, D33). Hierarchical states (`signedOut`, `onboarding`, `active`) with eight `active` substates; explicit transitions, dialog context, persona-shaped responses. See `STATES.md`.
- **Classical NLP, not LLM** (D14). `NLEmbedding` for semantic similarity, `NLTagger` for entity recognition, custom intent classifier behind a protocol. Foundation Models on the long-term backlog.
- **Privacy non-negotiable** (D9, D24). On-device speech recognition only, zero telemetry, zero analytics, zero data sharing with anyone except the user's own M365 service. M365 data never persisted to disk.
- **Augments not replaces** (D27). CheckIn is a voice-first M365 status panel; Outlook and Teams remain the apps for reading bodies, composing replies, and joining meetings.
- **Persona** (D32). Calm, capable, brief; warm without familiarity; first-person singular; light dry humor only on refusals and redirects. See `PERSONA.md`.
- **Multi-modal accessibility** (D22). Full core experience reachable without voice; voice-only conveniences (bulk operations, quick queries) need not have touch counterparts.
- **Self-hostable** (D25, D26). Custom Azure App Registration via Settings > Advanced, plus full fork-and-rebuild path documented in `SELF-HOSTING.md`.

## Iceberg scope (per D12 and D29)

The voice surface ships in three tiers. Day 1 ships first; Day 2 and Day 3 are the roadmap.

**Day 1 (above the waterline).** Summary spoken on demand with optional sender/topic filter; refresh; stop and repeat; help; voice-driven open of summary items via deep-link to Outlook or Teams; sign-in; settings; conversation mode entry and exit. D18 out-of-scope refusals and D19 in-scope-unsupported redirects handle anything else. The full set of foundational decisions (D1 through D33) is in place.

**Day 2 (next release after launch).** Quick queries with terse response (counts, times). Mark single email as read. Flag single email. Reply by voice via Outlook deep-link in reply mode.

**Day 3 (subsequent release).** Soft-delete single email with confirmation per D28. Bulk operations (mark-all-read, flag-all, delete-all, with the "except the latest" modifier and count confirmation). Join meeting by voice via Teams deep-link.

This plan focuses on shipping Day 1.

## Day 1 build sequence

Each phase is testable in isolation; later phases depend on earlier ones.

### Phase 1: Project scaffolding and design artifacts

- `DESIGN.md`, `PERSONA.md`, `STATES.md`, `CAPABILITIES.md` finalized at the repo root.
- `PRIVACY.md` describing the privacy posture from D9, D11, and D24.
- `SELF-HOSTING.md` per D26.
- `README.md` describing the project as a voice-first M365 status panel that augments Outlook and Teams.
- App icon assets ready under `CheckIn/Assets.xcassets/`.
- New Xcode project created on Mac with bundle ID `com.excelano.checkin` and the URL schemes from `Info.plist`. Keeper Swift files added to the project.

### Phase 2: Architecture build

Architecture is built fresh per `STATES.md`. Keeper code (auth, Graph data layer, models, brand, utilities) carries over from the archived repo and stays untouched.

- `DialogState` Swift enum with associated values (suspended intent in `disambiguating`, pending action in `confirming`, recent context in `helpDisplayed`).
- `DialogContext` struct (focused entity, summary slots, last utterance, last system response, recent turn history, pending confirmations, reprompt counter, recent refusal and redirect phrasings).
- `StateMachine` class with `currentState` and `transition(to:)`; debug-only logging.
- `IntentClassifier`, `EntityMatcher`, `ResponseGenerator` protocols (per D15) with deterministic stubs for tests.
- `DeepLinkService` constructing URLs for Outlook (open inbox, message, calendar event; reply mode) and Teams (open chat; join meeting). `LSApplicationQueriesSchemes` declares `ms-outlook` and `msteams`.
- `SpeechService`: `SFSpeechRecognizer` with `requiresOnDeviceRecognition = true` (D9), VAD on the audio engine input tap, `contextualStrings` for proper-noun biasing, `AVAudioSession` configured `.playAndRecord` + `.voiceChat` for echo cancellation per D8 barge-in.
- `TTSService`: `AVSpeechSynthesizer` with locale-matched voice default, delegate callbacks for barge-in tracking, response template registry for persona-shaped output.
- Audio assets: three earcons (listening, thinking, confirmation) per D13 and D33, each under 500 ms.

### Phase 3: Day 1 voice intelligence

- Day 1 intent classifier: summary, filter-by-name, refresh, repeat, stop, help, open (with entity), exit, settings.
- Real `NLEmbedding`-based intent classifier behind the protocol from D15.
- Real `NLTagger`-based entity matcher with `contextualStrings` priming and contact-list source-of-truth.
- Day 1 response template registry: summary phrasings, refusal pool (D18), redirect pool (D19), help short and long variants (D30), error pools per category (D21), onboarding invitations (D31). All reviewed against `PERSONA.md`.
- Custom language model from D10 implemented as opt-in but disabled by default (Settings only). Day 1 uses `contextualStrings` plus fuzzy matching.

### Phase 4: User-visible UI

- `ContentView` (auth gate per D33).
- `SummaryView` (the only main screen per D27).
- `HelpView` sheet per D30 (multimodal, structured, contextual).
- `SettingsView` sheet (Voice section per D5; Listening Mode per D17; Voice Recognition Tuning per D10; Advanced per D25).
- `OnboardingFlow` sequence per D31 (welcome, permissions, mode, first query).
- Listening indicator, thinking indicator, captioning view per D22.
- VoiceOver labels and Dynamic Type on every interactive element per D22.
- Reduced-motion variants per D22.

### Phase 5: Integration and on-device verification

Phase 5 is sliced into named sub-phases (5.0, 5.1, …) so commit messages and handoff notes can reference them stably. Each slice is self-contained at its boundary, fits a single execution session, and has explicit done-criteria. Slices are executed via the Mac-Claude / Debian-Claude handoff workflow tracked in `~/mac/notes/` (offline of this repo).

The five-bullet sketch in the original Phase 5 — wire state machine to UI, end-to-end voice flow on simulator, on-device test loop, cross-state behavior, privacy audit — is the work; the slices below give it shape.

**5.0 — TTS wired. (Done, commit `3c5fc52`, 2026-05-15.)** `AppleTTSService` replaced its `fatalError` stubs with a real `AVSpeechSynthesizer` backed by an `AsyncStream<TTSEvent>` (started, wordBoundary, paused, resumed, finished, cancelled). `SessionCoordinator` consumes the events, transitions through `.speaking`, returns to the configured rest state. Tap-to-talk verified end-to-end on iPhone 15. Word-boundary callbacks land for the future D8 hook.

**5.1 — Audio pipeline finish.** Three coordinated changes that close out the audio side of the voice loop.

- *Silent-by-design intent handling.* `SessionCoordinator.handle(_ update:)` checks `response.text.isEmpty` before transitioning to `.speaking` and routes straight to the rest state if empty. Covers `.stop` (intentionally empty per `ResponseTemplateRegistry.stopAcknowledged`) and any future silent intent as a category, not a one-off.
- *Voice and rate Settings wiring.* `SettingsView`'s `voiceIdentifier` and `speechRate` (`@AppStorage`-backed) are read by `AppleTTSService.speak(_:)` and applied to each `AVSpeechUtterance`. Live-update is a choice; reading at speak-time is fine.
- *Earcons.* The three audio assets from Phase 2 (listening, thinking, confirmation per D13 and D33, each under 500 ms) fire at the matching state-machine transitions via a small `EarconService` behind a protocol. Earcons share the existing `.playAndRecord/.voiceChat` audio session without fighting the synthesizer.

Done when: `.stop` no longer strands the state machine; voice picker has an audible effect when changed; the three earcons play cleanly at their transitions without clipping the synthesizer.

**5.2 — Real Graph fetch.** Single biggest user-visible delta. Today every response is the hardcoded "I haven't fetched yet" fallback. The keeper `GraphClient` (carried over from the archived voice repo, untouched since) is wired into the response path: next meeting, unread email count, pending Teams chats. `.summary` answers with real numbers; `.filter` answers with real sender or topic matches; `.refresh` re-fetches.

Done when: a cold-launch summary on David's iPhone 15 returns real data from his M365 tenant; refresh re-fetches without re-auth; privacy posture verified (no `URLSession` traffic outside Microsoft Graph and identity endpoints, M365 data not persisted to disk per D9 and D24).

**5.3 — Intent plumbing.** Fills out the remaining Day 1 intent surface. Sliced at execution time into four sub-phases, executed in the order shown below (5.3a → 5.3c → 5.3d → 5.3b).

- *5.3a — `.open` routing plus ambient intents. (Done, commit `b056729`, 2026-05-18.)* Deep-link routing through `DeepLinkService` for all three entity types (email, meeting, chat), plus `.repeatLast` and `.exit`. Bundled polish on `.open` anchors and summary phrasing.
- *5.3c — Domain-narrowed summaries and sender filtering. (Done, commit `3895b26`, 2026-05-19.)* Domain detector (`.email` / `.chat` / `.meeting` / `.all`) routes both `.summary` and `.filter`-no-sender requests to the right slice of the data. `.filter` with a resolved sender (via the existing `NLTaggerEntityMatcher`) narrows to that sender's matches. New registry methods: `summaryEmailOnly`, `summaryChatOnly`, `summaryMeetingOnly`, `summaryFilteredBySender`. Downstream domain detection on both classifier paths handles the classifier's `.summary` / `.filter` noise for plain count queries without anchor tuning.
- *5.3d — Meeting details plumbing.* The `Meeting` model adds `subject`, `organizer`, and `attendees`; Graph `/me/events` `$select` is extended to populate them. A new `meetingDetailed(focus:)` registry method answers "what / who / when" questions about the next meeting with focused phrasing. `summaryMeetingOnly` routes through it; `summarySentence`'s embedded meeting phrase gains the subject in a tight form. Carry-forward A from 5.3c.
- *5.3b — Disambiguation panel plus confirmation panel.* The D33 `.disambiguating` state UI for the two-sender case, informed by the precision findings 5.3c surfaced (NLTagger fall-throughs on short names, fuzzy matches on partial overlap). The confirmation panel for sign-out (Day 1 case identified during design); the open question whether any other Day 1 confirmation case exists is resolved at slice-start.

Done (umbrella) when: every Day 1 intent the classifier emits drives a real side effect or a real response; nothing falls through to the no-op fallback; the natural-utterance set David exercised in 5.3c verification gets a useful answer end to end.

**5.4 — Conversation mode and D8 barge-in.** The architectural lift Mac-Claude diagnosed 2026-05-15. Wire `SFSpeechRecognizer`'s natural `isFinal` delivery into a `listening → processing → speaking` transition in conversation mode, so hands-free turn-taking actually advances the state machine without a mic tap. Once that's in, D8 auto-cut barge-in: VAD on the input tap during `.speaking` cuts the synthesizer at the next word boundary (the scaffold from 5.0 emits the events). Settings' Listening Mode toggle, currently exposed but pointing at the broken path, becomes correct.

Done when: conversation mode runs a multi-turn loop on device without mic taps; D8 barge-in cuts the synthesizer cleanly mid-response and re-enters listening.

This slice may split. Auto-finalization could turn out hairier than it looks (the `endAudio()` rapid-call issue Mac-Claude found on 2026-05-15 may want its own investigation). Call at slice-start.

**5.5 — Privacy audit and pre-TestFlight gate.** Rolls forward into Phase 6 entrance.

- Confirm no `URLSession` calls outside Microsoft Graph and Microsoft identity endpoints.
- Confirm no analytics, crash reporters, or telemetry SDKs anywhere in the dependency graph.
- Persona drift sweep across `ResponseTemplateRegistry` — every phrase reviewed against `PERSONA.md`.
- Accessibility pass: VoiceOver labels, Dynamic Type at largest size, reduced-motion variants per D22.

Done when: privacy posture is provably clean by code inspection; persona phrasing is consistent end-to-end; accessibility runs without warnings at the largest Dynamic Type setting.

### Phase 6: Pre-TestFlight checklist

- Permission strings in `Info.plist` reviewed.
- App Store Connect App Privacy declaration set to "Data Not Collected."
- Persona drift check across the response template registry.
- Accessibility test pass: VoiceOver, Dynamic Type at largest size, reduced motion.
- Privacy posture documented in README and `PRIVACY.md`.
- Final smoke test on physical device.

## Out of scope

The architecture explicitly excludes several patterns common to traditional email and messaging apps:

- Detail views for emails or chats. D27 puts these behind deep-links to Outlook and Teams.
- Email body parsing or HTML stripping. The app does not display bodies, so it does not need to parse them.
- In-app reply composition. Reply by voice via Outlook deep-link in reply mode (Day 2).
- Voice-driven list browsing. Single screen plus deep-link covers browsing.

## Configuration

- Client ID for `excelano.onmicrosoft.com` tenant (publisher-verified) lives in `Constants.swift` as the default. Phase 4 wires `@AppStorage` so users can override per D25.
- Bundle ID: `com.excelano.checkin`.
- Redirect URI: `msauth.com.excelano.checkin://auth`.
- Brand colors: dark navy `#0f2233`, teal `#2ab8d0`, muted `#6a8899`.

## Reference

- `DESIGN.md` — 33 design decisions, the source of truth for what we are building and why.
- `PERSONA.md` — the working voice persona reference.
- `STATES.md` — the application state diagram and transitions.
- `CAPABILITIES.md` — Apple voice/audio API and Natural Language framework capability scan.
- `PHASE3-NOTES.md` — patterns extracted from the archived web prototype, queued for Phase 3.
- `PRIVACY.md` — privacy posture statement.
- `SELF-HOSTING.md` — full self-hosting walkthrough.
