import SwiftUI
import Sparkle

struct CheckForUpdatesView: View {
    @ObservedObject var updateManager: UpdateManager
    
    var body: some View {
		Button("Check for Updates...", systemImage: "arrow.triangle.2.circlepath") {
            updateManager.checkForUpdates()
        }
        .disabled(!updateManager.canCheckForUpdates)
    }
}
