# CheckIn: Features

What a user can do, mapped to the entry point in the UI.

| Function | Triggered by |
|---|---|
| Sign in with Microsoft 365 | "Sign In with Microsoft" button on launch when signed out |
| Sign out | Settings sheet → Sign Out (with confirm dialog; the section is hidden when not signed in) |
| Refresh inbox (meeting, chats, emails) | Pull-to-refresh on the list or empty-day state. Also auto-refreshes when the app returns to the foreground (skipped if a refresh finished within the last 30 seconds). |
| Background refresh of inbox while the app is closed | iOS `BGAppRefreshTask` scheduled every time the app goes to the background, with a 30-min minimum interval. Actual cadence is at the OS's discretion (typically 15-60 min during active hours, less when quiet). Disabled by iOS if you force-quit from the app switcher until the next launch. |
| App-icon badge showing pending items | iOS app-icon badge updated to `unread emails + pending chats` after every refresh and after every local mark-read / delete. Meetings are intentionally excluded — they're scheduled, not items to triage. Requests notification permission (`.badge` only) on first use; silently no-ops if denied. |
| See when a refresh failed | Orange warning banner ("Couldn't reach Microsoft — pull to retry") appears between the top bar and the content when any Graph call in the last refresh hit an error. Cleared automatically by the next successful refresh. Covers full refreshes, the show-all toggle's refetch, and the mark-all-read top-up. Detailed errors still go to `os.Logger` for diagnostics. |
| See next meeting in the next 24 hours | Top of the list when one exists; cancelled events and events you've declined are skipped |
| See the rest of today's meetings | "Later today" section between the next-meeting card and the Chats section, showing each remaining meeting as a compact row (time of day + subject). Same cancelled/declined skip. Tap a row to join in Teams (falls back to Outlook Calendar). Window ends at start of tomorrow local time, so we don't bleed into tomorrow. |
| See a conflict warning when the next meeting overlaps another | Orange triangle + "Overlaps another meeting" line on the meeting card. Computed across the same 10-event window we fetch; back-to-back meetings (one ending exactly when the next starts) don't count. |
| Highlight when the next meeting is starting soon | When the meeting starts within the next 3 minutes, the time label flips from the usual cyan "in N min" to orange "Starting soon". In-progress meetings continue to show "now" in cyan — they're not urgent in the same way. Refreshes when the view re-renders (foreground transition or pull-to-refresh). |
| Join that meeting in Teams | Tap the meeting card (falls back to Outlook Calendar if no Teams join URL) |
| Open Outlook Calendar | Tap a non-Teams meeting card |
| RSVP to a meeting (Accept / Maybe / Decline) | Three buttons under the meeting info, visible when you haven't responded; optimistic update, POSTs to Graph with sendResponse=true |
| See your current RSVP state on a responded meeting | Pill ("Accepted", "Tentative", "Declined") under the meeting info, in place of the buttons |
| Auto-mark matching invite emails read after RSVP | After a successful RSVP, unread emails whose subject matches the meeting subject (or "Updated: ..." / "Cancelled: ...") are marked read |
| See up to 20 newest unread emails | Email section |
| See the count of additional unread beyond the 20 shown | "+ N more unread" inline in the Email section header, next to the count badge, when total unread > 20 |
| Bulk mark visible emails as read | Email section header → ellipsis pill → "Mark N read". Sends a Graph `$batch` POST (chunked at 20 ops per batch when N > 20); selectively reverts only operations that failed. Tops up from the server if "more unread" remains. |
| Bulk mark visible "Other" inbox emails as read | Same menu → "Mark N in Other read" (visible only when N > 0). Uses Microsoft's Focused/Other classification from Graph's `inferenceClassification` field. |
| Bulk mark visible meeting notices as read | Same menu → "Mark N meeting notices read" (visible only when N > 0). Covers `meetingCancelled`, `meetingAccepted`, `meetingTentativelyAccepted`, `meetingDeclined` from Graph's `meetingMessageType` field. Leaves actionable `meetingRequest` invites alone. |
| Bulk mark visible mailing-list emails as read | Same menu → "Mark N mailing lists read" (visible only when N > 0). Detected by the presence of an RFC 2369 `List-Unsubscribe` header in `internetMessageHeaders`. |
| Bulk flag all unflagged visible emails | Same menu → "Flag N" (visible only when there are unflagged emails). |
| Bulk unflag all flagged visible emails | Same menu → "Unflag N" (visible only when there are flagged emails). |
| Lift the 20-email cap to see everything unread | Same menu → "Show all N" (visible only when there are emails beyond the cap). Persists across launches. Toggle back via "Show top 20". |
| Read each email's sender, subject, and preview | Each row shows sender + relative time, subject, and Graph's bodyPreview (up to 2 lines) |
| See a flag indicator on flagged emails | Orange flag icon next to the sender name |
| Reply to an email in Outlook | Tap an email row (opens Outlook compose with `Re: <subject>` to the sender) |
| Mark an email read | Swipe right-to-left on the row, or long-press → "Mark read" (optimistic, reverts on failure) |
| Flag / unflag an email | Swipe left-to-right on the row, or long-press → "Flag" / "Unflag" (optimistic, reverts on failure) |
| Mark all visible from this sender as read | Long-press an email row → "Mark N from this sender read" (visible only when N > 1; same SMTP address) |
| Mark all visible with this subject as read | Long-press an email row → "Mark N with this subject read" (visible only when N > 1). Subjects are normalized: Re:/Fwd:/Fw:/Aw:/Sv: prefixes stripped iteratively, case-insensitive. |
| Copy the sender's email address | Long-press an email row → "Copy sender address". Writes the SMTP address to the system pasteboard. |
| Delete an email | Long-press an email row → "Delete" (red, last item). Graph moves the message to the user's Deleted Items folder, where it stays recoverable in Outlook for the tenant's retention window. |
| See pending Teams chats from the last 24 hours where someone else sent the last message | Chats section, above emails |
| See the sender plus other thread participants | "with A, B, C" line below the sender name; wraps to 2 lines, collapses to "with A, B +N" for big groups |
| Open a chat in Teams | Tap a chat row (falls back to the Teams app if no chat URL) |
| Override the Azure App Registration with your own | Settings → "Custom Azure registration" → enter Application (client) ID and/or Directory (tenant) ID → "Save and sign in" (signs out, rebuilds MSAL, sends you to Sign In) |
| Revert to Excelano's default registration | Settings → "Reset to defaults" |
| Open the Settings sheet | Top-right gear button, visible on both the summary screen and the sign-in screen (so a stuck custom registration can be undone before sign-in) |

## Not yet supported

- Reply to a chat from inside the app (the tap hands off to Teams)
- Open the specific calendar event for non-Teams meetings (only the calendar at large)
