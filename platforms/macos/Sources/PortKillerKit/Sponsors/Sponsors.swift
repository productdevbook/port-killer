public import Foundation

public struct Sponsor: Identifiable, Codable, Hashable, Sendable {
    public var name: String?
    public var login: String
    public var avatar: String?
    public var amount: Int
    public var link: String?
    public var org: Bool?

    public var id: String { login }

    public var displayName: String {
        guard let name, !name.isEmpty else { return login }
        return name
    }

    public var avatarURL: URL? { avatar.flatMap(URL.init(string:)) }
    public var profileURL: URL? { link.flatMap(URL.init(string:)) ?? URL(string: "https://github.com/\(login)") }
    public var isActive: Bool { amount > 0 }
}

public struct Contributor: Identifiable, Codable, Hashable, Sendable {
    public var login: String
    public var avatarUrl: String
    public var htmlUrl: String
    public var contributions: Int

    public var id: String { login }
    public var avatarURL: URL? { URL(string: avatarUrl) }
    public var profileURL: URL? { URL(string: htmlUrl) }

    enum CodingKeys: String, CodingKey {
        case login
        case avatarUrl = "avatar_url"
        case htmlUrl = "html_url"
        case contributions
    }
}

public struct SponsorCache: Codable, Sendable {
    public var sponsors: [Sponsor]
    public var contributors: [Contributor]
    public var fetchedAt: Date

    public init(sponsors: [Sponsor], contributors: [Contributor], fetchedAt: Date) {
        self.sponsors = sponsors
        self.contributors = contributors
        self.fetchedAt = fetchedAt
    }

    public var isStale: Bool {
        Date().timeIntervalSince(fetchedAt) > 86_400
    }
}

public enum SponsorDisplayInterval: String, CaseIterable, Identifiable, Codable, Sendable {
    case monthly = "Monthly"
    case bimonthly = "Every 2 Months"
    case quarterly = "Every 3 Months"
    case never = "Never"

    public var id: String { rawValue }

    public var days: Int? {
        switch self {
        case .monthly: 30
        case .bimonthly: 60
        case .quarterly: 90
        case .never: nil
        }
    }
}

public enum SponsorsClient {
    static let sponsorsURL = URL(string: "https://raw.githubusercontent.com/productdevbook/static/main/sponsors.json")
    static let contributorsURL = URL(string: "https://api.github.com/repos/productdevbook/port-killer/contributors")

    public static func fetch() async throws -> SponsorCache {
        guard let sponsorsURL, let contributorsURL else { throw URLError(.badURL) }
        var contributorsRequest = URLRequest(url: contributorsURL)
        contributorsRequest.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        contributorsRequest.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        async let sponsorData = data(for: URLRequest(url: sponsorsURL))
        async let contributorData = data(for: contributorsRequest)
        let sponsors = try JSONDecoder().decode([Sponsor].self, from: try await sponsorData)
        let contributors = try JSONDecoder().decode([Contributor].self, from: try await contributorData)
            .filter { !$0.login.lowercased().contains("[bot]") }
        return SponsorCache(sponsors: sponsors, contributors: contributors, fetchedAt: Date())
    }

    private static func data(for request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}
