// ios-app/Sources/AppState.swift
import Foundation
import SwiftUI

final class AppState: ObservableObject {

    // Core data
    @Published var tasks: [TaskItem] = []
    @Published var archivedTasks: [ArchivedTask] = []

    // UI state (mirrors React)
    @Published var searchQuery: String = ""
    @Published var isStatsViewActive = false
    @Published var isArchiveViewActive = false
    @Published var activeArchiveTab: ArchiveTab = .completed
    @Published var calendarViewMode: CalendarViewMode = .card
    @Published var calendarFilters: [TaskStatus: Bool] = [.notStarted: true, .started: true, .completed: true]

    // Calendar window (start ~45 days in past)
    @Published var calendarStartDate: Date = Calendar.current.date(byAdding: .day, value: -45, to: Date()) ?? Date()

    // Bulk-select (Inbox & Archive)
    @Published var isBulkSelectActiveInbox = false
    @Published var selectedInboxTaskIds: Set<Int> = []

    @Published var isBulkSelectActiveArchive = false
    @Published var selectedArchiveTaskIds: Set<Int> = []

    // Stats view toggle
    @Published var statsViewType: StatsViewType = .summary // .summary or .barchart


    init() {
        self.tasks = SampleData.generateTasks()
    }

    // MARK: - Filtering & search

    var filteredTasks: [TaskItem] {
        guard !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return tasks
        }
        let q = searchQuery.lowercased()
        return tasks.filter { t in
            t.text.lowercased().contains(q) || (t.notes?.lowercased().contains(q) ?? false)
        }
    }

    var unassignedTasks: [TaskItem] {
        filteredTasks.filter { $0.date == nil }
    }

    // MARK: - Calendar expansion (recurrence instances)

    func calendarDays() -> [CalendarDay] {
        // For search, compress to only matching days like React
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
            // compressed set from visible tasks
            var set = Set<String>()
            for t in filteredTasks {
                guard let base = t.date else { continue }
                if t.isRecurring, let rec = t.recurrence {
                    var d = (base.asISODateOnlyUTC ?? Date())
                    let end = Calendar.current.date(byAdding: .year, value: 1, to: d)!
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
                return .init(dateString: ds,
                             dayName: d.formatted(.dateTime.weekday(.abbreviated)),
                             dayOfMonth: Calendar.current.component(.day, from: d))
            }
        }
    }

    func visibleCalendarTasks(for days: [CalendarDay]) -> [TaskItem] {
        let visibleSet = Set(days.map { $0.dateString })
        var out: [TaskItem] = []

        for t in filteredTasks {
            guard let baseDate = t.date else { continue } // skip inbox

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
                        inst.date = ds
                        inst.status = ov.status ?? .notStarted
                        inst.startedAt = ov.startedAt
                        inst.completedAt = ov.completedAt
                        // rating stored in override; preserved via actions
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

    // MARK: - Mutations (align with React handlers)

    func addTask(text: String) {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let now = Date()
        let t = TaskItem(
            id: Int(now.timeIntervalSince1970 * 1000),
            text: text.trimmingCharacters(in: .whitespaces),
            notes: "",
            date: nil,
            status: .notStarted,
            recurrence: nil,
            createdAt: now,
            startedAt: nil,
            completedAt: nil,
            completedOverrides: nil
        )
        tasks.append(t)
    }

    func deleteToTrash(_ task: TaskItem) {
        guard let idx = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        let t = tasks.remove(at: idx)
        let archived = ArchivedTask(
            id: t.id, text: t.text, notes: t.notes, date: t.date,
            status: t.status, createdAt: t.createdAt, startedAt: t.startedAt, completedAt: t.completedAt,
            archivedAt: Date(), archiveReason: "deleted", rating: nil
        )
        archivedTasks.append(archived)
    }

    func duplicate(_ task: TaskItem) {
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
        // insert after original if exists
        if let i = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks.insert(copy, at: min(i+1, tasks.count))
        } else {
            tasks.append(copy)
        }
    }

    func moveToInbox(_ task: TaskItem) {
        guard let idx = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[idx].date = nil
        tasks[idx].recurrence = nil
        tasks[idx].completedOverrides = nil
        tasks[idx].status = .notStarted
    }

    func reschedule(_ task: TaskItem, to newDate: String) {
        guard let idx = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[idx].date = newDate
    }

    func updateRecurrence(_ task: TaskItem, to newRecurrence: Recurrence) {
        guard let idx = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        if newRecurrence == .never {
            tasks[idx].recurrence = nil
            tasks[idx].completedOverrides = nil
        } else {
            tasks[idx].recurrence = newRecurrence
            if tasks[idx].completedOverrides == nil { tasks[idx].completedOverrides = [:] }
        }
    }

    /// Handles both normal and recurring instance status updates
    func updateStatus(_ task: TaskItem, to newStatus: TaskStatus, instanceDate: String? = nil) {
        let now = Date()

        // Instance of recurring: write into overrides
        if task.isRecurring, let ds = instanceDate {
            guard let idx = tasks.firstIndex(where: { $0.id == task.id || $0.text == task.text && $0.createdAt == task.createdAt }) else { return }
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

        // Non-recurring: update directly; auto-archive if completed
        guard let idx = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        if newStatus == .completed, tasks[idx].recurrence == nil, tasks[idx].date != nil {
            let t = tasks.remove(at: idx)
            let archived = ArchivedTask(
                id: t.id, text: t.text, notes: t.notes, date: t.date,
                status: .completed, createdAt: t.createdAt,
                startedAt: t.startedAt ?? now, completedAt: now,
                archivedAt: now, archiveReason: "completed", rating: nil
            )
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

    func rate(_ task: TaskItem, rating: TaskRating?, instanceDate: String? = nil) {
        if task.isRecurring, let ds = instanceDate {
            guard let idx = tasks.firstIndex(where: { $0.id == task.id || $0.text == task.text && $0.createdAt == task.createdAt }) else { return }
            if tasks[idx].completedOverrides == nil { tasks[idx].completedOverrides = [:] }
            var ov = tasks[idx].completedOverrides?[ds] ?? TaskOverride()
            ov.rating = (ov.rating == rating ? nil : rating)
            tasks[idx].completedOverrides?[ds] = ov
        } else if let i = tasks.firstIndex(where: { $0.id == task.id }) {
            // store simple rating on notes via tag? keep separate: use completedOverrides under own date if exists
            // For non-recurring, attach rating by using today’s override bucket
            let ds = task.date ?? ISO8601.dateOnly.string(from: Date())
            if tasks[i].completedOverrides == nil { tasks[i].completedOverrides = [:] }
            var ov = tasks[i].completedOverrides?[ds] ?? TaskOverride()
            ov.rating = (ov.rating == rating ? nil : rating)
            tasks[i].completedOverrides?[ds] = ov
        }
    }

    func archiveTask(_ task: TaskItem) {
        guard let idx = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        let t = tasks.remove(at: idx)
        let archived = ArchivedTask(
            id: t.id, text: t.text, notes: t.notes, date: t.date,
            status: t.status, createdAt: t.createdAt, startedAt: t.startedAt, completedAt: t.completedAt,
            archivedAt: Date(), archiveReason: t.status.rawValue, rating: nil
        )
        archivedTasks.append(archived)
    }

    func restoreTask(_ archived: ArchivedTask) {
        // Drop archive-specific fields
        let restored = TaskItem(
            id: archived.id, text: archived.text, notes: archived.notes, date: archived.date,
            status: archived.status, recurrence: nil, createdAt: archived.createdAt,
            startedAt: archived.startedAt, completedAt: archived.completedAt, completedOverrides: nil
        )
        tasks.append(restored)
        archivedTasks.removeAll { $0.id == archived.id }
    }

    func deletePermanently(_ archivedId: Int) {
        archivedTasks.removeAll { $0.id == archivedId }
    }

    func emptyArchive(reason: ArchiveTab) {
        archivedTasks.removeAll { $0.archiveReason == reason.rawValue }
    }


    func toggleBulkSelectInbox() {
        isBulkSelectActiveInbox.toggle()
        selectedInboxTaskIds.removeAll()
    }
    
    func toggleBulkSelectArchive() {
        isBulkSelectActiveArchive.toggle()
        selectedArchiveTaskIds.removeAll()
    }
    
    func setAllInboxSelection(_ ids: [Int]) {
        if selectedInboxTaskIds.count == ids.count {
            selectedInboxTaskIds.removeAll()
        } else {
            selectedInboxTaskIds = Set(ids)
        }
    }
    
    func archiveSelectedInbox() {
        guard !selectedInboxTaskIds.isEmpty else { return }
        let now = Date()
        let (toArchive, toKeep) = tasks.partitioned { selectedInboxTaskIds.contains($0.id) }
        tasks = toKeep
        archivedTasks.append(contentsOf: toArchive.map {
            ArchivedTask(id: $0.id, text: $0.text, notes: $0.notes, date: $0.date,
                         status: $0.status, createdAt: $0.createdAt, startedAt: $0.startedAt,
                         completedAt: $0.completedAt, archivedAt: now, archiveReason: $0.status.rawValue, rating: nil)
        })
        toggleBulkSelectInbox()
    }
    
    func deleteSelectedInbox() {
        guard !selectedInboxTaskIds.isEmpty else { return }
        let now = Date()
        let (toDelete, toKeep) = tasks.partitioned { selectedInboxTaskIds.contains($0.id) }
        tasks = toKeep
        archivedTasks.append(contentsOf: toDelete.map {
            ArchivedTask(id: $0.id, text: $0.text, notes: $0.notes, date: $0.date,
                         status: $0.status, createdAt: $0.createdAt, startedAt: $0.startedAt,
                         completedAt: $0.completedAt, archivedAt: now, archiveReason: "deleted", rating: nil)
        })
        toggleBulkSelectInbox()
    }
    
    func restoreSelectedArchive() {
        guard !selectedArchiveTaskIds.isEmpty else { return }
        let (selected, keep) = archivedTasks.partitioned { selectedArchiveTaskIds.contains($0.id) }
        archivedTasks = keep
        tasks.append(contentsOf: selected.map {
            TaskItem(id: $0.id, text: $0.text, notes: $0.notes, date: $0.date,
                     status: $0.status, recurrence: nil, createdAt: $0.createdAt,
                     startedAt: $0.startedAt, completedAt: $0.completedAt, completedOverrides: nil)
        })
        toggleBulkSelectArchive()
    }
    
    func deleteSelectedArchivePermanently() {
        guard !selectedArchiveTaskIds.isEmpty else { return }
        archivedTasks.removeAll { selectedArchiveTaskIds.contains($0.id) }
        toggleBulkSelectArchive()
    }
}

// MARK: - Calendar Day model
struct CalendarDay: Identifiable, Hashable {
    var id = UUID()
    var dateString: String
    var dayName: String
    var dayOfMonth: Int
}

// MARK: - Sample data (ports your React generator roughly)

enum SampleData {
    static func generateTasks() -> [TaskItem] {
        var items: [TaskItem] = []

enum StatsViewType: String, CaseIterable {
    case summary, barchart
}

// A few fixed like your top of array
// --- Safe date helpers (avoid crashes if parsing fails) ---
func d(_ s: String) -> Date { ISO8601.dateTime.date(from: s) ?? Date() } // use a fallback if parsing fails
func od(_ s: String) -> Date? { ISO8601.dateTime.date(from: s) }         // optional date

let fixed: [TaskItem] = [
    TaskItem(
        id: Int(Date().timeIntervalSince1970) + 101,
        text: "Plan team lunch for next week",
        notes: "Need to decide on a location and send out a poll.",
        date: "2025-10-03",
        status: .notStarted,
        recurrence: nil,
        createdAt: Date(),
        startedAt: nil,
        completedAt: nil,
        completedOverrides: nil
    ),
    TaskItem(
        id: Int(Date().timeIntervalSince1970) + 102,
        text: "Prepare slides for Monday's presentation",
        notes: "Focus on Q3 performance metrics.",
        date: "2025-10-02",
        status: .started,
        recurrence: nil,
        createdAt: d("2025-09-30T10:00:00Z"),
        startedAt: od("2025-10-01T14:00:00Z"),
        completedAt: nil,
        completedOverrides: nil
    ),
    TaskItem(
        id: Int(Date().timeIntervalSince1970) + 103,
        text: "Submit weekly progress report",
        notes: "Report was submitted yesterday morning.",
        date: "2025-10-01",
        status: .completed,
        recurrence: nil,
        createdAt: d("2025-09-29T09:00:00Z"),
        startedAt: od("2025-10-01T09:00:00Z"),
        completedAt: od("2025-10-01T11:30:00Z"),
        completedOverrides: [
            "2025-10-01": TaskOverride(
                status: .completed,
                startedAt: od("2025-10-01T09:00:00Z"),
                completedAt: od("2025-10-01T11:30:00Z"),
                rating: .liked
            )
        ]
    ),
    TaskItem(
        id: Int(Date().timeIntervalSince1970) + 104,
        text: "Review new design mockups",
        notes: "Check for mobile responsiveness.",
        date: "2025-10-02",
        status: .notStarted,
        recurrence: nil,
        createdAt: Date(),
        startedAt: nil,
        completedAt: nil,
        completedOverrides: nil
    ),
    TaskItem(
        id: Int(Date().timeIntervalSince1970) + 105,
        text: "Debug issue #5821 on the staging server",
        notes: "The login page is throwing a 500 error.",
        date: "2025-10-02",
        status: .started,
        recurrence: nil,
        createdAt: d("2025-10-02T08:00:00Z"),
        startedAt: od("2025-10-02T10:15:00Z"),
        completedAt: nil,
        completedOverrides: nil
    ),
    TaskItem(
        id: Int(Date().timeIntervalSince1970) + 106,
        text: "Daily Standup Meeting",
        notes: "",
        date: "2025-09-01",
        status: .notStarted,
        recurrence: .daily,
        createdAt: d("2025-08-01T09:00:00Z"),
        startedAt: nil,
        completedAt: nil,
        completedOverrides: [:]
    )
]
items.append(contentsOf: fixed)


        // More random tasks (trimmed vs your full JS for brevity)
        let sampleTexts = [
            "Finalize Q4 budget report","Design user authentication flow","Develop API endpoint for user profiles",
            "Write documentation for the new SDK","Plan social media campaign","Fix memory leak in the main service",
            "Review and merge PR #512","Onboard new marketing intern","Prepare presentation for stakeholders",
            "Refactor the old payment module","Create A/B test","Analyze user feedback","Schedule annual team retreat"
        ]

        // Safe parse (never force-unwrap)
        let start = ISO8601.dateTime.date(from: "2025-07-01T00:00:00Z") ?? Date(timeIntervalSince1970: 0)
        let end   = ISO8601.dateTime.date(from: "2025-11-01T00:00:00Z") ?? Date()

        func randDate(_ a: Date, _ b: Date) -> Date {
            let t = TimeInterval.random(in: a.timeIntervalSince1970...b.timeIntervalSince1970)
            return Date(timeIntervalSince1970: t)
        }

        for i in 1...60 {
            let assigned = Bool.random() || Bool.random() // ~75%
            let dateStr: String? = assigned ? ISO8601.dateOnly.string(from: randDate(start, end)) : nil
            let status: TaskStatus = {
                guard assigned else { return .notStarted }
                let r = Double.random(in: 0..<1)
                if r < 0.4 { return .completed }
                if r < 0.7 { return .started }
                return .notStarted
            }()
            let createdAt = randDate(start, Date())
            var startedAt: Date? = nil
            var completedAt: Date? = nil
            if status != .notStarted { startedAt = randDate(createdAt, Date()) }
            if status == .completed, let s = startedAt { completedAt = randDate(s, Date()) }

            items.append(
                TaskItem(
                    id: Int(Date().timeIntervalSince1970) + i,
                    text: sampleTexts.randomElement() ?? "Task",
                    notes: Bool.random() ? "Check requirements doc / may slip." : nil,
                    date: dateStr,
                    status: status,
                    recurrence: nil,
                    createdAt: createdAt,
                    startedAt: startedAt,
                    completedAt: completedAt,
                    completedOverrides: nil
                )
            )
        }
        return items

    }
}
