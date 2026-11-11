# Blick

Blick is a Microsoft 365 status panel for iPhone, iPad and Apple Watch: the next
meeting, the rest of the day's calendar, unread Outlook email, Teams chats with
new activity and Teams presence on one screen. From there you RSVP, reply, triage
mail, and set presence and Out of Office, and the Home Screen widget, Control
Center controls, Siri and Shortcuts, and the watch do the quick ones without
opening the app.

It talks only to Microsoft Graph and Microsoft identity, with your own account's
permissions. There is no backend, no analytics and no third-party SDK.

https://excelano.com/blick/ is the product page for every platform.

## Documents

[FEATURES.md](FEATURES.md) maps what the app does to where it is in the UI.
[PRIVACY.md](PRIVACY.md) states what data stays on the device and what leaves it,
and [SECURITY.md](SECURITY.md) how to report a vulnerability.
[IT-APPROVAL.md](IT-APPROVAL.md) is for a user whose employer requires an
administrator to approve the app before it can sign in.
[SELF-HOSTING.md](SELF-HOSTING.md) covers building your own copy against your own
Azure app registration and Apple Developer team.

## Building

The app builds with Xcode from `Blick.xcodeproj`, which fetches MSAL through Swift
Package Manager on first open. The unit tests live in the `BlickKit` package. A
Debug build launched with `--demo` shows made-up data in place of a Microsoft 365
account.

## License

MIT. See [LICENSE](LICENSE).
