# Releasing Blick

Blick ships the way every iOS app in the fleet does: through the release apps
in `excelano/shipping` (`shots-appstore`, `build-release`, `ship-appstore`), run
from a clone that holds a `ship.toml` (gitignored), with the version submitted
for App Review by hand in App Store Connect. What follows is particular to
Blick.

`shots-appstore` takes the screenshots on the iPhone, iPad and Watch
simulators; on a watch simulator `packaging/ios/shots.sh` runs the embedded
watch app, and the demo data comes from `--demo` and `--demo-email-list` in
`DemoMode.swift`.

The export signs with the App Store profiles for the app, the widget, the
watch app and the watch widgets, all of which must be in the Mac's profile
directory. The MSAL framework ships without symbols, so its dSYM warning at
upload is expected and harmless.

Because the app is unusable without a Microsoft sign-in, App Review needs
Sign-In Required on and the standing demo tenant account on the record. App
Privacy stays "Data Not Collected": the only network destinations are
Microsoft Graph and Microsoft identity, and the only cross-device traffic is
non-credential status over WatchConnectivity, plus the one-time sign-in code the
phone relays when the watch signs itself in. iPad orientations must list all
four, because a universal app's upload validation requires it for
multitasking even though the iPhone stays portrait-only.
