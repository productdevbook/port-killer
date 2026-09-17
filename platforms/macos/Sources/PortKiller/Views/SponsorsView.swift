import AppKit
import PortKillerKit
import SwiftUI

struct SponsorsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let sponsors = model.sponsors
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(spacing: 16) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(.pink)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sponsors")
                            .font(.largeTitle.weight(.bold))
                        Text("PortKiller is free and open source thanks to these people.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let url = AppInfo.sponsors {
                        Link(destination: url) {
                            Label("Become a Sponsor", systemImage: "heart")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                }

                if !sponsors.activeSponsors.isEmpty {
                    grid("Sponsors", people: sponsors.activeSponsors.map(Person.init))
                }
                if !sponsors.contributors.isEmpty {
                    grid("Contributors", people: sponsors.contributors.map(Person.init))
                }
                if !sponsors.pastSponsors.isEmpty {
                    grid("Past Sponsors", people: sponsors.pastSponsors.map(Person.init), dimmed: true)
                }
            }
            .padding(28)
        }
        .overlay {
            if sponsors.sponsors.isEmpty, sponsors.contributors.isEmpty {
                if sponsors.isLoading {
                    ProgressView()
                } else if sponsors.failed {
                    ContentUnavailableView {
                        Label("Couldn't Load Sponsors", systemImage: "wifi.exclamationmark")
                    } actions: {
                        Button("Try Again") { Task { await sponsors.refresh() } }
                    }
                }
            }
        }
        .navigationTitle("Sponsors")
        .task {
            model.sponsors.markShown()
            await model.sponsors.refreshIfStale()
        }
    }

    private func grid(_ title: String, people: [Person], dimmed: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92, maximum: 110), spacing: 12)], spacing: 12) {
                ForEach(people) { person in
                    PersonCard(person: person)
                        .opacity(dimmed ? 0.6 : 1)
                }
            }
        }
    }
}

private struct Person: Identifiable {
    var id: String
    var name: String
    var avatar: URL?
    var profile: URL?
    var detail: String?

    init(_ sponsor: Sponsor) {
        id = "sponsor:\(sponsor.login)"
        name = sponsor.displayName
        avatar = sponsor.avatarURL
        profile = sponsor.profileURL
    }

    init(_ contributor: Contributor) {
        id = "contributor:\(contributor.login)"
        name = contributor.login
        avatar = contributor.avatarURL
        profile = contributor.profileURL
        detail = contributor.contributions == 1 ? "1 commit" : "\(contributor.contributions) commits"
    }
}

private struct PersonCard: View {
    let person: Person
    @State private var hovering = false

    var body: some View {
        Button {
            if let profile = person.profile { NSWorkspace.shared.open(profile) }
        } label: {
            VStack(spacing: 6) {
                AsyncImage(url: person.avatar) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Image(systemName: "person.crop.circle.fill")
                        .resizable()
                        .foregroundStyle(.tertiary)
                }
                .frame(width: 52, height: 52)
                .clipShape(.circle)
                .scaleEffect(hovering ? 1.06 : 1)
                Text(person.name)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                if let detail = person.detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(hovering ? AnyShapeStyle(.fill.quaternary) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.snappy, value: hovering)
    }
}
