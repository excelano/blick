# CheckIn: iOS Voice/Audio API Capabilities

This is a reference scan of Apple's voice and audio API surface, scoped to the four areas relevant to CheckIn: speech recognition (`SFSpeechRecognizer`), speech synthesis (`AVSpeechSynthesizer` / `AVSpeechUtterance`), audio routing and session management (`AVAudioSession`), and Siri/Shortcuts integration (`AppIntents`). Last scanned 2026-05-07 against iOS 17.6 as the deployment target. Used as the empirical companion to DESIGN.md decisions; each item answers what the API does, what it cannot do, and how that should shape design choices for a state-driven, multi-modal voice app.

## SFSpeechRecognizer

### On-device versus server recognition

**What it is.** `SFSpeechRecognizer` runs against either Apple's servers or a fully local model. The choice is controlled per-request via `SFSpeechRecognitionRequest.requiresOnDeviceRecognition` (iOS 13+), and per-recognizer via `SFSpeechRecognizer.supportsOnDeviceRecognition` which reports whether the local model exists for that locale on this device.

**Constraints.** Not every supported recognition locale has an on-device model; the union of locales with on-device support is smaller than `supportedLocales()` and varies by device class and iOS version. On-device recognition has historically been slightly less accurate than server recognition for difficult audio, though the gap on modern devices is narrow. `supportsOnDeviceRecognition` can return `false` for some locales on some hardware even when the recognizer is otherwise available; always check before forcing on-device. The simulator does not always match device behavior for on-device support; verify on hardware.

**Implication for design.** Force `requiresOnDeviceRecognition = true` for all CheckIn recognition since email and meeting content is sensitive, and treat the absence of on-device support for the user's locale as a hard preflight failure with a clear screen-displayed message rather than silently falling back to cloud. ([SFSpeechRecognizer](https://developer.apple.com/documentation/speech/sfspeechrecognizer), [supportsOnDeviceRecognition](https://developer.apple.com/documentation/Speech/SFSpeechRecognizer/supportsOnDeviceRecognition), [requiresOnDeviceRecognition](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/requiresondevicerecognition))

### Streaming partial results and the delegate API

**What it is.** Setting `SFSpeechRecognitionRequest.shouldReportPartialResults = true` causes the task to fire interim transcriptions continuously as audio arrives. Two callback styles are supported: a closure handler (`recognitionTask(with:resultHandler:)`) and an `SFSpeechRecognitionTaskDelegate` with separate methods for `didHypothesizeTranscription`, `didFinishRecognition`, `speechRecognitionDidDetectSpeech`, `speechRecognitionTaskWasCancelled`, and `didFinishSuccessfully`.

**Constraints.** Partial results are not stable; the recognizer will frequently rewrite earlier tokens as more context arrives. There is no formal "stable prefix" API; you decide when to commit. The result's `isFinal` flag becomes true only at end-of-audio or after explicit `endAudio()`.

**Implication for design.** Use the delegate form so the state machine has distinct transition points (speech-detected, hypothesis-updated, finalized, cancelled). Treat partial results as display-only feedback; only act on commands at `isFinal` or after a debounced stable interval. ([recognitionTask(with:delegate:)](https://developer.apple.com/documentation/speech/sfspeechrecognizer/1649894-recognitiontask), [SFSpeechRecognitionTaskDelegate](https://developer.apple.com/documentation/speech/sfspeechrecognitiontaskdelegate))

### Confidence scores

**What it is.** Each `SFTranscriptionSegment` carries a `confidence` float (0.0 to 1.0) reflecting per-token recognizer confidence, plus `timestamp`, `duration`, and `alternativeSubstrings`. `SFTranscription.formattedString` is the joined string; `bestTranscription` is the highest-confidence transcription on the result.

**Constraints.** Confidence values are only populated on the final result, not on partials; partial-result segments report `0.0` confidence. The values are calibrated by Apple but are not directly comparable across locales or across iOS versions. There is no per-utterance aggregate confidence score; the app must roll one up itself.

**Implication for design.** Confidence is a useful tiebreaker after-the-fact (e.g. for picking between command interpretations on the final result), but it cannot drive real-time UI feedback. For the state machine, plan to gate destructive actions like "send" on a minimum aggregate confidence threshold derived from segments. ([SFTranscriptionSegment](https://developer.apple.com/documentation/speech/sftranscriptionsegment), [confidence](https://developer.apple.com/documentation/speech/sftranscriptionsegment/confidence))

### End-pointing and silence detection

**What it is.** The framework does no automatic end-of-utterance detection for `SFSpeechAudioBufferRecognitionRequest`. The app decides when to call `endAudio()` and finalize the task. The system's voice-search-style end-pointing that Siri uses is not exposed.

**Constraints.** No silence-detection callback, no VAD primitive, no configurable silence threshold. Apps typically build their own end-pointing using the audio engine's input tap (RMS power on the buffer, or `AVAudioRecorder.averagePower(forChannel:)` if using that path). The `speechRecognitionDidDetectSpeech` delegate fires once at first speech, but there is no symmetric "speech ended" callback.

**Implication for design.** Build a small VAD loop on the input audio tap (RMS level, sustained-silence timer, with hangover) as part of the listening state. Make the silence threshold a tunable parameter exposed in the state machine config so it can be adjusted per-context (a longer threshold during dictation, shorter during command listening). ([Recognizing speech in live audio](https://developer.apple.com/documentation/Speech/recognizing-speech-in-live-audio))

### Contextual hints (`contextualStrings`)

**What it is.** `SFSpeechRecognitionRequest.contextualStrings` accepts an array of phrases that bias the recognizer toward matching them. Apple recommends staying at or below 100 entries.

**Constraints.** Effectiveness is documented as "improves recognition" without quantification; community reports range from "noticeably helpful" for unusual proper nouns to "barely changes results" for already-common names. Contextual strings cannot define pronunciations, only word-form hints. They reset per-request, so the list must be re-supplied each time. They do not override the language model for words it already knows confidently.

**Implication for design.** Push the user's contact display names (sender name list from Microsoft Graph, plus Teams display names) into `contextualStrings` for each command-listening session; cap at the most-recent or most-frequent 100. For CheckIn, the more reliable lever for unusual names is the iOS 17 custom language model (next item), with `contextualStrings` as the lightweight fallback when training data is not yet collected. ([Customize on-device speech recognition (WWDC23)](https://developer.apple.com/videos/play/wwdc2023/10101/))

### Custom language model (iOS 17+)

**What it is.** iOS 17 introduces `SFCustomLanguageModelData` and `SFSpeechLanguageModel` for building a custom on-device language model with extra vocabulary, weighted phrases, and per-phrase pronunciations using X-SAMPA. The model is generated at runtime, persisted to disk, and attached to a request via `customizedLanguageModel`.

**Constraints.** On-device-only; requires `requiresOnDeviceRecognition = true` to take effect. X-SAMPA pronunciations are supported only for a subset of locales (English variants are well-supported; check per-locale). Training data uses a templated DSL (phrases with variable slots) so you can generate combinatorial coverage without writing every variation. Model generation has measurable cost (seconds, not milliseconds, for non-trivial models); do it asynchronously and cache.

**Implication for design.** This is the right surface for proper-noun robustness (contact names like "Christa", "Tony", "Tomasz"), Teams channel names, and the small fixed command vocabulary ("read", "reply", "send", "skip", "the second one"). Build the custom model on first launch (and refresh when contacts change) from the user's M365 contacts plus the command grammar; cache the compiled `SFSpeechLanguageModel` to disk. ([SFCustomLanguageModelData](https://developer.apple.com/documentation/speech/sfcustomlanguagemodeldata), [SFSpeechLanguageModel](https://developer.apple.com/documentation/speech/sfspeechlanguagemodel), [Customize on-device speech recognition (WWDC23)](https://developer.apple.com/videos/play/wwdc2023/10101/))

### Maximum recognition duration

**What it is.** Server-based recognition has a long-standing limit of approximately one minute of audio per request. On-device recognition (iOS 13+) lifts this limit; sessions can run effectively as long as the audio engine stays running.

**Constraints.** Even on-device, very long sessions consume battery and memory, and accuracy degrades on extremely long contiguous audio. Apple's guidance is to chunk long inputs at natural pauses. The one-minute server cap is enforced silently via task termination, not always via a clean error.

**Implication for design.** Since CheckIn forces on-device, the limit is not a hard constraint, but the listening state should still bound itself to short windows (10 to 20 seconds for command capture, longer for dictation) and recycle the recognition request between windows. This also gives natural state-machine boundaries for re-applying contextual hints as context changes. ([Recognizing speech in live audio](https://developer.apple.com/documentation/Speech/recognizing-speech-in-live-audio))

### Authorization model

**What it is.** Two separate authorizations. `SFSpeechRecognizer.requestAuthorization` covers speech recognition; `AVAudioApplication.requestRecordPermission` (iOS 17+; previously `AVAudioSession.requestRecordPermission`) covers the microphone. Both require Info.plist entries: `NSSpeechRecognitionUsageDescription` and `NSMicrophoneUsageDescription`. Missing keys cause the app to crash on first use, not silently deny.

**Constraints.** The two prompts are independent; users can grant one and deny the other. A denied state can only be changed via Settings; there is no in-app re-prompt. On iOS 17, `AVAudioApplication` is the canonical entry point for recording permission and replaces the deprecated `AVAudioSession` accessor.

**Implication for design.** Build a permissions state in the state machine that requests both up-front on first launch with a screen explaining why each is needed, and a clear settings-deeplink path for the denied case. Treat the two permissions as a single logical "voice ready" state for downstream transitions. ([NSSpeechRecognitionUsageDescription](https://developer.apple.com/documentation/bundleresources/information-property-list/nsspeechrecognitionusagedescription), [NSMicrophoneUsageDescription](https://developer.apple.com/documentation/BundleResources/Information-Property-List/NSMicrophoneUsageDescription))

### Audio input options and supported formats

**What it is.** Three request types: `SFSpeechAudioBufferRecognitionRequest` (live `AVAudioPCMBuffer` feed, the only choice for streaming), `SFSpeechURLRecognitionRequest` (file at a URL), and the abstract `SFSpeechRecognitionRequest` base. The buffer request accepts the native input format from `AVAudioEngine.inputNode`, typically 44.1 or 48 kHz mono float32 PCM.

**Constraints.** The buffer request has no public sample-rate or channel constraint, but in practice the engine input tap dictates the format; do not resample unless you have a reason. File-based requests support common formats (m4a, wav, caf, mp3) but not all codecs across all iOS versions; test the specific codec on-device.

**Implication for design.** Use `SFSpeechAudioBufferRecognitionRequest` exclusively for live capture, fed from a single shared `AVAudioEngine` tap. File-based recognition is only relevant if CheckIn ever transcribes a recorded voicemail or saved memo; not in scope for v1. ([SFSpeechAudioBufferRecognitionRequest](https://developer.apple.com/documentation/speech/sfspeechaudiobufferrecognitionrequest))

### Error handling and recovery

**What it is.** Errors arrive via the result handler's `Error?` parameter or the delegate's `task(_:didFinishSuccessfully:)` with `false`. Common cases include network unavailable (server-only requests), recognizer unavailable (`isAvailable` flips on locale change or system load), and authorization revoked at runtime.

**Constraints.** Error domains and codes are not always stable across iOS versions; some failures arrive only as a generic recognizer error with a code rather than a typed enum. The recognizer's `isAvailable` property is KVO-observable, but transitions can be brief; a one-shot read can miss them.

**Implication for design.** The state machine needs an explicit `recognitionFailed` state with a recovery sub-state that distinguishes transient (retry once, log) from terminal (surface to user, exit listening mode) errors. Observe `isAvailable` via KVO and treat false as a hard interrupt of any active listening. ([SFSpeechRecognizer](https://developer.apple.com/documentation/speech/sfspeechrecognizer))

## AVSpeechSynthesizer / AVSpeechUtterance

### Voice selection and enumeration

**What it is.** `AVSpeechSynthesisVoice.speechVoices()` returns all installed voices. Each voice has a `language` (BCP-47), `identifier`, `name`, `quality` (`.default`, `.enhanced`, `.premium`), and `voiceTraits` (an `OptionSet` including `.isPersonalVoice` and `.isNoveltyVoice` on iOS 17+). `AVSpeechSynthesisVoice(language:)` returns the system default for the given language. iOS 17 ships over 150 preinstalled voices.

**Constraints.** Enhanced and premium voices are not preinstalled; users must download them in Settings (Accessibility → Spoken Content → Voices). Your app cannot trigger or check the download flow programmatically beyond observing whether the voice is now enumerable. Personal Voice requires a separate user authorization (`AVSpeechSynthesizer.requestPersonalVoiceAuthorization`, iOS 17+) and the user must have created one. Some novelty voices (Bells, Cellos, Trinoids, etc.) ship by default and will appear in `speechVoices()`; filter them out for serious use.

**Implication for design.** On first launch, enumerate voices, prefer `.premium` then `.enhanced` then `.default` for the user's locale, and remember the choice. Expose a Settings screen letting the user pick a voice; show download status (present versus not-present in `speechVoices()`) and a "go to Settings" deeplink to fetch a higher-quality voice. Treat Personal Voice as an opt-in advanced setting; do not request authorization at first launch. ([AVSpeechSynthesisVoice](https://developer.apple.com/documentation/avfaudio/avspeechsynthesisvoice), [AVSpeechSynthesisVoiceQuality](https://developer.apple.com/documentation/avfaudio/avspeechsynthesisvoicequality), [Extend Speech Synthesis with personal and custom voices (WWDC23)](https://developer.apple.com/videos/play/wwdc2023/10033/))

### Prosody control

**What it is.** `AVSpeechUtterance` exposes `rate` (0.0 to 1.0, with `AVSpeechUtteranceDefaultSpeechRate` near 0.5), `pitchMultiplier` (0.5 to 2.0, default 1.0), `volume` (0.0 to 1.0, default 1.0), `preUtteranceDelay`, and `postUtteranceDelay`. Rate is non-linear; values below 0.4 sound noticeably slow.

**Constraints.** The rate scale is empirical; Apple does not document the linear mapping. Volume here is multiplicative on top of system volume and is not a substitute for system volume. Pitch and rate apply to the whole utterance unless you use SSML or attributed-string ranges. Per-utterance delay is honored, but cumulative delays across many short utterances drift slightly.

**Implication for design.** Use a small set of prosody presets (normal, slower-for-clarity, faster-for-skim) rather than exposing raw values to the user. Consider a slightly slower rate (around 0.48) for the morning summary read-out where comprehension matters more than speed. ([AVSpeechUtterance](https://developer.apple.com/documentation/avfaudio/avspeechutterance))

### Prosody markup: SSML and attributed strings

**What it is.** Apple does not implement full SSML. iOS 16+ provides `AVSpeechUtterance(attributedString:)` honoring `NSAttributedString.Key.accessibilitySpeechIPANotation` (per-range IPA pronunciation), `.accessibilitySpeechPunctuation` (speak-each-punctuation toggle), `.accessibilitySpeechSpellOut`, and `.accessibilitySpeechQueueAnnouncement`. iOS 17 adds `AVSpeechUtterance(ssmlRepresentation:)` accepting a documented subset of SSML: `<speak>`, `<break>`, `<prosody>` (rate, pitch, volume), `<emphasis>`, `<phoneme>` (IPA only), `<sub>` (alias), and `<voice>`. Tags outside this subset are ignored or cause an init failure.

**Constraints.** No PLS lexicon support; pronunciations must be inline. IPA coverage is voice-dependent; some symbols (notably some `ɡ`, `ɹ` variants) are inconsistently supported across voices. SSML's `<say-as>` (interpret-as for dates, numbers, addresses) is not in the supported subset; you have to pre-format strings yourself. Mixing SSML and attributed-string forms in one utterance is not supported; pick one.

**Implication for design.** Pre-format dynamic content (times, dates, sender names, message counts) in plain text before synthesis rather than relying on `<say-as>`. Use `<break>` between summary sections and `<emphasis>` on sender names in the morning briefing. Reserve IPA pronunciations for known-problem proper nouns from the contact list, parallel to the speech-recognition custom language model entries. ([init(ssmlRepresentation:)](https://developer.apple.com/documentation/avfaudio/avspeechutterance/3566308-init), [accessibilitySpeechIPANotation](https://developer.apple.com/documentation/foundation/nsattributedstring/key/accessibilityspeechipanotation))

### Delegate callbacks during playback

**What it is.** `AVSpeechSynthesizerDelegate` provides `didStart`, `willSpeakRangeOfSpeechString` (per-word/character range during synthesis), `didFinish`, `didPause`, `didContinue`, and `didCancel`. The `willSpeak` range is given against the original (non-attributed) string content.

**Constraints.** `willSpeakRangeOfSpeechString` fires at word granularity for most voices; finer granularity is not available. For SSML-initialized utterances, the range maps to the spoken text, not the SSML source, which complicates synchronizing UI highlights with marked-up content.

**Implication for design.** Use `willSpeakRangeOfSpeechString` to drive a "current item" highlight as the morning summary reads aloud (current email subject, current meeting). `didFinish` is the natural transition trigger from a "speaking" state to "listening for next command." Always handle `didCancel` distinctly from `didFinish`; barge-in by the user is a cancel, not a finish. ([AVSpeechSynthesizerDelegate](https://developer.apple.com/documentation/avfaudio/avspeechsynthesizerdelegate))

### Pause, resume, stop semantics

**What it is.** `pauseSpeaking(at:)` and `stopSpeaking(at:)` accept an `AVSpeechBoundary` of `.immediate` or `.word`. `.immediate` cuts off audio mid-syllable; `.word` finishes the current word first. `continueSpeaking()` resumes from the pause point. `stopSpeaking` flushes the queue.

**Constraints.** `.word` boundary on `stopSpeaking` introduces a delay of up to a few hundred milliseconds before the synthesizer is fully idle; the state machine should not assume instantaneous transition. Pause/continue is not perfectly seamless across all voices; some voices restart the current word.

**Implication for design.** Use `.immediate` for barge-in (user starts speaking while the app is reading). Use `.word` only for graceful UI-driven pauses. Treat `stopSpeaking(.immediate)` followed by `didCancel` as the canonical interrupt sequence in the state machine. ([AVSpeechBoundary](https://developer.apple.com/documentation/avfaudio/avspeechboundary))

### Write-to-file API

**What it is.** `write(_:toBufferCallback:)` (iOS 13+) synthesizes an utterance and delivers `AVAudioBuffer` chunks (in practice `AVAudioPCMBuffer`) to a callback, instead of playing them. Suitable for caching synthesized prompts or rendering to an audio file using the voice's `audioFileSettings`.

**Constraints.** Multiple developer reports (iOS 16 and iOS 17 early releases) of the callback never firing or firing inconsistently, particularly when the synthesizer instance is short-lived; hold the synthesizer as a long-lived property. The simulator has had recurring issues with both regular speech and the write API across iOS 16 and 17 builds; always validate on a physical device. The empty-frame-length terminator buffer must be detected to know when synthesis is complete.

**Implication for design.** Write-to-file is appealing for pre-rendering frequently-spoken prompts ("good morning", "you have N new messages") to remove synthesis latency from the morning flow, but the bug history makes it risky for v1. Defer this optimization to v2 after measuring real synthesis latency on-device. ([write(_:toBufferCallback:)](https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer/write(_:tobuffercallback:)), [AVSpeechSynthesizer broken on iOS 17 thread](https://developer.apple.com/forums/thread/738048))

### Mixing with other audio

**What it is.** `AVSpeechSynthesizer.usesApplicationAudioSession` (default `true`) controls whether the synthesizer uses the app's configured `AVAudioSession` or a private one. With `true`, the app's category and options (including `.mixWithOthers` and `.duckOthers`) apply to synthesis playback.

**Constraints.** Setting `usesApplicationAudioSession = false` hands session control to the synthesizer and ignores app-level options; this is the wrong choice for any app that also records audio. With `true`, the synthesizer activates the session on `speak`; if recording was active, you must coordinate so the session category supports both directions.

**Implication for design.** Keep `usesApplicationAudioSession = true` and configure the session at app level. Use `.duckOthers` so background music (Apple Music, podcasts) lowers but does not stop while CheckIn speaks; this matches user expectations for a check-in flow that may run while music is playing. ([usesApplicationAudioSession](https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer/usesapplicationaudiosession), [mixWithOthers](https://developer.apple.com/documentation/avfaudio/avaudiosession/categoryoptions/1616611-mixwithothers))

### Background playback

**What it is.** With `UIBackgroundModes` containing `audio` in Info.plist and an active audio session, `AVSpeechSynthesizer` can continue speaking after the app is backgrounded or the screen locks.

**Constraints.** Apple's review guidelines require that background-audio capability be justified by a user-facing audio feature; speech synthesis for screen-reader-style read-out qualifies, but you must not use it as a back-door for other background work. The session must already be active when backgrounding occurs; activating it from the background state is unreliable.

**Implication for design.** Add `audio` to `UIBackgroundModes` so the morning summary keeps reading if the user locks the phone or switches apps mid-briefing. Document the justification in App Review notes when submitting. ([UIBackgroundModes](https://developer.apple.com/documentation/bundleresources/information-property-list/uibackgroundmodes))

## AVAudioSession

### Categories

**What it is.** Categories declare the app's audio role. The relevant ones are `.playback` (audio out only, can play locked-screen and mix per options), `.record` (mic input only, no playback), and `.playAndRecord` (full duplex, required for any app that both speaks and listens).

**Constraints.** `.playback` does not allow recording even if you also configure the engine for input; the engine input tap will silently produce no audio. Switching category at runtime is allowed but causes a brief audio glitch and may invalidate active routes. Selecting `.playAndRecord` enables additional routing options not available to other categories (notably `.defaultToSpeaker`, `.allowBluetooth`).

**Implication for design.** Use `.playAndRecord` for the main app session, set once at app launch. Treat any need to switch categories at runtime as a code smell; if the morning flow needs purely playback at one moment and purely recording the next, still use `.playAndRecord` throughout. ([AVAudioSession](https://developer.apple.com/documentation/AVFAudio/AVAudioSession))

### Modes

**What it is.** Modes refine category behavior. `.default`, `.spokenAudio` (favors speech clarity, raises tolerance for ducking), `.voiceChat` (full-duplex with platform echo cancellation, AGC, noise suppression), `.measurement` (disables system processing for recording fidelity), `.voicePrompt` (iOS 12+, optimized for short prompts, different routing on CarPlay).

**Constraints.** Platform acoustic echo cancellation is only enabled in `.voiceChat` mode (or via `setPrefersEchoCancelledInput` on supported hardware in iOS 17+). `.voiceChat` also forces specific input/output processing that subtly changes recorded audio; pure transcription of clean voice may be slightly better in `.measurement`, but only if the speaker is not active. `.spokenAudio` interacts well with `.duckOthers` and is the right choice for read-aloud apps that do not record concurrently.

**Implication for design.** Use `.voiceChat` mode whenever CheckIn might be speaking and listening simultaneously (or even in quick alternation), so platform AEC suppresses the synthesizer's audio from the mic. Consider `.voicePrompt` for the brief Siri-triggered "what's next" entry path on CarPlay. Document the trade: `.voiceChat` is preferable to `.measurement` here because barge-in matters more than transcription fidelity. ([voiceChat mode](https://developer.apple.com/documentation/avfaudio/avaudiosession/mode-swift.struct/voicechat), [setPrefersEchoCancelledInput](https://developer.apple.com/documentation/avfaudio/avaudiosession/setprefersechocancelledinput(_:)))

### Options

**What it is.** Category options modify behavior. The relevant ones for CheckIn are `.mixWithOthers` (CheckIn audio mixes with other apps at full volume), `.duckOthers` (other apps quiet down while CheckIn plays), `.allowBluetooth` (legacy Bluetooth HFP input), `.allowBluetoothA2DP` (A2DP output), and `.defaultToSpeaker` (route to the loudspeaker rather than the earpiece in `.playAndRecord`).

**Constraints.** `.allowBluetooth` and `.defaultToSpeaker` have a documented interaction: enabling both routes input through a Bluetooth headset's mic if available, output through the speaker otherwise. Without `.defaultToSpeaker`, `.playAndRecord` routes to the earpiece, which is wrong for a hands-free flow. AirPods (and most modern Bluetooth headsets) use the AirPods mic and speaker as one route regardless of `.defaultToSpeaker`. `.duckOthers` only applies while the session is active; deactivating the session restores the other app's volume.

**Implication for design.** Configure `.playAndRecord` with `[.duckOthers, .defaultToSpeaker, .allowBluetoothA2DP, .allowBluetooth]`. This gives correct hands-free behavior on iPhone speaker, AirPods, and CarPlay alike. Activate the session when the user opens the app and deactivate on app background only if no synthesis or recognition is active. ([AVAudioSession.CategoryOptions](https://developer.apple.com/documentation/avfaudio/avaudiosession/categoryoptions))

### Interruption handling

**What it is.** `AVAudioSession.interruptionNotification` fires with a `userInfo` dictionary containing `AVAudioSessionInterruptionTypeKey` (`.began` or `.ended`) and on `.ended` an `AVAudioSessionInterruptionOptionKey` indicating whether the system suggests resuming (`.shouldResume`). Triggers include incoming phone calls, FaceTime, alarms, Siri, and other apps requesting an exclusive session.

**Constraints.** On `.began`, your audio is already stopped by the system; you cannot prevent it. On `.ended` with `.shouldResume`, you must reactivate the session yourself; the system does not auto-resume. iOS 17 added some refinements around how Siri activations report interruption versus duck. Multiple rapid interruptions (e.g., a Siri activation immediately followed by an alarm) can leave your session in an unexpected state; defensive reactivation is necessary.

**Implication for design.** The state machine needs an `interrupted` state that can be entered from any active state. On entry, capture what was happening (speaking versus listening) and on `.ended` resume that activity if `.shouldResume` is set, otherwise return to idle. Always reactivate the session explicitly after interruption; never assume it is still active. ([Handling audio interruptions](https://developer.apple.com/documentation/avfaudio/handling-audio-interruptions))

### Route change handling

**What it is.** `AVAudioSession.routeChangeNotification` fires when the audio route changes (AirPods connected, headphones unplugged, CarPlay attached, Bluetooth speaker disconnected). The `userInfo` provides `AVAudioSessionRouteChangeReasonKey` (`.newDeviceAvailable`, `.oldDeviceUnavailable`, `.categoryChange`, `.override`, `.routeConfigurationChange`, etc.) and the previous route description.

**Constraints.** Headphones unplugged conventionally pauses playback (the `.oldDeviceUnavailable` reason is the trigger). New device available does not automatically pause; you decide. CarPlay routes change input and output simultaneously and may also trigger a category change notification; handle them in either order. The `.routeConfigurationChange` reason fires for sample rate or channel changes within the same physical route and is usually safe to ignore.

**Implication for design.** Wire route-change handling into the state machine as a soft interrupt: on headphones unplugged, pause speaking and prompt the user before continuing on the speaker. On CarPlay attached, optionally adjust prosody (slightly slower) and keep the session active. On AirPods connected mid-flow, no action needed. ([Responding to audio route changes](https://developer.apple.com/documentation/avfaudio/avaudiosession/responding_to_audio_session_route_changes), [AVAudioSession.RouteChangeReason](https://developer.apple.com/documentation/avfaudio/avaudiosession/routechangereason))

### Microphone authorization

**What it is.** Separate from speech recognition authorization. iOS 17 introduced `AVAudioApplication.requestRecordPermission` as the new entry point; `AVAudioSession.requestRecordPermission` still works but is deprecated. `NSMicrophoneUsageDescription` is required.

**Constraints.** Denied permission cannot be re-prompted; the only path to grant is Settings. Permission is per-app, not per-session. The simulator grants a synthetic permission automatically; real-device behavior is the only source of truth.

**Implication for design.** Cover this under the unified "voice ready" permissions state described in the SFSpeechRecognizer section. Use `AVAudioApplication` for new code per iOS 17 guidance. ([NSMicrophoneUsageDescription](https://developer.apple.com/documentation/BundleResources/Information-Property-List/NSMicrophoneUsageDescription))

### Background audio entitlement and Info.plist

**What it is.** Add `audio` to the `UIBackgroundModes` array in Info.plist to let the app continue audio (playback or recording) when backgrounded. No separate entitlement file is required for this capability on iOS.

**Constraints.** Adding `audio` to `UIBackgroundModes` is reviewed by App Review; misuse (using it as a way to keep general background execution alive) leads to rejection. The session must be active before backgrounding. CarPlay scenarios may need additional entitlements (`com.apple.developer.carplay-*`) depending on whether you ship a CarPlay scene or rely on Siri-only integration.

**Implication for design.** Include `audio` in `UIBackgroundModes` for v1 to support locked-screen morning flows. Defer any CarPlay-scene entitlement work; rely on App Intents and Siri for CarPlay invocation in v1. ([UIBackgroundModes](https://developer.apple.com/documentation/bundleresources/information-property-list/uibackgroundmodes))

### Echo cancellation

**What it is.** When the device speaker and mic are simultaneously active, the synthesizer's audio leaks into the mic and corrupts recognition. Platform acoustic echo cancellation suppresses this. It is enabled automatically in `.voiceChat` mode, and on iOS 17+ can be enabled in `.playAndRecord` with `.default` mode by calling `setPrefersEchoCancelledInput(true)` on supported hardware.

**Constraints.** Hardware support varies; `setPrefersEchoCancelledInput` returns success but the underlying hardware may not honor it on older devices. AEC quality is hardware-dependent and is best on iPhone 12 and later. AEC adds a small amount of input latency (tens of milliseconds) and slightly alters the input signal; this is usually invisible to recognition but can matter for `.measurement` workflows.

**Implication for design.** Use `.voiceChat` mode as the primary path. Treat `setPrefersEchoCancelledInput` as a useful fallback if you have a reason to stay in `.default` mode. Do not attempt to implement custom echo cancellation; the platform implementation is good and the alternatives are not. ([setPrefersEchoCancelledInput](https://developer.apple.com/documentation/avfaudio/avaudiosession/setprefersechocancelledinput(_:)))

### Simulator versus device differences

**What it is.** The iOS Simulator approximates audio APIs but has well-known divergence: microphone routing uses the Mac's input device, audio session category enforcement is looser, route change notifications do not reflect real Bluetooth devices, AEC is essentially absent, and `AVSpeechSynthesizer` has had multiple regressions in iOS 16/17 simulators where speech is silent.

**Constraints.** Speech recognition often works in the simulator but is the only audio API consistently reliable there. Anything voice-out or barge-in must be tested on a real device.

**Implication for design.** Set up a tight on-device dev loop early. Treat simulator passes as necessary-but-not-sufficient. Add a small "audio diagnostics" debug screen to the app that logs the active route, category, mode, and AEC state, so issues on real devices and TestFlight builds are easy to diagnose.

## AppIntents

### Intent definition basics

**What it is.** `AppIntent` is a Swift protocol; an intent is a struct conforming to it with `@Parameter` properties for inputs and a `perform()` method returning a result. iOS 16 introduced the framework; iOS 17 added significant refinements (extension support, custom dynamic options, predictable intents). Build settings auto-generate metadata from the conforming types; no `.intentdefinition` file needed.

**Constraints.** Intents must be `Codable` and have a no-arg initializer; complex types as parameters require `AppEntity` conformance. App Intents do not replace all of SiriKit; certain domains (messaging on the lock screen, payments, ride-booking, media playback control via system UI) still flow through SiriKit's INIntent classes. The framework was iOS 16+ and is the recommended path for everything new on iOS 17.6.

**Implication for design.** Use App Intents for all CheckIn voice-trigger entry points: "open CheckIn", "what's next", "read my email", "summary". Plan intents at coarse granularity matching natural Siri phrases, not at fine granularity matching internal state-machine transitions. The state machine takes over once the intent's `perform()` opens the app. ([AppIntent](https://developer.apple.com/documentation/appintents/appintent), [App Intents framework](https://developer.apple.com/documentation/appintents))

### Parameter resolution

**What it is.** `@Parameter` properties drive the resolution flow. From Siri voice, the system asks the user for missing values via spoken dialog. In-app launches can supply values directly. iOS 17 supports dynamic options via `DynamicOptionsProvider` so the candidate values can be drawn from runtime data (e.g. recent senders).

**Constraints.** Parameter dialog text is required for voice flows; missing prompt strings produce poor user experience. Type coercion from spoken input to your parameter type is best for built-in types (`String`, `Int`, dates, persons, locations); custom enums require explicit `AppEnum` conformance and localized title strings.

**Implication for design.** Most v1 CheckIn intents take no parameters (the "summary" command summarizes the next item in the prepared queue). For "read email from X", take a `Person`-typed parameter and let Siri handle the contact lookup. Build the more interactive flows (reply, send) inside the app rather than as App Intents, since they are stateful and benefit from the state-machine context. ([Parameter resolution](https://developer.apple.com/documentation/appintents/parameter-resolution))

### Spoken response (`ProvidesDialog`)

**What it is.** Conforming an intent's return type to `ProvidesDialog` lets `perform()` return both a result and an `IntentDialog` that Siri speaks to the user. Combined with `ShowsSnippetView` you can also show a SwiftUI view in the Siri UI.

**Constraints.** The dialog is spoken by the system Siri voice, not by `AVSpeechSynthesizer` and not by the voice the user picked in your app. There is no way to override the Siri voice for an App Intent response; consistency between Siri's voice and CheckIn's in-app voice cannot be achieved here. Dialog text is plain (no SSML).

**Implication for design.** Use `ProvidesDialog` only for short confirmations of background actions ("Marked as read"). For anything substantive (reading a message body, summarizing meetings), `OpensIntent` so control transfers into the app where the chosen `AVSpeechSynthesizer` voice and full state-machine context apply.

### Open-in-app versus background execution

**What it is.** `static var openAppWhenRun: Bool = true` (or conformance to `OpensIntent`) brings the app to the foreground before `perform()` completes. `ForegroundContinuableIntent` allows starting in the background and then requesting foreground continuation via `requestToContinueInForeground()`. Default is background execution.

**Constraints.** Background-running intents have a few seconds of execution time; long work needs to either continue in the foreground or be deferred to a background task. Foregrounding from CarPlay and the lock screen has different UX (lock screen requires authentication for some actions; CarPlay shows a short transition and may require Siri confirmation).

**Implication for design.** "What's next" and "summary" intents should `OpensIntent` because the natural flow is to read content aloud and accept follow-up commands; that requires a foreground app with a live audio session. "Mark as read" or "skip" style intents (if added later) can run in the background with a `ProvidesDialog` confirmation. ([ForegroundContinuableIntent](https://developer.apple.com/documentation/appintents/foregroundcontinuableintent))

### Disambiguation

**What it is.** `requestDisambiguation(among:dialog:)` on a parameter's `$`-prefixed property wrapper asks Siri to present a list of choices and returns the user's pick. `requestConfirmation(for:dialog:)` similarly confirms a value.

**Constraints.** Disambiguation is built for short lists (3 to 6 items in practice); long lists become a tedious voice loop. The dialog text supports interpolated parameter names but no markup. Disambiguation only runs if Siri triggered the intent; programmatic invocation from inside the app skips it.

**Implication for design.** Reserve disambiguation for the cases where Siri-side resolution genuinely needs it (multiple contacts named "Tony"). For richer command flows like "the second one", do disambiguation inside the state machine using an in-app voice prompt rather than via App Intents, where you have full prosody control. ([requestDisambiguation](https://developer.apple.com/documentation/appintents/intentparameter/requestdisambiguation(among:dialog:)))

### `AppShortcutsProvider` and phrases

**What it is.** A type conforming to `AppShortcutsProvider` declares a static array of `AppShortcut`s, each binding an intent to one or more spoken phrases. Phrases must include `\(.applicationName)` somewhere. iOS 17 enables defining the provider in an App Intents extension so phrases work without launching the host app in the background.

**Constraints.** Phrases are not freely composable; users must say something close to the registered phrase plus the app name. Variations beyond what you register are not auto-discovered. You can include up to one parameter slot per phrase. Phrases are localized via `AppShortcutPhrase` strings tables. Apple advises a small set per shortcut (typically 5 or fewer phrasings).

**Implication for design.** Register a small set of high-value phrases: "what's next on \(.applicationName)", "open my \(.applicationName)", "read my email on \(.applicationName)", "check in with \(.applicationName)". Localize at least to English first; add German if the user's language patterns warrant it. ([AppShortcutsProvider](https://developer.apple.com/documentation/appintents/appshortcutsprovider))

### Donations

**What it is.** `IntentDonationManager.shared.donate(intent:)` records that an intent ran, which influences Siri suggestions, Smart Stack widgets, Spotlight, and Focus filtering. `PredictableIntent` and `RelevantContext` let the system reason about timing and context for proactive surfacing.

**Constraints.** Donations are cumulative and ranked by recency and relevance; very frequent donations of the same intent produce diminishing returns. There is no public API to read or clear your own donations from outside Settings. Donations made via the older `INInteraction` SiriKit API and donations made via `IntentDonationManager` are not unified perfectly; once you adopt App Intents, donate exclusively through the new path.

**Implication for design.** Donate the "what's next" / "summary" intent every morning when the user opens the app and again at natural transitions (after a summary, after sending a reply). This trains Siri to surface CheckIn at the right time without requiring "Hey Siri" every morning.

### Trigger surfaces (Siri, Shortcuts, lock screen, CarPlay)

**What it is.** A registered App Intent runs from "Hey Siri", the Shortcuts app, Spotlight search, the Action Button (iPhone 15 Pro+), Focus mode automations, the lock screen Shortcuts widget, and CarPlay (via Siri). The same `perform()` runs in all cases; the framework abstracts the surface.

**Constraints.** Lock-screen and CarPlay invocations cannot freely show in-app UI; foreground-required intents prompt the user to unlock or accept the transition. Some surfaces (CarPlay especially) prefer short spoken responses over opening the app; design accordingly. The "Hey Siri" wake word is owned by Siri; CheckIn cannot register a custom wake word.

**Implication for design.** Treat App Intents as the entry layer that gets the user from elsewhere into the app's voice loop. The state machine begins once `perform()` foregrounds the app and finishes setup. Avoid designing flows that require lots of UI from the lock screen or CarPlay; spoken dialog is the primary modality there, and the screen is secondary.

## Natural Language framework

Apple's Natural Language framework (`import NaturalLanguage`) is the on-device classical NLP layer that sits between the recognized transcript from `SFSpeechRecognizer` and the intent classifier and entity extractor in CheckIn's voice intelligence layer. It is the right surface for v1 because it requires no model-training infrastructure beyond Create ML, runs entirely on-device, and avoids the size, memory, and approval costs of an LLM. Foundation Models is explicitly out of scope for this section.

### NLEmbedding

**What it is.** `NLEmbedding` maps strings to fixed-length real-valued vectors so that semantically similar strings land near each other in vector space. Two flavors: word embeddings via `NLEmbedding.wordEmbedding(for:)` and sentence embeddings via `NLEmbedding.sentenceEmbedding(for:)`. Vectors are 512 doubles. Built-in word and sentence embeddings ship for English, Spanish, French, Italian, German, Portuguese, and Simplified Chinese. Distance is computed via `distance(between:and:distanceType:)` and nearest-neighbor lookup via `neighbors(for:maximumCount:distanceType:)`; the only `NLDistanceType` exposed is `.cosine`. Custom word embeddings can be packaged as `.mlmodel` assets and loaded by URL.

**Constraints.** Static embeddings; the same word always maps to the same vector regardless of surrounding context, so polysemous words (e.g. "meeting" the noun versus "meeting" the verb form) are not disambiguated. Only seven languages have built-in support; non-supported languages require a custom embedding or fall back to the contextual model below. Sentence embeddings are available from iOS 14 onward and use Apple's own pretrained model (not BERT). The vocabulary of the built-in word embedding is finite; out-of-vocabulary tokens return `nil` rather than a graceful approximation. Cosine is the only distance metric; if you need Euclidean or dot-product, compute it on the raw vector arrays yourself. Loading the embedding has measurable cost (tens of milliseconds first-time, smaller subsequently); hold a reference instead of reloading per call.

**Implication for design.** Use `NLEmbedding.sentenceEmbedding(for: .english)` to compute a vector for the recognized utterance and score cosine similarity against pre-computed vectors for each canonical intent phrase ("summarize", "what's next", "read it", "skip", "help"). Pick the highest scorer above a confidence threshold; below threshold, route to the out-of-scope intent. Cache the loaded embedding for the app lifetime. ([NLEmbedding](https://developer.apple.com/documentation/naturallanguage/nlembedding), [sentenceEmbedding(for:)](https://developer.apple.com/documentation/naturallanguage/nlembedding/sentenceembedding(for:)), [NLDistanceType.cosine](https://developer.apple.com/documentation/naturallanguage/nldistancetype/cosine))

### NLTagger

**What it is.** `NLTagger` annotates text with linguistic information by tag scheme. The relevant schemes are `.lexicalClass` (part of speech: noun, verb, adjective, etc.), `.nameType` (named entity recognition), `.lemma` (dictionary form of a word), and `.language` (per-segment language detection). Tags are produced via `enumerateTags(in:unit:scheme:options:)` over a unit of `.word`, `.sentence`, `.paragraph`, or `.document`. Useful options include `.omitPunctuation`, `.omitWhitespace`, `.omitOther`, and `.joinNames` (which collapses multi-token names like "David Anderson" into a single tag).

**Constraints.** Built-in `.nameType` recognizes only three entity classes: `.personalName`, `.placeName`, and `.organizationName`. There is no built-in entity for time expressions, dates, durations, email addresses, or message subjects; for those you must combine with `NSDataDetector` (dates, addresses, phone numbers, links) or a custom Core ML word tagger. NER quality is decent for common Western names and degrades on unusual ones, hyphenated names, and names that overlap common words. Lemmatization quality varies by language. The tagger holds a reference to the input string; mutating the string while enumerating is a use-after-free in disguise.

**Implication for design.** Run `NLTagger` with `.nameType` and `.joinNames` to extract contact-name candidates from utterances like "read the email from David Anderson"; cross-reference the result against the user's contact list rather than trusting the tagger alone. Use `NSDataDetector` in parallel for dates and time ranges. If accuracy on the proper-noun list (which overlaps the speech recognition custom language model vocabulary) becomes a bottleneck, train a custom Core ML word tagger on synthetic CheckIn-style utterances; this is the natural escalation path. ([NLTagger](https://developer.apple.com/documentation/naturallanguage/nltagger), [Identifying people, places, and organizations](https://developer.apple.com/documentation/naturallanguage/identifying-people-places-and-organizations))

### NLLanguageRecognizer

**What it is.** `NLLanguageRecognizer` identifies the language of a string. `dominantLanguage(for:)` is the one-shot static helper. The instance form supports incremental processing via `processString(_:)`, returns the most likely language via `dominantLanguage`, and exposes `languageHypotheses(withMaximum:)` which returns a `[NLLanguage: Double]` of confidence scores for the top N candidates. Constraints can be set via `languageConstraints` (allowed languages) and `languageHints` (prior probabilities) to bias detection.

**Constraints.** Detection is unreliable on very short inputs; short command-style utterances of two or three words are exactly the worst case. Confidence scores are not calibrated probabilities, just relative rankings. Mixed-language inputs return the dominant language only; there is no per-span language segmentation from this class (use `NLTagger` with the `.language` scheme for that, with similar caveats on short input). Adding `languageHints` matching the user's profile noticeably improves accuracy on short inputs.

**Implication for design.** For v1, the user's locale is fixed at app setup and recognition runs in that locale's custom language model, so language detection is not on the hot path. Keep `NLLanguageRecognizer` as a diagnostic tool: if recognized text repeatedly fails to match any intent embedding, run language detection (with `languageHints` set to the configured locale plus likely alternates) to catch the case where the user is dictating in the wrong language and surface a clear "your locale is set to English" prompt. ([NLLanguageRecognizer](https://developer.apple.com/documentation/naturallanguage/nllanguagerecognizer))

### NLTokenizer

**What it is.** `NLTokenizer` segments text into units of `.word`, `.sentence`, `.paragraph`, or `.document`. Tokenization is locale-aware: `setLanguage(_:)` selects the segmenter, which matters for languages without whitespace word boundaries (Chinese, Japanese, Thai). Enumeration via `enumerateTokens(in:using:)` yields `Range<String.Index>` plus `NLTokenizer.Attributes` flags such as `.numeric` and `.symbolic`. Unicode handling is correct including for combining characters, emoji sequences, and grapheme clusters.

**Constraints.** Sentence segmentation depends on punctuation and is unreliable on transcripts where the recognizer omits final punctuation, which is the common case for `SFSpeechRecognizer` partial and final results without explicit dictation commands. Word tokenization on English mostly matches whitespace plus punctuation rules; do not assume token count equals "what the user said" count. There is no streaming tokenizer; you tokenize a complete string at a time.

**Implication for design.** Tokenize the final transcript at `.word` granularity to drive simple keyword-presence checks before falling back to embedding similarity (a fast pre-filter for unambiguous commands like a single word "skip"). Use `.sentence` granularity only where the input is known to be punctuated, such as a dictated email reply with explicit punctuation commands. ([NLTokenizer](https://developer.apple.com/documentation/naturallanguage/nltokenizer))

### NLContextualEmbedding

**What it is.** Introduced at WWDC 2023 and available from iOS 17, `NLContextualEmbedding` is a transformer-based (BERT-family) embedding model that produces a sequence of context-dependent vectors per input rather than one static vector per token. Identified by language or script via `NLContextualEmbeddingKey`; covers up to 27 languages across three scripts (Latin, Cyrillic, CJK). Exposes asset-management APIs to request asset download (`requestAssets(completionHandler:)`), check availability (`hasAvailableAssets`), and load (`load()`) before use. Vectors are produced by `embeddingResult(for:language:)` returning an `NLContextualEmbeddingResult` with per-token vectors. Designed to be the embedding source for custom Create ML text classifiers and word taggers via the multilingual BERT route.

**Constraints.** iOS 17 only; not available on iOS 16 or earlier. Model assets are downloaded on demand and not bundled in the OS by default; first use requires a download (a few hundred megabytes for the multilingual model), and `hasAvailableAssets` must be checked before calling `load()`. Memory footprint when loaded is much larger than `NLEmbedding` (hundreds of megabytes versus tens). Latency per inference is materially higher; expect tens of milliseconds per short utterance on modern hardware versus sub-millisecond for static embedding lookup. The contextual vectors are a sequence (one per token), not a single sentence vector; pooling (mean, CLS-style first token, or attention-weighted) is the developer's responsibility. The output dimensionality and tokenizer are model-specific and queried via the model's properties.

**Implication for design.** Default v1 to `NLEmbedding` sentence embeddings for intent similarity; the latency, memory, and download cost of `NLContextualEmbedding` are not justified for a small fixed intent set. Reserve `NLContextualEmbedding` for two scenarios that may emerge later: multilingual operation outside the seven-language NLEmbedding set, and training a custom Create ML text classifier where contextual embeddings as the feature extractor materially outperform static embeddings on short ambiguous utterances. Treat the asset download as a known onboarding cost if v2 adopts this. ([NLContextualEmbedding](https://developer.apple.com/documentation/naturallanguage/nlcontextualembedding), [NLContextualEmbeddingKey](https://developer.apple.com/documentation/naturallanguage/nlcontextualembeddingkey), [Explore Natural Language multilingual models (WWDC23)](https://developer.apple.com/videos/play/wwdc2023/10042/))

### Custom Core ML text classifiers and word taggers

**What it is.** Create ML supports two text-model templates: a text classifier (input string, output category label) and a word tagger (input string, output sequence of per-token labels). Training is done in the Create ML app or via the `CreateML` Swift framework. Feature-extraction options include the older static word embedding, dynamic-embedding-based (sentence) features, transfer-learning over a built-in static embedding, and on iOS 17 the BERT contextual embedding from `NLContextualEmbedding`. Trained `.mlmodel` files are deployed in the app bundle and consumed via `NLModel(mlModel:)` then attached to an `NLTagger` (for word taggers) or invoked directly via `NLModel.predictedLabel(for:)` (for text classifiers).

**Constraints.** Training data quality drives accuracy more than feature choice; small or unbalanced datasets produce brittle models even with BERT features. Word-tagger labeled-data format (per-token JSON with token and label arrays) is finicky; tokenization mismatches between training and inference are a common silent failure. Model files using BERT features are larger than static-embedding versions, though still small compared to the embedding asset itself, which is shared. Versioning is the developer's problem; an `.mlmodel` baked into the app cannot be updated without an app release.

**Implication for design.** Skip custom Create ML for v1; the intent set is small enough that `NLEmbedding` cosine similarity against canonical phrases plus a confidence threshold is sufficient and far cheaper to maintain. Promote to a custom text classifier only when (a) ambiguous-but-real utterances start landing in the out-of-scope bucket in production telemetry, or (b) the multilingual story expands beyond the built-in seven languages. When that happens, generate training data synthetically from intent templates plus the user's contact list, and prefer BERT-based features only if a static-embedding-trained model fails to hit the accuracy target. ([NLModel](https://developer.apple.com/documentation/naturallanguage/nlmodel), [Creating a model from data](https://developer.apple.com/documentation/createml))

### Performance and threading

**What it is.** All Natural Language framework APIs run synchronously on the calling thread. Static `NLEmbedding` lookups are sub-millisecond after first load; `NLTagger` enumeration on short utterances is similarly fast. `NLLanguageRecognizer` and `NLTokenizer` are negligible on short inputs. `NLContextualEmbedding` inference is tens of milliseconds per utterance on modern hardware once loaded. Memory footprint of a loaded built-in `NLEmbedding` is measured in tens of megabytes; `NLContextualEmbedding` in hundreds. All processing is on-device with no network call.

**Constraints.** The framework is documented as thread-safe for concurrent reads on a loaded `NLEmbedding` or `NLContextualEmbedding`, but `NLTagger` instances hold mutable string state and must not be shared across threads. First-call latency for any model includes a one-time load cost; budget for this in a warm-up step rather than letting the user experience it on the first command. There is no async API; wrap calls in a `Task` or dispatch to a background queue if you need to avoid blocking the main thread.

**Implication for design.** Warm `NLEmbedding.sentenceEmbedding(for: locale)` and any custom `NLModel` during the same setup step that warms the audio session and the recognizer's custom language model. Run NL processing on a dedicated background queue keyed off the state machine's "transcript ready" event, not on the main thread. The latency budget for intent classification on the final transcript is comfortably under 50 milliseconds with `NLEmbedding`, leaving headroom for entity extraction and the action lookup before the synthesis turn begins. ([Natural Language](https://developer.apple.com/documentation/NaturalLanguage))

### Integration with the speech path

**What it is.** Transcripts arrive from `SFSpeechRecognizer` as `SFTranscription` objects, with partial results firing during dictation and a final result at end-of-audio. The Natural Language framework consumes plain `String` input. The integration question is which transcript stage to feed into NL, and how partial-result instability interacts with the cost and side-effects of NL processing.

**Constraints.** Partial results are not stable; tokens get rewritten as more audio arrives, and confidence is not populated until the final result. Running expensive NL processing (especially `NLContextualEmbedding`) on every partial is wasteful and can produce a flicker of conflicting intent classifications. Running NL only on the final result delays user feedback by the silence-detection hangover plus the recognizer's finalization time, typically a few hundred milliseconds. Partial-result NL is only worth the cost for cheap operations (tokenization, keyword scan, language detection on accumulated text).

**Implication for design.** The state machine should run a cheap pass on partials (`NLTokenizer` for keyword detection of unambiguous early-exit commands like "stop", "cancel", "skip") and a full pass (`NLEmbedding` similarity for intent, `NLTagger` for entities, `NSDataDetector` for dates) only on the final transcript. Display the cheap-pass result as a hint in the UI while audio continues; commit and act on the full-pass result. This matches the broader rule from the SFSpeechRecognizer section that destructive actions must wait for `isFinal`. ([SFTranscription](https://developer.apple.com/documentation/speech/sftranscription), [Natural Language](https://developer.apple.com/documentation/NaturalLanguage))

## Sources

Primary sources are Apple developer documentation pages, linked inline above. Apple's WWDC sessions used as supplementary primary sources are [Customize on-device speech recognition (WWDC23)](https://developer.apple.com/videos/play/wwdc2023/10101/), [Extend Speech Synthesis with personal and custom voices (WWDC23)](https://developer.apple.com/videos/play/wwdc2023/10033/), [Explore Natural Language multilingual models (WWDC23)](https://developer.apple.com/videos/play/wwdc2023/10042/), [Make apps smarter with Natural Language (WWDC20)](https://developer.apple.com/videos/play/wwdc2020/10657/), [Dive into App Intents (WWDC22)](https://developer.apple.com/videos/play/wwdc2022/10032/), and [Donate intents and expand your app's presence (WWDC21)](https://developer.apple.com/videos/play/wwdc2021/10231/). Two third-party sources fill specific gaps and are flagged here: Ben Dodson's blog on [Personal Voice integration](https://bendodson.com/weblog/2024/04/03/using-your-personal-voice-in-an-ios-app/) for the practical voiceTraits pattern; and Apple Developer Forums threads on [AVSpeechSynthesizer iOS 17 issues](https://developer.apple.com/forums/thread/738048) for the bug history that is not in the formal documentation. Where Apple documentation contradicts a third-party source, the documentation governs.
