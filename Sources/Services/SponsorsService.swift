import Foundation

/// Service for fetching sponsors from static JSON
actor SponsorsService {
    private let sponsorsURL = URL(string: "https://raw.githubusercontent.com/productdevbook/static/main/sponsors.json")!

    enum SponsorsError: Error, LocalizedError {
        case networkError(Error)
        case invalidResponse
        case decodingError(Error)

        var errorDescription: String? {
            switch self {
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            case .invalidResponse:
                return "Invalid response from server"
            case .decodingError(let error):
                return "Failed to parse sponsors: \(error.localizedDescription)"
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
            throw SponsorsError.decodingError(error)
        }
    }
}
