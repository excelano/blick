# Phase 3 Implementation Notes

Working notes for Phase 3 (Day 1 voice intelligence) extracted from the archived web prototype at `excelano/checkin-web-prototype` (commit `141a3be`). Each section captures a working pattern that solves a concrete Phase 3 problem. Translate to Swift when implementing; do not port the JavaScript line-by-line.

These notes feed the response template registry (Phase 3, per `PLAN.md`) and the intent classifier and entity matcher behind the protocols introduced in Phase 2.

## Disambiguation prompt strategy

When `active.disambiguating` is entered with multiple candidates, the prompt shape depends on what distinguishes them. The prototype's `askWhichOne` (app.js:957) chose between three strategies and produced a single TTS string each time.

```
if (distinct senders > 1)
    "Which one? <sender list>?"
else if (all candidates share one sender, subjects differ)
    "Which one? the email about <subject A>? Or the email about <subject B>?"
else (sender shared, subjects identical, e.g. duplicates)
    if (count == 2) "There are two of those. Say first or second?"
    else            "There are <n> of those. Say a number from one to <n>?"
```

The trailing question mark in each clause matters: the prosody cues "your turn" without padding. Match the persona register from `PERSONA.md` (calm, brief, no apology). Port to Swift as a function on the disambiguation response template; expose it through the `ResponseGenerator` protocol.

## Sender list with counts

Summary phrasing needs to render a list of senders that may contain duplicates. The prototype's `listNames` (app.js:478) preserves first-seen order, collapses repeats with a count phrase, and uses an Oxford comma.

```
counts = ordered map of sender -> occurrences
parts = []
for (name, count) in counts:
    if count == 1: parts.push name
    if count == 2: parts.push name + " twice"
    else:          parts.push name + " " + count + " times"

if parts.length == 1: return parts[0]
if parts.length == 2: return parts[0] + " and " + parts[1]
return parts[..-1].join(", ") + ", and " + parts.last
```

Renders "Mike, Sarah, Tony three times, Lisa twice." Direct lift into the summary template; this is the canonical phrasing for the Day 1 summary intent.

## Ordinal map

Maps spoken ordinals and short numerals to integers. Use during disambiguation when the prompt says "say a number from one to N." Source: app.js:1035.

```
"first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5,
"the first one": 1, "the second one": 2, "the third one": 3,
"1st": 1, "2nd": 2, "3rd": 3, "4th": 4, "5th": 5
```

Pair with a number-word table (one through ten) for raw counts. Live in the entity matcher; small enough to be a `[String: Int]` literal.

## Confirmation and denial lexicons

The prototype handled yes/no with hand-curated lists rather than a classifier. Source: app.js:1000.

```
CONFIRM: yes, confirm, send, send it, ok, okay, go ahead, do it, yep, yeah
DENY:    cancel, never mind, no, nope, stop
```

Use these as the seed table for the `active.confirming` state's input handler. Worth keeping as a flat lookup before sending anything to `NLEmbedding`; confirmation utterances are short and high-frequency, and an exact match is faster and more reliable.

## Possessive normalization

A pre-classifier text pass that rewrites "Mark's email" as "email from Mark." Massively simplifies downstream pattern matching at the cost of one regex. Source: app.js:724-771.

Two passes:

```
"Mark's email"               -> "email from Mark"
"David Anderson's latest email" -> "latest email from David Anderson"
"reply to Tony's chat"       -> "reply to chat from Tony"
"marks email" (no apostrophe) -> "email from mark"
```

Run before intent classification. In Swift, a small `NormalizationPipeline` struct with ordered passes; possessive rewriting is one pass alongside lowercase, punctuation strip, and "e-mail" -> "email."

## Pending command idle timeout

Suspended dialog states need a TTL. The prototype set a 20-second timer on every assignment to `pendingCommand` and cleared the state with "Never mind, then." if it expired. Source: app.js:62-87.

The mechanism (Object.defineProperty setter) is JS-specific. In Swift:

```
StateMachine.transition(to: .disambiguating(...)) starts a Task that
sleeps for the TTL and then transitions to idle if still in the same
state. transition(to:) cancels any prior Task before starting a new one.
```

TTL values to start with: 20 seconds for `disambiguating`, 8 seconds for `confirming` (already in STATES.md). The "never mind, then." phrasing fits the persona; keep it as the timeout-expiry response template.

## Anaphora via last-viewed-item

When the user says a verb with no entity ("reply"), the resolver substitutes the most recently viewed item. The prototype tracked this as `state.lastViewedItem` (app.js:38, 895-905, 935-945). The new design generalizes this to a richer focused-entity tracker on `DialogContext`, but the seed pattern is right: a single most-recent reference, scoped to the current session, cleared on refresh or sign-out.

In the Day 1 architecture, the analogue is `DialogContext.focusedEntity`. The prototype's pattern of "if no name, check context; if context exists, use it; otherwise ask 'who?'" maps directly to the resolution logic in `IntentClassifier`.

## Multi-source candidate scoring

When the user answers a "which one" prompt with something other than a clean ordinal, the prototype scored each candidate against the response across multiple sources. Source: app.js:1057.

```
score = 0
if response contains full sender name:        score += 3
for each token in sender (length > 2):        +1 if token in response
for each token in subject/topic (length > 2): +1 if token in response
if response contains "email" or "mail" and item is email:    score += 2
if response contains "chat" or "message" and item is chat:   score += 2

pick the unique top scorer
if tied, narrow candidates to top scorers and re-prompt
```

The substring check at the top is what `NLEmbedding` semantic similarity replaces in the new design (Anthony/Tony, Liz/Elizabeth, etc.). The other dimensions stay: token overlap on subject and type signals are still valuable. Implement as a scoring function that takes a `DialogContext`, a transcript, and a candidate list, returning a ranked array.

## Test corpus

The prototype's `COMMAND_PATTERNS` table (app.js:661-722) is the wrong implementation under D14 (string prefix matching), but every prefix in the table is a real utterance that should classify correctly post-rebuild. Convert to test fixtures:

```
("read email from Tony", .open(.email, name: "Tony"))
("reply to chat from Liz", .reply(.chat, name: "Liz"))
("read latest from Mike", .open(nil, name: "Mike", qualifier: .latest))
("mark all read", .markAllRead)
...
```

The Day 1 intent classifier should pass every Day 1 row in this fixture. Day 2 and Day 3 rows become future fixtures activated when those intents come into scope.

## What to skip

The prototype's `logUnrecognized` helper writes failed transcripts to localStorage (app.js:1192). This conflicts with D24 (zero data sharing, including local). Do not port. Surface the failure to the user via the persona's error register and let it go.

The prototype's `viewDetail`, `showReply`, `hideReply`, and the entire detail and reply view stack are out of scope under D27 (single screen plus deep-link). The deep-link path replaces them; do not port.
