/**
 * TunnelStatus+UI.swift
 * PortKiller
 *
 * UI helpers (status colors, URL formatting) for tunnel status enums.
 * Kept out of the model layer so the models stay Foundation-only.
 */

import SwiftUI

extension CloudflareTunnelStatus {
    /// Color used for the status indicator dot.
    var color: Color {
        switch self {
        case .idle: .secondary.opacity(0.3)
        case .starting: .orange
        case .active: .green
        case .stopping: .orange
        case .error: .red
        }
    }
}

extension NamedTunnelStatus {
    /// Color used for the status indicator dot.
    var color: Color {
        switch self {
        case .stopped: .secondary.opacity(0.3)
        case .starting: .orange
        case .running: .green
        case .stopping: .orange
        case .error: .red
        }
    }
}

extension String {
    /// Strips the `https://` scheme for compact tunnel-URL display.
    var shortenedTunnelURL: String {
        replacingOccurrences(of: "https://", with: "")
    }
}
