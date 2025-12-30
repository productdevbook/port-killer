import Foundation
import Defaults

/// Represents a sponsor from static JSON
struct Sponsor: Identifiable, Codable, Sendable, Hashable {
    let name: String?
    let login: String
    let avatar: String?
    let amount: Int
    let link: String?
    let org: Bool?

    var id: String { login }

    var displayName: String {
        guard let name, !name.isEmpty else { return login }
        return name
    }

    var avatarUrl: String { avatar ?? "" }
    var profileUrl: URL? {
        guard let link else { return nil }
        return URL(string: link)
    }
}

struct Contributor: Identifiable, Codable, Sendable, Hashable {
	let login: String
	let avatarUrl: String
	let htmlUrl: String
	let contributions: Int
	
	// Calculated property for ID
	var id: String { login }
	
	enum CodingKeys: String, CodingKey {
		case login
		case avatarUrl = "avatar_url"
		case htmlUrl = "html_url"
		case contributions
	}
}

/// Cached sponsor data with timestamp
struct SponsorCache: Codable, Defaults.Serializable {
    let sponsors: [Sponsor]
    let contributors: [Contributor]
    let fetchedAt: Date

    var isStale: Bool {
        // Cache is stale after 24 hours
        Date().timeIntervalSince(fetchedAt) > 86400
    }
}

/// Sponsor display interval options
enum SponsorDisplayInterval: String, CaseIterable, Codable, Defaults.Serializable {
    case monthly = "Monthly"
    case bimonthly = "Every 2 Months"
    case quarterly = "Every 3 Months"
    case never = "Never"

    var days: Int? {
        switch self {
        case .monthly: return 30
        case .bimonthly: return 60
        case .quarterly: return 90
        case .never: return nil
        }
    }

    var localizedName: String {
        switch self {
        case .monthly: return "Monthly"
        case .bimonthly: return "Every 2 Months"
        case .quarterly: return "Every 3 Months"
        case .never: return "Never"
        }
    }
}
