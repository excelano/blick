// WatchSignInWire.swift
// BlickKit
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

/// The WatchConnectivity vocabulary for signing the watch in. The watch builds
/// the sign-in request and keeps the PKCE verifier; the phone runs the web
/// sign-in and carries back only the one-time code, which the watch redeems
/// itself. No token crosses the link in either direction.
public enum WatchSignInWire {
    public static let stepKey = "watchSignIn"
    public static let reportKey = "watchSignInReport"

    public enum Step {
        public static let begin = "begin"
        public static let code = "code"
        public static let signOut = "signOut"
    }

    public enum Field {
        public static let clientID = "clientID"
        public static let authority = "authority"
        public static let url = "url"
        public static let code = "code"
        public static let state = "state"
        public static let result = "result"
    }

    public enum Report {
        public static let signedIn = "signedIn"
        public static let signedOut = "signedOut"
        public static let failedPrefix = "failed: "
    }
}
