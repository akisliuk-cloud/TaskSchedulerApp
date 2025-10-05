import Foundation
import SwiftUI

// MARK: - Core Data Models (Added here to resolve build errors)

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

struct TaskItem: Identifiable, Codable, Equatable {
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
    
    // ** FIX FOR BUILD ERROR **
    // Manual conformance to Equatable and Hashable
    static func == (lhs: ArchivedTask, rhs: ArchivedTask) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - View / stats toggles
enum StatsViewType: String, CaseIterable {
    case summary, barchart
}
enum CalendarViewMode { case card, list }


// MARK: - App State
final class AppState: ObservableObject {

    // MARK: - Undo System
    private var undoState: ([TaskItem], [ArchivedTask])?
    @Published var snackbarMessage: String?
    private var snackbarWorkItem: DispatchWorkItem?

    // MARK: - Core data
    @Published var tasks: [TaskItem] = []
    @Published var archivedTasks: [ArchivedTask] = []

    // MARK: - UI state
    @Published var activeTab: Tab = .home {
        didSet {
            // Logic to control search bar visibility
            if activeTab == .search {
                isSearchVisible.toggle()
                // If we toggle search off, return to previous tab or home
                if !isSearchVisible {
                    activeTab = oldValue == .search ? .home : oldValue
                }
            } else {
                isSearchVisible = false
            }
        }
    }
    @Published var searchQuery: String = ""
    @Published var isSearchVisible = false
    @Published var isStatsViewActive = false
    @Published var isArchiveViewActive = false
    @Published var activeArchiveTab: ArchiveTab = .completed
    @Published var calendarViewMode: CalendarViewMode = .card
    @Published var calendarFilters: [TaskStatus: Bool] = [.notStarted: true, .started: true, .completed: true]
    @Published var isCalendarCollapsed = false
    @Published var isInboxCollapsed = false
    
    @Published var calendarStartDate: Date = Calendar.current.date(byAdding: .day, value: -45, to: Date()) ?? Date()

    // MARK: - Bulk-select
    @Published var isBulkSelectActiveInbox = false
    @Published var selectedInboxTaskIds: Set<Int> = []
    @Published var isBulkSelectActiveArchive = false
    @Published var selectedArchiveTaskIds: Set<Int> = []
    
    init() {
        self.tasks = SampleData.generateTasks()
    }
    
    // MARK: - UNDO Actions
    private func saveUndoState(message: String) {
        undoState = (tasks, archivedTasks)
        snackbarMessage = message
        
        snackbarWorkItem?.cancel()
        
        let workItem = DispatchWorkItem { [weak self] in
            self?.snackbarMessage = nil
            self?.undoState = nil
        }
        snackbarWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: workItem)
    }

    func performUndo() {
        if let (previousTasks, previousArchived) = undoState {
            self.tasks = previousTasks
            self.archivedTasks = previousArchived
        }
        snackbarMessage = nil
        undoState = nil
        snackbarWorkItem?.cancel()
    }
    
    // MARK: - Computed Properties

    var unassignedTasks: [TaskItem] {
        filteredTasks.filter { $0.date == nil }
    }
    
    var filteredTasks: [TaskItem] {
        guard !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return tasks }
        let q = searchQuery.lowercased()
        return tasks.filter { $t in
            $t.text.lowercased().contains(q) || ($t.notes ?? "").lowercased().contains(q)
        }
    }
    
    // MARK: - Calendar expansion

    func calendarDays() -> [CalendarDay] {
        if searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            var days: [CalendarDay] = []
            var cur = calendarStartDate
            for _ in 0..<90 {
                let ds = ISO8601.dateOnly.string(from: cur)
                let tz = TimeZone(secondsFromGMT: 0) ?? .current
                let c = Calendar.current.dateComponents(in: tz, from: cur)
                let dayName = cur.formatted(.dateTime.weekday(.abbreviated))
                days.append(.init(dateString: ds, dayName: dayName, dayOfMonth: c.day ?? 1))
                cur = Calendar.current.date(byAdding: .day, value: 1, to: cur) ?? cur
            }
            return days
        } else {
            var set = Set<String>()
            for t in filteredTasks {
                guard let base = t.date else { continue }
                if t.isRecurring, let rec = t.recurrence {
                    var d = (base.asISODateOnlyUTC ?? Date())
                    let end = Calendar.current.date(byAdding: .year, value: 1, to: d) ?? d
                    while d <= end {
                        set.insert(ISO8601.dateOnly.string(from: d))
                        d = Self.step(d, by: rec)
                    }
                } else {
                    set.insert(base)
                }
            }
            return set.sorted().map { ds in
                let d = ds.asISODateOnlyUTC ?? Date()
                return .init(
                    dateString: ds,
                    dayName: d.formatted(.dateTime.weekday(.abbreviated)),
                    dayOfMonth: Calendar.current.component(.day, from: d)
                )
            }
        }
    }

    func visibleCalendarTasks(for days: [CalendarDay]) -> [TaskItem] {
        let visibleSet = Set(days.map { $0.dateString })
        var out: [TaskItem] = []

        for t in filteredTasks {
            guard let baseDate = t.date else { continue }

            if t.isRecurring, let rec = t.recurrence {
                var d = (baseDate.asISODateOnlyUTC ?? Date())
                let endDateStr = days.last?.dateString ?? ISO8601.dateOnly.string(from: Date())
                let end = (endDateStr.asISODateOnlyUTC ?? Date())

                while d <= end {
                    let ds = ISO8601.dateOnly.string(from: d)
                    if visibleSet.contains(ds) {
                        let ov = t.completedOverrides?[ds] ?? TaskOverride()
                        var inst = t
                        inst.id = Int("\(t.id)\(ds.replacingOccurrences(of: "-", with: ""))") ?? t.id
                        inst.isInstance = true
                        inst.date = ds
                        inst.status = ov.status ?? .notStarted
                        inst.startedAt = ov.startedAt
                        inst.completedAt = ov.completedAt
                        inst.parentId = t.id
                        inst.rating = ov.rating
                        out.append(inst)
                    }
                    d = Self.step(d, by: rec)
                }
            } else {
                if visibleSet.contains(baseDate) { out.append(t) }
            }
        }
        return out
    }
    
    private static func step(_ d: Date, by rec: Recurrence) -> Date {
        switch rec {
        case .daily:   return Calendar.current.date(byAdding: .day, value: 1, to: d) ?? d
        case .weekly:  return Calendar.current.date(byAdding: .day, value: 7, to: d) ?? d
        case .monthly: return Calendar.current.date(byAdding: .month, value: 1, to: d) ?? d
        case .never:   return d
        }
    }

    // MARK: - Mutations
    
    func addTask(text: String, notes: String?, assignedTo: String?) {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let now = Date()
        let t = TaskItem(
            id: Int(now.timeIntervalSince1970 * 1000),
            text: text.trimmingCharacters(in: .whitespaces),
            notes: notes,
            date: nil,
            status: .notStarted,
            recurrence: nil,
            createdAt: now,
            createdBy: "Adrian Kisliuk",
            assignedTo: assignedTo,
            completedOverrides: nil
        )
        tasks.append(t)
    }

    func updateTask(_ task: TaskItem, text: String, notes: String?, date: String?, status: TaskStatus, recurrence: Recurrence, assignedTo: String?) {
        let parentId = task.isInstance ? task.parentId : task.id
        guard let idx = tasks.firstIndex(where: { $0.id == parentId }) else { return }
        
        saveUndoState(message: "Task updated")
        
        tasks[idx].text = text.trimmingCharacters(in: .whitespaces)
        tasks[idx].notes = notes?.trimmingCharacters(in: .whitespaces)
        tasks[idx].assignedTo = assignedTo
        
        let newDate = (date?.isEmpty ?? true) ? nil : date
        if tasks[idx].date != newDate {
            tasks[idx].date = newDate
        }
        
        if tasks[idx].status != status {
            updateStatus(tasks[idx], to: status, instanceDate: tasks[idx].date)
        }
        
        if (tasks[idx].recurrence ?? .never) != recurrence {
            updateRecurrence(tasks[idx], to: recurrence)
        }
    }

    func deleteToTrash(_ task: TaskItem) {
        let parentId = task.isInstance ? task.parentId : task.id
        guard let idx = tasks.firstIndex(where: { $0.id == parentId }) else { return }
        saveUndoState(message: "Task deleted")
        let t = tasks.remove(at: idx)
        let archived = ArchivedTask(from: t, reason: "deleted")
        archivedTasks.append(archived)
    }

    func duplicate(_ task: TaskItem) {
        saveUndoState(message: "Task duplicated")
        let now = Date()
        var copy = task
        copy.id = Int(now.timeIntervalSince1970 * 1000) + 1
        copy.text = "Copy of \(task.text)"
        copy.date = nil
        copy.status = .notStarted
        copy.createdAt = now
        copy.startedAt = nil
        copy.completedAt = nil
        copy.recurrence = nil
        copy.completedOverrides = nil
        copy.isInstance = false
        copy.parentId = nil
        if let i = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks.insert(copy, at: min(i+1, tasks.count))
        } else {
            tasks.append(copy)
        }
    }

    func moveToInbox(_ task: TaskItem) {
        let parentId = task.isInstance ? task.parentId : task.id
        guard let idx = tasks.firstIndex(where: { $0.id == parentId }) else { return }
        saveUndoState(message: "Task moved to Inbox")
        tasks[idx].date = nil
        tasks[idx].recurrence = nil
        tasks[idx].completedOverrides = nil
        tasks[idx].status = .notStarted
    }

    func reschedule(_ task: TaskItem, to newDate: String) {
        let parentId = task.isInstance ? task.parentId : task.id
        guard let idx = tasks.firstIndex(where: { $0.id == parentId }) else { return }
        saveUndoState(message: "Task rescheduled")
        tasks[idx].date = newDate
    }

    func updateRecurrence(_ task: TaskItem, to newRecurrence: Recurrence) {
        let parentId = task.isInstance ? task.parentId : task.id
        guard let idx = tasks.firstIndex(where: { $0.id == parentId }) else { return }
        if newRecurrence == .never {
            tasks[idx].recurrence = nil
            tasks[idx].completedOverrides = nil
        } else {
            tasks[idx].recurrence = newRecurrence
            if tasks[idx].completedOverrides == nil { tasks[idx].completedOverrides = [:] }
        }
    }
    
    func cycleRating(for task: TaskItem, instanceDate: String?) {
        let parentId = task.isInstance ? task.parentId : task.id
        guard let parentTask = tasks.first(where: { $0.id == parentId }) else { return }
        
        let currentRating: TaskRating?
        
        if parentTask.isRecurring, let ds = instanceDate {
            currentRating = parentTask.completedOverrides?[ds]?.rating
        } else {
            currentRating = parentTask.rating
        }

        let newRating: TaskRating?
        switch currentRating {
        case .none: newRating = .liked
        case .liked: newRating = .disliked
        case .disliked: newRating = nil
        }
        
        rate(task, rating: newRating, instanceDate: instanceDate)
    }

    func rate(_ task: TaskItem, rating: TaskRating?, instanceDate: String?) {
        let parentId = task.isInstance ? task.parentId : task.id
        guard let idx = tasks.firstIndex(where: { $0.id == parentId }) else { return }
        
        if tasks[idx].isRecurring, let ds = instanceDate {
            if tasks[idx].completedOverrides == nil { tasks[idx].completedOverrides = [:] }
            var ov = tasks[idx].completedOverrides?[ds] ?? TaskOverride()
            ov.rating = rating
            tasks[idx].completedOverrides?[ds] = ov
        } else {
             tasks[idx].rating = rating
        }
    }
    
    func updateStatus(_ task: TaskItem, to newStatus: TaskStatus, instanceDate: String?) {
        let now = Date()
        let parentId = task.isInstance ? task.parentId : task.id
        
        if task.isInstance, let ds = instanceDate {
            guard let idx = tasks.firstIndex(where: { $0.id == parentId }) else { return }
            if tasks[idx].completedOverrides == nil { tasks[idx].completedOverrides = [:] }
            var ov = tasks[idx].completedOverrides?[ds] ?? TaskOverride()
            ov.status = newStatus
            switch newStatus {
            case .started:
                ov.startedAt = ov.startedAt ?? now
                ov.completedAt = nil
            case .completed:
                ov.startedAt = ov.startedAt ?? now
                ov.completedAt = now
            case .notStarted:
                ov.startedAt = nil
                ov.completedAt = nil
            }
            tasks[idx].completedOverrides?[ds] = ov
            return
        }

        guard let idx = tasks.firstIndex(where: { $0.id == parentId }) else { return }
        if newStatus == .completed, tasks[idx].recurrence == nil, tasks[idx].date != nil {
            saveUndoState(message: "Task completed")
            let t = tasks.remove(at: idx)
            let archived = ArchivedTask(from: t, reason: "completed", status: .completed, startedAt: t.startedAt ?? now, completedAt: now)
            archivedTasks.append(archived)
        } else {
            tasks[idx].status = newStatus
            switch newStatus {
            case .started:
                tasks[idx].startedAt = tasks[idx].startedAt ?? now
                tasks[idx].completedAt = nil
            case .notStarted:
                tasks[idx].startedAt = nil
                tasks[idx].completedAt = nil
            case .completed:
                tasks[idx].completedAt = now
            }
        }
    }

    func archiveTask(_ task: TaskItem) {
        let parentId = task.isInstance ? task.parentId : task.id
        guard let idx = tasks.firstIndex(where: { $0.id == parentId }) else { return }
        saveUndoState(message: "Task archived")
        let t = tasks.remove(at: idx)
        let archived = ArchivedTask(from: t, reason: t.status.rawValue)
        archivedTasks.append(archived)
    }

    func restoreTask(_ archived: ArchivedTask) {
        saveUndoState(message: "Task restored")
        let restored = TaskItem(from: archived)
        tasks.append(restored)
        archivedTasks.removeAll { $0.id == archived.id }
    }

    func deletePermanently(_ archivedId: Int) {
        saveUndoState(message: "Deleted permanently")
        archivedTasks.removeAll { $0.id == archivedId }
    }
    
    // MARK: - Bulk Actions

    func archiveSelectedInbox() {
        guard !selectedInboxTaskIds.isEmpty else { return }
        saveUndoState(message: "\(selectedInboxTaskIds.count) tasks archived")
        let (toArchive, toKeep) = tasks.partitioned { selectedInboxTaskIds.contains($0.id) }
        tasks = toKeep
        archivedTasks.append(contentsOf: toArchive.map {
            ArchivedTask(from: $0, reason: $0.status.rawValue)
        })
        isBulkSelectActiveInbox = false
        selectedInboxTaskIds.removeAll()
    }

    func deleteSelectedInbox() {
        guard !selectedInboxTaskIds.isEmpty else { return }
        saveUndoState(message: "\(selectedInboxTaskIds.count) tasks deleted")
        let (toDelete, toKeep) = tasks.partitioned { selectedInboxTaskIds.contains($0.id) }
        tasks = toKeep
        archivedTasks.append(contentsOf: toDelete.map {
            ArchivedTask(from: $0, reason: "deleted")
        })
        isBulkSelectActiveInbox = false
        selectedInboxTaskIds.removeAll()
    }
    
    func moveTasksToInbox(ids: Set<Int>) {
        saveUndoState(message: "\(ids.count) tasks moved to inbox")
        for id in ids {
            if let task = tasks.first(where: { $0.id == id }), let idx = tasks.firstIndex(of: task) {
                 tasks[idx].date = nil
                 tasks[idx].recurrence = nil
                 tasks[idx].completedOverrides = nil
                 tasks[idx].status = .notStarted
            }
        }
    }
    
    func reorderInboxTasks(from source: IndexSet, to destination: Int) {
        var unassignedIndices: [Int] = []
        for i in 0..<tasks.count {
            if tasks[i].date == nil {
                unassignedIndices.append(i)
            }
        }
        
        let movedTaskIndices = source.map { unassignedIndices[$0] }
        
        let tasksToMove = movedTaskIndices.map { tasks[$0] }
        
        for index in movedTaskIndices.sorted(by: >) {
            tasks.remove(at: index)
        }
        
        let destinationIndex: Int
        if destination < unassignedIndices.count {
            destinationIndex = unassignedIndices[destination]
            let taskAtDestination = tasks[destinationIndex]
            if let finalIndex = tasks.firstIndex(of: taskAtDestination) {
                 tasks.insert(contentsOf: tasksToMove, at: finalIndex)
            }
        } else {
            tasks.append(contentsOf: tasksToMove)
        }
    }
}


// MARK: - Sample Data & Helpers (Also moved here)
enum SampleData {
    static func generateTasks() -> [TaskItem] {
        var items: [TaskItem] = []
        func d(_ s: String) -> Date { ISO8601.dateTime.date(from: s) ?? Date() }
        func od(_ s: String) -> Date? { ISO8601.dateTime.date(from: s) }
        
        let fixed: [TaskItem] = [
             TaskItem(id: 101, text: "Plan team lunch", notes: "Decide location.", date: "2025-10-03", status: .notStarted, recurrence: nil, createdAt: Date()),
             TaskItem(id: 102, text: "Prep presentation", notes: "Q3 metrics.", date: "2025-10-02", status: .started, recurrence: nil, createdAt: d("2025-09-30T10:00:00Z"), startedAt: od("2025-10-01T14:00:00Z")),
             TaskItem(id: 103, text: "Submit report", notes: "Submitted yesterday.", date: "2025-10-01", status: .completed, recurrence: nil, createdAt: d("2025-09-29T09:00:00Z"), startedAt: od("2025-10-01T09:00:00Z"), completedAt: od("2025-10-01T11:30:00Z"), completedOverrides: ["2025-10-01": .init(rating: .liked)]),
             TaskItem(id: 104, text: "Review mockups", notes: "Mobile responsiveness.", date: "2025-10-02", status: .notStarted, recurrence: nil, createdAt: Date()),
             TaskItem(id: 105, text: "Daily Standup", notes: "", date: "2025-09-01", status: .notStarted, recurrence: .daily, createdAt: d("2025-08-01T09:00:00Z"), completedOverrides: [:])
        ]
        items.append(contentsOf: fixed)
        
        let sampleTexts = ["Finalize Q4 budget", "Design auth flow", "Develop user API", "Write SDK docs", "Plan social media", "Fix memory leak"]
        let start = Calendar.current.date(byAdding: .day, value: -60, to: Date())!
        let end = Calendar.current.date(byAdding: .day, value: 30, to: Date())!
        func randDate(_ a: Date, _ b: Date) -> Date {
            let t = TimeInterval.random(in: a.timeIntervalSince1970...b.timeIntervalSince1970)
            return Date(timeIntervalSince1970: t)
        }

        for i in 1...60 {
            let assigned = Double.random(in: 0...1) > 0.25
            let dateStr: String? = assigned ? ISO8601.dateOnly.string(from: randDate(start, end)) : nil
            let status: TaskStatus = assigned ? [.completed, .started, .notStarted].randomElement()! : .notStarted
            let createdAt = randDate(start, Date())
            
            items.append(TaskItem(id: 1000 + i, text: sampleTexts.randomElement()!, notes: nil, date: dateStr, status: status, recurrence: nil, createdAt: createdAt))
        }
        return items
    }
}

extension String {
    var asISODateOnlyUTC: Date? {
        ISO8601.dateOnly.date(from: self)
    }
}

extension ISO8601DateFormatter {
    static let dateOnly: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()
    
    static let dateTime: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}

extension Array {
    func partitioned(by predicate: (Element) -> Bool) -> ([Element], [Element]) {
        var matching: [Element] = []
        var rest: [Element] = []
        for e in self {
            if predicate(e) { matching.append(e) } else { rest.append(e) }
        }
        return (matching, rest)
    }
}

