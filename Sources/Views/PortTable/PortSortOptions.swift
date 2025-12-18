/// PortSortOptions - Sorting configuration for port table
///
/// Defines available sort orders for the port table view:
/// - Port number
/// - Process name
/// - PID
/// - Type (process category)
/// - Address
/// - User
/// - Actions (favorite/watched status)
///
/// - Note: Each sort order can be ascending or descending.

import Foundation

/// Available sort orders for port table
enum SortOrder: String, CaseIterable {
    case port = "Port"
    case process = "Process"
    case pid = "PID"
    case type = "Type"
    case address = "Address"
    case user = "User"
    case actions = "Actions"
}
