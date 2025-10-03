import SwiftUI

// Simple app-wide state that mirrors just enough of your React state to run
final class AppState: ObservableObject {
    @Published var tasks: [TaskItem] = SampleData.make()
    @Published var archived: [TaskItem] = []
    
    @Published var newTaskText: String = ""
    @Published var calendarViewMode: CalendarViewMode = .card
    @Published var calendarFilters = CalendarFilters()
    @Published var searchQuery: String = ""
    
    // Add a new “inbox” task
    func addTask() {
        let trimmed = newTaskText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let item = TaskItem(text: trimmed, notes: nil, date: nil, status: .not_started, recurrence: nil, createdAt: Date())
        tasks.append(item)
        newTaskText = ""
    }
    
    // Actions referenced in your logs
    func deleteToTrash(_ task: TaskItem) {
        if let idx = tasks.firstIndex(of: task) {
            var t = tasks.remove(at: idx)
            // mark as deleted by archiving with a special status (we'll just push to archived)
            t.status = .not_started
            archived.append(t)
        }
    }

    func duplicate(_ task: TaskItem) {
        let copy = TaskItem(text: "Copy of \(task.text)",
                            notes: task.notes,
                            date: nil, // inbox
                            status: .not_started,
                            recurrence: nil,
                            createdAt: Date())
        // insert after original if present
        if let idx = tasks.firstIndex(of: task) {
            tasks.insert(copy, at: idx + 1)
        } else {
            tasks.append(copy)
        }
    }

    func moveToInbox(_ task: TaskItem) {
        if let idx = tasks.firstIndex(of: task) {
            tasks[idx].date = nil
            tasks[idx].status = .not_started
            tasks[idx].recurrence = nil
        }
    }

    func reschedule(_ task: TaskItem, to newDate: String) {
        if let idx = tasks.firstIndex(of: task) {
            tasks[idx].date = newDate
        }
    }
    
    func toggleStatus(_ task: TaskItem, to newStatus: TaskStatus) {
        if let idx = tasks.firstIndex(of: task) {
            tasks[idx].status = newStatus
            switch newStatus {
            case .started:
                if tasks[idx].startedAt == nil { tasks[idx].startedAt = Date() }
                tasks[idx].completedAt = nil
            case .completed:
                if tasks[idx].startedAt == nil { tasks[idx].startedAt = Date() }
                tasks[idx].completedAt = Date()
            case .not_started:
                tasks[idx].startedAt = nil
                tasks[idx].completedAt = nil
            }
        }
    }
    
    var filteredTasks: [TaskItem] {
        let base: [TaskItem]
        if searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            base = tasks
        } else {
            let q = searchQuery.lowercased()
            base = tasks.filter { t in
                t.text.lowercased().contains(q) || (t.notes?.lowercased().contains(q) ?? false)
            }
        }
        return base.filter { t in
            switch t.status {
            case .not_started: return calendarFilters.not_started
            case .started:     return calendarFilters.started
            case .completed:   return calendarFilters.completed
            }
        }
    }
    
    // group tasks by day string (yyyy-MM-dd)
    var tasksByDate: [String: [TaskItem]] {
        Dictionary(grouping: filteredTasks.compactMap { $0.date != nil ? $0 : nil }) { $0.date! }
    }
}

struct ContentView: View {
    @StateObject private var state = AppState()
    
    private let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .init(secondsFromGMT: 0)
        return f
    }()
    
    var body: some View {
        NavigationView {
            VStack(spacing: 12) {
                header
                filtersRow
                addRow
                contentArea
            }
            .padding()
            .navigationTitle("Task Scheduler")
        }
    }
    
    // MARK: - Sections
    
    private var header: some View {
        HStack {
            TextField("Search…", text: $state.searchQuery)
                .textFieldStyle(.roundedBorder)
            Picker("View", selection: $state.calendarViewMode) {
                Text("Card").tag(CalendarViewMode.card)
                Text("List").tag(CalendarViewMode.list)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 200)
        }
    }
    
    private var filtersRow: some View {
        HStack(spacing: 8) {
            Toggle("To Do", isOn: $state.calendarFilters.not_started).toggleStyle(.switch)
            Toggle("Started", isOn: $state.calendarFilters.started).toggleStyle(.switch)
            Toggle("Done", isOn: $state.calendarFilters.completed).toggleStyle(.switch)
        }
        .font(.caption)
    }
    
    private var addRow: some View {
        HStack {
            TextField("Add a new task…", text: $state.newTaskText)
                .textFieldStyle(.roundedBorder)
            Button {
                state.addTask()
            } label: {
                Image(systemName: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
        }
    }
    
    @ViewBuilder
    private var contentArea: some View {
        if state.calendarViewMode == .card {
            // Very simple “calendar”: today row + tasks grouped by date
            ScrollView {
                if state.tasksByDate.isEmpty {
                    Text("No scheduled tasks. Add some or move inbox tasks to dates.")
                        .foregroundStyle(.secondary)
                        .padding(.top, 40)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(state.tasksByDate.keys.sorted(), id: \.self) { day in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(dayHeader(day))
                                    .font(.headline)
                                ForEach(state.tasksByDate[day] ?? []) { task in
                                    TaskRow(task: task,
                                            onDelete: { state.deleteToTrash(task) },
                                            onDuplicate: { state.duplicate(task) },
                                            onInbox: { state.moveToInbox(task) },
                                            onSetStatus: { state.toggleStatus(task, to: $0) })
                                }
                            }
                            .padding()
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
                        }
                    }
                }
            }
        } else {
            // List “inbox” + scheduled
            List {
                Section("Inbox") {
                    ForEach(state.filteredTasks.filter { $0.date == nil }) { task in
                        TaskRow(task: task,
                                onDelete: { state.deleteToTrash(task) },
                                onDuplicate: { state.duplicate(task) },
                                onInbox: { /* already inbox */ },
                                onSetStatus: { state.toggleStatus(task, to: $0) })
                    }
                }
                Section("Scheduled") {
                    ForEach(state.filteredTasks.filter { $0.date != nil }) { task in
                        TaskRow(task: task,
                                onDelete: { state.deleteToTrash(task) },
                                onDuplicate: { state.duplicate(task) },
                                onInbox: { state.moveToInbox(task) },
                                onSetStatus: { state.toggleStatus(task, to: $0) })
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }
    
    private func dayHeader(_ yyyyMMdd: String) -> String {
        yyyyMMdd // keep as-is for now (e.g., “2025-10-03”)
    }
}

// MARK: - Small Task Row

private struct TaskRow: View {
    let task: TaskItem
    let onDelete: () -> Void
    let onDuplicate: () -> Void
    let onInbox: () -> Void
    let onSetStatus: (TaskStatus) -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(task.text)
                    .font(.body)
                    .strikethrough(task.status == .completed, color: .secondary)
                if let notes = task.notes, !notes.isEmpty {
                    Text(notes).font(.caption).foregroundStyle(.secondary)
                }
                if let date = task.date {
                    Text("Date: \(date)").font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text("Inbox").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Menu {
                Button("To Do") { onSetStatus(.not_started) }
                Button("Started") { onSetStatus(.started) }
                Button("Completed") { onSetStatus(.completed) }
                Divider()
                Button("Duplicate") { onDuplicate() }
                Button("Move to Inbox") { onInbox() }
                Divider()
                Button(role: .destructive) { onDelete() } label: {
                    Text("Delete (to Trash)")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.quaternary)
        )
    }
}
