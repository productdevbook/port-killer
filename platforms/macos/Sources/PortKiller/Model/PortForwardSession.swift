import AsyncAlgorithms
import DequeModule
import Foundation
import Observation
import PortKillerKit

struct ForwardLogEntry: Identifiable, Hashable {
    enum Source: String {
        case kubectl
        case socat
        case portKiller = "portkiller"
    }

    let id = UUID()
    var date = Date()
    var source: Source
    var message: String
    var isError: Bool
}

@Observable
final class PortForwardSession: Identifiable {
    enum Status: Equatable {
        case stopped
        case connecting
        case connected
        case waitingToReconnect(Date)
        case stopping
        case failed
    }

    private struct Tools {
        var kubectl: URL
        var socat: URL?
    }

    private enum Outcome: Sendable {
        case exited(String, Int32)
        case lost(Int)
        case failed(String)
    }

    let id: UUID
    var configuration: PortForwardConfiguration
    private(set) var status: Status = .stopped
    private(set) var lastError: String?
    private(set) var connectedSince: Date?
    private(set) var logs: Deque<ForwardLogEntry> = []

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private let notifier: Notifier

    init(configuration: PortForwardConfiguration, preferences: Preferences, notifier: Notifier) {
        id = configuration.id
        self.configuration = configuration
        self.preferences = preferences
        self.notifier = notifier
    }

    var isActive: Bool { task != nil }

    var isConnected: Bool { status == .connected }

    func start() {
        guard task == nil else { return }
        guard let kubectl = preferences.locate(.kubectl) else {
            status = .failed
            lastError = KubectlError.notInstalled.localizedDescription
            return
        }
        let tools = Tools(kubectl: kubectl, socat: preferences.locate(.socat))
        lastError = nil
        task = Task(name: "Port forward \(configuration.name)") { [weak self] in
            await self?.supervise(tools)
        }
    }

    func stop() {
        guard let task, !task.isCancelled else { return }
        task.cancel()
        status = .stopping
    }

    func restart() {
        Task(name: "Restart \(configuration.name)") { [weak self] in
            await self?.stopAndWait()
            self?.start()
        }
    }

    func stopAndWait() async {
        let running = task
        stop()
        await running?.value
    }

    func clearLogs() {
        logs.removeAll()
    }

    private func supervise(_ tools: Tools) async {
        var attempt = 0
        while !Task.isCancelled {
            status = .connecting
            let outcome = await runOnce(tools)
            guard !Task.isCancelled else { break }
            let wasConnected = connectedSince != nil
            connectedSince = nil
            switch outcome {
            case .exited(let source, let code):
                fail("\(source) exited with status \(code)")
            case .lost(let port):
                fail("Nothing listens on port \(port) anymore")
            case .failed(let message):
                fail(message)
            }
            if wasConnected {
                attempt = 0
                if preferences.portForwardNotifications, configuration.notifyOnDisconnect {
                    notifier.post(title: "Disconnected", body: "\(configuration.name) lost its connection.")
                }
            }
            guard configuration.autoReconnect else {
                status = .failed
                break
            }
            attempt += 1
            let delay = min(pow(2, Double(min(attempt, 5))), 30)
            status = .waitingToReconnect(Date().addingTimeInterval(delay))
            try? await Task.sleep(for: .seconds(delay))
        }
        if Task.isCancelled || status != .failed { status = .stopped }
        connectedSince = nil
        task = nil
    }

    private func runOnce(_ tools: Tools) async -> Outcome {
        let configuration = configuration
        if configuration.proxyPort != nil, tools.socat == nil {
            return .failed("socat isn't installed. Install it with brew install socat, or turn off the proxy.")
        }
        if configuration.usesDirectExec, let socat = tools.socat, let proxyPort = configuration.proxyPort {
            let script: URL
            do {
                script = try PortForwardPlan.writeDirectExecScript(configuration, kubectl: tools.kubectl, socat: socat)
            } catch {
                return .failed("Couldn't prepare the proxy script: \(error.localizedDescription)")
            }
            defer { try? FileManager.default.removeItem(at: script) }
            return await withTaskGroup(of: Outcome.self) { group in
                group.addTask {
                    await self.runProcess(.socat, socat, PortForwardPlan.directExecArguments(listenPort: proxyPort, script: script))
                }
                group.addTask {
                    await self.watchHealth(port: proxyPort)
                }
                let outcome = await group.next() ?? .failed("Stopped")
                group.cancelAll()
                return outcome
            }
        }
        return await withTaskGroup(of: Outcome.self) { group in
            group.addTask {
                await self.runProcess(.kubectl, tools.kubectl, PortForwardPlan.kubectlArguments(configuration))
            }
            group.addTask {
                guard await self.waitUntilListening(port: configuration.localPort) else {
                    return .failed("kubectl didn't open port \(configuration.localPort)")
                }
                if let proxyPort = configuration.proxyPort, let socat = tools.socat {
                    return await withTaskGroup(of: Outcome.self) { inner in
                        inner.addTask {
                            await self.runProcess(.socat, socat, PortForwardPlan.proxyArguments(listenPort: proxyPort, targetPort: configuration.localPort))
                        }
                        inner.addTask {
                            await self.watchHealth(port: proxyPort)
                        }
                        let outcome = await inner.next() ?? .failed("Stopped")
                        inner.cancelAll()
                        return outcome
                    }
                }
                return await self.watchHealth(port: configuration.localPort)
            }
            let outcome = await group.next() ?? .failed("Stopped")
            group.cancelAll()
            return outcome
        }
    }

    nonisolated private func runProcess(_ source: ForwardLogEntry.Source, _ executable: URL, _ arguments: [String]) async -> Outcome {
        do {
            let code = try await CommandRunner.stream(
                executable,
                arguments,
                environment: ["PATH": CommandLineTool.searchPath],
                ownProcessGroup: source == .socat
            ) { @MainActor [weak self] line in
                self?.receive(line, from: source)
            }
            return .exited(source.rawValue, code)
        } catch {
            return .failed("\(source.rawValue): \(error.localizedDescription)")
        }
    }

    nonisolated private func waitUntilListening(port: Int) async -> Bool {
        for _ in 0..<60 {
            if Task.isCancelled { return false }
            if await PortScanner.isListening(port: port) { return true }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return false
    }

    nonisolated private func watchHealth(port: Int) async -> Outcome {
        guard await waitUntilListening(port: port) else { return .failed("Port \(port) didn't open") }
        await markConnected()
        var failures = 0
        for await _ in AsyncTimerSequence(interval: .seconds(3), clock: .continuous) {
            if await PortScanner.isListening(port: port) {
                failures = 0
            } else {
                failures += 1
                if failures >= 2 { return .lost(port) }
            }
        }
        return .failed("Stopped")
    }

    private func markConnected() {
        guard let task, !task.isCancelled, status != .connected else { return }
        status = .connected
        connectedSince = Date()
        lastError = nil
        append(.portKiller, "Connected on localhost:\(configuration.effectivePort)", isError: false)
        if preferences.portForwardNotifications, configuration.notifyOnConnect {
            notifier.post(title: "Connected", body: "\(configuration.name) is ready on port \(configuration.effectivePort).")
        }
    }

    private func receive(_ line: String, from source: ForwardLogEntry.Source) {
        let isError = PortForwardOutput.isError(line)
        append(source, line, isError: isError)
        if isError { lastError = line }
        if let port = PortForwardOutput.conflictingPort(in: line) {
            Task(name: "Resolve port \(port) conflict") { [weak self] in
                await self?.resolveConflict(on: port)
            }
        }
    }

    private func resolveConflict(on port: Int) async {
        let stale = await PortScanner.scan().filter { listener in
            listener.port == port && ["kubectl", "socat"].contains(listener.processName)
        }
        guard !stale.isEmpty else {
            append(.portKiller, "Port \(port) is used by another app", isError: true)
            return
        }
        append(.portKiller, "Port \(port) is held by a stale \(stale[0].processName), stopping it", isError: false)
        for listener in stale {
            try? await ProcessTerminator.terminate(listener.pid)
        }
    }

    private func fail(_ message: String) {
        lastError = message
        append(.portKiller, message, isError: true)
    }

    private func append(_ source: ForwardLogEntry.Source, _ message: String, isError: Bool) {
        logs.append(ForwardLogEntry(source: source, message: message, isError: isError))
        if logs.count > 500 { logs.removeFirst() }
    }
}
