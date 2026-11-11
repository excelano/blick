# Security Policy

## Reporting a vulnerability

Please report suspected vulnerabilities privately, using the **Report a vulnerability** button on the Security tab of this repository. If that button is not there, or you would rather not go through GitHub, email david.anderson@excelano.com instead. I aim to respond within seven days.

Please do not open public issues for security problems.

## Supported versions

The latest release receives security fixes. Older versions are not supported. A fix ships in a new App Store release.

## What Blick can access

Blick connects only to Microsoft Graph and Microsoft identity endpoints, with the delegated permissions in `BlickKit/Sources/BlickKit/GraphScopes.swift` and the signed-in user's own token. It writes to the Microsoft 365 account only in response to an action the user takes. The widget, Control Center controls and App Intents make the same calls from the same device with the same token.

The Apple Watch app receives non-credential status data from the iPhone over WatchConnectivity and relays actions back to it. If Sign in on Apple Watch is turned on, the watch obtains its own token from Microsoft through a single-use code the iPhone relays; no token moves between devices.

With permission, and only while Bogenzeit is turned on, Blick reads approximate location while the app is open.

## What Blick stores

The Microsoft sign-in token is in the iOS Keychain, with iCloud sync off. A snapshot of the last summary, the starred senders, a pinned presence, and the identifiers used to tell new messages from seen ones sit in an App Group container shared only with Blick's own extensions. The app's preferences hold the display settings, a custom app registration if one is entered, and the latest coordinates while Bogenzeit is on. Removing the app removes the container and the preferences. [PRIVACY.md](PRIVACY.md) describes each in full.
