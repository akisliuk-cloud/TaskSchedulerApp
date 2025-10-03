import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var tasks: [TaskItem] = []
    @Published var archived: [TaskItem] = []
    @Published var search: String = ""
    @Published var calendarStart: Date = Calendar.current.date(byAdding: .day, value: -45, to: .now) ?? .now
    @Published var showArchive = false
    @Published var showStats = false
    @Published var calendarViewMode: CalendarViewMode = .card
    @Published var calendarFilters = CalendarFilters()

    init() {
        tasks = SampleData.generate()
    }

    var filteredTasks: [TaskItem] {
        guard !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return tasks }
        let q = search.lowercased()
        return tasks.filter {
            $0.text.lowercased().contains(q) || ($0.notes?.lowercased().contains(q) ?? false)
        }
    }

    func tasksBy(dateString: String) -> [TaskItem] {
        filteredTasks.filter { $0.date == dateString }
    }

    func unassigned() -> [TaskItem] {
        filteredTasks.filter { $0.date == nil }
    }

    func updateStatus(_ task: TaskItem, to newStatus: TaskStatus) {
        guard let idx = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        var t = tasks[idx]
        let now = ISO8601DateFormatter().string(from: .now)

        switch newStatus {
        case .notStarted:
            t.status = .notStarted
            t.startedAt = nil
            t.completedAt = nil
        case .started:
            t.status = .started
            if t.startedAt == nil { t.startedAt = now }
            t.completedAt = nil
        case .completed:
            // Auto-archive non-recurring completed tasks
            if t.recurrence == .never || t.recurrence == nil {
                t.status = .completed
                if t.startedAt == nil { t.startedAt = now }
                t.completedAt = now
                t.archivedAt = now
                t.archiveReason = .completed
                tasks.remove(at: idx)
                archived.append(t)
                return
            } else {
                t.status = .completed
                t.completedAt = now
            }
        }
        tasks[idx] = t
    }

    func archive(_ task: TaskItem) {
        guard let idx = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        var t = tasks[idx]
        t.archivedAt = ISO8601DateFormatter().string(from: .now)
        t.archiveReason = .fromStatus(t.status)
        tasks.remove(at: idx)
        archived.append(t)
    }

    func deleteToTrash(_ task: TaskItem) {
        guard let idx = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        var t = tasks[idx]
        t.archivedAt = ISO8601DateFormatter().string(from: .now)
        t.archiveReason = .deleted
        tasks.remove(at: idx)
        archived.append(t)
    }

    func duplicate(_ task: TaskItem) {
        var copy = task
        copy.id = UUID()
        copy.text = "Copy of \(task.text)"
        copy.date = nil
        copy.status = .notStarted
        copy.createdAt = ISO8601DateFormatter().string(from: .now)
        copy.startedAt = nil
        copy.completedAt = nil
        copy.rating = nil
        copy.completedOverrides = nil
        tasks.insert(copy, at: min(tasks.count, (tasks.firstIndex(where: {$0.id == task.id}) ?? tasks.count) + 1))
    }

    func moveToInbox(_ task: TaskItem) {
        guard let idx = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        var t = tasks[idx]
        t.date = nil
        t.status = .notStarted
        t.recurrence = .never
        t.completedOverrides = nil
        tasks[idx] = t
    }

    func reschedule(_ task: TaskItem, to newDate: String) {
        guard let idx = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        var t = tasks[idx]
        t.date = newDate
        tasks[idx] = t
    }
}

struct ContentView: View {
    @StateObject private var state = AppState()
    @State private var selectedDay: String? = nil
    @State private var showDaySheet = false

    private var calendarDays: [CalendarDay] {
        // “Compressed” if searching; otherwise 90-day scrolling window
        if state.search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            var days: [CalendarDay] = []
            let start = state.calendarStart
            for i in 0..<90 {
                let d = Calendar.current.date(byAdding: .day, value: i, to: start) ?? .now
                days.append(.init(date: d))
            }
            return days
        } else {
            let set = Set(state.filteredTasks.compactMap { $0.date })
            return set.sorted().compactMap { CalendarDay(string: $0) }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                header
                Group {
                    if state.showArchive {
                        ArchivesView(state: state)
                    } else if state.showStats {
                        StatsPlaceholderView(back: { state.showStats = false })
                    } else {
                        calendarCard
                        inboxCard
                    }
                }
            }
            .padding()
            .sheet(isPresented: $showDaySheet) {
                if let ds = selectedDay {
                    DaySheetView(state: state, dateString: ds)
                        .presentationDetents([.medium, .large])
                }
            }
            .navigationTitle("Task Scheduler")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Task Scheduler")
                .font(.largeTitle).bold()
            Spacer()
            searchField
            Button {
                state.showArchive = true
                state.showStats = false
            } label: {
                Label("Archive", systemImage: "archivebox")
                    .labelStyle(.iconOnly)
            }
            Button {
                state.showArchive = false
                state.showStats = true
            } label: {
                Label("Stats", systemImage: "chart.bar")
                    .labelStyle(.iconOnly)
            }
        }
    }

    private var searchField: some View {
        TextField("Search tasks…", text: $state.search)
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 260)
    }

    private var calendarCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Daily Calendar", systemImage: "calendar")
                    .font(.headline)
                Spacer()
                Picker("", selection: $state.calendarViewMode) {
                    Text("Card").tag(CalendarViewMode.card)
                    Text("List").tag(CalendarViewMode.list)
                }
                .pickerStyle(.segmented)
                Button("Today") {
                    state.calendarStart = Calendar.current.date(byAdding: .day, value: -3, to: .now) ?? .now
                }
            }

            if state.calendarViewMode == .card {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(calendarDays) { day in
                            let ds = day.isoDate
                            let tasks = state.tasksBy(dateString: ds)
                                .filter { state.calendarFilters.contains($0.status) }
