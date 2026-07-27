import Foundation
import UserNotifications

enum PoolNotificationPurpose: String, Codable {
    case nextPoolTest
    case nextTreatmentStep
    case treatmentRetest
}

@MainActor
final class NotificationService: ObservableObject {

    static let shared = NotificationService()
    static let nextPoolTestIdentifier = "next-pool-test"

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

    @discardableResult
    func scheduleNextPoolTestReminder(at date: Date, reason: String) async -> String? {
        guard isAuthorized else { return nil }
        let fireDate = adjustedFutureDate(date)

        let content = UNMutableNotificationContent()
        content.title = "Next pool test"
        content.body = reason.isEmpty ? "It's time to log your next pool test." : reason
        content.sound = .default
        content.categoryIdentifier = "POOL_TEST_REMINDER"

        await schedule(
            identifier: Self.nextPoolTestIdentifier,
            content: content,
            date: fireDate
        )
        return Self.nextPoolTestIdentifier
    }

    func cancelNextPoolTestReminder() {
        cancel(identifier: Self.nextPoolTestIdentifier)
    }

    @discardableResult
    func replaceNextPoolTestReminder(at date: Date, reason: String) async -> String? {
        cancelNextPoolTestReminder()
        return await scheduleNextPoolTestReminder(at: date, reason: reason)
    }

    @discardableResult
    func scheduleTreatmentStepReminder(
        treatmentID: UUID,
        nextTreatmentName: String,
        afterMinutes: Int
    ) async -> String? {
        guard isAuthorized, afterMinutes > 0 else { return nil }
        let identifier = "treatment-step-\(treatmentID.uuidString)"

        let content = UNMutableNotificationContent()
        content.title = "Time for your next pool treatment"
        content.body = "Ready to add \(nextTreatmentName). Tap to open Pool Side."
        content.sound = .default
        content.categoryIdentifier = "TREATMENT_REMINDER"

        await schedule(
            identifier: identifier,
            content: content,
            date: Date().addingTimeInterval(TimeInterval(afterMinutes * 60))
        )
        return identifier
    }

    @discardableResult
    func scheduleTreatmentRetestReminder(
        treatmentID: UUID,
        parameter: String,
        afterMinutes: Int,
        reason: String
    ) async -> String? {
        guard isAuthorized, afterMinutes > 0 else { return nil }
        let identifier = "treatment-retest-\(treatmentID.uuidString)"

        let content = UNMutableNotificationContent()
        content.title = "Retest \(displayParameter(parameter))"
        content.body = reason
        content.sound = .default
        content.categoryIdentifier = "POOL_TEST_REMINDER"

        await schedule(
            identifier: identifier,
            content: content,
            date: Date().addingTimeInterval(TimeInterval(afterMinutes * 60))
        )
        return identifier
    }

    /// Compatibility wrapper for the pre-refactor API.
    @discardableResult
    func scheduleNextStepReminder(nextTreatmentName: String, afterMinutes: Int) async -> String {
        await scheduleTreatmentStepReminder(
            treatmentID: UUID(),
            nextTreatmentName: nextTreatmentName,
            afterMinutes: afterMinutes
        ) ?? "treatment-step-unscheduled-\(UUID().uuidString)"
    }

    private func schedule(identifier: String, content: UNMutableNotificationContent, date: Date) async {
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date),
            repeats: false
        )
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            print("NotificationService: failed to schedule — \(error)")
        }
    }

    /// Cancels a previously scheduled notification
    func cancel(identifier: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    func cancelTreatmentReminder(for treatment: Treatment) {
        [
            treatment.reminderNotificationIdentifier,
            treatment.stepReminderNotificationIdentifier,
            treatment.retestReminderNotificationIdentifier
        ]
        .compactMap { $0 }
        .forEach { cancel(identifier: $0) }

        treatment.reminderNotificationIdentifier = nil
        treatment.stepReminderNotificationIdentifier = nil
        treatment.retestReminderNotificationIdentifier = nil
    }

    func cancelAllPoolSideNotifications() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [Self.nextPoolTestIdentifier]
        )
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let identifiers = requests
                .map(\.identifier)
                .filter {
                    $0.hasPrefix("treatment-step-")
                        || $0.hasPrefix("treatment-retest-")
                        || $0.hasPrefix("treatment-")
                }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
        }
    }

    func pendingNotificationDebugSummary() async -> String {
        let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        guard !requests.isEmpty else { return "No pending Pool Side notifications." }

        return requests
            .filter {
                $0.identifier == Self.nextPoolTestIdentifier
                    || $0.identifier.hasPrefix("treatment-step-")
                    || $0.identifier.hasPrefix("treatment-retest-")
                    || $0.identifier.hasPrefix("treatment-")
            }
            .map { request in
                "- \(request.identifier): \(request.content.title) — \(request.content.body)"
            }
            .joined(separator: "\n")
    }

    private func adjustedFutureDate(_ date: Date) -> Date {
        let minimumDate = Date().addingTimeInterval(60)
        return max(date, minimumDate)
    }

    private func displayParameter(_ parameter: String) -> String {
        switch parameter {
        case "freeChlorine": return "FC/CC"
        case "combinedChlorine": return "CC"
        case "pH": return "pH"
        case "totalAlkalinity": return "TA"
        case "calciumHardness": return "CH"
        case "cyanuricAcid": return "CYA"
        default: return "pool water"
        }
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
