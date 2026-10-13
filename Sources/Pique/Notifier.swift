import AppKit
import UserNotifications

/// macOS notifications: print milestones (with one camera frame) and printer online/offline (no frame).
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let enabledKey = "notifications"
    /// Camera frames show the inside of the printer and part of the room, and can appear on the lock screen.
    static let imagesKey = "notificationImages"
    static private(set) var shared: Notifier?

    private let camera: Camera

    init(camera: Camera) {
        self.camera = camera
        super.init()
        UNUserNotificationCenter.current().delegate = self
        Self.shared = self
    }

    static func requestAuthorization(_ done: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async { done(granted) }
        }
    }

    // Show banners even while the app is frontmost.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    private var enabled: Bool { UserDefaults.standard.bool(forKey: Self.enabledKey) }

    func printStateChanged(from old: PrinterStatus.State, to new: PrinterStatus.State, status: PrinterStatus) {
        guard enabled else { return }
        let title: String.LocalizationValue
        switch (old, new) {
        case (.paused, .printing): title = "Print resumed"
        case (.idle, .preparing), (.idle, .printing), (.finished, .preparing), (.finished, .printing),
             (.failed, .preparing), (.failed, .printing): title = "Print started"
        case (_, .paused): title = "Print paused"
        case (_, .finished): title = "Print finished"
        case (_, .failed): title = status.wasCanceled ? "Print canceled" : "Print failed"
        default: return
        }
        var body = [status.fileName]
        if [.paused, .failed].contains(new), let percent = status.percent { body.append("\(percent)%") }
        let text = body.compactMap { $0 }.joined(separator: " · ")
        snapshot { image in self.post(String(localized: title, bundle: AppLanguage.bundle), text, image: image) }
    }

    func printerOnline(_ online: Bool) {
        guard enabled else { return }
        let title = online
            ? String(localized: "Printer online", bundle: AppLanguage.bundle)
            : String(localized: "Printer offline", bundle: AppLanguage.bundle)
        post(title, UserDefaults.standard.string(forKey: "printerIP") ?? "", image: nil)
    }

    func sendTest() {
        snapshot { image in
            self.post(String(localized: "Notifications are on", bundle: AppLanguage.bundle),
                      String(localized: "Print updates will look like this.", bundle: AppLanguage.bundle), image: image)
        }
    }

    /// One frame for the notification: the live one if a window streams, else a single grab. None if turned off.
    private func snapshot(_ done: @escaping (Data?) -> Void) {
        guard UserDefaults.standard.object(forKey: Self.imagesKey) as? Bool ?? true else { return done(nil) }
        if camera.live, let frame = camera.lastJPEG { return done(frame) }
        Camera.grabFrame(done)
    }

    private func post(_ title: String, _ body: String, image: Data?) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let image {
            // The system moves the file into its own store, so a throwaway temp file is fine.
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).jpg")
            if (try? image.write(to: url)) != nil,
               let attachment = try? UNNotificationAttachment(identifier: "frame", url: url) {
                content.attachments = [attachment]
            } else {
                try? FileManager.default.removeItem(at: url)
            }
        }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
