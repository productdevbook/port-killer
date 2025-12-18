import Foundation
import Defaults

extension AppState {
    /// Stops the auto-refresh task.
    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    /// Starts a background task that periodically refreshes the port list.
    func startAutoRefresh() {
        refreshTask = Task { @MainActor in
            await self.refresh()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Defaults[.refreshInterval]))
                if !Task.isCancelled { await self.refresh() }
            }
        }
    }
}
