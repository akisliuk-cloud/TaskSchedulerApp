import Foundation

// MARK: - Core Data Models

enum TaskStatus: String, Codable, CaseIterable, Identifiable {
    case notStarted = "not_started"
    case started
    case completed
    
    var id: String { self.rawValue }
    
    var displayName: String {
        switch self {
        case .notStarted: "To Do"
        case .started: "Started"
        case .completed: "Completed"
        }
    }
}

enum TaskRating: String, Codable {
    case liked, disliked
}

enum Recurrence: String, Codable, CaseIterable, Identifiable {
    case never, daily, weekly, monthly
    var id: String { self.rawValue }
}

enum ArchiveTab: String, CaseIterable, Identifiable {
    case not_started, started, completed, deleted
    var id: String { rawValue }
}

struct TaskOverride: Codable, Hashable {
    var status: TaskStatus?
    var startedAt: Date?
    var completedAt: Date?
    var rating: TaskRating?
}

struct TaskItem: Identifiable, Codable, Equatable, Hashable {
    var id: Int
    var text: String
    var notes: String?
    var date: String? // YYYY-MM-DD
    var status: TaskStatus
    var recurrence: Recurrence?
    var createdAt: Date
    var createdBy: String = "Adrian Kisliuk" // Default value
    var assignedTo: String?
    var startedAt: Date?
    var completedAt: Date?
    var completedOverrides: [String: TaskOverride]?
    var parentId: Int? // Used for instances
    var isInstance: Bool = false
    var rating: TaskRating?

    var isRecurring: Bool { recurrence != nil && recurrence != .never }

    // Initializer from ArchivedTask
    init(from archived: ArchivedTask) {
        self.id = archived.id
        self.text = archived.text
        self.notes = archived.notes
        self.date = archived.date
        self.status = archived.status
        self.recurrence = nil // Restored tasks lose recurrence
        self.createdAt = archived.createdAt
        self.createdBy = "Adrian Kisliuk"
        self.assignedTo = nil // and assignment
        self.startedAt = archived.startedAt
        self.completedAt = archived.completedAt
        self.completedOverrides = nil
        self.rating = archived.rating
    }
    
    // Default initializer
    init(id: Int, text: String, notes: String?, date: String?, status: TaskStatus, recurrence: Recurrence?, createdAt: Date, createdBy: String = "Adrian Kisliuk", assignedTo: String? = nil, startedAt: Date? = nil, completedAt: Date? = nil, completedOverrides: [String : TaskOverride]?, parentId: Int? = nil, isInstance: Bool = false, rating: TaskRating? = nil) {
        self.id = id
        self.text = text
        self.notes = notes
        self.date = date
        self.status = status
        self.recurrence = recurrence
        self.createdAt = createdAt
        self.createdBy = createdBy
        self.assignedTo = assignedTo
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.completedOverrides = completedOverrides
        self.parentId = parentId
        self.isInstance = isInstance
        self.rating = rating
    }
    
    // Conformance for Equatable and Hashable
    static func == (lhs: TaskItem, rhs: TaskItem) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
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
    var archiveReason: String // "deleted", "not_started", "started", "completed"
    var rating: TaskRating?
    
    // Custom initializer to create an ArchivedTask from a TaskItem
    init(from task: TaskItem, reason: String, status: TaskStatus? = nil, startedAt: Date? = nil, completedAt: Date? = nil) {
        self.id = task.id
        self.text = task.text
        self.notes = task.notes
        self.date = task.date
        self.status = status ?? task.status
        self.createdAt = task.createdAt
        self.startedAt = startedAt ?? task.startedAt
        self.completedAt = completedAt ?? task.completedAt
        self.archivedAt = Date()
        self.archiveReason = reason
        self.rating = task.rating
    }
    
    // Manual conformance to Equatable and Hashable
    static func == (lhs: ArchivedTask, rhs: ArchivedTask) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - View-specific Models
struct CalendarDay: Identifiable, Hashable {
    var id = UUID()
    var dateString: String
    var dayName: String
    var dayOfMonth: Int
}

enum CalendarViewMode { case card, list }

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

