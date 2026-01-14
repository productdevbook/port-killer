import SwiftUI

struct EmptySelectionView: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Service Details")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider()

            VStack {
                Spacer()
                Image(systemName: "arrow.left")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
                Text("Select a service")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
        }
        .background(Color.primary.opacity(0.02))
    }
}
