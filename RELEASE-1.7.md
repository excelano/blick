# Blick 1.7: Build Plan

The working plan for the 1.7 cut. Shipped functionality lives in `FEATURES.md`,
the uncommitted backlog in `POTENTIAL-FEATURES.md`, and the App Store runbook in
`RELEASING.md`. This file is scaffolding for one release: when 1.7 ships, its
contents migrate into `FEATURES.md` and this file goes away.

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
| Inbox refactor | Split `Inbox.swift` along existing seams. No behavior change. |
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

`CheckInSnapshot` already carries `topEmails: [SnapshotEmail]` and
`topChats: [SnapshotChat]`, both keyed by stable ids, and already persists to the
app group through `saveToAppGroup`. The new-message diff has a substrate; it does
not need a new one invented for it.

`.backgroundTask(.appRefresh(...))` in `CheckInApp.swift` already runs
`inbox.refresh()` on whatever cadence iOS grants, and `MeetingNotifications`
already owns the local-notification plumbing for meeting reminders. The nudge
hooks in directly after that refresh and reuses that plumbing.

## Inbox refactor

`CheckIn/Services/Inbox.swift` is a single `@Observable final class` carrying
roughly a hundred members behind four `// MARK` comments. Disposition adds to it
heavily and the nudge adds to it lightly, so left alone it finishes 1.7 past two
thousand lines with the feature diffs buried inside it.

Swift extensions cannot add stored properties, so the stored state stays in the
main file. Everything else moves into `extension Inbox` files along seams that are
already visible in the declaration order: the meeting store and meeting
operations, presence and status, bulk email actions, single email actions, the
watch relay, compose and send, chat operations, and browse and search. This lands
as its own commit with no behavior change, so it reviews as a move rather than as
a rewrite. `CheckIn/Views/MessagePreviewSheet.swift` at a thousand lines gets the
same treatment if disposition pushes it further.

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

Sixteen commits across six slices. Each slice builds green and is independently
verifiable on device. Slice 0 has to precede disposition and the nudge, since both
land in `Inbox`. Starred senders has to precede the nudge's settings commit,
because the default depends on the starred set existing. The agenda is independent
of all of it and goes early for a visible win.

### Slice 0: Inbox split, three commits, no behavior change

Ten files out of one. Stored state, the refresh core, snapshot publishing, and the
undo and transient-message machinery stay in `Inbox.swift`; the rest becomes
`extension Inbox` files of roughly two hundred lines each.

| Commit | Files |
|---|---|
| 0a | `Inbox+Watch.swift`, `Inbox+Compose.swift`, `Inbox+Browse.swift` |
| 0b | `Inbox+Meetings.swift`, `Inbox+Chats.swift`, `Inbox+Presence.swift` |
| 0c | `Inbox+EmailActions.swift`, `Inbox+BulkActions.swift`, `Inbox+Intents.swift` |

Leaf groups move first, so the extensions with the fewest inbound calls come out
while the file is still whole. Every commit is a pure move and should review as
one. If a commit needs a real edit to compile, that is a signal the seam was drawn
wrong, and it is worth stopping on rather than papering over.

### Slice A: seven-day agenda, three commits

`GraphClient.agendaEvents(days:)` wraps the existing `eventsInRange` and adds the
conflict computation it currently skips, with agenda state and an accessor on
`Inbox`. `AgendaView.swift` renders the rolling list with day separators, dimmed
past events, a highlighted current event, and the same conflict triangles the
today surfaces use. The third commit wires the "Later today" header chevron and
the iPad detail-pane routing.

### Slice B: disposition, four commits

`GraphClient` gains `deleteMessage`, `moveMessage(id:toFolder:)`, and
`fetchMailFolders`, with `Inbox` methods doing optimistic update and undo
registration. The long-press menu gains Archive, Delete, and Move, with a
destination picker sheet for the last. `MessagePreviewSheet` gets the same three
actions. Bulk variants and the non-PATCH batch helper come last and are the first
thing to cut if the release runs long, since single-message disposition is the
feature and bulk is only an accelerant.

Worth checking early: the well-known `archive` folder has to actually resolve in
the mailbox. Graph accepts it as a well-known name, but a mailbox that has never
had Outlook's Archive button pressed may not have provisioned the folder. The
fallback is a lookup by name through `fetchMailFolders`, which the same commit is
building anyway.

### Slice C: starred senders, two commits

The store lands first, holding display name plus address in the app group, and it
is the one genuinely unit-testable piece in this release because it carries no
`@Dependency` and makes no Graph call. The second commit adds star and unstar to
the email row's long-press menu, the contact-picker entry, and a management list
in Settings.

### Slice D: new-message nudge, three commits

The diff against a persisted seen-set, the notification content builder, and
first-run suppression come first, then the hooks into the background and
foreground refresh paths, then the per-channel settings with the honest footer
copy.

Testing the background path is otherwise miserable, so: pause in LLDB once the app
has backgrounded and call `_simulateLaunchForTaskWithIdentifier:` on the shared
`BGTaskScheduler` with `com.excelano.checkin.refresh`. That turns a multi-hour wait
on the OS scheduler into a one-second round trip.

### Slice E: release

Bump `Config/Version.xcconfig`, migrate this file into `FEATURES.md`, retire the
backlog entries this cut consumed, delete this file, stage the ASC paste sheet,
and follow `RELEASING.md` from the archive step.

### If the cut runs long

The break is clean after slice B. Ship 0, A, and B as 1.7, and take C and D as
1.8. Those two are coupled to each other and to nothing else here, so they
separate without leaving anything half-built.
