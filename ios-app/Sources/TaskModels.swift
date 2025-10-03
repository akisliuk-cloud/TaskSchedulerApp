import Foundation

// MARK: - Core enums

enum TaskStatus: String, Codable, CaseIterable, Hashable {
    case notStarted = "not_started"
    case started = "started"
    case completed = "completed"
}

enum TaskRating: String, Codable, Hashable {
    case liked
    case disliked
}

enum TaskRecurrence: String, Codable, Hashable {
    case never      // use nil in TaskItem.recurrence to mean "never"
    case daily
    case weekly
    case monthly
}

enum ArchiveReason: String, Codable, Hashable {
    case deleted
    case not_started
    case started
    case completed
}

// MARK: - Recurring instance override

struct TaskInstanceOverride: Codable, Hashable {
    var status: TaskStatus?
    var startedAt: Date?
    var completedAt: Date?
    var rating: TaskRating?
}

// MARK: - Task model used throughout the app

struct TaskItem: Identifiable, Codable, Hashable {
    var id: UUID
    var text: String
    var notes: String
    /// ISO date string "yyyy-MM-dd" for scheduled day; nil = Inbox
    var date: String?
    var status: TaskStatus
    /// nil means "never". If set, treat as series and use completedOverrides.
    var recurrence: TaskRecurrence?
    var createdAt: Date
    var startedAt: Date?
    var completedAt: Date?
    var rating: TaskRating?

    /// For recurring tasks: keyed by ISO day "yyyy-MM-dd"
    var completedOverrides: [String: TaskInstanceOverride]?

    // Archive
    var archivedAt: Date?
    var archiveReason: ArchiveReason?

    init(
        id: UUID = UUID(),
        text: String,
        notes: String = "",
        date: String? = nil,
        status: TaskStatus = .notStarted,
        recurrence: TaskRecurrence? = nil,
        createdAt: Date = Date(),
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        rating: TaskRating? = nil,
        completedOverrides: [String: TaskInstanceOverride]? = nil,
        archivedAt: Date? = nil,
        archiveReason: ArchiveReason? = nil
    ) {
        self.id = id
        self.text = text
        self.notes = notes
        self.date = date
        self.status = status
        self.recurrence = recurrence == .never ? nil : recurrence
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.rating = rating
        self.completedOverrides = completedOverrides
        self.archivedAt = archivedAt
        self.archiveReason = archiveReason
    }
}

// MARK: - Helpers

extension Date {
    /// Returns "yyyy-MM-dd" in UTC
    var isoDayString: String {
        let fmt = DateFormatter()
        fmt.calendar = Calendar(identifier: .iso8601)
        fmt.timeZone = TimeZone(secondsFromGMT: 0)
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: self)
    }
}

extension String {
    /// Parses "yyyy-MM-dd" in UTC into Date (midday to avoid DST issues)
    var asIsoDayDate: Date? {
        let fmt = DateFormatter()
        fmt.calendar = Calendar(identifier: .iso8601)
        fmt.timeZone = TimeZone(secondsFromGMT: 0)
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.date(from: self)
    }
}
