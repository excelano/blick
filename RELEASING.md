# Releasing Blick

A release runs from a clone that holds a `ship.toml` (gitignored), through the
release apps in `excelano/shipping`: `shots-appstore` takes the screenshots on
the iPhone, iPad and Watch simulators, `build-release` bumps the version,
archives and exports the signed build on the Mac, tags, and attaches the
`.ipa` to the GitHub release, and `ship-appstore` uploads that build, fills in
App Store Connect, and submits it for review. Nothing is done in Xcode or in
the App Store Connect website.

What the repository holds for that:

- `Config/Version.xcconfig` is the single source of the marketing version and
  the build number. Every target inherits both from the project-level base
  configuration; do not re-declare either key in a target's build settings, or
  the target's value silently wins. The build number is global and monotonic
  across the app record, and App Store Connect rejects one it has already
  accepted, so a re-upload after a rejection moves to the next number.
- `packaging/store-listing.toml` is the listing copy and the reviewer's notes,
  pushed on every release. The demo account's credentials live only in the
  App Store Connect sign-in fields.
- `packaging/release-notes.toml` is what changed in the release being cut, and
  its `version` must match, or the release stops.
- `packaging/ios/shots.sh` is the screenshot recipe: which screens, in which
  state, from the demo data the Debug build carries (`--demo` and
  `--demo-email-list` in `DemoMode.swift`). On a watch simulator it runs the
  embedded watch app.

The export signs with the App Store profiles for the app, the widget, the
watch app and the watch widgets, all of which must be in the Mac's profile
directory. The MSAL framework ships without symbols, so its dSYM warning at
upload is expected and harmless.

Because the app is unusable without a Microsoft sign-in, App Review needs
Sign-In Required on and the standing demo tenant account on the record. App
Privacy stays "Data Not Collected": the only network destinations are
Microsoft Graph and Microsoft identity, and the only cross-device traffic is
non-credential status over WatchConnectivity. iPad orientations must list all
four, because a universal app's upload validation requires it for
multitasking even though the iPhone stays portrait-only.

Development installs on a device go through `~/bin/build-to-phone.sh blick`
on the Mac.
