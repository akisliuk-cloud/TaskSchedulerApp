// ios-app/Sources/TaskModels.swift
import Foundation

enum TaskStatus: String, Codable, CaseIterable, Identifiable {
    case notStarted = "not_started"
    case started = "started"
    case completed = "completed"
    var id: String { rawValue }
}

enum Recurrence: String, Codable, CaseIterable, Identifiable {
    case never, daily, weekly, monthly
    var id: String { rawValue }
    var isRepeating: Bool { self != .never }
}

enum TaskRating: String, Codable, CaseIterable, Identifiable {
    case liked, disliked
    var id: String { rawValue }
}

struct TaskOverride: Codable, Hashable {
    var status: TaskStatus? = nil
    var startedAt: Date? = nil
    var completedAt: Date? = nil
    var rating: TaskRating? = nil
}

struct TaskItem: Identifiable, Codable, Hashable {
    var id: Int
    var text: String
    var notes: String?
    /// yyyy-MM-dd in UTC (nil = inbox)
    var date: String?
    var status: TaskStatus
    var recurrence: Recurrence? // nil = never
    var createdAt: Date
    var startedAt: Date?
    var completedAt: Date?
    /// Overrides for recurring instances keyed by yyyy-MM-dd
    var completedOverrides: [String: TaskOverride]?

    // For UI convenience
    var isRecurring: Bool { recurrence != nil && recurrence != .never }
}

struct ArchivedTask: Identifiable, Codable, Hashable {
    var id: Int
    var text: String
    var notes: String?
    var date: String?
    var status: TaskStatus
    var createdAt: Date
    var startedAt: Date?
    var completedAt: Date?
    var archivedAt: Date
    /// "completed" | "deleted" | "not_started" | "started"
    var archiveReason: String
    var rating: TaskRating?
}

enum ArchiveTab: String, CaseIterable, Identifiable {
    case not_started, started, completed, deleted
    var id: String { rawValue }
}

enum CalendarViewMode: String, CaseIterable, Identifiable {
    case card, list
    var id: String { rawValue }
}

// MARK: - Date helpers

enum ISO8601 {
    static let dateOnly: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static let dateTime: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()
}

extension String {
    /// Parse yyyy-MM-dd -> Date in UTC
    var asISODateOnlyUTC: Date? { ISO8601.dateOnly.date(from: self) }
}
