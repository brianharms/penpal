import Foundation
import EventKit

/// Creates calendar events via EventKit (works with synced Google Calendar)
class CalendarService {
    static let shared = CalendarService()

    private let store = EKEventStore()

    /// Request access to calendar
    func requestAccess() async -> Bool {
        do {
            return try await store.requestFullAccessToEvents()
        } catch {
            print("Calendar access error: \(error)")
            return false
        }
    }

    /// Create a calendar event
    func createEvent(
        title: String,
        startString: String,
        endString: String? = nil,
        location: String? = nil
    ) async throws -> String {
        let hasAccess = await requestAccess()
        guard hasAccess else {
            throw CalendarError.accessDenied
        }

        guard let startDate = parseDateTime(startString) else {
            throw CalendarError.invalidDate
        }

        let endDate: Date
        if let endString = endString, let parsed = parseDateTime(endString) {
            endDate = parsed
        } else {
            // Default to 1 hour event
            endDate = startDate.addingTimeInterval(3600)
        }

        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = startDate
        event.endDate = endDate
        event.calendar = store.defaultCalendarForNewEvents
        if let location = location {
            event.location = location
        }

        try store.save(event, span: .thisEvent)

        // Format confirmation
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let startLabel = formatter.string(from: startDate)

        if let location = location {
            return "added to calendar: \(title) — \(startLabel) at \(location)"
        }
        return "added to calendar: \(title) — \(startLabel)"
    }

    // MARK: - Date/Time Parsing

    private func parseDateTime(_ string: String) -> Date? {
        let lower = string.lowercased().trimmingCharacters(in: .whitespaces)
        let cal = Calendar.current
        let now = Date()

        // ISO 8601 with time
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        if let date = isoFormatter.date(from: string) {
            return date
        }

        // ISO 8601 date only
        isoFormatter.formatOptions = [.withFullDate]
        if let date = isoFormatter.date(from: string) {
            return date
        }

        // Relative day + time: "tomorrow 2pm", "friday 3:30pm"
        let parts = lower.components(separatedBy: " ")
        if parts.count >= 2 {
            let dayPart = parts[0]
            let timePart = parts.dropFirst().joined(separator: " ")

            if let baseDate = parseRelativeDay(dayPart),
               let time = parseTime(timePart) {
                return combineDateTime(date: baseDate, time: time)
            }
        }

        // Just a date
        if let date = parseRelativeDay(lower) {
            // Default to 9am for date-only
            var components = cal.dateComponents([.year, .month, .day], from: date)
            components.hour = 9
            return cal.date(from: components)
        }

        // Common datetime formats
        let formats = [
            "yyyy-MM-dd HH:mm",
            "yyyy-MM-dd h:mm a",
            "MMM d h:mm a",
            "MMM d, yyyy h:mm a",
            "MMMM d h:mm a",
            "MM/dd/yyyy h:mm a"
        ]
        for format in formats {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            if let date = formatter.date(from: string) {
                return date
            }
        }

        return nil
    }

    private func parseRelativeDay(_ string: String) -> Date? {
        let cal = Calendar.current
        let now = Date()

        switch string {
        case "today":
            return now
        case "tomorrow":
            return cal.date(byAdding: .day, value: 1, to: now)
        case "next week":
            return cal.date(byAdding: .weekOfYear, value: 1, to: now)
        default:
            break
        }

        // Day names
        let dayNames = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
        if let targetDay = dayNames.firstIndex(where: { string.contains($0) }) {
            let currentDay = cal.component(.weekday, from: now) - 1
            var daysAhead = targetDay - currentDay
            if daysAhead <= 0 { daysAhead += 7 }
            return cal.date(byAdding: .day, value: daysAhead, to: now)
        }

        return nil
    }

    private func parseTime(_ string: String) -> Date? {
        let formats = ["h:mm a", "h:mma", "HH:mm", "h a", "ha", "hh:mma", "hh:mm a"]
        for format in formats {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.locale = Locale(identifier: "en_US_POSIX")
            if let date = formatter.date(from: string) {
                return date
            }
        }
        return nil
    }

    private func combineDateTime(date: Date, time: Date) -> Date {
        let cal = Calendar.current
        let dateComponents = cal.dateComponents([.year, .month, .day], from: date)
        let timeComponents = cal.dateComponents([.hour, .minute], from: time)

        var combined = DateComponents()
        combined.year = dateComponents.year
        combined.month = dateComponents.month
        combined.day = dateComponents.day
        combined.hour = timeComponents.hour
        combined.minute = timeComponents.minute

        return cal.date(from: combined) ?? date
    }
}

enum CalendarError: Error {
    case accessDenied
    case invalidDate
    case saveFailed
}
