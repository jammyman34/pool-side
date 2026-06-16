import SwiftUI

// MARK: - Toast Message Model

struct ToastMessage: Equatable {
    let id = UUID()
    let text: String
    let icon: String
    let color: Color

    static func == (lhs: ToastMessage, rhs: ToastMessage) -> Bool {
        lhs.id == rhs.id
    }

    static func notificationSet(label: String) -> ToastMessage {
        ToastMessage(
            text: "Reminder set — we'll notify you in \(label)",
            icon: "bell.fill",
            color: PoolColor.poolTeal
        )
    }

    static func treatmentComplete() -> ToastMessage {
        ToastMessage(
            text: "Step marked complete",
            icon: "checkmark.circle.fill",
            color: PoolColor.statusIdeal
        )
    }

    static func treatmentIncomplete(reminderCanceled: Bool) -> ToastMessage {
        ToastMessage(
            text: reminderCanceled ? "Reminder canceled" : "Step reopened",
            icon: reminderCanceled ? "bell.slash.fill" : "arrow.uturn.left.circle.fill",
            color: PoolColor.poolTeal
        )
    }

    static func saved() -> ToastMessage {
        ToastMessage(
            text: "Test results saved",
            icon: "checkmark.circle.fill",
            color: PoolColor.statusIdeal
        )
    }
}

// MARK: - Toast View

struct ToastView: View {
    let message: ToastMessage

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: message.icon)
                .font(.subheadline)
                .foregroundStyle(message.color)
            Text(message.text)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(PoolColor.primaryText)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.15), radius: 16, y: 4)
        )
        .padding(.horizontal, 24)
    }
}

// MARK: - Toast Modifier

struct ToastModifier: ViewModifier {
    @Binding var toast: ToastMessage?

    func body(content: Content) -> some View {
        ZStack(alignment: .bottom) {
            content
            if let message = toast {
                ToastView(message: message)
                    .padding(.bottom, 100)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: message.id) {
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        guard toast?.id == message.id else { return }
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            toast = nil
                        }
                    }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: toast)
    }
}

extension View {
    func toast(_ message: Binding<ToastMessage?>) -> some View {
        modifier(ToastModifier(toast: message))
    }
}

// MARK: - Previews

#Preview("Notification Set") {
    ToastView(message: .notificationSet(label: "20 min"))
        .padding()
        .background(PoolColor.appBackground)
}

#Preview("Treatment Complete") {
    ToastView(message: .treatmentComplete())
        .padding()
        .background(PoolColor.appBackground)
}

#Preview("Saved") {
    ToastView(message: .saved())
        .padding()
        .background(PoolColor.appBackground)
}
