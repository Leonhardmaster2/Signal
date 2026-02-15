import EventKit

final class EventKitService {
    static let shared = EventKitService()
    private let store = EKEventStore()

    // MARK: - Reminders

    func createReminder(title: String, dueDate: Date?, notes: String?) async throws {
        let granted = try await store.requestFullAccessToReminders()
        guard granted else { throw EventKitServiceError.accessDenied("Reminders") }

        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.calendar = store.defaultCalendarForNewReminders()
        if let due = dueDate {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: due
            )
        }
        reminder.notes = notes
        try store.save(reminder, commit: true)
    }

    // MARK: - Calendar Events

    func createCalendarEvent(title: String, startDate: Date, duration: TimeInterval, notes: String?) async throws {
        let granted = try await store.requestFullAccessToEvents()
        guard granted else { throw EventKitServiceError.accessDenied("Calendar") }

        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = startDate
        event.endDate = startDate.addingTimeInterval(duration)
        event.calendar = store.defaultCalendarForNewEvents
        event.notes = notes
        try store.save(event, span: .thisEvent)
    }
}

enum EventKitServiceError: LocalizedError {
    case accessDenied(String)

    var errorDescription: String? {
        switch self {
        case .accessDenied(let service):
            return "\(service) access denied. Please enable in Settings."
        }
    }
}
