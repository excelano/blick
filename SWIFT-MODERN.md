# Swift Since 2016: A Modern Features Cheat Sheet

A companion to `GUIDE.md`. Where that document walks through the CheckIn architecture, this one walks through the parts of Swift that older Swift books (anything pre-2018) do not cover. Treat it as the "what's new since Swift 3" reference, with CheckIn-specific examples.

Swift in 2016 was at version 3. As of CheckIn's iOS 17 target, the toolchain is Swift 5.9+. The major additions that matter for an app developer building today are concurrency (Swift 5.5), property wrappers (Swift 5.1), result builders (Swift 5.4), macros (Swift 5.9), and the entire SwiftUI framework on top. The 2016 book teaches the foundations cleanly, but the actual day-to-day surface of a modern Swift codebase looks notably different from what it taught.

This document is organized roughly in order of how often you will encounter each feature in CheckIn. Concurrency comes first because Phase 5 is going to hit it from every angle. Property wrappers come second because they are the entire vocabulary of SwiftUI state. The rest follow in decreasing frequency.

---

## 1. Concurrency: async, await, Task, AsyncStream, actors

The single biggest change in Swift since 2016. Swift now has first-class concurrency: structured concurrency rules, an `async`/`await` keyword pair that suspends rather than blocks, sequences that produce values over time, and isolated reference types called actors. The model is closer to Rust's `async`/`await` than to Go's goroutines, but with stronger compile-time guarantees and an explicit notion of "main thread" via `@MainActor`.

### 1.1 async functions

A function marked `async` can suspend. Calling one requires `await` at the call site, and the call site itself must be inside an `async` context (another `async` function, a `Task` block, or a SwiftUI `.task` modifier). The compiler enforces this — you cannot accidentally call an async function from a sync context.

```swift
func transcribe(_ url: URL) async throws -> String {
    let audio = try await loadAudio(from: url)
    let text  = try await recognizer.recognize(audio)
    return text
}
```

Read aloud: "transcribe takes a URL, is async, can throw, and returns a string. We await loadAudio, which can throw and is async. Then we await recognizer.recognize."

The `try await` pair is two separate things glued together. `try` propagates errors. `await` marks the suspension point. Order matters: `try await` is correct, `await try` is a compile error. The mental model: at every `await`, the function pauses, the runtime can do other work, and the function resumes later — possibly on a different thread. This is the Swift equivalent of Rust's `.await?`.

### 1.2 Task

`async` functions are inert without something to run them. That something is `Task`. A `Task` is a lightweight unit of work that the runtime schedules on its thread pool. Construct one with the `Task { ... }` initializer.

```swift
Task {
    do {
        let text = try await transcribe(url)
        print(text)
    } catch {
        print("Failed: \(error)")
    }
}
```

Tasks inherit context from where they are constructed. If you create a `Task` inside a `@MainActor` method, the task body also runs on the main actor by default. If you want to escape that, use `Task.detached { ... }` — but you almost never do, because detached tasks lose the structured-concurrency guarantees that make the rest of this section nice to work with.

In CheckIn you will see `Task { @MainActor in ... }` and `Task.detached { ... }` both appear. The first is the common case (do some work, hop to main if needed). The second is rare and should be flagged in code review.

Cancellation is cooperative. Inside a task body you can check `Task.isCancelled` or call `try Task.checkCancellation()` (which throws `CancellationError` if the task was cancelled). A parent task that finishes will cancel its child tasks automatically — this is what structured concurrency buys you. When you write a long-running task body, it is your job to check cancellation at sensible points.

### 1.3 The .task modifier (SwiftUI specifically)

SwiftUI has a view modifier `.task { ... }` that is the right way to start async work from a view. It is preferred over `.onAppear { Task { ... } }` for one critical reason: the `.task` block is automatically cancelled when the view leaves the hierarchy. The plain `.onAppear` + `Task` combination leaks a task if the user navigates away mid-work.

```swift
.task {
    while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(0.35))
        phase = (phase + 1) % 3
    }
}
```

This pattern appears in `CheckIn/Views/Indicators.swift` for the three-dot Thinking animation. The original implementation used `Timer.scheduledTimer` in `.onAppear` with no invalidation — a classic concurrency bug the modern approach prevents structurally. If `ThinkingIndicator` leaves the view hierarchy, the task is cancelled, the sleep returns early, `Task.isCancelled` becomes true, and the loop exits cleanly.

### 1.4 async let (parallel awaits)

When you have two independent async operations you want to run in parallel, `async let` starts both immediately and you await their results when you need them.

```swift
async let calendar = graphClient.fetchTodaysMeetings()
async let unread   = graphClient.fetchUnreadEmails()
let summary = Summary(meetings: try await calendar, emails: try await unread)
```

Read aloud: "async-let calendar equals the call. Async-let unread equals the call. Both have started running. Then we await calendar and emails to build the summary." Compared to writing two sequential `await` calls, `async let` cuts wall-clock time roughly in half when the two operations are independent.

### 1.5 AsyncStream and AsyncSequence

When you have a producer that yields multiple values over time, you don't return a `[String]` or use a Combine `Publisher` — you return an `AsyncSequence`. The most common concrete type you'll build is `AsyncStream<T>`.

```swift
func partialTranscripts() -> AsyncStream<String> {
    AsyncStream { continuation in
        let task = recognizer.startRecognizing { result in
            continuation.yield(result.bestTranscription.formattedString)
            if result.isFinal {
                continuation.finish()
            }
        }
        continuation.onTermination = { _ in task.cancel() }
    }
}

for await partial in partialTranscripts() {
    captionText = partial
}
```

Read aloud: "for-await partial in partial-transcripts." The `for await` loop awaits each value as it arrives. This is the natural pattern for Phase 5's speech recognizer pipeline — partial results stream in over the network of frameworks, and the UI consumes them one at a time. Go programmers will recognize this as the Swift equivalent of `for x := range ch`; Rust programmers will recognize it as `while let Some(x) = stream.next().await`.

`AsyncSequence` is a protocol. `AsyncStream` is the concrete type you instantiate when you need to bridge a callback-based API (which is exactly what SFSpeechRecognizer is) into the modern async world.

### 1.6 Actors

An `actor` is a reference type with isolated mutable state. Every property access from outside the actor is async; the runtime serializes access so the data is never raced.

```swift
actor TranscriptStore {
    private var entries: [String] = []
    func append(_ entry: String) { entries.append(entry) }
    func snapshot() -> [String] { entries }
}

let store = TranscriptStore()
await store.append("hello")
let all = await store.snapshot()
```

Read aloud: "actor TranscriptStore. Await store dot append. Await store dot snapshot." Note the `await` even on a synchronous-looking method — calling across an actor boundary is itself a suspension point because the runtime may need to wait for the actor to be free.

Inside the actor, code runs synchronously and has full access to the actor's state. Outside, every touch is awaited. CheckIn doesn't yet use any custom actors, but you will run into them in framework code (e.g., `URLSession.shared` is bridged through one).

### 1.7 @MainActor

The most important "global actor" you'll see is `@MainActor`. Anything annotated `@MainActor` runs on the main thread, period. Most SwiftUI types are implicitly main-actor isolated. UI updates must happen on the main thread, and `@MainActor` is how Swift now encodes that rule in the type system.

```swift
@MainActor
class ViewModel: ObservableObject {
    @Published var caption: String = ""
}
```

Or per-method:

```swift
class GraphClient {
    @MainActor
    func presentResult(_ summary: Summary) { /* updates UI */ }
}
```

If you try to call a `@MainActor` function from a non-main context without `await`, the compiler stops you. This is the type-level enforcement Rust's `Send`/`Sync` give you, applied to "this code must run on this specific actor." A common Phase 5 pattern: do the work on a background task, then `await MainActor.run { ... }` to hop to main and update state.

```swift
Task {
    let summary = try await graphClient.fetchSummary()
    await MainActor.run {
        stateMachine.context.lastSummary = summary
    }
}
```

### 1.8 Sendable

`Sendable` is a marker protocol that says "values of this type can safely cross actor boundaries." Value types whose stored properties are all `Sendable` get it automatically. Reference types must opt in by inheriting from `Sendable` and proving they're internally safe (typically by being immutable or actor-isolated). The compiler will yell at you when you try to pass a non-`Sendable` reference type into a `Task` body or across an actor boundary.

Swift 5.9 still has the `Sendable` checking at warnings level for many cases. Swift 6 (rumoured but not yet on CheckIn's bar) will tighten this to errors. For now, treat `Sendable` warnings as future errors and fix them as they appear.

### 1.9 The full Phase 5 concurrency picture

When Phase 5 wires the real services, the call graph will look something like this. Take a moment with it; everything you've read above is in here.

```swift
// In SummaryView, when the user taps the mic and we transition to listening:
.onChange(of: stateMachine.currentState) { _, new in
    if case .active(.listening) = new {
        listenTask = Task {
            do {
                for await partial in speechService.transcripts() {
                    await MainActor.run { captionText = partial }
                }
            } catch {
                await MainActor.run {
                    stateMachine.transition(to: .active(.idle))
                }
            }
        }
    } else {
        listenTask?.cancel()
    }
}
```

Reading aloud: "on-change of currentState, comma underscore comma new in. If case dot active dot listening equals new. listenTask equals Task. Do, for await partial in speechService dot transcripts. Await MainActor dot run, captionText equals partial."

`listenTask` is a `Task<Void, Never>?` stored in view state. The view cancels it on any other state transition. The recognizer's `AsyncStream` finishes naturally when speech ends. Errors propagate back to a state transition. There is no manual thread management. There are no callbacks. The compiler has checked every actor hop.

---

## 2. Property Wrappers

Property wrappers (Swift 5.1) let a type encapsulate how a property is stored and accessed. Externally a property wrapper looks like a normal property; internally it's a struct that wraps a value with logic. The desugaring is what unlocks SwiftUI's declarative state model.

Read aloud: "@State var phase equals zero" reads as "at-State var phase equals zero." When fluent devs say "the at-State on phase," they mean the property wrapper attached to the property.

### 2.1 The basic mechanism

You declare a property wrapper as a struct with a `wrappedValue` and the `@propertyWrapper` attribute.

```swift
@propertyWrapper
struct Trimmed {
    private var value: String = ""
    var wrappedValue: String {
        get { value }
        set { value = newValue.trimmingCharacters(in: .whitespaces) }
    }
    init(wrappedValue: String) { self.wrappedValue = wrappedValue }
}

struct User {
    @Trimmed var name: String = "  Alice  "  // stored as "Alice"
}
```

What the compiler does: rewrites `@Trimmed var name` into a private `_name: Trimmed` plus a computed `name` that forwards through the wrapper. The wrapper itself is just a regular struct. This means it can have other API surface — accessible via the `projectedValue` and the `$name` syntax we'll see below.

### 2.2 The SwiftUI state wrappers

SwiftUI ships a handful of property wrappers that are the entire vocabulary of state in a SwiftUI app. The ones CheckIn uses:

**`@State`** marks a view-local source of truth. The view owns the value, the value persists across re-renders, and changing it triggers re-rendering. The book-2016 brain analogy: it's the "instance variable" of a SwiftUI view (which is itself a struct). When you mutate it, SwiftUI notices and re-runs `body`. Use for primitive values local to one view.

```swift
@State private var phase = 0
```

**`@Binding`** is a two-way reference to someone else's state. When a parent view holds `@State var selection = "tap"` and passes `$selection` (note the dollar sign) into a child as a binding, the child receives a `@Binding` that reads and writes back to the parent. The dollar-sign prefix is the `projectedValue` we mentioned — `@State` projects a `Binding` for exactly this use.

```swift
struct ParentView: View {
    @State private var listeningMode = "tapToTalk"
    var body: some View {
        ModeStep(selection: $listeningMode, onContinue: { ... })
    }
}

struct ModeStep: View {
    @Binding var selection: String  // mutates ParentView's state
    // ...
}
```

Read aloud: "at-State private var listeningMode equals tap-to-talk. Pass dollar-listeningMode to ModeStep." If you've used React, this is "lifted state" with explicit syntax for the lift.

**`@AppStorage`** is a `@State`-like wrapper that reads and writes a `UserDefaults` key. Persistent across app launches. The CheckIn codebase uses it heavily for user preferences.

```swift
@AppStorage("listeningMode") private var listeningMode: String = "tapToTalk"
```

That single line says: bind this property to UserDefaults key `listeningMode`, type `String`, default `"tapToTalk"`. The default is used only on first read when the key has never been written. SwiftUI re-renders the view automatically when any process writes to that UserDefaults key.

**`@Environment`** is a read-only wrapper that pulls a value out of the SwiftUI environment — accessibility settings, color scheme, dismiss actions, etc. The book covered none of this because SwiftUI didn't exist.

```swift
@Environment(\.accessibilityReduceMotion) private var reduceMotion
@Environment(\.dismiss) private var dismiss
```

The `\.foo` syntax is a "key path." It points to a property without invoking it. `accessibilityReduceMotion` is a `Bool` you read; `dismiss` is a closure-like value you call (`dismiss()`) to close a sheet or pop a navigation stack.

**`@FocusState`** (iOS 15+) handles which control currently has keyboard focus. CheckIn doesn't use this since it has no text fields, but it's worth knowing for future expansion.

### 2.3 ObservableObject, @StateObject, @ObservedObject (the older pattern)

Before iOS 17, the pattern for shared, observable reference types was:

```swift
class AuthService: ObservableObject {
    @Published var isAuthenticated = false
}

struct ContentView: View {
    @StateObject private var auth = AuthService()  // owned, lifetime managed
    // or:
    @ObservedObject var auth: AuthService          // passed in, not owned
    var body: some View { ... }
}
```

`@Published` is a property wrapper that emits a Combine publisher every time the value changes. `ObservableObject` is a protocol requiring an `objectWillChange` publisher. `@StateObject` and `@ObservedObject` are the view-side wrappers that subscribe to the changes and trigger re-renders.

This pattern still works and is still common in older codebases. iOS 17 introduces a replacement.

### 2.4 @Observable (iOS 17, what CheckIn uses)

The `@Observable` macro replaces the `ObservableObject` + `@Published` ceremony with a single annotation on the class. Inside the class, mutable properties become individually observable. Inside views, you no longer need `@StateObject`/`@ObservedObject`/`@EnvironmentObject` — a plain `@State` (for ownership) or a plain property (for non-owned) suffices.

```swift
@Observable
final class AuthService {
    var isAuthenticated = false        // observable, no @Published needed
    func signIn() { isAuthenticated = true }
}

@main
struct CheckInApp: App {
    @State private var authService = AuthService()
    var body: some Scene {
        WindowGroup {
            ContentView(authService: authService)
        }
    }
}

struct ContentView: View {
    var authService: AuthService       // not @StateObject, not @ObservedObject
    var body: some View {
        Text(authService.isAuthenticated ? "Signed in" : "Signed out")
    }
}
```

The macro rewrites your class to track which properties each view reads and only re-renders that view when those specific properties change. Performance is meaningfully better than the older `ObservableObject` model, which re-rendered any subscriber on any change.

`@Observable` is CheckIn's default for service classes. `StateMachine`, `AuthService`, and the various service stubs all use it. When you read CheckIn code you will see `@Observable final class Foo` and `var stateMachine: StateMachine` more often than the older pattern.

---

## 3. Result Builders

A result builder (Swift 5.4) is a compile-time DSL machinery that takes a block of expressions and feeds them through a builder protocol to produce a single result value. The most famous example is `@ViewBuilder`, which is what makes every SwiftUI `body` work.

When you write:

```swift
var body: some View {
    VStack {
        Text("Hello")
        Text("World")
    }
}
```

…the closure passed to `VStack` is not a normal Swift closure. The `init` of `VStack` takes a `@ViewBuilder` closure, which means the compiler rewrites the contents. Two `Text` lines become approximately:

```swift
VStack(content: { ViewBuilder.buildBlock(Text("Hello"), Text("World")) })
```

`buildBlock` returns a `TupleView<(Text, Text)>`. SwiftUI knows how to lay out a tuple-view. If you write an `if`/`else` inside the closure, the compiler calls `buildEither(first:)` or `buildEither(second:)`. A `for` loop becomes `buildArray`. The protocol's methods are the grammar of the DSL.

You almost never write your own result builder. But knowing what's happening matters for two reasons. First, error messages get cryptic when you accidentally write something that doesn't fit the builder's grammar (a `let` declaration inside a `body` is a common one — let bindings aren't expressions, so the builder rejects them). Second, you'll see other result builders in the wild: `RegexBuilder` for declarative regex construction (Swift 5.7+), `CommandsBuilder` for menus, and various server-side DSLs.

For reading purposes, the mental model is "this closure looks like normal Swift but it's actually compile-time fed through a builder that turns the statements into a structured value." That's enough to navigate.

---

## 4. Macros

Swift 5.9 (2023) added a macro system. Two flavors: freestanding and attached.

A **freestanding macro** is invoked with `#name`. The most common one is `#Preview`, which generates an Xcode preview for SwiftUI.

```swift
#Preview {
    SummaryView(stateMachine: StateMachine(), authService: AuthService())
}
```

The macro expands at compile time into a `PreviewProvider` conformance. Other freestanding macros include `#expect` (in modern testing frameworks), `#URL`, `#stringify` (the canonical tutorial example).

An **attached macro** is invoked with `@name` and modifies the declaration it's attached to. `@Observable` is the most relevant one — it's attached to a class and rewrites it to be observable. Others you'll meet: `@MainActor` is conceptually a macro-ish annotation (technically a global actor attribute, predates macros), `@Test` in Swift Testing, `@Sendable` on closures.

Reading macro-using code, you mostly just need to know "this annotation does some compile-time rewriting; the implementation lives in a separate module that the compiler loads." If you ever want to write your own (you almost certainly won't for CheckIn), they live in their own SwiftPM target and depend on `swift-syntax`. The Apple docs and the SE-0382 / SE-0389 proposals are the primary references.

---

## 5. Opaque Return Types and Existentials: some vs any

The keyword `some` and the keyword `any` look similar and do very different things. Knowing the difference is essential to reading SwiftUI code.

`some Foo` is an **opaque return type**. It says "I return one specific type that conforms to Foo, but the caller doesn't get to know which one." The compiler picks the type. Every call site gets the same concrete type back. This is what every SwiftUI `body` uses:

```swift
var body: some View {
    VStack { Text("Hi") }
}
```

The actual return type is something monstrous like `VStack<TupleView<(Text)>>`. The compiler erases it to `some View` for your reading sanity and the caller's. But it's still one specific type, picked at compile time.

`any Foo` is an **existential type**. It says "I have a box containing some Foo — I don't know which, and it can be a different one each time." `any` enables heterogeneous collections:

```swift
let mix: [any View] = [Text("a"), Image("b"), Color.red]  // works
let same: [some View] = [Text("a"), Text("b")]            // works (all Text)
let nope: [some View] = [Text("a"), Image("b")]           // compile error
```

Rule of thumb: prefer `some` when you can. Use `any` only when you genuinely need to put different conforming types in the same box (heterogeneous arrays, dictionary values, etc.). `some` is faster (no boxing) and more analyzable by the compiler.

Read aloud: "var body, some View" → "var body, some View." Engineers say "some" — not "some kind of" or "any" — because that's the keyword.

Note on history: pre-Swift 5.6, you could write `func foo(view: View)` and Swift would silently treat `View` as an existential. Modern Swift requires `any View` to make that explicit. If you see plain `View` as a type in an old example, mentally translate it to `any View`.

---

## 6. Quality of Life: Result, if-let shorthand, regex, Identifiable

A handful of smaller features show up frequently enough to matter.

**`Result<Success, Failure>`** (Swift 5.0) is a value type wrapping either success or failure. Predates async/await. Still common in callback-style APIs that haven't been modernized.

```swift
func loadToken(completion: @escaping (Result<Token, AuthError>) -> Void) { ... }

loadToken { result in
    switch result {
    case .success(let token): use(token)
    case .failure(let error): handle(error)
    }
}
```

`Result` has `.get()` (throws on failure), `.map`, `.flatMap`, etc. In modern code you usually convert: `let token = try await loadToken()` rather than the callback form.

**`if let` shorthand** (Swift 5.7, 2022) lets you skip repeating the name:

```swift
// Old:
if let user = user { print(user.name) }
// New:
if let user { print(user.name) }
```

CheckIn uses the shorthand throughout. Reads as "if let user."

**Regex literals** (Swift 5.7, 2022) put regex syntax directly in the language. Both literal regex (`/.../`) and the declarative `Regex { ... }` DSL exist.

```swift
let emailPattern = /[\w.]+@[\w.]+/
if let match = "ping me at foo@bar.com" .firstMatch(of: emailPattern) {
    print(match.0)
}
```

CheckIn doesn't currently use regex (intent classification is embedding-based per D14), but Phase 5 might pull regex in for entity post-processing.

**`Identifiable`** (Swift 5.1, 2019) is a protocol with one requirement: `var id: Hashable` (or any `Identifiable` ancestor). SwiftUI's `ForEach` requires it to track view identity stably across mutations.

```swift
struct EmailRow: Identifiable {
    let id: String  // the Graph message ID
    let from: String
    let subject: String
}

ForEach(emails) { email in
    EmailRow(email: email)
}
```

When data conforms to `Identifiable`, `ForEach` can take just the array — no explicit `\.id` key path needed.

---

## 7. SwiftUI Lifecycle and Identity

A short section because most of this is in `GUIDE.md` already. The key thing to internalize: SwiftUI views are *value types* that get re-created on every render. The persistent state is held by SwiftUI itself, keyed by view identity. View identity is determined structurally — same position in the same parent's body means same identity, which means SwiftUI reuses the same `@State` storage.

Three modifiers you will use:

`.onAppear { ... }` fires when the view enters the hierarchy. Closure is sync. For async work, use `.task`.

`.onDisappear { ... }` fires when the view leaves. Sync. Less common than `.onAppear`.

`.task { ... }` fires when the view appears, runs an async closure, and *cancels the task automatically* when the view leaves. This is the right place to start any async work tied to a view's lifetime. Section 1.3 above shows the pattern.

`.onChange(of:) { _, new in ... }` fires when the watched value changes. Replaced the older `.onChange(of:) { new in ... }` syntax in iOS 17 (the new form takes the old and new values; the old form only got the new). You will see both in the wild; the two-argument form is preferred.

---

## 8. CheckIn cross-reference: where to see each feature

A quick lookup table for grep-and-read.

| Feature | First appearance in CheckIn | What to learn from it |
|---|---|---|
| `@Observable` | `State/StateMachine.swift` | The macro replaces ObservableObject/@Published |
| `@State` (owned) | `CheckInApp.swift` | App owns `stateMachine` and `authService` |
| `@Binding` | `Views/OnboardingFlow.swift`, ModeStep | Two-way pass into a substep |
| `@AppStorage` | `Views/SettingsView.swift` | UserDefaults-backed reactive state |
| `@Environment(\.dismiss)` | `Views/SettingsView.swift` | Modal dismiss from inside a sheet |
| `@Environment(\.accessibilityReduceMotion)` | `Views/Indicators.swift` | Honor system accessibility setting |
| `.task { ... }` | `Views/Indicators.swift` | Auto-cancelling async work |
| `some View` (opaque return) | every `body` | The SwiftUI default |
| `@ViewBuilder` (implicit via VStack et al) | every `body` | The DSL machinery is invisible |
| `if let` shorthand | many views | Modern unwrap syntax |
| Result-builder switch (`case .x: ...`) | `Views/ContentView.swift` body | Switching on state-machine state inside body |

Phase 5 will add:

| Feature | Where it will appear | What you'll learn |
|---|---|---|
| `async`/`await` | `Services/SpeechService.swift` | Async function signatures |
| `Task { ... }` | `Views/SummaryView.swift` `onChange` | Bridging sync to async |
| `Task.cancel()` | view-stored `Task<Void, Never>?` | Cancelling on state transition |
| `AsyncStream<String>` | `Services/SpeechService.swift` | Bridging callback to async sequence |
| `for await` | speech-result consumer | Iterating an async sequence |
| `@MainActor` | UI-touching callbacks | Hopping to main thread |
| `await MainActor.run { ... }` | result-handlers in Tasks | Explicit main-thread hop |
| `Sendable` warnings | wherever you pass state into a Task | Concurrency-safety boundaries |

---

## 9. What this doc does not cover (and where to read about it)

I've deliberately left out features that don't matter for CheckIn or that you can pick up on demand. For completeness:

**SwiftData** (iOS 17) — modern Core Data replacement for local persistence. CheckIn doesn't persist M365 data on device (D9), so this is not relevant. If a future personal project needs local storage, learn it then.

**Combine** — Apple's reactive framework. Predates async/await and is being slowly subsumed by `AsyncSequence`. CheckIn doesn't use Combine directly. You'll see it in framework internals.

**UIKit interop** — `UIViewRepresentable` and `UIViewControllerRepresentable` for wrapping UIKit views inside SwiftUI. CheckIn doesn't need it; you can read the docs when you do.

**Swift Testing** (Swift 5.10, 2024) — replaces XCTest with a more modern API based on macros (`@Test`, `#expect`). CheckIn's test scaffolding is still XCTest. Worth a half-hour of reading when you're ready to write tests.

**SwiftPM internals** — Package.swift, plugin targets, build configuration. You've seen the surface (MSAL via SPM). Deep customization is rarely needed.

**Server-side Swift** — Vapor, Hummingbird, AsyncHTTPClient. A different world from iOS but the same language. Worth knowing exists; not a priority unless you decide to write Swift on the backend.

---

## 10. Recommended reading order if you have a weekend

If you have time before the Mac Mini lands and want to push deeper than this document:

The Swift Programming Language book on swift.org is the canonical reference and gets updated for each language version. The Concurrency chapter alone is worth a slow read.

The WWDC sessions for Concurrency (2021), Observable (2023), and Macros (2023) are dense and good. Apple's developer site has them with transcripts.

Paul Hudson's Hacking with Swift articles cover modern features practically and are well-written. Free.

The async/await section of the rustaceans-do-Swift mental-model essay (you'll find it by searching "Swift async Rust comparison") is worth twenty minutes.

For the architecture side of building real apps, "Modern Concurrency in Swift" by Marin Todorov (Kodeco, 2022) is the most thorough single source.

---

Last updated: 2026-05-11, alongside the Phase 4 commit and the Tatsiana palette alignment.
