import Foundation

extension Date {

    var isToday: Bool {
        Calendar.current.isDateInToday(self)
    }

    var isYesterday: Bool {
        Calendar.current.isDateInYesterday(self)
    }

    /// "Today", "Yesterday", or "Jun 4"
    var relativeDisplay: String {
        if isToday { return "Today" }
        if isYesterday { return "Yesterday" }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: self)
    }

    /// "Jun 4, 2025"
    var shortDisplay: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: self)
    }

    /// "Jun 4, 2025 at 10:32 AM"
    var fullDisplay: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: self)
    }

    /// Days since this date (rounded down)
    var daysAgo: Int {
        Calendar.current.dateComponents([.day], from: self, to: Date()).day ?? 0
    }

    /// Date components for grouping test history by month
    var monthYearKey: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f.string(from: self)
    }
}
