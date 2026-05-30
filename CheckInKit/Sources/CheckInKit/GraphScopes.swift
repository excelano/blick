// GraphScopes.swift
// CheckInKit
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

/// Microsoft Graph delegated scopes CheckIn requests at sign-in and on
/// silent token refresh. Shared so the app's `AuthService` and the widget
/// extension's `WidgetTokenProvider` ask for the same permissions instead
/// of drifting and silently breaking a downstream call.
///
/// MSAL for iOS automatically requests openid, profile, and offline_access,
/// so those don't appear here.
public enum GraphScopes {
    /// Mail.ReadWrite drives the email mutation surface (mark read, flag).
    /// Mail.Send drives the in-app reply-all action. Calendars.ReadWrite
    /// drives the next-meeting fetch and RSVP (accept/tentative/decline)
    /// calls. MailboxSettings.ReadWrite drives the Out-of-Office toggle.
    public static let base = [
        "User.Read",
        "Mail.ReadWrite",
        "Mail.Send",
        "Calendars.ReadWrite",
        "MailboxSettings.ReadWrite",
    ]

    /// Chat.ReadWrite drives the Teams pending-chat surface including
    /// posting replies into existing threads. Presence.ReadWrite drives
    /// the presence picker and Control Center / widget quick-sets.
    public static let teams = [
        "Chat.ReadWrite",
        "Presence.ReadWrite",
    ]

    /// Every scope CheckIn ever asks for. The widget extension uses this
    /// because it doesn't carry the Teams-on/off toggle — anything the
    /// app cached, the widget can ride.
    public static let all = base + teams

    /// The scope set for an MSAL acquire, dropping Teams scopes when the
    /// user has opted out so consent isn't requested for surfaces they
    /// won't use.
    public static func scopes(enableTeams: Bool) -> [String] {
        enableTeams ? all : base
    }
}
