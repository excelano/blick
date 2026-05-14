# CheckIn Phase 4 Follow-ups

Findings from the Phase 4 code review (commit 8295660) that were deferred rather than fixed in the immediate cleanup commit. Pick these up when Phase 5 wiring lands on the SwiftUI surface.

The two criticals (ThinkingIndicator timer leak, false-checkmark UI in PermissionsStep) are already fixed.

---

## Important: address before Phase 5 wires real services

### 1. Voice Recognition Tuning toggle flickers on tap-to-on

**Where.** `CheckIn/Views/SettingsView.swift`, `voiceTuningSection`, around lines 160-174.

**Why.** The custom `Binding`'s setter shows the disclosure sheet but does not write `voiceTuningEnabled`. SwiftUI re-evaluates the getter immediately, sees the AppStorage value still false, and snaps the toggle visually back to off. The disclosure then appears over a toggle that looks unchanged.

**Fix.** Use a normal binding and intercept with `.onChange`. The disclosure's Cancel path explicitly sets the AppStorage back to false; the Turn-on path leaves it true.

```swift
Toggle("Voice Recognition Tuning", isOn: $voiceTuningEnabled)
    .onChange(of: voiceTuningEnabled) { _, new in
        if new { showTuningDisclosure = true }
    }
```

In `VoiceTuningDisclosureSheet`, the "Not now" button writes `enabled = false` before dismissing. The "Turn on" button keeps it true and proceeds to the (Phase 5) contact fetch and `buildModel`.

### 2. CustomLanguageModelManager constructed transiently in toggle setter

**Where.** `CheckIn/Views/SettingsView.swift`, line 168-171.

**Why.** `Task { @MainActor in CustomLanguageModelManager().disable() }` constructs a fresh instance each time. Fine right now because `disable()` only touches UserDefaults and the file system. Will break in Phase 5 if the manager grows instance state (a build task handle, retry counter, etc.).

**Fix.** Inject via initializer or hold as `@State` in `SettingsView`, consistent with how `StateMachine` and `AuthService` are passed in:

```swift
struct SettingsView: View {
    var authService: AuthService
    var stateMachine: StateMachine
    @State private var lmManager = CustomLanguageModelManager()
    ...
}
```

### 3. micTapped() does not handle .processing

**Where.** `CheckIn/Views/SummaryView.swift`, `micTapped()` switch around lines 234-249.

**Why.** During `.active(.processing)` the mic button is enabled (`micEnabled` returns true for any `.active`), shows the start-listening icon (`micSymbol` returns `mic.fill`), but tapping does nothing because the switch falls to `default: break`. False affordance.

**Fix.** Either disable the button during processing, or pick an explicit behavior. Disabling is simpler and matches STATES.md, which does not define a touch action for processing:

```swift
private var micEnabled: Bool {
    switch stateMachine.currentState {
    case .active(.processing): return false
    case .active: return true
    default: return false
    }
}
```

The button visual will dim automatically because the symbol uses `Brand.accentDim` when `micEnabled` is false.

### 4. Sign-out dismiss sequencing

**Where.** `CheckIn/Views/SettingsView.swift` `signOut()`, called from the destructive button around line 209.

**Why.** `signOut()` calls `dismiss()` and `stateMachine.transition(to: .signedOut)` in close sequence. SwiftUI sheet dismissal is asynchronous; ContentView swaps SummaryView for SignInView mid-animation. No crash but UIKit may log about presenting over a deallocating view controller.

**Fix.** Defer the state transition to after the dismiss has had a chance to settle:

```swift
private func signOut() {
    authService.signOut()
    dismiss()
    Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(50))
        stateMachine.transition(to: .signedOut)
        stateMachine.resetContext()
    }
}
```

Or restructure so `ContentView`'s switch on `currentState` triggers the dismiss naturally, removing the explicit `dismiss()` call. Either way, get them out of the same render pass.

### 5. External deauthentication recovery

**Where.** `CheckIn/Views/ContentView.swift` `bootstrapOnLaunch`, around lines 43-48.

**Why.** Fires once via `.onAppear`. If MSAL deauthenticates outside the normal sign-out path (token revoked at the server, MDM wipe, manual cache clear from system settings), the gate does not detect it. SummaryView keeps rendering with a dead auth session.

**Fix.** Make the Phase 5 token-acquisition error path responsible for the transition. Every place that calls `acquireTokenSilently` or `acquireToken` and catches a fatal auth error should call `stateMachine.transition(to: .signedOut)` before surfacing the error to the user. Alternatively, expose `isAuthenticated` as an observable property on `AuthService` (already done since it is `@Observable`) and have `ContentView` use `.onChange(of: authService.isAuthenticated)` to react. The latter is cleaner.

```swift
.onChange(of: authService.isAuthenticated) { _, isAuth in
    if !isAuth, case .active = stateMachine.currentState {
        stateMachine.transition(to: .signedOut)
        stateMachine.resetContext()
    }
}
```

This reads tighter than scattering signedOut transitions through every error path.

---

## Minor: opportunistic cleanup

### restState() mapping duplicated across three files

**Where.**
- `CheckIn/Views/SummaryView.swift` `restState()`, line 273
- `CheckIn/Views/ContentView.swift` `bootstrapAfterAuth`, line 56
- `CheckIn/Views/OnboardingFlow.swift` `complete()`, around the same pattern

**Why.** Three places convert `RestState` to `ActiveSubstate` with the same trivial mapping. Fine now; will drift the moment one site grows additional logic.

**Fix.** A computed property on `StateMachine`:

```swift
var preferredActiveSubstate: ActiveSubstate {
    preferredRestState == .listening ? .listening : .idle
}
```

Then `stateMachine.preferredActiveSubstate` everywhere instead of the inline conversion.

---

## Out of scope for this list

The reviewer also noted that `StateMachine.preferredRestState` is mutated directly by views without going through `transition()`. That is intentional: it is a preference that shapes future transitions, not a dialog state transition itself. Worth a brief code comment on the property, but not a behavior change.

---

Last updated: 2026-05-08, alongside Phase 4 commit `8295660` and the critical-fixes follow-up commit.
