import Foundation
import UserNotifications

@MainActor
final class NotificationService: ObservableObject {

    static let shared = NotificationService()

    @Published var isAuthorized: Bool = false

    private init() {
        Task { await checkAuthorizationStatus() }
    }

    // MARK: - Authorization

    func checkAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized
    }

    /// Requests notification permission. Returns true if granted.
    func requestPermission() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            isAuthorized = granted
            return granted
        } catch {
            return false
        }
    }

    // MARK: - Schedule

    /// Schedules a reminder for the next treatment step.
    /// - Parameters:
    ///   - nextTreatmentName: Name of the next chemical to add
    ///   - afterMinutes: Minutes from now when the notification should fire
    /// - Returns: The notification identifier (for cancellation)
    @discardableResult
    func scheduleNextStepReminder(
        nextTreatmentName: String,
        afterMinutes: Int
    ) async -> String {
        let identifier = "treatment-\(UUID().uuidString)"

        let content = UNMutableNotificationContent()
        content.title = "Time for your next pool treatment"
        content.body = "Ready to add \(nextTreatmentName). Tap to open Pool Side."
        content.sound = .default
        content.categoryIdentifier = "TREATMENT_REMINDER"

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: TimeInterval(afterMinutes * 60),
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            print("NotificationService: failed to schedule — \(error)")
        }

        return identifier
    }

    /// Cancels a previously scheduled notification
    func cancel(identifier: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    // MARK: - Toast Message Helper

    /// Human-readable string for a wait interval
    static func waitLabel(minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes) minute\(minutes == 1 ? "" : "s")"
        }
        let hours = minutes / 60
        let remaining = minutes % 60
        if remaining == 0 {
            return "\(hours) hour\(hours == 1 ? "" : "s")"
        }
        return "\(hours) hr \(remaining) min"
    }
}
