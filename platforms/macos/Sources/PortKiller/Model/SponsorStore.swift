import Foundation
import Observation
import PortKillerKit

@Observable
final class SponsorStore {
    let preferences: Preferences

    private(set) var isLoading = false
    private(set) var failed = false

    init(preferences: Preferences) {
        self.preferences = preferences
    }

    var sponsors: [Sponsor] { preferences.sponsorCache?.sponsors ?? [] }
    var contributors: [Contributor] { preferences.sponsorCache?.contributors ?? [] }

    var activeSponsors: [Sponsor] { sponsors.filter(\.isActive) }
    var pastSponsors: [Sponsor] { sponsors.filter { !$0.isActive } }

    var isDue: Bool {
        guard let days = preferences.sponsorInterval.days else { return false }
        guard let lastShown = preferences.sponsorLastShown else { return true }
        return Date().timeIntervalSince(lastShown) >= Double(days) * 86_400
    }

    func markShown() {
        preferences.sponsorLastShown = Date()
    }

    func refreshIfStale() async {
        guard preferences.sponsorCache?.isStale ?? true else { return }
        await refresh()
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            preferences.sponsorCache = try await SponsorsClient.fetch()
            failed = false
        } catch {
            failed = sponsors.isEmpty
        }
    }
}
