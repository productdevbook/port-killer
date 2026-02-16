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
        stopAutoRefresh()
        refreshTask = Task { @MainActor in
            var unchangedCycles = 0
            _ = await self.refresh()
            while !Task.isCancelled {
                let baseInterval = max(1, Defaults[.refreshInterval])
                let delaySeconds = adaptiveRefreshDelay(baseInterval: baseInterval, unchangedCycles: unchangedCycles)
                try? await Task.sleep(for: .seconds(delaySeconds))
                guard !Task.isCancelled else { break }

                let didChange = await self.refresh()
                unchangedCycles = didChange ? 0 : min(unchangedCycles + 1, 60)
            }
        }
    }

    /// Dynamically backs off polling when the port list stays stable.
    private func adaptiveRefreshDelay(baseInterval: Int, unchangedCycles: Int) -> Double {
        let base = Double(baseInterval)
        let multiplier: Double

        switch unchangedCycles {
        case 0..<6:
            multiplier = 1.0
        case 6..<12:
            multiplier = 1.5
        default:
            multiplier = 2.0
        }

        return min(base * multiplier, 30.0)
    }
}
