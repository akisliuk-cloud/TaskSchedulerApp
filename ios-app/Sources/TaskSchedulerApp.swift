// MARK: - TaskScheduler (SwiftUI) Starter Kit
// iOS 17+, Swift 5.9
// -------------------------------------------------
// Dieses Starter-Projekt bildet deine React-App 1:1 in SwiftUI nach –
// mit portierbarer Kernlogik (UTC-Datum), Wiederholungen mit Overrides,
// Suche, Kalender-Expansion, Archiv-Handling und Statistik.
// Persistenz per UserDefaults (JSON). Später leicht auf CoreData/CloudKit hebbar.

import SwiftUI

// MARK: - Domain Models

enum TaskStatus: String, Codable, CaseIterable { case notStarted = "not_started", started = "started", completed = "completed" }

enum Recurrence: String, Codable, CaseIterable { case never, daily, weekly, monthly }

enum Rating: String, Codable, CaseIterable { case liked, disliked }

enum ArchiveReason: String, Codable, CaseIterable { case not_started, started, completed, deleted }

struct CompletedOverride: Codable, Hashable {
    var status: TaskStatus? = nil
    var startedAt: Date? = nil
    var completedAt: Date? = nil
    var rating: Rating? = nil
}

struct Task: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var text: String
    var notes: String = ""
    /// YYYY-MM-DD (UTC) oder nil für Inbox
    var date: String? = nil
    var status: TaskStatus = .notStarted
    var recurrence: Recurrence? = nil
    var createdAt: Date = .now
    var startedAt: Date? = nil
    var completedAt: Date? = nil
    var rating: Rating? = nil
    /// Nur genutzt, wenn recurrence != .never
    var completedOverrides: [String: CompletedOverride]? = nil // key = YYYY-MM-DD (UTC)
}

struct ArchivedTask: Codable, Identifiable, Hashable {
    var id: String
    var text: String
    var notes: String
    var date: String?
    var status: TaskStatus
    var recurrence: Recurrence?
    var createdAt: Date
    var startedAt: Date?
    var completedAt: Date?
    var rating: Rating?
    var completedOverrides: [String: CompletedOverride]?

    var archivedAt: Date = .now
    var archiveReason: ArchiveReason
}

// MARK: - UTC Date Helpers (portable)

enum UTCDate {
    static let calendarUTC: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }()

    static func toYMD(_ d: Date) -> String {
        let c = calendarUTC
        let y = c.component(.year, from: d)
        let m = c.component(.month, from: d)
        let day = c.component(.day, from: d)
        return String(format: "%04d-%02d-%02d", y, m, day)
    }

    static func parseYMD(_ ymd: String) -> Date {
        let comps = ymd.split(separator: "-")
        guard comps.count == 3,
              let y = Int(comps[0]),
              let m = Int(comps[1]),
              let d = Int(comps[2]) else { return Date(timeIntervalSince1970: 0) }
        return calendarUTC.date(from: DateComponents(timeZone: .gmt, year: y, month: m, day: d)) ?? Date(timeIntervalSince1970: 0)
    }

    static func addDays(_ ymd: String, _ n: Int) -> String {
        let date = parseYMD(ymd)
        let next = calendarUTC.date(byAdding: .day, value: n, to: date) ?? date
        return toYMD(next)
    }

    static func mondayOfWeek(for date: Date) -> Date {
        let weekday = calendarUTC.component(.weekday, from: date)
        // In Gregorian: 1=Sunday ... 7=Saturday → wir wollen Montag=2 → Offset berechnen
        let isoOffset = ((weekday + 5) % 7) // 0=Montag ... 6=Sonntag
        return calendarUTC.date(byAdding: .day, value: -isoOffset, to: date) ?? date
    }

    static func isoWeekNumber(for date: Date) -> Int {
        // ISO-8601 Woche per Calendar
        var cal = calendarUTC
        cal.firstWeekday = 2 // Monday
        cal.minimumDaysInFirstWeek = 4
        return cal.component(.weekOfYear, from: date)
    }

    static func quarter(for date: Date) -> Int {
        let m = calendarUTC.component(.month, from: date)
        return ((m - 1) / 3) + 1
    }

    static func semester(for date: Date) -> Int { calendarUTC.component(.month, from: date) <= 6 ? 1 : 2 }
}

extension TimeZone { static let gmt = TimeZone(secondsFromGMT: 0)! }

// MARK: - Seed Data (Demo)

extension Task {
    static func demo() -> [Task] {
        var arr: [Task] = []
        arr.append(Task(text: "Plan team lunch for next week", notes: "Decide location & poll.", date: "2025-10-03"))
        arr.append(Task(text: "Prepare slides for Monday's presentation", notes: "Focus Q3 metrics.", date: "2025-10-02", status: .started, createdAt: UTCDate.parseYMD("2025-09-30"), startedAt: UTCDate.parseYMD("2025-10-01")))
        arr.append(Task(text: "Submit weekly progress report", notes: "Submitted yesterday.", date: "2025-10-01", status: .completed, createdAt: UTCDate.parseYMD("2025-09-29"), startedAt: UTCDate.parseYMD("2025-10-01"), completedAt: UTCDate.parseYMD("2025-10-01"), rating: .liked))
        arr.append(Task(text: "Review new design mockups", notes: "Check mobile.", date: "2025-10-02"))
        arr.append(Task(text: "Debug issue #5821", notes: "500 on login", date: "2025-10-02", status: .started, createdAt: UTCDate.parseYMD("2025-10-02"), startedAt: UTCDate.parseYMD("2025-10-02")))
        arr.append(Task(text: "Daily Standup Meeting", notes: "", date: "2025-09-01", status: .notStarted, recurrence: .daily, completedOverrides: [:], createdAt: UTCDate.parseYMD("2025-08-01")))
        return arr
    }
}

// MARK: - Store & Persistence

@MainActor
final class TaskStore: ObservableObject {
    @Published var tasks: [Task] = []
    @Published var archived: [ArchivedTask] = []
    @Published var theme: ColorScheme? = nil // nil=system

    private let storageKey = "task-app-state-v1"

    init(loadDemo: Bool = true) {
        load()
        if tasks.isEmpty && loadDemo {
            tasks = Task.demo()
        }
    }

    func save() {
        let payload = AppState(tasks: tasks, archived: archived, theme: theme == .dark ? "dark" : (theme == .light ? "light" : nil))
        do {
            let data = try JSONEncoder().encode(payload)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch { print("Save error: \(error)") }
    }

    func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        do {
            let decoded = try JSONDecoder().decode(AppState.self, from: data)
            self.tasks = decoded.tasks
            self.archived = decoded.archived
            if decoded.theme == "dark" { theme = .dark }
            else if decoded.theme == "light" { theme = .light }
            else { theme = nil }
        } catch { print("Load error: \(error)") }
    }

    struct AppState: Codable { let tasks: [Task]; let archived: [ArchivedTask]; let theme: String? }
}

// MARK: - ViewModel (Logic port)

@MainActor
final class TaskViewModel: ObservableObject {
    @Published var query: String = ""
    @Published var calendarStartYMD: String = {
        let today = UTCDate.toYMD(.now)
        var d = UTCDate.parseYMD(today)
        d = UTCDate.calendarUTC.date(byAdding: .day, value: -45, to: d) ?? d
        return UTCDate.toYMD(d)
    }()
    @Published var calendarViewMode: CalendarMode = .card
    @Published var filters: Set<TaskStatus> = [.notStarted, .started, .completed]

    enum CalendarMode { case card, list }

    private let store: TaskStore
    init(store: TaskStore) { self.store = store }

    // FILTERED by search
    var filteredTasks: [Task] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return store.tasks }
        return store.tasks.filter { t in
            t.text.lowercased().contains(q) || (!t.notes.isEmpty && t.notes.lowercased().contains(q))
        }
    }

    // Calendar days (90 Tage oder komprimierte Treffer)
    struct DayItem: Identifiable { let id = UUID(); let ymd: String; let weekdayShort: String; let dayOfMonth: Int }

    var calendarDays: [DayItem] {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            var days: [DayItem] = []
            var ymd = calendarStartYMD
            for _ in 0..<90 {
                let d = UTCDate.parseYMD(ymd)
                let wd = d.formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "en_US")))
                let dom = UTCDate.calendarUTC.component(.day, from: d)
                days.append(.init(ymd: ymd, weekdayShort: wd, dayOfMonth: dom))
                ymd = UTCDate.addDays(ymd, 1)
            }
            return days
        } else {
            var set = Set<String>()
            for t in filteredTasks {
                guard let date = t.date else { continue }
                if let r = t.recurrence, r != .never {
                    // 1 Jahr expandieren
                    var cur = date
                    let end = UTCDate.addDays(date, 365)
                    while cur <= end {
                        set.insert(cur)
                        switch r {
                        case .daily: cur = UTCDate.addDays(cur, 1)
                        case .weekly: cur = UTCDate.addDays(cur, 7)
                        case .monthly:
                            let dd = UTCDate.parseYMD(cur)
                            let next = UTCDate.calendarUTC.date(byAdding: .month, value: 1, to: dd) ?? dd
                            cur = UTCDate.toYMD(next)
                        case .never: break
                        }
                    }
                } else {
                    set.insert(date)
                }
            }
            let sorted = set.sorted()
            return sorted.map { ymd in
                let d = UTCDate.parseYMD(ymd)
                let wd = d.formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "en_US")))
                let dom = UTCDate.calendarUTC.component(.day, from: d)
                return .init(ymd: ymd, weekdayShort: wd, dayOfMonth: dom)
            }
        }
    }

    // Sichtbare Kalender-Tasks (Expansion inkl. Overrides)
    struct CalendarTask: Identifiable { let id: String; let parentId: String?; let base: Task; let ymd: String; let instanceStatus: TaskStatus; let startedAt: Date?; let completedAt: Date?; let rating: Rating?; let isInstance: Bool }

    var visibleCalendarTasks: [CalendarTask] {
        let visibleDates = Set(calendarDays.map { $0.ymd })
        var out: [CalendarTask] = []
        for t in filteredTasks {
            guard let date = t.date else { continue }
            if let r = t.recurrence, r != .never {
                let last = calendarDays.last?.ymd
                guard let end = last else { continue }
                var cur = date
                while cur <= end {
                    if visibleDates.contains(cur) {
                        let ov = t.completedOverrides?[cur] ?? CompletedOverride()
                        let st = ov.status ?? .notStarted
                        out.append(.init(id: t.id + "-" + cur, parentId: t.id, base: t, ymd: cur, instanceStatus: st, startedAt: ov.startedAt, completedAt: ov.completedAt, rating: ov.rating ?? t.rating, isInstance: true))
                    }
                    switch r {
                    case .daily: cur = UTCDate.addDays(cur, 1)
                    case .weekly: cur = UTCDate.addDays(cur, 7)
                    case .monthly:
                        let dd = UTCDate.parseYMD(cur)
                        let next = UTCDate.calendarUTC.date(byAdding: .month, value: 1, to: dd) ?? dd
                        cur = UTCDate.toYMD(next)
                    case .never: break
                    }
                }
            } else {
                if visibleDates.contains(date) {
                    out.append(.init(id: t.id, parentId: nil, base: t, ymd: date, instanceStatus: t.status, startedAt: t.startedAt, completedAt: t.completedAt, rating: t.rating, isInstance: false))
                }
            }
        }
        return out
    }

    // Aufgaben pro Tag
    var tasksByDate: [String: [CalendarTask]] {
        Dictionary(grouping: visibleCalendarTasks, by: { $0.ymd })
    }

    // MARK: - Mutations (portiert aus React)

    func addTask(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        store.tasks.append(Task(text: text))
        store.save()
    }

    func updateTask(_ taskId: String, mutate: (inout Task) -> Void) {
        guard let idx = store.tasks.firstIndex(where: { $0.id == taskId }) else { return }
        var t = store.tasks[idx]
        mutate(&t)
        store.tasks[idx] = t
        store.save()
    }

    func setRating(taskId: String, rating: Rating?) {
        updateTask(taskId) { $0.rating = ($0.rating == rating) ? nil : rating }
    }

    func setInstanceRating(parentId: String, on ymd: String, rating: Rating?) {
        updateTask(parentId) { t in
            var overrides = t.completedOverrides ?? [:]
            var cur = overrides[ymd] ?? CompletedOverride()
            cur.rating = (cur.rating == rating) ? nil : rating
            overrides[ymd] = cur
            t.completedOverrides = overrides
        }
    }

    func setStatus(taskId: String, _ newStatus: TaskStatus) {
        guard let idx = store.tasks.firstIndex(where: { $0.id == taskId }) else { return }
        var t = store.tasks[idx]
        let now = Date()
        switch newStatus {
        case .started:
            if t.startedAt == nil { t.startedAt = now }
            t.completedAt = nil
        case .completed:
            if t.recurrence == nil { // auto-archive für Einmal-Tasks
                let archived = ArchivedTask(id: t.id, text: t.text, notes: t.notes, date: t.date, status: .completed, recurrence: nil, createdAt: t.createdAt, startedAt: t.startedAt ?? now, completedAt: now, rating: t.rating, completedOverrides: nil, archivedAt: now, archiveReason: .completed)
                store.tasks.remove(at: idx)
                store.archived.append(archived)
                store.save()
                return
            } else {
                t.completedAt = now
            }
        case .notStarted:
            t.startedAt = nil; t.completedAt = nil
        }
        t.status = newStatus
        store.tasks[idx] = t
        store.save()
    }

    func setInstanceStatus(parentId: String, on ymd: String, _ newStatus: TaskStatus) {
        updateTask(parentId) { t in
            var ov = t.completedOverrides ?? [:]
            var cur = ov[ymd] ?? CompletedOverride()
            let now = Date()
            switch newStatus {
            case .started:
                if cur.startedAt == nil { cur.startedAt = now }
                cur.completedAt = nil
            case .completed:
                if cur.startedAt == nil { cur.startedAt = now }
                cur.completedAt = now
            case .notStarted:
                cur.startedAt = nil; cur.completedAt = nil
            }
            cur.status = newStatus
            ov[ymd] = cur
            t.completedOverrides = ov
        }
    }

    func deleteTask(_ taskId: String) {
        guard let idx = store.tasks.firstIndex(where: { $0.id == taskId }) else { return }
        let t = store.tasks[idx]
        let archived = ArchivedTask(id: t.id, text: t.text, notes: t.notes, date: t.date, status: t.status, recurrence: t.recurrence, createdAt: t.createdAt, startedAt: t.startedAt, completedAt: t.completedAt, rating: t.rating, completedOverrides: t.completedOverrides, archivedAt: .now, archiveReason: .deleted)
        store.tasks.remove(at: idx)
        store.archived.append(archived)
        store.save()
    }

    func archiveTask(_ taskId: String) {
        guard let idx = store.tasks.firstIndex(where: { $0.id == taskId }) else { return }
        let t = store.tasks[idx]
        let reason: ArchiveReason = (t.status == .notStarted ? .not_started : t.status == .started ? .started : .completed)
        let archived = ArchivedTask(id: t.id, text: t.text, notes: t.notes, date: t.date, status: t.status, recurrence: t.recurrence, createdAt: t.createdAt, startedAt: t.startedAt, completedAt: t.completedAt, rating: t.rating, completedOverrides: t.completedOverrides, archivedAt: .now, archiveReason: reason)
        store.tasks.remove(at: idx)
        store.archived.append(archived)
        store.save()
    }

    func restoreTask(_ archivedId: String) {
        guard let idx = store.archived.firstIndex(where: { $0.id == archivedId }) else { return }
        let a = store.archived[idx]
        let t = Task(id: a.id, text: a.text, notes: a.notes, date: a.date, status: a.status, recurrence: a.recurrence, createdAt: a.createdAt, startedAt: a.startedAt, completedAt: a.completedAt, rating: a.rating, completedOverrides: a.completedOverrides)
        store.archived.remove(at: idx)
        store.tasks.append(t)
        store.save()
    }

    func emptyArchive(for reason: ArchiveReason) {
        store.archived.removeAll { $0.archiveReason == reason }
        store.save()
    }
}

// MARK: - Statistics (weekly/monthly/quarter/semester/yearly)

struct StatsResult {
    let total: Int
    let completed: Int
    let open: Int
    let completionRate: Int
    let chartData: [BarItem]
    let granularity: Granularity
    let periodLabel: String
    let likedCompleted: Int
    let dislikedCompleted: Int
    let likedOpen: Int
    let dislikedOpen: Int
    let likedDeleted: Int
    let dislikedDeleted: Int

    struct BarItem: Identifiable { let id = UUID(); let label: String; let completed: Int; let open: Int }
    enum Granularity { case day, week, month }
}

extension TaskViewModel {
    enum StatsPeriod { case weekly, monthly, quarterly, semester, yearly }

    func stats(period: StatsPeriod, year: Int, month: Int? = nil, quarter: Int? = nil, semester: Int? = nil, weekOfYear: Int? = nil) -> StatsResult {
        // 1) Zeitraum bestimmen
        let cal = UTCDate.calendarUTC
        var start: Date = .now, end: Date = .now
        var label = ""
        var gran: StatsResult.Granularity = .day

        func ymdRangeToDates(_ y1:Int,_ m1:Int,_ d1:Int,_ y2:Int,_ m2:Int,_ d2:Int) -> (Date, Date) {
            let s = cal.date(from: DateComponents(timeZone: .gmt, year: y1, month: m1, day: d1))!
            let e = cal.date(from: DateComponents(timeZone: .gmt, year: y2, month: m2, day: d2, hour: 23, minute: 59, second: 59))!
            return (s,e)
        }

        switch period {
        case .yearly:
            (start, end) = ymdRangeToDates(year,1,1, year,12,31); label = "Year: \(year)"; gran = .month
        case .semester:
            if (semester ?? 1) == 1 { (start,end) = ymdRangeToDates(year,1,1, year,6,30); label = "First Semester (H1), \(year)" }
            else { (start,end) = ymdRangeToDates(year,7,1, year,12,31); label = "Second Semester (H2), \(year)" }
            gran = .month
        case .quarterly:
            let q = quarter ?? 1
            let startMonth = (q - 1) * 3 + 1
            let endMonth = startMonth + 2
            let endDay = [1,3,5,7,8,10,12].contains(endMonth) ? 31 : (endMonth == 2 ? (year % 4 == 0 ? 29 : 28) : 30)
            (start,end) = ymdRangeToDates(year,startMonth,1, year,endMonth,endDay)
            let ranges = [1:"Jan - Mar",2:"Apr - Jun",3:"Jul - Sep",4:"Oct - Dec"]
            label = "Q\(q) (\(ranges[q]!), \(year))"; gran = .month
        case .monthly:
            let m = month ?? 1
            let endDay = [1,3,5,7,8,10,12].contains(m) ? 31 : (m == 2 ? (year % 4 == 0 ? 29 : 28) : 30)
            (start,end) = ymdRangeToDates(year,m,1, year,m,endDay)
            let mName = DateComponents(calendar: cal, year: year, month: m, day: 1).date!.formatted(Date.FormatStyle().month(.wide))
            label = "\(mName), \(year)"; gran = .week
        case .weekly:
            // CW via week number → wir nähern uns über Montag in Woche
            let jan4 = cal.date(from: DateComponents(timeZone: .gmt, year: year, month: 1, day: 4))!
            var comp = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: jan4)
            comp.weekOfYear = weekOfYear ?? 1
            let anyDayOfWeek = cal.date(from: comp)!
            let monday = UTCDate.mondayOfWeek(for: anyDayOfWeek)
            start = monday
            end = cal.date(byAdding: .day, value: 6, to: monday)!
            let sStr = start.formatted(.dateTime.month(.abbreviated).day())
            let eStr = end.formatted(.dateTime.month(.abbreviated).day())
            let cw = UTCDate.isoWeekNumber(for: start)
            label = "Week: \(sStr) - \(eStr) (CW \(cw), \(year))"; gran = .day
        }

        // 2) Relevante Tasks (inkl. Archiv)
        let all = store.tasks + store.archived.map { a in
            Task(id: a.id, text: a.text, notes: a.notes, date: a.date, status: a.status, recurrence: a.recurrence, createdAt: a.createdAt, startedAt: a.startedAt, completedAt: a.completedAt, rating: a.rating, completedOverrides: a.completedOverrides)
        }

        let rangeYMD = stride(from: start, through: end, by: 24*3600).map { UTCDate.toYMD($0) }
        let setRange = Set(rangeYMD)

        let relevant = all.filter { t in
            guard let ymd = t.date else { return false }
            return setRange.contains(ymd)
        }

        let completed = relevant.filter { $0.status == .completed }
        let open = relevant.filter { $0.status != .completed }
        let deleted = store.archived.filter { setRange.contains($0.date ?? "") && $0.archiveReason == .deleted }

        let total = completed.count + open.count
        let rate = total > 0 ? Int(round((Double(completed.count)/Double(total))*100.0)) : 0

        // Ratings
        let likedCompleted = completed.filter{ $0.rating == .liked }.count
        let dislikedCompleted = completed.filter{ $0.rating == .disliked }.count
        let likedOpen = open.filter{ $0.rating == .liked }.count
        let dislikedOpen = open.filter{ $0.rating == .disliked }.count
        let likedDeleted = deleted.filter{ $0.rating == .liked }.count
        let dislikedDeleted = deleted.filter{ $0.rating == .disliked }.count

        // Gruppierung
        var grouped: [String: (Int,Int)] = [:] // key -> (completed, open)
        for t in completed + open {
            guard let ymd = t.date else { continue }
            let d = UTCDate.parseYMD(ymd)
            let key: String
            switch gran {
            case .day: key = ymd
            case .week: key = UTCDate.toYMD(UTCDate.mondayOfWeek(for: d))
            case .month:
                let y = UTCDate.calendarUTC.component(.year, from: d)
                let m = UTCDate.calendarUTC.component(.month, from: d)
                key = String(format: "%04d-%02d", y, m)
            }
            var entry = grouped[key] ?? (0,0)
            if t.status == .completed { entry.0 += 1 } else { entry.1 += 1 }
            grouped[key] = entry
        }

        // ChartData entlang der Range
        var bars: [StatsResult.BarItem] = []
        switch gran {
        case .day:
            for ymd in rangeYMD {
                let v = grouped[ymd] ?? (0,0)
                let d = UTCDate.parseYMD(ymd)
                let lab = d.formatted(.dateTime.weekday(.abbreviated).day())
                bars.append(.init(label: lab, completed: v.0, open: v.1))
            }
        case .week:
            // Alle Montags der Range
            var set = Set<String>()
            for ymd in rangeYMD {
                let mon = UTCDate.toYMD(UTCDate.mondayOfWeek(for: UTCDate.parseYMD(ymd)))
                set.insert(mon)
            }
            for k in set.sorted() {
                let d = UTCDate.parseYMD(k)
                let endW = UTCDate.calendarUTC.date(byAdding: .day, value: 6, to: d)!
                let cw = UTCDate.isoWeekNumber(for: d)
                let lab = "CW \(cw) (" + d.formatted(.dateTime.month(.abbreviated).day()) + " - " + endW.formatted(.dateTime.month(.abbreviated).day()) + ")"
                let v = grouped[k] ?? (0,0)
                bars.append(.init(label: lab, completed: v.0, open: v.1))
            }
        case .month:
            let yStart = UTCDate.calendarUTC.component(.year, from: start)
            let mStart = UTCDate.calendarUTC.component(.month, from: start)
            let yEnd = UTCDate.calendarUTC.component(.year, from: end)
            let mEnd = UTCDate.calendarUTC.component(.month, from: end)
            if yStart == yEnd {
                for m in mStart...mEnd {
                    let key = String(format: "%04d-%02d", yStart, m)
                    let lab = DateComponents(calendar: UTCDate.calendarUTC, year: yStart, month: m).date!.formatted(.dateTime.month(.abbreviated))
                    let v = grouped[key] ?? (0,0)
                    bars.append(.init(label: lab, completed: v.0, open: v.1))
                }
            }
        }

        return StatsResult(total: total, completed: completed.count, open: open.count, completionRate: rate, chartData: bars, granularity: gran, periodLabel: label, likedCompleted: likedCompleted, dislikedCompleted: dislikedCompleted, likedOpen: likedOpen, dislikedOpen: dislikedOpen, likedDeleted: likedDeleted, dislikedDeleted: dislikedDeleted)
    }
}

// MARK: - Views (Minimal, erweiterbar)

struct ContentView: View {
    @StateObject var store = TaskStore()
    @StateObject var vm: TaskViewModel

    init() {
        let store = TaskStore()
        _store = StateObject(wrappedValue: store)
        _vm = StateObject(wrappedValue: TaskViewModel(store: store))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                header
                calendar
                inbox
            }
            .padding()
            .navigationTitle("Task Scheduler")
        }
        .preferredColorScheme(store.theme)
    }

    // Header mit Suche & Theme Toggle
    private var header: some View {
        HStack(spacing: 8) {
            TextField("Search tasks...", text: $vm.query)
                .textFieldStyle(.roundedBorder)
            Button(action: { toggleTheme() }) { Image(systemName: "moon.circle") }
        }
    }

    private func toggleTheme() {
        if store.theme == .dark { store.theme = .light }
        else if store.theme == .light { store.theme = nil }
        else { store.theme = .dark }
        store.save()
    }

    // Calendar Card/List Toggle (nur Gerüst)
    private var calendar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Daily Calendar").font(.headline)
                Spacer()
                Picker("View", selection: Binding(get: { vm.calendarViewMode }, set: { vm.calendarViewMode = $0 })) {
                    Text("Card").tag(TaskViewModel.CalendarMode.card)
                    Text("List").tag(TaskViewModel.CalendarMode.list)
                }
                .pickerStyle(.segmented)
            }
            ScrollView(vm.calendarViewMode == .card ? .horizontal : .vertical) {
                if vm.calendarViewMode == .card {
                    HStack(spacing: 8) {
                        ForEach(vm.calendarDays) { day in
                            VStack(alignment: .leading) {
                                Text(day.weekdayShort).bold()
                                Text("\(day.dayOfMonth)").font(.largeTitle).foregroundStyle(.secondary)
                                let items = vm.tasksByDate[day.ymd] ?? []
                                let done = items.filter{ $0.instanceStatus == .completed }.count
                                let started = items.filter{ $0.instanceStatus == .started }.count
                                let todo = items.filter{ $0.instanceStatus == .notStarted }.count
                                if done > 0 { badge("\(done) done", .green) }
                                if started > 0 { badge("\(started) started", .orange) }
                                if todo > 0 { badge("\(todo) to do", .blue) }
                            }
                            .padding()
                            .frame(width: 140, height: 160)
                            .background(.thinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                } else {
                    VStack(spacing: 6) {
                        ForEach(vm.calendarDays) { day in
                            let items = vm.tasksByDate[day.ymd] ?? []
                            HStack {
                                Text(UTCDate.parseYMD(day.ymd), format: .dateTime.weekday(.wide).month().day())
                                Spacer()
                                let done = items.filter{ $0.instanceStatus == .completed }.count
                                let started = items.filter{ $0.instanceStatus == .started }.count
                                let todo = items.filter{ $0.instanceStatus == .notStarted }.count
                                if todo > 0 { circleCount(todo, .blue) }
                                if started > 0 { circleCount(started, .orange) }
                                if done > 0 { circleCount(done, .green) }
                            }
                            .padding(8)
                            .background(.thinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
            }
            .frame(height: 180)
        }
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.caption).bold()
            .padding(.horizontal, 8).padding(.vertical, 4)
            .foregroundStyle(.white)
            .background(color)
            .clipShape(Capsule())
    }

    private func circleCount(_ n: Int, _ color: Color) -> some View {
        Text("\(n)")
            .font(.caption).bold()
            .frame(width: 24, height: 24)
            .foregroundStyle(.white)
            .background(color)
            .clipShape(Circle())
    }

    // Inbox (unassigned)
    private var inbox: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Task Inbox").font(.headline)
            HStack {
                TextField("Add a new task...", text: .constant(""))
                    .textFieldStyle(.roundedBorder)
                Button(action: { vm.addTask("New Task") }) { Image(systemName: "plus.circle.fill") }
            }
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(vm.filteredTasks.filter{ $0.date == nil }) { t in
                        HStack(alignment: .firstTextBaseline) {
                            Text(t.text)
                            Spacer()
                            Button { vm.archiveTask(t.id) } label { Image(systemName: "archivebox") }
                            Button { vm.deleteTask(t.id) } label { Image(systemName: "trash") }
                        }
                        .padding(8)
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .frame(maxHeight: 280)
        }
    }
}

// MARK: - App Entry

@main
struct TaskSchedulerApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
