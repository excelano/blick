# Blick 1.7: Build Plan

The working plan for the 1.7 cut. Shipped functionality lives in `FEATURES.md`,
the uncommitted backlog in `POTENTIAL-FEATURES.md`, and the App Store runbook in
`RELEASING.md`. This file is scaffolding for one release: when 1.7 ships, its
contents migrate into `FEATURES.md` and this file goes away.

## Status as of 2026-09-04

| Slice | State |
|---|---|
| 0 — Inbox section pass | Done, on `main`. Landed as one commit, not three; the cross-file split proved impossible (see below). |
| A — seven-day agenda | Done, on `main`, verified on device. Two commits, not three. |
| B — disposition | B1 and B2/B3 done and verified against the live mailbox, on branch `mail-disposition`. Four fixes from that testing are in a fourth commit. B4 (bulk) outstanding. |
| C — starred senders | Done, on `main`, verified on device. Two commits plus a one-line sign-out fix. |
| D — new-message nudge | D1, D2/D3 built on branch `new-message-nudge`, installed on the phone. **Not yet verified against a live message.** Test path: star a sender or set New email to Everyone, let a message arrive with Blick closed, say "What's my Blick" to Siri. |
| E — release | Not started. |

Two pieces of work landed alongside the plan rather than in it. The meeting context
menu moved out of `SummaryView` into `MeetingContextMenu.swift` so agenda rows
could carry RSVP, and compact meeting rows gained a "Needs reply" pill for
invitations still unanswered — an agenda spanning a week is where those actually
turn up. Separately, the whole codebase was renamed from CheckIn to Blick, which
is why every path below reads `Blick/…`.

The open risk in B is archive. It addresses Graph's well-known `archive` folder
without a lookup, and a mailbox that never provisioned one will fail with
"Couldn't archive that message." The fallback is resolving it by name from
`fetchMailFolders`, which is already built for the Move picker.

## Why this cut looks the way it does

Blick was designed as a status and triage surface that sits alongside Outlook and
Teams. Every scope boundary in the app reflects that origin. The email list is
capped to unread out of the Inbox folder, the calendar window closes at local
midnight, and the app never speaks unless you open it and pull. Those were the
right calls for a companion, because Outlook was always one app switch away and
its badge was doing the work Blick did not have to do.

As of 1.6 the app became the daily driver for calendar, mail, and Teams. That
changes what those boundaries cost. A companion that cannot tell you mail arrived
is fine; a primary client that cannot is leaving you blind between launches. A
companion that cannot file a message is fine; a primary client that cannot means
every real disposition decision still routes you back to Outlook. A companion
that stops at midnight is fine; a primary client that cannot answer "what does
tomorrow look like" is not.

1.7 closes those three gaps. None of them is a new capability so much as the
removal of a boundary that was correct under the old framing and is not under the
new one.

## Scope

Three features and one refactor. No new Graph scopes, so no re-consent prompt for
existing users and no change to `IT-APPROVAL.md`. The privacy posture is untouched
throughout: every call is Microsoft Graph on the already-authenticated device, and
nothing new leaves it.

| Workstream | Shape |
|---|---|
| Inbox section pass | Twenty `// MARK` sections in place. No behavior change, no access-level change. |
| Calendar beyond today | Seven-day rolling agenda, reached from the "Later today" header. |
| Mail disposition | Archive, delete, and move, each with undo. |
| New-message nudge | Local notification on new mail and chats, filtered by starred senders. |

## What already exists

Three findings that make this cheaper than the backlog entries imply, recorded
here so a later session does not re-derive them.

`GraphClient.eventsInRange(start:end:)` already fetches `/me/calendarView` over an
arbitrary window, orders by start, caps at 100 events, and maps to `[Meeting]`. It
was built as a reference pool for conflict detection on invite emails and is
displayed nowhere in the UI. The agenda is largely a view on top of a fetch that
already ships; what it lacks is conflict computation, which `recomputeConflicts`
and `overlapsAny` already implement for today's window.

`BlickSnapshot` already carries `topEmails: [SnapshotEmail]` and
`topChats: [SnapshotChat]`, both keyed by stable ids, and already persists to the
app group through `saveToAppGroup`. The new-message diff has a substrate; it does
not need a new one invented for it.

`.backgroundTask(.appRefresh(...))` in `BlickApp.swift` already runs
`inbox.refresh()` on whatever cadence iOS grants, and `MeetingNotifications`
already owns the local-notification plumbing for meeting reminders. The nudge
hooks in directly after that refresh and reuses that plumbing.

## Inbox section pass

`Blick/Services/Inbox.swift` is a single `@Observable final class` carrying
roughly a hundred members behind four `// MARK` comments. Disposition adds to it
heavily and the nudge adds to it lightly, so left alone it finishes 1.7 past two
thousand lines with the feature diffs buried inside it.

The obvious fix, splitting the type across `extension Inbox` files, does not work
here, and the reason is worth recording so it does not get proposed again. `Inbox`
holds its state in thirteen `private(set)` properties, and `private(set)` in Swift
is file-scoped: an extension in another file gets the getter but not the setter.
The file has seventy-eight mutation sites on `summary` alone, and nearly every
method worth moving is one of them. Splitting therefore costs either the
encapsulation or a redesign. Dropping `private(set)` to internal would let all
sixteen files that currently only read this state write it as well, in a
single-target app where internal means everything. Preserving the invariant
instead means funneling every mutation through a named API on the core type, which
is a real redesign of all seventy-eight sites and several days of work with no
user-visible result at the end.

So 1.7 sections the file in place instead: real `// MARK` sections with related
methods gathered under each, and no change to any access level or any line of
logic. That keeps every invariant and gets most of the navigability the split was
wanted for. The file stays one file and grows to roughly two thousand lines with
disposition, which is worse and is not qualitatively different.

The mutation-funnel refactor is still worth doing on its own merits, because
seventy-eight ad-hoc mutations of one shared observable is the actual design
problem and the line count is only its symptom. It belongs in its own cut, done
deliberately, rather than as the opening commit of a three-feature release.

## Calendar beyond today

A seven-day rolling agenda rather than a day-at-a-time pager. The question this
feature exists to answer is "what is coming up," and a rolling list answers it
without navigation, where a pager charges a tap per day. The existing 100-event
cap covers a week comfortably for any realistic calendar.

Past events render dimmed, the current event is highlighted, and day boundaries
get separators. The entry point is the "Later today" section header, made tappable
with a chevron so it matches the navigation spine email and chats already use.
That tap was deliberately deferred in an earlier cut precisely because this
destination did not exist yet.

## Mail disposition

The largest surface area of the three, and the one that turns unread-zero into
inbox-zero.

Delete is `DELETE /me/messages/{id}`, which moves the message to Deleted Items
rather than destroying it, so the action is recoverable both in Outlook and by our
own undo. Archive is `POST /me/messages/{id}/move` to the well-known `archive`
folder, with undo moving it back to `inbox`. Move needs a destination list, which
means a new `/me/mailFolders` fetch, the only genuinely new Graph call in this
release.

Two implementation notes. The existing `batchPatch` helper is PATCH-only, so batch
variants of move and delete need a sibling helper for POST and DELETE operations;
single-message paths ship first and batching follows if it earns its place. And
all three actions register through the existing `UndoableBulkAction` and
`performUndo` scaffolding, which is what makes a destructive action safe to offer
at all.

Delete is offered from the long-press menu only, never from a swipe. Swipe already
carries mark-read in one direction and flag in the other, and reworking that set to
free a slot for a destructive gesture trades a well-understood interaction for a
mis-swipe that deletes mail. The menu costs one extra tap and removes the whole
class of accident.

Watch parity is out of scope for this cut.

## New-message nudge

After each background refresh, diff the newly published snapshot's email and chat
ids against the previously persisted set and raise a local notification for what is
genuinely new. Dedupe must survive across refreshes so a message never notifies
twice, and the first run after install or sign-in must stay silent rather than
announcing the entire existing inbox.

The ceiling is structural and worth designing around rather than apologizing for
later. `BGAppRefreshTask` timing is entirely at the OS's discretion, keyed to usage
and power, so this is "you find out before too long" and not real time. The
real-time alternatives, APNs and Graph change-notification webhooks, both require a
server endpoint, which is a backend and a hard stop in the privacy posture. The
settings footer says so in plain language, the way the background-refresh row
already explains itself, so the behavior reads as a designed limit rather than a
broken notification.

## Starred senders

A scoped subset of the curated-people-list backlog entry, built only as far as the
notification filter needs and no further. A starred set of display name plus
address lives in the app group, populated by long-pressing an email row or through
the same contact picker compose already uses, which runs out of process and needs
neither a Contacts permission nor a `People.Read` scope.

Notification settings then read per channel as off, all senders, or starred only,
defaulting to starred only. This default is the point of the feature. A nudge that
fires for every message that lands is noise on a busy morning, and noise is the
fastest way to get notification permission revoked altogether, at which point the
feature is worse than not having shipped.

## Scope risk

This is a larger cut than 1.6, which was attachments plus a newline fix. If it
drags, the clean split is to ship the refactor, the agenda, and disposition as
1.7, then take the nudge and starred senders as 1.8. Those two are coupled to each
other and to nothing else in this plan, so they separate without leaving anything
half-built.

## Release

Bump `Config/Version.xcconfig` to 1.7 with the next monotonic build number, move
this file's contents into `FEATURES.md`, reconcile the backlog entries this cut
consumed out of `POTENTIAL-FEATURES.md`, stage the ASC paste sheet, and follow
`RELEASING.md` from there.

## Slice plan

Each slice builds green and is independently verifiable on device. Slice 0 had to
precede disposition and the nudge, since both land in `Inbox`. Starred senders has
to precede the nudge's settings commit, because the default depends on the starred
set existing. The agenda was independent of all of it and went early for a visible
win.

Slices 0, A and B below are written as-built; C, D and E remain plans.

### Slice 0: Inbox section pass, one commit, no behavior change

Twenty `// MARK` sections replace the four the file had, with members reordered so
each section is contiguous: observable state, the meeting store, nested types,
dependencies and caps, init and lifecycle, refresh, counts and identity, three
meeting sections, meeting notifications, presence, two email sections, bulk
actions, undo, chats, browse and search, compose, and the watch relay.

The reorder is mechanical but large, so it was done by script with a verification
pass asserting the multiset of code and doc-comment lines is identical before and
after. Two latent defects surfaced and were fixed in the same pass: the `#if DEBUG`
guard around `loadDemo` had drifted apart from its `#endif` across a member
boundary, and `markChatRead`'s doc comment had been orphaned above `chatIdentity`
by an earlier insertion, leaving one function undocumented and the other carrying
two stacked doc comments.

### Slice A: seven-day agenda, two commits (done)

Smaller than planned, in a useful way. The plan called for an
`agendaEvents(days:)` wrapper adding conflict computation; neither was needed.
`Inbox.recomputeConflicts()` already recomputes `hasConflict` across the whole
meeting store, so loading the agenda window into the store makes agenda meetings
and today's meetings flag each other for free, and `eventsInRange` is reused
exactly as it stood. `GraphClient` took no code change at all, only a corrected
doc comment.

The real work was the store. `agendaMeetingIds` is a fourth index, which made
overlapping membership real for the first time — a today meeting is normally an
agenda member too — so the drop-then-load in `loadTodayMeetings`, which had
hand-checked two indexes inline, became a shared `idsRetained(excluding:)` helper
both loaders consult before evicting anything.

`AgendaView.swift` renders the rolling list grouped under day headers, omitting
days with nothing scheduled, and carries its own 30-second clock tick so a meeting
crosses from upcoming to live to past without a refresh. `LaterMeetingRow` is
shared rather than duplicated, gaining `isPast` for dimming, and it stopped
rendering a tap target for meetings with no `joinUrl` — those taps were already
dead, but the row still advertised "Join meeting in Teams" to VoiceOver.

The iPad detail-pane routing in the original plan turned out to be unnecessary:
the existing full lists are plain sheets in both size classes, so the agenda
matches them.

The entry point deviated. The plan said only "make the Later today header
tappable", but that header renders only when the section is populated, so the
agenda would have been unreachable at the end of a day — exactly when "what does
tomorrow look like" gets asked. The section is now always rendered, carrying an
inline "Nothing else today — see the week" row when the day is done.

### Slice B: disposition, four commits so far (B4 outstanding)

**As built.** Delete is a move to Deleted Items rather than
`DELETE /me/messages/{id}`. Both land the message in the same folder, but `DELETE`
answers 204 with no body while `/move` returns the relocated message — and a move
re-creates the message, so its id changes. Without the new id there is no handle
to move it back, and a destructive action with no undo is not worth offering.
`Inbox.disposeEmail` is the one path all three actions share, and the undo moves
the returned id back to the inbox, never the original.

`emailDispositionMenu` was extracted from the start rather than inlined on one
screen, because the meeting menu had just taught that the second caller always
arrives; here there were three (summary rows, browse list, preview sheet). It
takes an `onDisposed` callback because `Inbox` owns the summary's copy of a
message but not the browse list's local `inboxEmails`/`results`, nor the preview
sheet's need to dismiss itself. On the preview sheet the three actions sit behind
an overflow menu, since that bar already collapses Mark unread and Forward to
bare icons to fit Reply's label.

B2 and B3 landed as one commit: B3 extends the same shared menu B2 introduced.

**B4, still to do.** Bulk variants plus the non-PATCH batch helper — `batchPatch`
is PATCH-only, and move is POST. This is the first thing to cut if the release
runs long, since single-message disposition is the feature and bulk is only an
accelerant.

**Verified on live mail, 2026-09-04.** Archive, delete, undo, and Move to… all
landed in the right Outlook folders. The archive risk did not materialise: this
mailbox has the well-known `archive` folder, and Graph accepts the name. The
name-lookup fallback through `fetchMailFolders` stays unbuilt until a tenant
proves it necessary. The testing found four defects, fixed in one commit:

Archiving an unread message killed the app with a Swift exclusivity violation.
The unread counter was adjusted as `summary?.x = f(summary?.x)`, and with
optional chaining on the left Swift opens the write access to `summary` before it
evaluates the right side, which reads `summary` again. Two of the four sites were
slice B's; the other two predated it (mark-read from the browse list, reply-all)
and had never been hit with an unread row still on the glance. All four now go
through `adjustUnreadEmails(by:)`, which reads and writes in two statements.

Undo re-inserted the row under its original id, but the move back re-creates the
message a second time, so any later action on that row targeted an id that no
longer resolved and failed with "Couldn't move that message." The restored row
now carries the id the move back returns, via a new `Email.with(id:)`.

The undo banner rendered only on the summary, so an archive from the full Email
list played out behind that sheet and expired unseen. The banners moved into
`InboxBanners`, an overlay the summary and the Email list both show; the list's
Undo refetches its rows so the restored message comes back there too.

Two debug prints were added along the way and kept as hooks, listed in the
run-blick skill: the folder fetch's elapsed time and counts, and the Graph error
behind a failed disposition. The first open of Move to… spun for a long while
once and never again; the fetch itself measured under 0.3s every time after, so
the one-off was most likely a silent token refresh, and the print is there to
tell the two apart if it recurs.

### Slice C: starred senders, two commits (done)

**As built.** The store lives in BlickKit as `StarredSenderStore`, one JSON array
in the App Group, with `StarredSender` holding a display name and a trimmed,
lowercased address. It matches by address for mail and by display name for Teams
chat, because `ChatMessage` carries only the sender's name. Nine tests cover it.
Running them revealed the run-blick skill was pointing at a `BlickTests` scheme
that does not exist; the tests are in the package and run from its directory
against a simulator.

Star/Unstar sender sits in the email row's long-press menu on the summary and the
full Email list, only when the message carries an address. Starred rows show a
small star after the sender's name. Settings has a Starred senders row that opens
a management list: swipe to unstar, and an Add button on the composer's
out-of-process `ContactPicker`, which now returns a `PickedContact` carrying the
name as well as the address. `Inbox` mirrors the store into observable state so
rows and Settings re-render on change.

Starred senders survive sign-out. They are a device preference, not account
state, and David chose to keep it that way.

### Slice D: new-message nudge, three commits (built, unverified)

**As built.** `NewMessageTracker` (BlickKit) keeps a per-channel ledger of ids
in the App Group and reports what a refresh saw for the first time. The first
refresh after install or sign-in seeds silently; a message once seen never
reports again even after leaving and re-entering the unread list; the ledger is
capped at 1000 per channel, oldest out first; a channel whose fetch failed leaves
its ledger alone. Seven tests. Chats are keyed by thread id plus last-message
timestamp because `ChatMessage.id` is a per-instance UUID.

`MessageNotifications` posts one notification per new message under the
`blick.message.` prefix, with separate thread ids for mail and chat. The
alert-permission prompt moved into `NotificationAuthorization`, shared with the
meeting reminders. The nudge posts only when `Inbox.isAppActive()` is false; the
app wires that closure to `UIApplication.applicationState`, so a background-task
or Siri-intent launch reads as background without waiting on a scene-phase
change. Sign-out resets the ledger.

Settings: New email and New chats pickers (Off, Starred senders, Everyone),
default Starred senders. Leaving Off requests alert permission and reverts on
refusal. Starring the first sender also requests it, because the default is on
without the user ever visiting Settings. The footer says delivery rides on iOS
background refresh and that real-time would need a server Blick does not have.

**Not yet done.** Live verification. A notification tap only brings Blick to
the foreground; `userInfo` already carries `emailId` or `chatId`, so routing to
the preview is a follow-up if wanted. The LLDB `_simulateLaunchForTaskWithIdentifier:`
path was not needed: Siri's "What's my Blick" runs the intent refresh with the
app in the background, which exercises the same code.

### Slice E: release

Bump `Config/Version.xcconfig`, migrate this file into `FEATURES.md`, retire the
backlog entries this cut consumed, delete this file, stage the ASC paste sheet,
and follow `RELEASING.md` from the archive step.

### If the cut runs long

The break is clean after slice B. Ship 0, A, and B as 1.7, and take C and D as
1.8. Those two are coupled to each other and to nothing else here, so they
separate without leaving anything half-built.
