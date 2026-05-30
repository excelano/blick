// PublishedConfig.swift
// CheckInKit
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

/// The Azure app-registration identifiers CheckIn ships with — the values
/// used when the user has not entered a custom registration. Lives in
/// CheckInKit so the app and the widget extension fall back to one source
/// instead of carrying byte-identical copies that drift silently.
public enum PublishedConfig {
    /// Published client ID of the `checkin` Azure app registration.
    public static let clientID = "0ce3820d-db53-4b2e-9621-6c4ccc086d5a"

    /// `organizations` authority so any work/school account can sign in
    /// against the published registration. A custom registration's tenant
    /// ID replaces `organizations` at the app layer.
    public static let authority = "https://login.microsoftonline.com/organizations"
}
