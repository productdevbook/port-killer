import Foundation
import SwiftUI
import Defaults

@Observable
@MainActor
final class SponsorManager {
    // MARK: - State
    var sponsors: [Sponsor] = []
    var contributors: [Contributor] = []
    var isLoading = false
    var error: Error?
    var shouldShowWindow = false

    // MARK: - Private
    private let service = SponsorsService()
    private var hasCheckedOnLaunch = false

    // MARK: - Init
    init() {
        loadCachedSponsors()
    }

    // MARK: - Public Methods

    /// Check if sponsors window should be shown (called on app launch)
    func checkAndShowIfNeeded() {
        guard !hasCheckedOnLaunch else { return }
        hasCheckedOnLaunch = true

        let interval = Defaults[.sponsorDisplayInterval]
        guard let days = interval.days else { return }

        let lastShown = Defaults[.lastSponsorWindowShown]
        let shouldShow: Bool

        if let lastShown {
            let daysSinceLastShown = Calendar.current.dateComponents(
                [.day],
                from: lastShown,
                to: Date()
            ).day ?? 0
            shouldShow = daysSinceLastShown >= days
        } else {
            shouldShow = true
        }

        if shouldShow {
            shouldShowWindow = true
        }

        // Refresh sponsors in background if cache is stale
        if Defaults[.sponsorCache]?.isStale ?? true {
            Task { @MainActor in
                await self.refreshSponsors()
            }
        }
    }

    /// Mark that sponsors window was shown
    func markWindowShown() {
        Defaults[.lastSponsorWindowShown] = Date()
        shouldShowWindow = false
    }

    /// Force show sponsors window (e.g., from Settings)
    func showSponsorsWindow() {
        shouldShowWindow = true
    }

    /// Refresh sponsors from API
    func refreshSponsors() async {
        isLoading = true
        error = nil

        do {
            async let fetchedSponsors = service.fetchSponsors()
            async let fetchedContributors = service.fetchContributors()
            
            let (sponsors, contributors) = try await (fetchedSponsors, fetchedContributors)
            
            // Filter out bots
            let validContributors = contributors.filter { !$0.login.lowercased().contains("[bot]") }
            
            print("Fetched \(sponsors.count) sponsors and \(validContributors.count) contributors")
            
            self.sponsors = sponsors
            self.contributors = validContributors

            Defaults[.sponsorCache] = SponsorCache(
                sponsors: sponsors,
                contributors: validContributors,
                fetchedAt: Date()
            )
        } catch {
            print("Failed to fetch sponsors/contributors: \(error)")
            self.error = error
        }

        isLoading = false
    }

    // MARK: - Private Methods

    private func loadCachedSponsors() {
        if let cache = Defaults[.sponsorCache] {
            sponsors = cache.sponsors
            // Filter cached contributors too, just in case
            contributors = cache.contributors.filter { !$0.login.lowercased().contains("[bot]") }
        }
    }
}
