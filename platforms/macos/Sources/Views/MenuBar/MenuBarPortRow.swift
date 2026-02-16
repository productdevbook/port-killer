/// MenuBarPortRow - Compact port row for menu bar
///
/// Thin wrapper around PortRowView with menuBar style.
/// Injects AppState into environment for PortRowView.

import SwiftUI

struct MenuBarPortRow: View {
    let port: PortInfo
    @Bindable var state: AppState
    @Binding var confirmingKill: String?

    var body: some View {
        PortRowView(
            port: port,
            style: .menuBar,
            killMode: .inline(confirmingKill: $confirmingKill)
        )
        .environment(state)
    }
}
