// DeepLinkService.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

/// URL builders for the only two apps CheckIn defers to: Outlook for mail
/// and calendar, Teams for chat and meetings. `LSApplicationQueriesSchemes`
/// in `Info.plist` declares `ms-outlook` and `msteams`, so
/// `UIApplication.canOpenURL(_:)` answers truthfully when the apps are
/// installed. Graph-returned URLs (`chat.webUrl`, `onlineMeeting.joinUrl`)
/// flow through `passthrough` rather than being reconstructed.
enum DeepLinkService {

    static var outlookInbox: URL? {
        URL(string: "ms-outlook://emails")
    }

    /// Microsoft's documented compose params are `to`, `subject`, `body`.
    /// A `Re:` subject is the closest the scheme gets to "reply to message
    /// N" — iOS Outlook exposes no per-message-id open.
    static func outlookReply(to recipient: String, subject: String, body: String? = nil) -> URL? {
        var components = URLComponents()
        components.scheme = "ms-outlook"
        components.host = "compose"
        var items = [
            URLQueryItem(name: "to", value: recipient),
            URLQueryItem(name: "subject", value: subject.hasPrefix("Re:") ? subject : "Re: \(subject)")
        ]
        if let body { items.append(URLQueryItem(name: "body", value: body)) }
        components.queryItems = items
        return components.url
    }

    static var outlookCalendar: URL? {
        URL(string: "ms-outlook://events")
    }

    static var teams: URL? {
        URL(string: "msteams://")
    }

    static func passthrough(_ urlString: String) -> URL? {
        URL(string: urlString)
    }
}
