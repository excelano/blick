// ControlKind.swift
// CheckInKit
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

/// Stable identifiers for CheckIn's Control Center controls. Shared so the
/// widget extension that declares each control and the app/extension code
/// that reloads them after a mutation agree on the same kind string.
public enum ControlKind {
    /// The Out-of-Office toggle — the only control with live state, so the
    /// only one worth reloading after a mutation. The presence buttons are
    /// fixed-action and have nothing to refresh.
    public static let outOfOffice = "com.excelano.checkin.control.outOfOffice"
    public static let setAvailable = "com.excelano.checkin.control.setAvailable"
    public static let setBusy = "com.excelano.checkin.control.setBusy"
    public static let setDoNotDisturb = "com.excelano.checkin.control.setDoNotDisturb"
    public static let setBeRightBack = "com.excelano.checkin.control.setBeRightBack"
    public static let setAway = "com.excelano.checkin.control.setAway"
    public static let setOffline = "com.excelano.checkin.control.setOffline"
    public static let resetStatus = "com.excelano.checkin.control.resetStatus"
}
