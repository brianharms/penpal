import Foundation
import EventKit

/// Creates reminders and todo lists via Apple Reminders (EventKit)
class ReminderService {
    static let shared = ReminderService()

    private let store = EKEventStore()

    /// Request access to reminders
    func requestAccess() async -> Bool {
        do {
            return try await store.requestFullAccessToReminders()
        } catch {
            print("Reminders access error: \(error)")
            return false
        }
    }

    /// Create a single reminder with optional due date
    func createReminder(title: String, dateString: String? = nil, timeString: String? = nil) async throws -> String {
        let hasAccess = await requestAccess()
        guard hasAccess else {
            throw ReminderError.accessDenied
        }

        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.calendar = store.defaultCalendarForNewReminders()

        // Parse date if provided
        if let dateString = dateString {
            let dueDate = parseDate(dateString, time: timeString)
            if let dueDate = dueDate {
                let cal = Calendar.current
                var components = cal.dateComponents([.year, .month, .day], from: dueDate)
                if let timeString = timeString, let time = parseTime(timeString) {
                    let timeComponents = cal.dateComponents([.hour, .minute], from: time)
                    components.hour = timeComponents.hour
                    components.minute = timeComponents.minute
                }
                reminder.dueDateComponents = components

                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                if timeString != nil {
                    formatter.timeStyle = .short
                }
                let dateLabel = formatter.string(from: dueDate)
                try store.save(reminder, commit: true)
                return "reminder set: \(title) — \(dateLabel)"
            }
        }

        try store.save(reminder, commit: true)
        return "reminder set: \(title)"
    }

    /// Create a todo list (Reminders list) with multiple items
    func createTodoList(name: String?, items: [String]) async throws -> String {
        let hasAccess = await requestAccess()
        guard hasAccess else {
            throw ReminderError.accessDenied
        }

        // Use existing default list or create named one
        let calendar: EKCalendar
        if let name = name, !name.isEmpty {
            // Try to find existing list with this name
            let existing = store.calendars(for: .reminder).first { $0.title.lowercased() == name.lowercased() }
            if let existing = existing {
                calendar = existing
            } else {
                // Create new list
                let newCal = EKCalendar(for: .reminder, eventStore: store)
                newCal.title = name
                newCal.source = store.defaultCalendarForNewReminders()?.source
                try store.saveCalendar(newCal, commit: true)
                calendar = newCal
            }
        } else {
            calendar = store.defaultCalendarForNewReminders() ?? store.calendars(for: .reminder).first!
        }

        // Add all items
        for item in items {
            let reminder = EKReminder(eventStore: store)
            reminder.title = item.trimmingCharacters(in: .whitespaces)
            reminder.calendar = calendar
            try store.save(reminder, commit: false)
        }
        try store.commit()

        let listLabel = name ?? "reminders"
        return "added \(items.count) items to \(listLabel)"
    }

    // MARK: - Date Parsing

    private func parseDate(_ string: String, time: String? = nil) -> Date? {
        let lower = string.lowercased().trimmingCharacters(in: .whitespaces)
        let cal = Calendar.current
        let now = Date()

        // Relative dates
        switch lower {
        case "today":
            return now
        case "tomorrow":
            return cal.date(byAdding: .day, value: 1, to: now)
        case "next week":
            return cal.date(byAdding: .weekOfYear, value: 1, to: now)
        default:
            break
        }

        // Day names: "monday", "tuesday", etc.
        let dayNames = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
        if let targetDay = dayNames.firstIndex(where: { lower.contains($0) }) {
            let currentDay = cal.component(.weekday, from: now) - 1 // 0-indexed
            var daysAhead = targetDay - currentDay
            if daysAhead <= 0 { daysAhead += 7 }
            return cal.date(byAdding: .day, value: daysAhead, to: now)
        }

        // ISO 8601
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withFullDate]
        if let date = isoFormatter.date(from: string) {
            return date
        }

        // Common formats
        let formats = ["yyyy-MM-dd", "MM/dd/yyyy", "MMM d", "MMMM d", "MMM d, yyyy"]
        for format in formats {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            if let date = formatter.date(from: string) {
                // If no year in format, assume this year or next
                if !format.contains("yyyy") {
                    var components = cal.dateComponents([.month, .day], from: date)
                    components.year = cal.component(.year, from: now)
                    if let adjusted = cal.date(from: components), adjusted < now {
                        components.year = cal.component(.year, from: now) + 1
                    }
                    return cal.date(from: components) ?? date
                }
                return date
            }
        }

        return nil
    }

    private func parseTime(_ string: String) -> Date? {
        let formats = ["h:mm a", "HH:mm", "h a", "ha", "h:mma"]
        for format in formats {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            if let date = formatter.date(from: string) {
                return date
            }
        }
        return nil
    }
}

enum ReminderError: Error {
    case accessDenied
    case saveFailed
}
