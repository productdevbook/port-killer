import SwiftUI

struct OnboardingFeaturesStep: View {
    private let features: [(icon: String, title: String, description: String, color: Color)] = [
        ("magnifyingglass", "Port Scanning", "See all listening ports in one place", .blue),
        ("xmark.circle.fill", "Quick Kill", "Terminate processes with one click", .red),
        ("star.fill", "Favorites", "Pin frequently used ports for quick access", .yellow),
        ("eye.fill", "Watched Ports", "Get notifications when ports become active", .purple),
        ("globe", "Cloudflare Tunnels", "Share local ports publicly", .orange),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What you can do")
                .font(.title2)
                .fontWeight(.bold)
                .padding(.bottom, 4)

            ForEach(features, id: \.title) { feature in
                HStack(spacing: 14) {
                    Image(systemName: feature.icon)
                        .font(.title3)
                        .foregroundStyle(feature.color)
                        .frame(width: 28, alignment: .center)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(feature.title)
                            .fontWeight(.medium)
                        Text(feature.description)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
