import SwiftUI

struct PortForwarderTableHeader: View {
    var body: some View {
        HStack(spacing: 0) {
            Text("Status")
                .frame(width: 80, alignment: .leading)
            Text("Name")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Service")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Port")
                .frame(width: 80, alignment: .leading)
            Text("Actions")
                .frame(width: 80, alignment: .center)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
