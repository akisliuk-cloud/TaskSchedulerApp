import Foundation

enum TaskStatus: String, Codable, CaseIterable {
    case not_started
    case started
    case completed
}

enum TaskRecurrence: String, Codable {
    case never
    case daily
    case weekly
    case monthly
}

enum Rating: String, Codable {
    case liked
    case disliked
}

enum CalendarViewMode: String, Codable {
    case card
    case list
}

struct CalendarFilters: Codable {
    var not_started: Bool = true
    var started: Bool = true
    var completed: Bool = true
}

struct TaskItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var text: String
    var notes: String?
    /// Use ISO yyyy-MM-dd for day-only scheduling, else nil means “inbox”
    var date: String?
    var status: TaskStatus
    var recurrence: TaskRecurrence?   // nil or .never means not recurring
    var createdAt: Date = Date()
    var startedAt: Date?
    var completedAt: Date?
    var rating: Rating?
    
    // For simplicity we omit completedOverrides for recurring instances in this minimal build
}
