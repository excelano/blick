# CheckIn: Architecture and Swift Guide

A reference document for reading and modifying the CheckIn codebase. Tailored for a senior engineer fluent in Java, Go, and a long list of other languages, but new to Swift and to iOS.

This guide is pitched at the level of "what do I need to know to read this code with confidence and make changes without surprise." It is not a Swift textbook; it is the bridge from what you already know to what the codebase assumes you know.

---

## Part 1. The big picture

### 1.1 What CheckIn is

CheckIn is a voice-first iOS app that gives a hands-free daily check-in for Microsoft 365: next meeting, unread emails, pending Teams chats. It does not display email bodies, does not implement reply, and does not duplicate Outlook or Teams. Tapping any item deep-links to the right Microsoft app. The app is designed around 33 numbered decisions in `DESIGN.md` and a hierarchical state machine in `STATES.md`. Every spoken phrase is reviewed against `PERSONA.md`.

### 1.2 The four layers

Reading inside-out:

**State machine spine.** The single source of truth for what the app is doing. `StateMachine` (an `@Observable` class) owns a `DialogState` enum and a `DialogContext` struct. Every voice or touch action transitions through this. SwiftUI views read the state and re-render automatically.

**Dialog layer.** Three protocols: `IntentClassifier` (what did the user mean), `EntityMatcher` (who or what did they refer to), `ResponseGenerator` (what do we say back). Concrete implementations: `NLEmbeddingIntentClassifier` using Apple's Natural Language framework, `NLTaggerEntityMatcher` for proper-noun extraction, `PersonaResponseGenerator` driving the persona-tuned `ResponseTemplateRegistry`.

**Service layer.** Side-effecty wrappers around iOS frameworks: `AuthService` (MSAL), `GraphClient` (Microsoft Graph), `SpeechService` (SFSpeechRecognizer, audio session, voice-activity detection), `TTSService` (AVSpeechSynthesizer), `EarconPlayer` (short audio cues), `DeepLinkService` (URL builders for Outlook and Teams), `CustomLanguageModelManager` (D10 opt-in tuning).

**View layer.** The SwiftUI surface added in Phase 4. `ContentView` is the auth gate, `SummaryView` is the only main screen per D27, and `OnboardingFlow`, `SettingsView`, and `HelpView` are the supporting flows. `Indicators.swift` holds the small animated views that surface state (listening, thinking, captioning).

### 1.3 A voice turn, end to end

To make the layering concrete, here is a single tap-and-speak interaction:

The user taps the mic button on `SummaryView`. The button action calls `stateMachine.transition(to: .active(.listening))`. SwiftUI re-renders because `currentState` is observable; the `voiceArea` switch now matches `.listening` and shows `ListeningIndicator`. Phase 5 hooks the same transition to `SpeechService.start()`, which configures `AVAudioSession`, starts the recognizer with on-device-only requirement, and runs voice-activity detection on the audio engine input tap.

The user says "what's on my plate." VAD detects end-of-utterance. The recognizer hands back a transcript. The state machine transitions to `.active(.processing(.thinking))`. The thinking earcon plays. The transcript goes into the dialog layer: `NLEmbeddingIntentClassifier.classify("what's on my plate")` computes sentence embeddings against the anchor catalog, finds `Intent.summary` is closest, and returns a `ClassifiedIntent` with confidence and any alternatives within the gap.

For `.summary` the state machine fetches the latest summary via `GraphClient` (or returns a cached one from `DialogContext.summary`) and asks `PersonaResponseGenerator.generate(for: classified, context: context)`. The generator pulls a phrasing from `ResponseTemplateRegistry.summarySentence(from: summary)` and returns a `SpokenResponse`. The state machine transitions to `.active(.speaking(response: ..., returnTo: .idle))`. `TTSService` plays the spoken text via `AVSpeechSynthesizer`. `CaptioningView` shows the same text on screen for the deaf-or-hearing-impaired path per D22.

When TTS finishes, the state machine transitions to the rest state (`.active(.idle)` for tap-to-talk, `.active(.listening)` for conversation mode). The dialog ledger remembers the phrasing so anti-repeat can avoid it next time, the turn is recorded in `DialogContext.turnHistory`, and the app awaits the next turn.

Phase 4 has the entire state-machine and view loop wired and observable. Phase 5 is where the real Apple service bodies plug in.

---

## Part 2. Swift idioms by way of comparison

This section is dense but mostly things you can read once and refer back to. The comparisons are to Java, Go, and where useful Rust. For Swift features added after Swift 3 (async/await, property wrappers, result builders, macros, SwiftUI), see the companion document `SWIFT-MODERN.md`.

### 2.1 Structs vs classes

Swift gives you both. They mean different things.

A `struct` is a value type. It is copied on assignment, copied on argument passing, equatable component-wise if you ask for it. Swift's `String`, `Array`, `Dictionary`, `Set`, and almost every type in the standard library are structs. The cost of "copying" is small because Swift uses copy-on-write internally; you do not pay for copies you do not mutate.

A `class` is a reference type. Multiple variables can point to the same instance. Reference cycles are a concern. Inheritance works on classes, not structs.

Java reference: structs are roughly Java records (value-typed by convention), classes are Java classes. Swift differs in that you write `let foo = Foo()` and reassigning `foo` to another `Foo` is a copy, not a reference reassignment.

Go reference: a Swift struct is a Go struct passed by value. A Swift class is a Go struct accessed via pointer. The default in Go is "by value unless you take the pointer"; the default in Swift is "by value if struct, by reference if class."

Rule of thumb for CheckIn: data carriers (`Email`, `Meeting`, `ChatMessage`, `CheckInSummary`, `DialogContext`, `Turn`) are structs. Things that own behavior, hold lifecycle state, or need shared identity (`StateMachine`, `AuthService`, `CustomLanguageModelManager`) are classes. The state machine has to be a class because it is observed across many views and they all need to see the same instance.

### 2.2 Protocols

Protocols are Swift's interface mechanism. They are richer than Java interfaces and similar in spirit to Go interfaces, with a few differences.

A protocol is a contract: methods, computed properties, associated types. Concrete types declare conformance: `struct NLTaggerEntityMatcher: EntityMatcher { ... }`. The conformance is checked statically.

You can extend a protocol to give it default implementations:

```swift
extension EntityMatcher {
    func match(text: String) -> [EntityMatch] {
        // default that delegates to the four-arg form
    }
}
```

Any type conforming to `EntityMatcher` automatically gets that default unless it overrides.

You can also extend concrete types after the fact:

```swift
extension Color {
    init(hex: UInt, alpha: Double = 1.0) { ... }
}
```

This is how `Brand.swift` adds `Color(hex: 0x2ab8d0)` even though `Color` is in SwiftUI's framework. Java has nothing equivalent. Go has a similar capability via type assertions plus method-on-newtype, but extension is more direct.

Protocols can have `associatedtype` requirements (like Java generics on the interface itself). They cannot inherit from a protocol that uses associatedtype if you want to use them as existential types (`var x: SomeProto`); for those cases use `some Proto` (an opaque type, like Go's "I return some specific type that conforms to this") or generics.

### 2.3 Optionals

`Optional<T>` is the same idea as Java's `Optional<T>`, but it is a built-in language feature and the compiler enforces nil-safety at every usage site.

`String?` is shorthand for `Optional<String>`. It can hold `.some(String)` or `.none`. You cannot accidentally call methods on a nil String; the compiler stops you.

The five idiomatic ways to use an optional:

```swift
let x: String? = ...

if let value = x { ... use value ... }            // optional binding
guard let value = x else { return }                // bail out early
let value = x ?? "default"                          // nil coalescing
let length = x?.count                                // optional chaining (returns Int?)
let length = x!.count                                // force-unwrap, crashes if nil
```

Force-unwrap (`!`) is the Swift equivalent of intentionally throwing a NullPointerException. Use it only when you genuinely know the value is non-nil and want a crash if you are wrong. CheckIn uses it almost nowhere.

`if let` and `guard let` both unwrap. The difference: `if let` enters the new scope only on success and continues without the value on failure. `guard let` introduces the unwrapped name into the current scope and forces the failure branch to leave the function.

### 2.4 Enums (this is the one Java programmers will love)

Swift enums are not Java enums. They are closer to Rust enums, ML-style sum types, or Java sealed classes with pattern matching.

An enum case can carry associated values:

```swift
enum DialogState: Equatable {
    case signedOut
    case onboarding(OnboardingSubstate)
    case active(ActiveSubstate)
}

enum ActiveSubstate: Equatable {
    case idle
    case listening
    case processing(ProcessingPhase)
    case speaking(response: SpokenResponse, returnTo: RestState)
    case disambiguating(suspendedIntent: SuspendedIntent, candidates: [Candidate])
    case confirming(pendingAction: PendingAction)
    case helpDisplayed(returnTo: RestState)
    case settingsDisplayed(returnTo: RestState)
}
```

You match on them with `switch`:

```swift
switch stateMachine.currentState {
case .signedOut:
    SignInView(...)
case .onboarding:
    OnboardingFlow(...)
case .active(.listening):
    ListeningIndicator()
case .active(.speaking(let response, _)):
    CaptioningView(text: response.text)
case .active(.disambiguating(let suspended, let candidates)):
    DisambiguatingPanel(utterance: suspended.utterance, candidates: candidates, ...)
default:
    EmptyView()
}
```

A few things to notice:

The `switch` is exhaustive; the compiler errors if you miss a case (unless you `default`). The `let` syntax binds the associated value to a name. `_` is "I don't care about this part." You can match nested patterns directly: `.active(.speaking)` matches any `.speaking` case regardless of payload.

This is the architectural backbone of CheckIn. The state machine is a single enum with associated values, the intent layer is an enum, the response category is an enum. Reach for enums liberally; they cost nothing at runtime and the compiler does the type-system work for you.

The Java mental model: think `sealed interface Shape { record Circle(double r) ...; record Square(double side) ...; }` and then `switch` with pattern matching. Swift had this baked in from day one.

### 2.5 Closures and trailing closure syntax

A closure is an anonymous function. The full syntax is:

```swift
let add: (Int, Int) -> Int = { (a, b) in
    a + b
}
```

But you almost never see the full form. Swift infers types aggressively, and trailing closures move the last closure argument outside the parens:

```swift
// Full form
button.onTapGesture(perform: { print("tapped") })

// Trailing closure — last argument moves outside
button.onTapGesture { print("tapped") }
```

When a function takes only a closure, the parens disappear too:

```swift
func work(_ block: () -> Void) { block() }
work { print("doing it") }
```

In SwiftUI you see this constantly. `Button { action } label: { Text("Tap me") }` is two trailing closures. The first is the action, the second is the label.

The argument list `in` separator is "here ends the parameter list, here begins the body":

```swift
displayNames.filter { name in name.hasPrefix("J") }
```

For single-argument closures, Swift gives you `$0`:

```swift
displayNames.filter { $0.hasPrefix("J") }
```

You will see all three forms in the codebase. They mean the same thing.

### 2.6 Property wrappers (the `@` prefixes)

A property wrapper is a generic struct (or class) that decorates a stored property. The decoration adds behavior: storage, observation, persistence, dependency injection, whatever. Java annotations are the closest analog, but property wrappers actually run code; Java annotations are passive metadata read by frameworks.

The ones you will see in CheckIn:

`@State` — view-owned mutable storage. The view owns the value; mutating it triggers a re-render. Used for transient UI state inside a single view (whether a sheet is open, what the user typed into a text field).

`@Binding` — a two-way reference into someone else's `@State`. The parent holds the storage; the child reads and writes through the binding. Pass it as `$variable` (the dollar prefix turns the wrapped value into the binding).

`@Observable` (a macro, technically, not a wrapper) — applied to a class. Properties read inside any view's `body` automatically subscribe that view to changes. Replaces the older `@ObservableObject` plus `@Published` pattern from before iOS 17. `StateMachine`, `AuthService`, and `CustomLanguageModelManager` all use this.

`@AppStorage("key")` — `@State` backed by `UserDefaults`. Survives launches. Used for `hasCompletedOnboarding`, `listeningMode`, `voiceTuningEnabled`, and the D25 client-ID overrides.

`@Environment(\.dismiss)` — value flowing down the view tree. The `\.dismiss` is a key path; the environment dictionary is keyed by these. Used inside sheets to call `dismiss()` and close them.

`@MainActor` — not a property wrapper, an actor isolation attribute. Pins a class or method to the main thread. UI work goes here. `AuthService` and `CustomLanguageModelManager` are both `@MainActor`.

The `$` prefix on a property wrapper variable gives you the projected value. For `@State var foo: Int`, `foo` is the `Int`, `$foo` is the `Binding<Int>`. Pass `$foo` when a child view declares `@Binding var foo: Int`.

### 2.7 Error handling

Swift errors look like Java checked exceptions but feel like Go's error returns. A function declared `throws` may throw an error (any type conforming to the `Error` protocol). Callers use `try` and one of three forms:

```swift
do {
    let token = try await authService.signIn(enableTeams: false)
} catch {
    // 'error' is implicitly available; the catch matches any Error
    errorMessage = error.localizedDescription
}

let token = try? await authService.signIn(enableTeams: false)  // Optional<String>
let token = try! await authService.signIn(enableTeams: false)  // crashes on error
```

Errors are typically defined as enums conforming to `LocalizedError`:

```swift
enum AuthError: LocalizedError {
    case notConfigured
    case noViewController
    case notAuthenticated
    case adminConsentRequired

    var errorDescription: String? {
        switch self { ... }
    }
}
```

You catch specific cases by pattern:

```swift
do {
    try operation()
} catch AuthError.adminConsentRequired {
    // handle this specific case
} catch let error as NSError where error.domain == MSALErrorDomain {
    // handle MSAL-specific NSErrors
} catch {
    // anything else
}
```

In contrast to Java, every throwing function must be marked `throws` and every call must be `try`-prefixed. There is no checked-vs-unchecked distinction. In contrast to Go, there is no explicit error return value; the language hides the plumbing.

### 2.8 Concurrency

Swift's modern concurrency model (Swift 5.5, late 2021) uses async/await with structured concurrency. If your last serious Swift exposure was 2016, this is entirely new.

A function declared `async` can suspend at `await` points:

```swift
func signIn(enableTeams: Bool) async throws -> String {
    let result = try await msalApp.acquireToken(with: params)
    return result.accessToken
}
```

Calling an async function requires an `await`. From synchronous code (like a button action), you wrap in a `Task`:

```swift
Button("Sign In") {
    Task {
        do {
            _ = try await authService.signIn(enableTeams: false)
            onAuthenticated()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

`Task` starts a unit of asynchronous work. It is roughly Java's `CompletableFuture.runAsync` or Go's `go func() {}` but with structured-concurrency rules: a Task inherits priority and actor context from where it was started, and cancellation propagates.

`@MainActor` is an actor attribute that pins code to the main thread. Calling a `@MainActor` method from a non-main context requires an `await`. Because views run on the main actor by default, calling main-actor code from a view body works without ceremony. The fence between background work and UI updates is the actor boundary.

`actor` (the keyword) declares a type whose mutable state is accessed serially. Like Java's `synchronized` blocks, but the compiler enforces that you cannot reach actor state without going through the actor. CheckIn does not currently define its own actors; `StateMachine` is an `@Observable class` running implicitly on the main actor because it is touched from views.

The mental shift from blocking + threads to async + suspension takes a beat, but the resulting code looks sequential. There is no callback hell, no `Future.thenCompose`. You just write `let x = try await foo()` and Swift figures out scheduling.

### 2.9 Strings

A `String` in Swift is not a sequence of bytes. It is not even a sequence of code points. It is a sequence of grapheme clusters, where a grapheme cluster is what a human would call "one character" (an emoji with a skin-tone modifier, or "n" plus a combining tilde making "ñ", count as one grapheme).

Two consequences:

You cannot index by integer. `s[5]` does not compile. You use `String.Index` values, which the API exposes via methods like `s.index(s.startIndex, offsetBy: 5)`. Range subscripts work the same way. The reason is that the cost of "the fifth character" depends on what is upstream; Swift refuses to hide the cost.

For most CheckIn work you do not need to index. You match prefixes (`s.hasPrefix(...)`), check contains (`s.contains(...)`), iterate, split, regex, lower/upper-case, trim. `s.lowercased()`, `s.split(separator: " ")`, and so on. When you do need indices, the API is verbose but explicit.

The `as NSString` bridge gives you Foundation's `NSString`, which is byte-positionable and works with `NSRegularExpression`. `NLTaggerEntityMatcher.matchNumbers` uses this pattern:

```swift
let nsText = lowercased as NSString
let matches = regex.matches(in: lowercased, range: NSRange(location: 0, length: nsText.length))
```

That is the price of bridging across the regex boundary. Modern Swift (5.7+) has a native `Regex` type that avoids the bridge entirely; the codebase predates that and uses NSRegularExpression for compatibility with older patterns.

### 2.10 Generics

Generics work like Java generics, with no erasure (the type information is retained at runtime) and with constraint syntax like Rust:

```swift
func first<T: Equatable>(in array: [T], matching value: T) -> T? {
    array.first { $0 == value }
}
```

Constraints can use `where` clauses for complex predicates:

```swift
extension Sequence where Element: Numeric {
    func sum() -> Element { reduce(0, +) }
}
```

The `some Proto` syntax (opaque return type) and `any Proto` syntax (existential type) are newer (Swift 5.7+) and worth understanding:

`some View` says "I return one specific type that conforms to View, but I am not telling you which." The compiler knows; the caller gets type-erasure-free composition. Used everywhere in SwiftUI.

`any View` is the existential equivalent: "any type conforming to View, boxed up." More flexible, less efficient, rarely seen in SwiftUI because the static composition is the point.

### 2.11 Result builders

A result builder is a piece of compiler-supported syntactic magic that turns a block of expressions into a single value via static methods. The canonical example is SwiftUI's `@ViewBuilder`:

```swift
VStack {
    Text("Hello")
    if showSubtitle {
        Text("subtitle")
    }
    Image(systemName: "star")
}
```

This is not a closure that returns one View. The `@ViewBuilder`-attributed parameter consumes each expression and assembles them into a tuple-of-views (or a conditional) using compiler-rewritten calls to static `buildBlock`, `buildEither`, `buildOptional`. You can write:

```swift
@ViewBuilder
private var summaryContent: some View {
    if let summary = stateMachine.context.summary {
        MeetingCard(...)
        ForEach(summary.emails) { ... }
    } else {
        notFetchedState
    }
}
```

and the compiler turns it into a working view hierarchy. No commas, no return statements, no array literal. Just write the views.

Other result builders in the standard library: `RegexComponentBuilder`, `AccessibilityRotorContentBuilder`. SwiftUI defines several specific to its DSL. You will rarely need to write your own.

---

## Part 3. SwiftUI

### 3.1 The View protocol and body

A View is a struct conforming to the `View` protocol. The protocol's only requirement (apart from default-provided ones) is the `body` computed property:

```swift
struct ListeningIndicator: View {
    var body: some View {
        ZStack { ... }
    }
}
```

Views are values. SwiftUI rebuilds them constantly: every state change can rebuild the entire body. This is cheap because views describe layout, they do not own UIKit objects directly. SwiftUI diffs the description against the previous one and updates only what changed.

Because a view is a struct, mutating it from inside requires careful thought. You cannot just `self.foo = bar` from within `body`. The state-management property wrappers exist precisely to give you mutable storage attached to a view value.

### 3.2 Result builders inside braces

The `body` returns `some View`. Inside braces under SwiftUI containers (`VStack`, `HStack`, `ZStack`, `ScrollView`, `Group`, `Form`, `Section`, etc.) you are inside a `@ViewBuilder` block. The rules:

```swift
VStack {
    Text("a")
    Text("b")
    Text("c")
}
```

is three views collected into one VStack. No commas. Each line is its own expression. Conditionals are allowed but each branch must produce a View:

```swift
if loaded {
    SummaryView(...)
} else {
    LoadingView()
}
```

`switch` works the same way, with each case producing a view. You cannot, however, freely intersperse non-view statements like `let x = 5; print(x)`. For that, you need a computed property:

```swift
private var content: some View {
    let truncatedSubject = String(email.subject.prefix(40))
    return VStack {
        Text(truncatedSubject)
        ...
    }
}
```

Note the `return`. Single-expression closures and properties have implicit return; multi-statement ones need `return`.

### 3.3 Modifiers as wrapping functions

Modifiers like `.padding()`, `.foregroundStyle(.red)`, `.font(.title)` are method calls on the view that return a new wrapped view. They do not mutate; they wrap.

This means order matters. `.padding().background(.red)` puts a red box around a padded view; `.background(.red).padding()` puts padding around a red box. When something is positioned wrong visually, suspect modifier order first.

A common pattern in CheckIn:

```swift
Button("Sign Out") { signOut() }
    .foregroundStyle(.red)
    .frame(maxWidth: .infinity, alignment: .center)
```

Each line wraps the previous. The original `Button` is intact at the bottom; the chain produces a different view.

### 3.4 State management

The five state-management mechanisms in CheckIn:

**`@State`.** Single-view-owned mutable storage. Use for "is this sheet showing", "is this button currently animating", "what did the user type". Lives and dies with the view. In `OnboardingFlow.swift`, `@State private var micRequested = false` is owned by `PermissionsStep`.

**`@Binding`.** A reference into someone else's `@State`. The parent stores; the child reads and writes. Pass with `$`:

```swift
struct ParentView: View {
    @State private var name = ""
    var body: some View {
        ChildView(text: $name)  // pass the binding
    }
}

struct ChildView: View {
    @Binding var text: String  // receives the binding
    var body: some View {
        TextField("Name", text: $text)  // pass it onward to TextField
    }
}
```

**`@Observable` classes.** Reference-typed shared state. Any property you read in any view's body subscribes that view to changes. `StateMachine` is the central example:

```swift
@Observable
final class StateMachine {
    private(set) var currentState: DialogState = .signedOut
    ...
}
```

Views take this in as a normal `var stateMachine: StateMachine`. No `@ObservedObject`, no `@StateObject` (those are pre-iOS-17 patterns); just declare it and read it. The compiler and runtime do the bookkeeping. Use `@State` to own one in a top-level view (like `CheckInApp.swift`):

```swift
@State private var stateMachine = StateMachine()
```

`@State` here means "I own this reference and am responsible for its lifecycle." It does not mean "this is a value type wrapped in @State"; the wrapper is content-agnostic.

**`@AppStorage`.** `@State` plus `UserDefaults`. The wrapped property is read and written through user defaults; the view re-renders when the underlying value changes (even if changed elsewhere in the app):

```swift
@AppStorage("listeningMode") private var listeningMode: String = "tapToTalk"
```

Used in `SettingsView`, `OnboardingFlow`, `CustomLanguageModelManager`, and `ContentView`. The string key namespaces the storage; matching keys across views see the same value.

**`@Environment`.** Implicit context flowing down the view tree. Two main uses in CheckIn: `@Environment(\.dismiss)` inside sheets to get the dismiss closure, and `@Environment(\.accessibilityReduceMotion)` to read the user's reduced-motion preference.

### 3.5 Sheets, navigation, lifecycle

A sheet is a modal that slides up from the bottom. You attach it via `.sheet(isPresented:)`:

```swift
.sheet(isPresented: $showHelp) {
    HelpView()
}
```

The `$showHelp` binding controls visibility. Toggle the bool to true and the sheet animates up; toggle to false (or call `dismiss()` from inside) and it slides away.

CheckIn drives sheets off the state machine, not local Bool state. The pattern in `SummaryView.swift`:

```swift
private var helpBinding: Binding<Bool> {
    Binding(
        get: {
            if case .active(.helpDisplayed) = stateMachine.currentState { return true }
            return false
        },
        set: { presented in
            if !presented {
                if case .active(.helpDisplayed(let returnTo)) = stateMachine.currentState {
                    stateMachine.transition(to: .active(returnTo == .listening ? .listening : .idle))
                }
            }
        }
    )
}
```

This synthesizes a Binding<Bool> from the state machine. The getter returns true when state is `.helpDisplayed`; the setter transitions back to the rest state when the system tells us the sheet was dismissed. The view stays a passive observer of the state machine.

`NavigationStack` is the iOS 17 navigation container; it replaces the older `NavigationView`. Push views with `.navigationDestination(for: ...)` or with `NavigationLink`. CheckIn uses `NavigationStack` only inside sheets to get a title bar with a Done button.

Lifecycle hooks attach to views:

`.onAppear { ... }` fires when the view becomes visible. Once. Refires if the view leaves and returns.

`.task { await ... }` fires when the view appears, like onAppear, but it is async-aware and is automatically cancelled when the view disappears. Use this for loading data.

`.onChange(of: someValue) { old, new in ... }` fires when a tracked value changes. Used in `SettingsView` to push a listening-mode change into the state machine.

### 3.6 Accessibility

Apple takes accessibility seriously enough that every public app should pass a basic VoiceOver pass. The key modifiers:

```swift
.accessibilityLabel("Microphone")              // what VoiceOver reads
.accessibilityHint("Tap to start listening")   // additional context after a pause
.accessibilityElement(children: .combine)      // group children into one element
.accessibilityElement(children: .ignore)       // hide all children, use only label
.accessibilityAddTraits(.isSelected)           // additional behavior cues
```

Dynamic Type happens for free if you use named fonts (`.body`, `.title2`, `.caption`) instead of fixed-size fonts (`.system(size: 14)`). The CheckIn convention is to use named fonts everywhere except for SF Symbol icons, which scale via SF Symbol weights and the icon's intrinsic font setting.

`@Environment(\.accessibilityReduceMotion)` reads the user's "Reduce Motion" toggle. `ListeningIndicator.swift` uses this to swap a pulse animation for a steady ring when the toggle is on.

VoiceOver testing is done by enabling it in the simulator (Cmd-F5) or on device (triple-click the side button). Phase 6's pre-TestFlight checklist will run a full pass.

---

## Part 4. CheckIn architecture in detail

### 4.1 The state machine

`State/DialogState.swift` is the single most important file in the codebase. Every other file makes sense in relation to it.

Top-level cases:

```swift
enum DialogState: Equatable {
    case signedOut
    case onboarding(OnboardingSubstate)
    case active(ActiveSubstate)
}
```

`OnboardingSubstate` is a flat enum with four cases: `welcome`, `permissions`, `mode`, `firstQuery`. `ActiveSubstate` is the meat:

```swift
enum ActiveSubstate: Equatable {
    case idle
    case listening
    case processing(ProcessingPhase)
    case speaking(response: SpokenResponse, returnTo: RestState)
    case disambiguating(suspendedIntent: SuspendedIntent, candidates: [Candidate])
    case confirming(pendingAction: PendingAction)
    case helpDisplayed(returnTo: RestState)
    case settingsDisplayed(returnTo: RestState)
}
```

The associated values carry payload that the substate cannot exist without: a speaking state must know what is being spoken; a confirming state must know what action is pending. Trying to transition to `.confirming` without a `PendingAction` is a compile error, not a runtime null check.

`RestState` is `idle` or `listening`, the two valid resting points. Speaking, help, and settings all carry a `returnTo` so they know where to land on exit. The state machine's `preferredRestState` property mirrors the current listening-mode setting.

`StateMachine` (the class) is the only place that mutates state:

```swift
@Observable
final class StateMachine {
    private(set) var currentState: DialogState = .signedOut
    private(set) var context: DialogContext = DialogContext()

    func transition(to newState: DialogState) {
        let from = currentState
        currentState = newState
        log(from: from, to: newState)
    }

    func updateContext(_ mutate: (inout DialogContext) -> Void) {
        mutate(&context)
    }
    ...
}
```

`private(set)` means external code can read but not write directly. The mutation closure pattern (`updateContext`) lets callers do batch context updates without exposing context to wholesale replacement.

### 4.2 The dialog protocols

Three protocols, each in `Dialog/`:

`IntentClassifier` answers "what did the user mean":
```swift
protocol IntentClassifier {
    func classify(_ utterance: String, context: DialogContext) -> ClassifiedIntent
}
```

`EntityMatcher` answers "who or what did they refer to":
```swift
protocol EntityMatcher {
    func match(text: String, domain: EntityDomain, context: DialogContext) -> [EntityMatch]
}
```

`ResponseGenerator` answers "what do we say back":
```swift
protocol ResponseGenerator {
    func generate(for intent: ClassifiedIntent, context: DialogContext) -> SpokenResponse
}
```

Phase 2 shipped deterministic stub implementations behind these protocols. Phase 3 replaced the stubs with real implementations using Apple's NaturalLanguage framework. The protocols stay; the bindings change. This is the D15 boundary: design clean seams now, swap implementations later, keep tests stable.

### 4.3 Concrete implementations

`NLEmbeddingIntentClassifier` (Phase 3). Uses `NLEmbedding.sentenceEmbedding(for: .english)` to compute a sentence embedding for the utterance, then computes cosine distance against a curated catalog of anchor phrases per intent (`IntentAnchors.swift`). The closest intent wins, subject to a confidence floor. Distance gaps below a threshold surface alternatives for D7 disambiguation. Below the unknown-floor, the result is `.unknown`.

`NLTaggerEntityMatcher` (Phase 3). Uses `NLTagger` with `.nameType` scheme to extract personal names. Reconciles surface forms against the senders and chat partners visible in the current `CheckInSummary` so "Tony" canonicalizes to "Tony Smith" when only one Tony is in scope. Falls back to first-name regex matching for utterances NLTagger ranks below threshold.

`PersonaResponseGenerator` (Phase 3). Switches on the classified intent and pulls phrasings from `ResponseTemplateRegistry`, an enum that holds every TTS string in the app. Anti-repeat: the generator filters the pool against `DialogContext.recentRefusals` and `recentRedirects` so the user does not hear the same line twice in a row.

`ResponseTemplateRegistry` is large (800+ lines). It is structured by purpose: refusal pool (12 phrasings), redirect pools per `UnsupportedKind` (5 pools, 8 each), latency reassurance and escalation, error pools by category, help short and long, onboarding invitations, confirmation prompts and success announcements per `ActionKind`, summary builders. Every phrase is reviewed against `PERSONA.md`.

### 4.4 Services

`Services/` is the side-effect layer. Each file wraps an iOS framework with a CheckIn-shaped API.

`AuthService` wraps MSAL. `signIn(enableTeams:)` fires the interactive browser flow; `acquireTokenSilently` refreshes silently or falls back to interactive. `signOut` clears the MSAL account. Marked `@MainActor` because MSAL's UI presentation needs the main thread.

`GraphClient` wraps Microsoft Graph for the four data fetches (user ID, today's meetings, unread emails, Teams chats) plus the Day 1 summary aggregator. Uses `URLSession` directly; no third-party HTTP library. Phase 5 wires it to the state machine on `.refresh` intent.

`SpeechService` (currently a stub) will own `SFSpeechRecognizer` configured for on-device only, the audio session, and voice-activity detection on the audio engine input tap. Per D9 this is non-negotiably on-device.

`TTSService` (stub) will wrap `AVSpeechSynthesizer`, with delegate callbacks for D8 barge-in tracking. Phase 5 wires the actual playback.

`EarconPlayer` (stub) plays the three short audio cues: listening, thinking, confirmation. The WAV files are in `Sounds/`, synthesized in Phase 2 from a pure-stdlib Python script.

`DeepLinkService` builds Outlook and Teams URLs. No state, no class, just `enum DeepLinkService` with static functions.

`CustomLanguageModelManager` (Phase 3). Manages the D10 custom language model: builds an `SFCustomLanguageModelData` over M365 contact display names and saves it under app support. Off by default; toggling on triggers the build, toggling off clears the file. The recognizer in `SpeechService` will read the prepared configuration when the feature is on.

### 4.5 Views

`Views/` holds Phase 4's SwiftUI surface.

`ContentView.swift` is the auth gate. It switches on `stateMachine.currentState`'s top-level case:

```swift
switch stateMachine.currentState {
case .signedOut:
    SignInView(authService: authService, onAuthenticated: bootstrapAfterAuth)
case .onboarding:
    OnboardingFlow(stateMachine: stateMachine)
case .active:
    SummaryView(stateMachine: stateMachine, authService: authService)
}
```

`bootstrapOnLaunch` runs in `.onAppear` and jumps the state machine past `.signedOut` if MSAL has a cached account.

`SummaryView.swift` is the only main screen. Layout: top bar (?, gear), summary content (meeting card + email rows + chat rows), voice area (state-driven indicator/caption/panel), mic button. Sheets for help and settings are bound to the state machine. Tapping any row deep-links via `DeepLinkService`.

`Indicators.swift` has the three small state-cue views: `ListeningIndicator`, `ThinkingIndicator`, `CaptioningView`. All three have reduce-motion variants per D22.

`HelpView.swift` is the D30 help sheet with three collapsible sections. Takes a `HelpFocus` enum to control which section opens by default based on recent context.

`SettingsView.swift` is the D5/D17/D10/D25 settings sheet. Uses `Form` for the iOS-standard settings appearance. Includes two child sheets: the D10 disclosure and the D25 explainer.

`OnboardingFlow.swift` is the four-step first-run flow, switching on `OnboardingSubstate`. Each step is its own private struct. Real permission requests use iOS 17's `AVAudioApplication.requestRecordPermission` and `SFSpeechRecognizer.requestAuthorization`.

---

## Part 5. Reading the code

### 5.1 Starting points

Three reading orders depending on what you want:

**To understand the architecture top-down:** read in this order:
1. `DESIGN.md` — the 33 numbered decisions
2. `STATES.md` — the state diagram
3. `State/DialogState.swift` — the enum that encodes the state diagram
4. `State/StateMachine.swift` — the class that owns the state
5. `Views/ContentView.swift` — how the state drives the UI
6. `Views/SummaryView.swift` — the main screen wiring

**To understand the voice flow:** start at the protocols and follow:
1. `Dialog/IntentClassifier.swift` — the protocol
2. `Dialog/IntentAnchors.swift` — the catalog of phrasings
3. `Dialog/NLEmbeddingIntentClassifier.swift` — the real implementation
4. `Dialog/NLTaggerEntityMatcher.swift` — entity extraction
5. `Dialog/ResponseTemplateRegistry.swift` — every TTS string
6. `Dialog/PersonaResponseGenerator.swift` — the picker

**To understand the data flow:** look at:
1. `Models/CheckInSummary.swift` — the wire-format-shaped struct
2. `Models/Email.swift`, `Meeting.swift`, `ChatMessage.swift` — the components
3. `Services/GraphClient.swift` — the fetcher
4. `State/DialogContext.swift` — the in-memory cache

### 5.2 Tracing a voice turn (Phase 5 wiring will be like this)

A voice turn is structured around state transitions. Walking through:

1. User taps mic. `SummaryView.micTapped()` calls `stateMachine.transition(to: .active(.listening))`. Phase 5 will also call `SpeechService.start()`.
2. SwiftUI re-renders SummaryView because `currentState` changed. The voiceArea switch matches `.listening` and shows `ListeningIndicator`. The mic icon flips to `stop.fill`.
3. The recognizer captures audio, VAD detects end of utterance, the recognizer hands back a transcript. Phase 5's `SpeechService` delegate call transitions to `.active(.processing(.thinking))`.
4. The thinking earcon plays. The processing branch dispatches: classify, match entities, fetch from Graph if needed.
5. `NLEmbeddingIntentClassifier.classify(utterance, context)` returns a `ClassifiedIntent`. `NLTaggerEntityMatcher.match(text, domain, context)` returns entity matches. The state machine combines them into a logical action.
6. For `.summary`: the cached `CheckInSummary` (or a fresh fetch) feeds `PersonaResponseGenerator.generate(for: classified, context)` which returns a `SpokenResponse`.
7. State transitions to `.active(.speaking(response: ..., returnTo: .idle))`. SwiftUI re-renders; the voiceArea switch shows `CaptioningView` with the response text. `TTSService.speak(response.text)` plays the audio.
8. TTS completion fires the speaking-finished delegate, which transitions to `.active(.idle)` (or `.listening` for conversation mode). The dialog ledger records the turn.

Cross-cutting concerns:
- Barge-in: tapping mic during `.speaking` cancels TTS and re-enters `.listening`.
- Out-of-scope: classify returns `.outOfScope`, response generator picks from refusal pool.
- In-scope-unsupported: classify returns `.inScopeUnsupported(.readContent)` etc., generator picks from the right redirect pool.
- Disambiguation: classifier returns alternatives within the gap, state transitions to `.disambiguating`.
- Confirmation (Day 2/3): destructive actions transition to `.confirming` first.

### 5.3 Adding a new intent (worked example for Day 2 "mark Tony's email as read")

The mechanical steps:

1. Add the case to the `Intent` enum in `Dialog/IntentClassifier.swift`:
   ```swift
   case markRead
   ```

2. Add anchor phrasings to `Dialog/IntentAnchors.swift`:
   ```swift
   (.markRead, [
       "mark as read",
       "mark Tony's email read",
       "mark this read",
       ...
   ])
   ```

3. Handle the new intent in `Dialog/PersonaResponseGenerator.swift`:
   ```swift
   case .markRead:
       return confirmationPrompt(for: pendingAction)
   ```

4. Add the action to `ActionKind` in `State/DialogState.swift`:
   ```swift
   case markEmailRead   // already there, was anticipated
   ```

5. Add a confirmation phrasing and success announcement to `ResponseTemplateRegistry`.

6. Wire the executor: when state transitions out of `.confirming` with yes, the state machine calls `GraphClient.markEmailRead(messageID:)` and transitions to `.processing` -> `.speaking` with the success response.

7. Add an example phrasing to `HelpView`'s `laterContent` (it's currently in "Coming later"), and move "Mark read" from there to `doNowContent`.

The protocols and templates do most of the work; the new code is small.

### 5.4 Where every D1-D33 decision lives

This is the cross-reference. When you wonder "where in the code is decision X enforced", this list answers.

D1 (state-based voice): `State/DialogState.swift`, `State/StateMachine.swift`, every voice transition.
D2 (multi-modal): `Views/SummaryView.swift` mic plus tap rows; the `?` and gear buttons.
D3 (explicit dialog context): `State/DialogContext.swift`.
D4 (explicit persona): `PERSONA.md`, `Dialog/ResponseTemplateRegistry.swift`.
D5 (voice parameters): `Views/SettingsView.swift` voice section, `@AppStorage("voiceIdentifier")`, `"speechRate"`, `"verbosityFull"`.
D6 (designed errors): `Dialog/ResponseTemplateRegistry.swift` error pools.
D7 (disambiguation): `ActiveSubstate.disambiguating`, `Views/SummaryView.swift` `DisambiguatingPanel`, `NLEmbeddingIntentClassifier` alternatives.
D8 (barge-in): `Views/SummaryView.swift` `micTapped()` while in `.speaking`. Phase 5 wires the actual TTS interrupt.
D9 (privacy/on-device): `Services/SpeechService.swift` `requiresOnDeviceRecognition = true`, `PRIVACY.md`.
D10 (custom LM opt-in): `Services/CustomLanguageModelManager.swift`, `Views/SettingsView.swift` voice tuning section.
D11 (no server-side speech): inverse of D9; nothing to point at.
D12 (Day 1 minimal): the `Intent` enum's case set.
D13 (silent on open + earcons): `Services/EarconPlayer.swift`, `Sounds/`.
D14 (classical NLP): `Dialog/NLEmbeddingIntentClassifier.swift`, `Dialog/NLTaggerEntityMatcher.swift`.
D15 (clean boundaries): the three Dialog protocols.
D16 (auto-listen, no wake word): superseded by D17.
D17 (conversation vs tap-to-talk): `@AppStorage("listeningMode")`, `Views/SettingsView.swift`, `StateMachine.preferredRestState`.
D18 (refusal pool): `Dialog/ResponseTemplateRegistry.refusals`.
D19 (redirect pools): `Dialog/ResponseTemplateRegistry.readContentRedirects` etc.
D20 (no content obscurance): no extra code; default iOS lock behavior.
D21 (latency pools): `Dialog/ResponseTemplateRegistry.latencyReassurance/Escalation`.
D22 (accessibility): `Views/Indicators.swift` reduce-motion, `.accessibilityLabel` everywhere, `CaptioningView`.
D23 (dialog context in memory): `State/DialogContext.swift`; nothing persists.
D24 (no telemetry): inverse; absence of telemetry SDKs.
D25 (custom Azure registration): `Views/SettingsView.swift` Advanced section, `@AppStorage("customClientID")`, `"customAuthority"`.
D26 (self-hosting docs): `SELF-HOSTING.md`.
D27 (single screen + deep-link): `Views/SummaryView.swift`, `Services/DeepLinkService.swift`.
D28 (confirmation pattern): `ActiveSubstate.confirming`, `Views/SummaryView.swift` `ConfirmingPanel`, Day 2/3 only.
D29 (Day 2/3 roadmap): `PLAN.md`, `Views/HelpView.swift` "Coming later" section.
D30 (help system): `Views/HelpView.swift`, `HelpFocus` enum.
D31 (onboarding): `Views/OnboardingFlow.swift`, four steps.
D32 (persona statement): `PERSONA.md`.
D33 (state enumeration): `State/DialogState.swift`, `STATES.md`.

---

## Part 6. iOS frameworks crash course

### 6.1 MSAL

Microsoft Authentication Library for Apple. Imports as `import MSAL`. The flow:

1. Configure once: `MSALPublicClientApplicationConfig` with client ID, authority URL, redirect URI. Build an `MSALPublicClientApplication`.
2. Sign in: `acquireToken(with: MSALInteractiveTokenParameters)` opens the system auth browser, returns a `MSALResult` with `accessToken` and `account`.
3. Refresh: `acquireTokenSilent(with: MSALSilentTokenParameters)` uses the cached refresh token. Catches `MSALError.interactionRequired` to fall back to interactive.
4. Sign out: `remove(MSALAccount)` clears the cache.

The redirect URI scheme is hardcoded into `Info.plist`'s URL types: `msauth.com.excelano.checkin`. The MSAL callback URL is delivered via SwiftUI's `.onOpenURL` on the root view.

### 6.2 Speech framework

`import Speech`. Two important types:

`SFSpeechRecognizer` does the recognition. Set `requiresOnDeviceRecognition = true` per D9. Pass an `SFSpeechAudioBufferRecognitionRequest` and feed it audio buffers from an `AVAudioEngine` input tap. Receive partial and final results via callback or async sequence.

`SFCustomLanguageModelData` (iOS 17+) builds a custom recognition model from phrases. Used in `CustomLanguageModelManager` to bias toward contact names. Save with `data.export(to: url)`, prepare for use with `SFSpeechLanguageModel.prepareCustomLanguageModel(for: url, ...)`, attach to a recognition request via `SFSpeechLanguageModel.Configuration`.

`SFSpeechRecognizer.requestAuthorization { status in ... }` requests permission. The status enum has `.authorized`, `.denied`, `.notDetermined`, `.restricted`.

### 6.3 AVFoundation

`import AVFoundation`. Three things matter for CheckIn:

`AVSpeechSynthesizer` for TTS. Configure with an `AVSpeechSynthesisVoice` (the user's choice from D5) and an `AVSpeechUtterance` with text and rate. Speak with `speak(utterance)`. The delegate provides callbacks for boundary detection (used for D8 barge-in tracking).

`AVAudioSession` configures the audio mode. `.playAndRecord` plus `.voiceChat` mode gives echo cancellation, which lets the mic stay hot during TTS playback for barge-in.

`AVAudioApplication.requestRecordPermission` (iOS 17+) requests microphone permission. `AVAudioApplication.shared.recordPermission` reads the current value.

### 6.4 NaturalLanguage

`import NaturalLanguage`. Two used in CheckIn:

`NLEmbedding.sentenceEmbedding(for: .english)` returns a sentence embedder. `embedder.distance(between: a, and: b)` returns cosine distance. `NLEmbeddingIntentClassifier` uses this to pick the closest anchor phrase.

`NLTagger` with `.nameType` scheme tags personal names, place names, organizations. Configured with options like `.joinNames` to merge "Tony" + "Smith" into a single span. `NLTaggerEntityMatcher` uses this for proper-noun extraction.

These are entirely on-device. No network.

### 6.5 UIKit interop

SwiftUI is fine for app-level work but interops with UIKit when needed. The places CheckIn touches it:

`UIApplication.shared.canOpenURL(url)` checks whether a deep-link target is installed. `UIApplication.shared.open(url)` performs the deep-link.

For MSAL's interactive flow, we hand it the root `UIViewController`. `AuthService` digs through `UIApplication.shared.connectedScenes` to find the `UIWindowScene`'s `keyWindow.rootViewController`. This is iOS 13+ idiomatic; it looks gnarly but is the documented pattern.

`AVAudioSession` is managed via `AVAudioSession.sharedInstance()`. CheckIn does this in `SpeechService` (Phase 5).

---

## Part 7. Project conventions

### File headers

Every Swift file starts with:

```swift
// FileName.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)
```

The author owns the work; AI assistance is acknowledged in-file. Commits also include a `Co-Authored-By: Claude <noreply@anthropic.com>` trailer.

### Numbered decisions as source of truth

`DESIGN.md` is the spec. When you see `D27` referenced in code or a doc, it points to that numbered decision in `DESIGN.md`. The decision number is stable across edits to the surrounding text. When you change behavior, update the decision; when you add a new pattern, add a new decision.

### Phase sequence

The build proceeds in numbered phases per `PLAN.md`:

1. Phase 1: scaffolding and design artifacts (complete)
2. Phase 2: architecture build (complete, commit f652f95)
3. Phase 3: Day 1 voice intelligence (complete, commit e34f2c1)
4. Phase 4: SwiftUI surface (complete, commit 8295660)
5. Phase 5: integration and on-device verification (next)
6. Phase 6: pre-TestFlight checklist (after Phase 5)

Each phase is testable in isolation and depends on earlier phases.

### Commit messages

Multi-paragraph body explaining what and why. Subject line under 70 characters. Follow the style of the previous commits (`Phase 4: SwiftUI surface`, `Phase 3: Day 1 voice intelligence`, etc.). HEREDOC the body for clean formatting.

---

## Part 8. Stumbling blocks

### Things that will surprise you

**Strings are not random-access.** Reaching for `s[i]` with an integer subscript will not compile. Lean on prefix/suffix/contains/split rather than indexing. When you must index, use `String.Index` arithmetic.

**Closures capture by reference for classes, by value for structs.** A closure that captures a class instance keeps it alive (potential retain cycle). Use `[weak self]` capture lists when needed:

```swift
Task { [weak self] in
    guard let self else { return }
    await self.doWork()
}
```

**`@State` should not be used for reference types you do not want to own.** Using `@State` on an `@Observable` class instance is fine for the lifecycle owner; passing it down to a child as a regular `var` (not `@State`) is the right pattern.

**SwiftUI's view identity is structural, not nominal.** Two `Text("foo")` instances that look the same are the same view to SwiftUI. Sometimes you need to give a view an explicit identity with `.id(someValue)` to force re-creation when a value changes. Rare in CheckIn so far.

**The simulator is limited.** Voice features in particular do not work the same way as on device. You will get the surface to render correctly but cannot truly verify the voice loop without an iPhone.

**`async` and main-thread updates are sneaky.** Code in a `Task` does not necessarily run on the main thread. Touching `@MainActor` class properties from a background context requires an `await`. Updating `@State` from a background Task without crossing back to MainActor will produce warnings or unexpected behavior. The general rule: anything that touches UI or `@Observable` views runs on the main actor.

### Common mistakes

**Forgetting `@MainActor` on a service class.** If the class touches UI or is observed by views, it should usually be `@MainActor`. `AuthService` and `CustomLanguageModelManager` are; `GraphClient` is not (its callers are responsible for hopping back to main).

**Forgetting `let` vs `var`.** In Swift `let` is constant, `var` is mutable. The compiler warns when you `var` something that is never mutated. Default to `let`.

**Using force-unwrap (`!`) where optional binding would do.** Force-unwrap means "I am asserting this is non-nil; crash otherwise." Reach for `if let` or `guard let` instead unless you genuinely know the invariant.

**Reaching for `@ObservedObject` or `@StateObject`.** Those are pre-iOS-17 patterns. The codebase uses `@Observable` everywhere; do not mix the old patterns in.

**Writing closures with explicit return when not needed.** Single-expression closures have implicit return:

```swift
displayNames.filter { name in name.hasPrefix("J") }     // returns Bool implicitly
displayNames.filter { name in return name.hasPrefix("J") }  // works, but verbose
```

The first form is the convention.

**Confusing `some` and `any`.** `some View` is "one specific concrete type the compiler picks." `any View` is "type-erased View, runtime-boxed." For SwiftUI's compositional style, `some` is what you want almost always.

---

## Closing notes

The codebase is structured to read top-down from the design docs. If something seems off, the question to ask is which numbered decision it is implementing; if the answer is unclear, the decision may need updating. The state machine spine is the thing to internalize first; everything else hangs off it.

When you come back to this after a few days, start with `DESIGN.md` for the why, `STATES.md` for the shape, and `Views/SummaryView.swift` plus `State/DialogState.swift` for the wiring. Phase 5 picks up from there.

Last updated: 2026-05-08, alongside Phase 4 commit `8295660`.
