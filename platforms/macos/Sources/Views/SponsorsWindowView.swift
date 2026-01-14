import SwiftUI

// MARK: - Sponsors Page View (Full Page in Main Window)

struct SponsorsPageView: View {
    @Bindable var sponsorManager: SponsorManager

    private let columns = [
        GridItem(.adaptive(minimum: 80, maximum: 100), spacing: 16)
    ]

    private var activeSponsors: [Sponsor] {
        sponsorManager.sponsors.filter { $0.amount > 0 }
    }

    private var pastSponsors: [Sponsor] {
        sponsorManager.sponsors.filter { $0.amount <= 0 }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                HStack(spacing: 16) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.pink)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sponsors")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("Thank you for supporting PortKiller!")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if let url = URL(string: AppInfo.githubSponsors) {
                        Link(destination: url) {
                            HStack(spacing: 6) {
                                Image(systemName: "heart.fill")
                                Text("Become a Sponsor")
                            }
                            .font(.callout)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.pink)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)

                // Sponsors Content
                if sponsorManager.sponsors.isEmpty && !sponsorManager.isLoading {
                    emptyState
                } else {
                    VStack(spacing: 24) {
                        // Active Sponsors
                        if !activeSponsors.isEmpty {
                            sponsorSection(
                                title: "Active Sponsors",
                                icon: "star.fill",
                                color: .yellow,
                                sponsors: activeSponsors
                            )
                        }
                        
                        // Contributors
                        if !sponsorManager.contributors.isEmpty {
                            contributorSection(
                                title: "Contributors",
                                icon: "hammer.fill",
                                color: .blue,
								contributors: sponsorManager.contributors
                            )
                        } else {
                            Text("No contributors found")
                        }
						
						// Past Sponsors
						if !pastSponsors.isEmpty {
							sponsorSection(
								title: "Past Sponsors",
								icon: "heart.fill",
								color: .secondary,
								sponsors: pastSponsors,
								dimmed: true
							)
						}
                    }
                }

            }
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            if sponsorManager.sponsors.isEmpty {
                await sponsorManager.refreshSponsors()
            }
        }
    }

    private func sponsorSection(title: String, icon: String, color: Color, sponsors: [Sponsor], dimmed: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(.headline)
                Text("(\(sponsors.count))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)

            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(sponsors) { sponsor in
                    SponsorCard(sponsor: sponsor, dimmed: dimmed)
                }
            }
            .padding(.horizontal, 24)
        }
    }
    
    private func contributorSection(title: String, icon: String, color: Color, contributors: [Contributor]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(.headline)
                Text("(\(contributors.count))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)

            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(contributors) { contributor in
                    ContributorCard(contributor: contributor)
                }
            }
            .padding(.horizontal, 24)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            if sponsorManager.error != nil {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 50))
                    .foregroundStyle(.secondary)

                Text("Couldn't load sponsors")
                    .font(.title2)
                    .fontWeight(.medium)

                Button("Try Again") {
                    Task {
                        await sponsorManager.refreshSponsors()
                    }
                }
                .buttonStyle(.borderedProminent)
            } else {
                Image(systemName: "person.3.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.secondary)

                Text("Be the first sponsor!")
                    .font(.title2)
                    .fontWeight(.medium)

                if let url = URL(string: AppInfo.githubSponsors) {
                    Link("Become a Sponsor", destination: url)
                        .buttonStyle(.borderedProminent)
                        .tint(.pink)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(60)
    }
}

// MARK: - Sponsor Card

struct SponsorCard: View {
    let sponsor: Sponsor
    var dimmed: Bool = false
    @State private var isHovered = false
    @State private var hasSponsorPage = false

    var body: some View {
        VStack(spacing: 8) {
            AsyncImage(url: URL(string: sponsor.avatarUrl)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    Image(systemName: "person.circle.fill")
                        .resizable()
                        .foregroundStyle(.secondary)
                case .empty:
                    ProgressView()
                @unknown default:
                    EmptyView()
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
            .scaleEffect(isHovered ? 1.08 : 1.0)
            .opacity(dimmed ? 0.6 : 1.0)
            .grayscale(dimmed ? 0.5 : 0)

            Text(sponsor.displayName)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(dimmed ? .secondary : .primary)
            
            Button {
                if hasSponsorPage {
                    if let url = URL(string: "https://github.com/sponsors/\(sponsor.login)") {
                        NSWorkspace.shared.open(url)
                    }
                } else {
                    if let url = sponsor.profileUrl {
                        NSWorkspace.shared.open(url)
                    }
                }
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: hasSponsorPage ? "heart.fill" : "person.fill")
                        .font(.system(size: 8))
                    Text(hasSponsorPage ? "Sponsor" : "Visit")
                        .font(.system(size: 9, weight: .semibold))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
            }
            .buttonStyle(.borderedProminent)
            .tint(hasSponsorPage ? .pink : .blue)
            .controlSize(.mini)
        }
        .frame(width: 80)
        .padding(10)
        .background(isHovered ? Color.primary.opacity(0.05) : Color.clear)
        .cornerRadius(8)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            if let url = sponsor.profileUrl {
                NSWorkspace.shared.open(url)
            }
        }
        .help("@\(sponsor.login)")
        .task {
            await checkSponsorPage()
        }
    }
    
    private func checkSponsorPage() async {
        guard let url = URL(string: "https://github.com/sponsors/\(sponsor.login)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                // GitHub returns 200 even for non-existent sponsor pages (redirects to profile)
                // We need to check if we got redirected
                if let url = httpResponse.url, url.absoluteString.contains("/sponsors/") {
                    hasSponsorPage = true
                } else {
                    hasSponsorPage = false
                }
            }
        } catch {
            // Ignore error, assume no sponsor page
        }
    }
}

// MARK: - Contributor Card

struct ContributorCard: View {
    let contributor: Contributor
    @State private var isHovered = false
    @State private var hasSponsorPage = false

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                AsyncImage(url: URL(string: contributor.avatarUrl)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        Image(systemName: "person.circle.fill")
                            .resizable()
                            .foregroundStyle(.secondary)
                    case .empty:
                        ProgressView()
                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(width: 48, height: 48)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
                
                // Contributions badge
                if contributor.contributions > 0 {
                    Text("\(contributor.contributions)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.blue)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 2)
                        )
                        .offset(x: 4, y: 4)
                }
            }
            .scaleEffect(isHovered ? 1.08 : 1.0)

            Text(contributor.login)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.tail)
                
            Button {
                if hasSponsorPage {
                    if let url = URL(string: "https://github.com/sponsors/\(contributor.login)") {
                        NSWorkspace.shared.open(url)
                    }
                } else {
                    if let url = URL(string: contributor.htmlUrl) {
                        NSWorkspace.shared.open(url)
                    }
                }
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: hasSponsorPage ? "heart.fill" : "person.fill")
                        .font(.system(size: 8))
                    Text(hasSponsorPage ? "Sponsor" : "Visit")
                        .font(.system(size: 9, weight: .semibold))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
            }
            .buttonStyle(.borderedProminent)
            .tint(hasSponsorPage ? .pink : .blue)
            .controlSize(.mini)
        }
        .frame(width: 80)
        .padding(10)
        .background(isHovered ? Color.primary.opacity(0.05) : Color.clear)
        .cornerRadius(8)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            if let url = URL(string: contributor.htmlUrl) {
                NSWorkspace.shared.open(url)
            }
        }
        .help("@\(contributor.login)")
        .task {
            await checkSponsorPage()
        }
    }
    
    private func checkSponsorPage() async {
        guard let url = URL(string: "https://github.com/sponsors/\(contributor.login)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                // GitHub returns 200 even for non-existent sponsor pages (redirects to profile)
                // We need to check if we got redirected
                if let url = httpResponse.url, url.absoluteString.contains("/sponsors/") {
                    hasSponsorPage = true
                } else {
                    hasSponsorPage = false
                }
            }
        } catch {
            // Ignore error, assume no sponsor page
        }
    }
}

