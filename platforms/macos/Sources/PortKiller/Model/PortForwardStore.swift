import Foundation
import Observation
import PortKillerKit

@Observable
final class PortForwardStore {
    let preferences: Preferences
    let notifier: Notifier

    private(set) var sessions: [PortForwardSession] = []
    private(set) var context: String?
    private(set) var isKillingStuckProcesses = false
    var selection: PortForwardSession.ID?

    init(preferences: Preferences, notifier: Notifier) {
        self.preferences = preferences
        self.notifier = notifier
        sessions = preferences.portForwards.map { PortForwardSession(configuration: $0, preferences: preferences, notifier: notifier) }
    }

    var connectedCount: Int {
        sessions.count(where: \.isConnected)
    }

    var activeCount: Int {
        sessions.count(where: \.isActive)
    }

    var selectedSession: PortForwardSession? {
        sessions.first { $0.id == selection }
    }

    var kubectl: Kubectl? {
        preferences.locate(.kubectl).map(Kubectl.init(executable:))
    }

    func startAutomatically() {
        guard preferences.portForwardAutoStart else { return }
        startAll()
    }

    func refreshContext() async {
        context = await kubectl?.currentContext()
    }

    func add(_ configuration: PortForwardConfiguration, start: Bool = false) {
        let session = PortForwardSession(configuration: configuration, preferences: preferences, notifier: notifier)
        sessions.append(session)
        selection = session.id
        save()
        if start { session.start() }
    }

    func update(_ configuration: PortForwardConfiguration) {
        guard let session = sessions.first(where: { $0.id == configuration.id }), session.configuration != configuration else { return }
        let wasActive = session.isActive
        session.configuration = configuration
        save()
        if wasActive {
            session.restart()
        }
    }

    func remove(_ id: PortForwardSession.ID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].stop()
        sessions.remove(at: index)
        if selection == id { selection = nil }
        save()
    }

    func move(_ ids: [PortForwardSession.ID], before destination: PortForwardSession.ID?) {
        let moving = sessions.filter { ids.contains($0.id) }
        var remaining = sessions.filter { !ids.contains($0.id) }
        let index = destination.flatMap { id in remaining.firstIndex { $0.id == id } } ?? remaining.endIndex
        remaining.insert(contentsOf: moving, at: index)
        sessions = remaining
        save()
    }

    func startAll() {
        for session in sessions where session.configuration.isEnabled {
            session.start()
        }
    }

    func stopAll() {
        sessions.forEach { $0.stop() }
    }

    func stopAllAndWait() async {
        await withDiscardingTaskGroup { group in
            for session in sessions {
                group.addTask(name: "Stop \(session.configuration.name)") { await session.stopAndWait() }
            }
        }
    }

    func killStuckProcesses() async {
        isKillingStuckProcesses = true
        defer { isKillingStuckProcesses = false }
        await stopAllAndWait()
        let pkill = URL(filePath: "/usr/bin/pkill")
        _ = try? await CommandRunner.run(pkill, ["-9", "-f", "kubectl.*port-forward"])
        _ = try? await CommandRunner.run(pkill, ["-9", "-f", "socat.*TCP-LISTEN"])
    }

    func addCustomNamespaces(_ names: [String]) {
        for name in names.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) where !name.isEmpty && !preferences.customNamespaces.contains(name) {
            preferences.customNamespaces.append(name)
        }
    }

    func removeCustomNamespace(_ name: String) {
        preferences.customNamespaces.removeAll { $0 == name }
    }

    private func save() {
        preferences.portForwards = sessions.map(\.configuration)
    }
}
