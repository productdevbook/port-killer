import Foundation

/// Service for fetching sponsors from static JSON
actor SponsorsService {
    private let sponsorsURL = URL(string: "https://raw.githubusercontent.com/productdevbook/static/main/sponsors.json")!
    private let contributorsURL = URL(string: "https://api.github.com/repos/productdevbook/port-killer/contributors")!

    enum SponsorsError: Error, LocalizedError, Sendable {
        case networkError(String)
        case invalidResponse
        case decodingError(String)

        var errorDescription: String? {
            switch self {
            case .networkError(let description):
                return "Network error: \(description)"
            case .invalidResponse:
                return "Invalid response from server"
            case .decodingError(let description):
                return "Failed to parse sponsors: \(description)"
            }
        }
    }

    /// Fetch sponsors from static JSON
    func fetchSponsors() async throws -> [Sponsor] {
        let (data, response) = try await URLSession.shared.data(from: sponsorsURL)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw SponsorsError.invalidResponse
        }

        do {
            return try JSONDecoder().decode([Sponsor].self, from: data)
        } catch {
            throw SponsorsError.decodingError(error.localizedDescription)
        }
    }

    /// Fetch contributors from GitHub API
    func fetchContributors() async throws -> [Contributor] {
        var request = URLRequest(url: contributorsURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw SponsorsError.invalidResponse
        }

        do {
            return try JSONDecoder().decode([Contributor].self, from: data)
        } catch {
            throw SponsorsError.decodingError(error.localizedDescription)
        }
    }
}
