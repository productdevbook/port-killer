import AppKit
import Observation
import UserNotifications

@Observable
final class Notifier: NSObject {
    struct KillRequest: Sendable {
        var port: Int
        var pid: Int32
    }

    nonisolated private static let killCategory = "PORT_ACTIVE"
    nonisolated private static let killAction = "KILL_PROCESS"

    private(set) var status: UNAuthorizationStatus = .notDetermined
    @ObservationIgnored var onKill: ((KillRequest) -> Void)?

    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleURL.pathExtension == "app" ? UNUserNotificationCenter.current() : nil
    }

    var isAvailable: Bool { center != nil }
    var isAuthorized: Bool { status == .authorized || status == .provisional }
    var isDenied: Bool { status == .denied }

    func setUp() {
        guard let center else { return }
        center.delegate = self
        let kill = UNNotificationAction(identifier: Self.killAction, title: "Kill Process", options: [.destructive])
        center.setNotificationCategories([UNNotificationCategory(identifier: Self.killCategory, actions: [kill], intentIdentifiers: [])])
        Task(name: "Notification authorization") {
            await refreshStatus()
            if status == .notDetermined { await requestAuthorization() }
        }
    }

    func refreshStatus() async {
        guard let center else { return }
        status = await center.notificationSettings().authorizationStatus
    }

    func requestAuthorization() async {
        guard let center else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
        await refreshStatus()
    }

    func openSystemSettings() {
        guard let identifier = Bundle.main.bundleIdentifier,
              let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(identifier)") else { return }
        NSWorkspace.shared.open(url)
    }

    func post(title: String, body: String, killing request: KillRequest? = nil) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let request {
            content.categoryIdentifier = Self.killCategory
            content.userInfo = ["port": request.port, "pid": Int(request.pid)]
        }
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}

extension Notifier: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == Self.killAction else { return }
        let info = response.notification.request.content.userInfo
        guard let port = info["port"] as? Int, let pid = info["pid"] as? Int else { return }
        await MainActor.run {
            onKill?(KillRequest(port: port, pid: Int32(pid)))
        }
    }
}
