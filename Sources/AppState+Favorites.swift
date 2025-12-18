import Foundation

extension AppState {
    /// Toggles favorite status for a port.
    func toggleFavorite(_ port: Int) {
        if favorites.contains(port) { favorites.remove(port) }
        else { favorites.insert(port) }
    }

    /// Checks if a port is marked as favorite.
    func isFavorite(_ port: Int) -> Bool { favorites.contains(port) }
}
