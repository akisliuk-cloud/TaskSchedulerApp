// ios-app/Sources/ContentView.swift
import SwiftUI
import Foundation
import Charts // iOS 16+. If targeting 15, the chart area shows a fallback message.

// MARK: - Scroll helpers (ids)
private func dayCardID(_ dateStr: String) -> String { "card-\(dateStr)" }
private func dayListID(_ dateStr: String) -> String { "list-\(dateStr)" }

// MARK: - iOS16-friendly empty state
struct CompatEmptyState: View {
    let title: String
    let systemImage: String

    var body: some View {
        Group {
            if #available(iOS 17.0, *) {
                ContentUnavailableView(title, systemImage: systemImage)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: systemImage)
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// MARK: - Root view
struct ContentView: View {
    @StateObject private var state = AppState()

    // Calendar modal
    @State private var showingDay: CalendarDay? = nil
    @State private var isModalBulkSelect = false
    @State private var selectedModalIds = Set<Int>() // instance ids

    // Inbox editing
    @State private var newTaskText = ""
    @State private var editingTaskId: Int? = nil
    @State private var editText = ""
    @State private var editNotes = ""
    @State private var editDate: String = ""
    @State private var editStatus: TaskStatus = .notStarted
    @State private var editRecurrence: Recurrence = .never

    // Calendar scroll control
    @State private var triggerScrollToToday = false

    var body: some View {
        VStack(spacing: 16) {
            header
            mainPanels
        }
        .padding()
        .sheet(item: $showingDay) { day in
            DayModalView(day: day, state: state,
                         isBulk: $isModalBulkSelect,
                         selectedIds: $selectedModalIds)
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Task Scheduler")
                        .font(.largeTitle).bold()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("Drag tasks to schedule. Tap a day for details.")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 12)
                TextField("Search tasks…", text: $state.searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 220)
                Button {
                    state.isArchiveViewActive = true
                    state.isStatsViewActive = false
                } label: {
                    Label("Archives", systemImage: "archivebox")
                }
                .buttonStyle(.bordered)
            }

            // quick view toggles
            HStack(spacing: 8) {
                Button {
                    state.isStatsViewActive = false
                    state.isArchiveViewActive = false
                } label: {
                    Label("Calendar", systemImage: "calendar")
                }
                .buttonStyle(.bordered)

                Button {
                    state.isStatsViewActive = true
                    state.isArchiveViewActive = false
                } label: {
                    Label("Stats", systemImage: "chart.bar")
                }
                .buttonStyle(.bordered)

                Button {
                    state.isArchiveViewActive = true
                    state.isStatsViewActive = false
                } label: {
                    Label("Archives", systemImage: "archivebox")
                }
                .buttonStyle(.bordered)

                Spacer()
            }
        }
    }

    // MARK: Main panels

    private var mainPanels: some View {
        VStack(spacing: 12) {
            Group {
                if state.isStatsViewActive {
                    StatsView(state: state)
                } else if state.isArchiveViewActive {
                    ArchivesView(state: state)
                } else {
                    calendarPanel
                }
            }
            if !(state.isArchiveViewActive || state.isStatsViewActive) {
                inboxPanel
            }
        }
    }

    // MARK: Calendar

    private var calendarPanel: some View {
        VStack(spacing: 10) {

            // Toolbar
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Button {
                        withAnimation { state.calendarViewMode = .card }
                    } label: {
                        Image(systemName: "square.grid.2x2")
                            .symbolVariant(state.calendarViewMode == .card ? .fill : .none)
                    }
                    Button {
                        withAnimation { state.calendarViewMode = .list }
                    } label: {
                        Image(systemName: "list.bullet")
                            .symbolVariant(state.calendarViewMode == .list ? .circle : .none)
                    }
                }
                .buttonStyle(.bordered)

                Divider().frame(height: 22)

                Button("Today") {
                    // keep the window near “today”
                    withAnimation {
                        state.calendarStartDate = Calendar.current.date(byAdding: .day, value: -3, to: Date()) ?? Date()
                    }
                    // trigger a scroll in the list/card below
                    triggerScrollToToday.toggle()
                }
                .buttonStyle(.borderedProminent)

                Spacer()

                // status filters
                HStack(spacing: 6) {
                    TogglePill(label: "To Do", isOn: Binding(
                        get: { state.calendarFilters[.notStarted] ?? true },
                        set: { state.calendarFilters[.notStarted] = $0 }
                    ), tint: .blue)
                    TogglePill(label: "Started", isOn: Binding(
                        get: { state.calendarFilters[.started] ?? true },
                        set: { state.calendarFilters[.started] = $0 }
                    ), tint: .orange)
                    TogglePill(label: "Done", isOn: Binding(
                        get: { state.calendarFilters[.completed] ?? true },
                        set: { state.calendarFilters[.completed] = $0 }
                    ), tint: .green)
                }
            }

            // Data
            let days = state.calendarDays()
            let expanded = state.visibleCalendarTasks(for: days)
            let tasksByDay = Dictionary(grouping: expanded) { $0.date ?? "" }
            let todayKey = ISO8601.dateOnly.string(from: Date())

            // Cards/List with ScrollViewReader so "Today" jumps
            if state.calendarViewMode == .card {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(days) { day in
                                let list = (tasksByDay[day.dateString] ?? [])
                                    .filter { state.calendarFilters[$0.status] ?? true }
                                DayCard(day: day, tasks: list) {
                                    showingDay = day
                                }
                                .id(dayCardID(day.dateString))
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .onChange(of: triggerScrollToToday) { _ in
                        withAnimation {
                            proxy.scrollTo(dayCardID(todayKey), anchor: .leading)
                        }
                    }
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(days) { day in
                                let list = (tasksByDay[day.dateString] ?? [])
                                    .filter { state.calendarFilters[$0.status] ?? true }

                                if state.searchQuery.isEmpty && list.isEmpty {
                                    EmptyView()
                                } else {
                                    DayRow(day: day, tasks: list) {
                                        showingDay = day
                                    }
                                    .id(dayListID(day.dateString))
                                }
                            }

                            if expanded.filter({ state.calendarFilters[$0.status] ?? true }).isEmpty {
                                CompatEmptyState(title: "No scheduled tasks in this period match your filters",
                                                 systemImage: "calendar")
                                    .padding(.top, 16)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }
                    .frame(height: 260)
                    .onChange(of: triggerScrollToToday) { _ in
                        withAnimation {
                            proxy.scrollTo(dayListID(todayKey), anchor: .top)
                        }
                    }
                }
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: Inbox

    private var inboxPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Task Inbox").font(.title3).bold()
                if !state.unassignedTasks.isEmpty {
                    Text("\(state.unassignedTasks.count)")
                        .font(.caption).bold()
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.secondary.opacity(0.2)))
                }
                Spacer()
                Button(state.isBulkSelectActiveInbox ? "Cancel" : "Select") {
                    state.toggleBulkSelectInbox()
                }
            }

            HStack(spacing: 8) {
                TextField("Add a new task…", text: $newTaskText, onCommit: {
                    state.addTask(text: newTaskText); newTaskText = ""
                })
                .textFieldStyle(.roundedBorder)
                Button {
                    state.addTask(text: newTaskText); newTaskText = ""
                } label: {
                    Image(systemName: "plus")
                }.buttonStyle(.borderedProminent)
            }

            if state.unassignedTasks.isEmpty {
                CompatEmptyState(title: "No unassigned tasks", systemImage: "tray")
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                // Bulk actions bar
                if state.isBulkSelectActiveInbox, !state.unassignedTasks.isEmpty {
                    HStack {
                        Button("Select All") {
                            state.setAllInboxSelection(state.unassignedTasks.map { $0.id })
                        }
                        Spacer()
                        Button {
                            state.archiveSelectedInbox()
                        } label: { Label("Archive", systemImage: "archivebox") }
                        Button(role: .destructive) {
                            state.deleteSelectedInbox()
                        } label: { Label("Delete", systemImage: "trash") }
                    }
                    .font(.subheadline)
                    .padding(.vertical, 2)
                }

                // List
                List {
                    ForEach(state.unassignedTasks) { t in
                        inboxRow(t)
                    }
                }
                .listStyle(.inset)
                .frame(minHeight: 160, maxHeight: 300)
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder private func inboxRow(_ t: TaskItem) -> some View {
        let isEditing = editingTaskId == t.id
        HStack(alignment: .top, spacing: 10) {
            if state.isBulkSelectActiveInbox {
                Toggle("", isOn: Binding(
                    get: { state.selectedInboxTaskIds.contains(t.id) },
                    set: { newValue in
                        if newValue { state.selectedInboxTaskIds.insert(t.id) }
                        else { state.selectedInboxTaskIds.remove(t.id) }
                    }
                ))
                .labelsHidden()
            } else {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.secondary)
            }

            if isEditing {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Task title", text: $editText)
                        .textFieldStyle(.roundedBorder)
                    TextField("Notes", text: $editNotes)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Picker("Status", selection: $editStatus) {
                            Text("To Do").tag(TaskStatus.notStarted)
                            Text("Started").tag(TaskStatus.started)
                            Text("Done").tag(TaskStatus.completed)
                        }.pickerStyle(.segmented)
                    }
                    HStack {
                        Picker("Repeat", selection: $editRecurrence) {
                            Text("Never").tag(Recurrence.never)
                            Text("Daily").tag(Recurrence.daily)
                            Text("Weekly").tag(Recurrence.weekly)
                            Text("Monthly").tag(Recurrence.monthly)
                        }.pickerStyle(.segmented)
                    }
                    HStack {
                        Text("Schedule Date")
                        TextField("yyyy-MM-dd", text: $editDate)
                            .textFieldStyle(.roundedBorder)
                    }
                    HStack {
                        Button("Cancel") { editingTaskId = nil }
                        Spacer()
                        Button("Save") { saveEdits(t) }
                            .buttonStyle(.borderedProminent)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(t.text).font(.body)
                        if let notes = t.notes, !notes.isEmpty {
                            Image(systemName: "note.text").foregroundStyle(.secondary)
                        }
                        if t.isRecurring {
                            Image(systemName: "repeat").foregroundStyle(.secondary)
                        }
                    }
                    Text("Created: \(formatDateTime(t.createdAt))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                if !state.isBulkSelectActiveInbox {
                    HStack(spacing: 0) {
                        Button { state.archiveTask(t) } label: {
                            Image(systemName: "archivebox")
                        }
                        .buttonStyle(.borderless)
                        .padding(6)

                        Button { state.duplicate(t) } label: {
                            Image(systemName: "plus.square.on.square")
                        }
                        .buttonStyle(.borderless)
                        .padding(6)

                        Button { state.deleteToTrash(t) } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .tint(.red)
                        .padding(6)
                    }
                    .opacity(0.9)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { if !state.isBulkSelectActiveInbox { beginEdit(t) } }
    }

    private func beginEdit(_ t: TaskItem) {
        editingTaskId = t.id
        editText = t.text
        editNotes = t.notes ?? ""
        editDate = t.date ?? ""
        editStatus = t.status
        editRecurrence = t.recurrence ?? .never
    }

    private func saveEdits(_ t: TaskItem) {
        guard let idx = state.tasks.firstIndex(where: { $0.id == t.id }) else { return }
        if editStatus == .completed, !(state.tasks[idx].isRecurring), !editDate.isEmpty {
            var done = state.tasks[idx]
            done.text = editText.trimmingCharacters(in: .whitespaces)
            done.notes = editNotes.trimmingCharacters(in: .whitespaces)
            done.date = editDate
            state.updateStatus(done, to: .completed)
        } else {
            state.tasks[idx].text = editText.trimmingCharacters(in: .whitespaces)
            state.tasks[idx].notes = editNotes.trimmingCharacters(in: .whitespaces)
            state.tasks[idx].date = editDate.isEmpty ? nil : editDate
            state.updateStatus(state.tasks[idx], to: editStatus)
            state.updateRecurrence(state.tasks[idx], to: editRecurrence)
        }
        editingTaskId = nil
    }
}

// MARK: - Subviews (Calendar elements)

private struct DayCard: View {
    let day: CalendarDay
    let tasks: [TaskItem]
    var onTap: () -> Void

    var body: some View {
        let isToday = day.dateString == ISO8601.dateOnly.string(from: Date())
        let done = tasks.filter { $0.status == .completed }.count
        let started = tasks.filter { $0.status == .started }.count
        let todo = tasks.filter { $0.status == .notStarted }.count

        VStack(alignment: .leading, spacing: 6) {
            Text(day.dayName).font(.caption).foregroundStyle(isToday ? .blue : .secondary)
            Text("\(day.dayOfMonth)").font(.title2).fontWeight(.semibold)
                .foregroundStyle(isToday ? .blue : .primary)
            Spacer()
            VStack(alignment: .leading, spacing: 4) {
                if done > 0 { badge("\(done) done", .green) }
                if started > 0 { badge("\(started) started", .orange) }
                if todo > 0 { badge("\(todo) to do", .blue) }
            }
        }
        .padding(10)
        .frame(width: 120, height: 150)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isToday ? .blue : .clear, lineWidth: 2)
                )
        )
        .onTapGesture { onTap() }
    }

    @ViewBuilder private func badge(_ text: String, _ color: Color) -> some View {
        Text(text).font(.caption2).bold()
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.2))
            .foregroundStyle(color).clipShape(Capsule())
    }
}

private struct DayRow: View {
    let day: CalendarDay
    let tasks: [TaskItem]
    var onTap: () -> Void

    var body: some View {
        let isToday = day.dateString == ISO8601.dateOnly.string(from: Date())
        let done = tasks.filter { $0.status == .completed }.count
        let started = tasks.filter { $0.status == .started }.count
        let todo = tasks.filter { $0.status == .notStarted }.count

        HStack {
            Text(dateLong(day.dateString))
                .font(.subheadline).fontWeight(.semibold)
                .foregroundStyle(isToday ? .blue : .primary)
            Spacer()
            HStack(spacing: 6) {
                if todo > 0 { chip("\(todo)", .blue) }
                if started > 0 { chip("\(started)", .orange) }
                if done > 0 { chip("\(done)", .green) }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.secondarySystemBackground))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(isToday ? .blue : .clear))
        )
        .onTapGesture { onTap() }
    }

    private func dateLong(_ ds: String) -> String {
        guard let d = ds.asISODateOnlyUTC else { return ds }
        let f = DateFormatter()
        f.timeZone = .init(secondsFromGMT: 0)
        f.dateFormat = "EEEE, MMMM d"
        return f.string(from: d)
    }

    @ViewBuilder private func chip(_ text: String, _ color: Color) -> some View {
        Text(text).font(.caption2).bold()
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.2))
            .foregroundStyle(color).clipShape(Capsule())
    }
}

// MARK: - Day Modal (keeps your bulk select)

private struct DayModalView: View {
    let day: CalendarDay
    @ObservedObject var state: AppState
    @Binding var isBulk: Bool
    @Binding var selectedIds: Set<Int>

    var body: some View {
        let days = [day]
        let expanded = state.visibleCalendarTasks(for: days)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text(day.dayName).font(.title2).bold()
                    Text(dateLong(day.dateString)).foregroundStyle(.secondary)
                }
                Spacer()
                Button(isBulk ? "Cancel" : "Select") { isBulk.toggle(); selectedIds = [] }
            }

            if expanded.isEmpty {
                CompatEmptyState(title: "No tasks for this day", systemImage: "calendar")
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(expanded) { t in
                            taskRow(t)
                        }
                    }
                }
            }

            if isBulk, !selectedIds.isEmpty {
                HStack {
                    Text("\(selectedIds.count) selected").font(.subheadline).bold()
                    Spacer()
                    Button {
                        bulkMoveToInbox(expanded: expanded)
                    } label: { Label("Move to Inbox", systemImage: "tray") }
                    Button {
                        bulkArchive(expanded: expanded)
                    } label: { Label("Archive", systemImage: "archivebox") }
                    .buttonStyle(.borderedProminent)
                    Button(role: .destructive) {
                        bulkDelete(expanded: expanded)
                    } label: { Label("Delete", systemImage: "trash") }
                }
                .padding(.top, 6)
            }
        }
        .padding()
    }

    @ViewBuilder private func taskRow(_ t: TaskItem) -> some View {
        let ring: Color = (t.status == .completed ? .green : t.status == .started ? .orange : .blue)
        HStack(alignment: .top, spacing: 12) {
            Circle().strokeBorder(ring, lineWidth: 3).frame(width: 16, height: 16).padding(.top, 4)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(t.text).font(.body).bold()
                    if t.isRecurring {
                        Label(t.recurrence?.rawValue.capitalized ?? "", systemImage: "repeat")
                            .font(.caption)
                            .padding(4)
                            .background(Color.secondary.opacity(0.15))
                            .clipShape(Capsule())
                    }
                    Spacer()
                    if isBulk {
                        Toggle("", isOn: Binding(
                            get: { selectedIds.contains(t.id) },
                            set: { newValue in
                                if newValue { selectedIds.insert(t.id) } else { selectedIds.remove(t.id) }
                            }
                        )).labelsHidden()
                    }
                }
                if let n = t.notes, !n.isEmpty {
                    Text(n).font(.subheadline).foregroundStyle(.secondary)
                }

                // Status / Recurrence / Rating controls (instance-aware)
                HStack(spacing: 8) {
                    Group {
                        Button("To Do") { state.updateStatus(t, to: .notStarted, instanceDate: day.dateString) }
                        Button("Started") { state.updateStatus(t, to: .started, instanceDate: day.dateString) }
                        Button("Done") { state.updateStatus(t, to: .completed, instanceDate: day.dateString) }
                    }.buttonStyle(.bordered)

                    Menu {
                        Button("Never") { state.updateRecurrence(t, to: .never) }
                        Button("Daily") { state.updateRecurrence(t, to: .daily) }
                        Button("Weekly") { state.updateRecurrence(t, to: .weekly) }
                        Button("Monthly") { state.updateRecurrence(t, to: .monthly) }
                    } label: {
                        Label("Repeat", systemImage: "repeat")
                    }

                    Menu {
                        Button("Like") { state.rate(t, rating: .liked, instanceDate: day.dateString) }
                        Button("Dislike") { state.rate(t, rating: .disliked, instanceDate: day.dateString) }
                        Button("Clear") { state.rate(t, rating: nil, instanceDate: day.dateString) }
                    } label: {
                        Label("Rating", systemImage: "hand.thumbsup")
                    }
                }

                HStack(spacing: 10) {
                    Button { state.archiveTask(t) } label: {
                        Label("Archive", systemImage: "archivebox")
                    }
                    Button { state.duplicate(t) } label: {
                        Label("Duplicate", systemImage: "plus.square.on.square")
                    }
                    Button { state.moveToInbox(t) } label: {
                        Label("Move to Inbox", systemImage: "tray")
                    }
                    Button(role: .destructive) { state.deleteToTrash(t) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .font(.caption)
                .tint(.secondary)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
    }

    private func bulkArchive(expanded: [TaskItem]) {
        let ids = selectedIds
        for t in expanded where ids.contains(t.id) {
            state.archiveTask(t)
        }
        selectedIds = []
        isBulk = false
    }
    private func bulkDelete(expanded: [TaskItem]) {
        let ids = selectedIds
        for t in expanded where ids.contains(t.id) {
            state.deleteToTrash(t)
        }
        selectedIds = []
        isBulk = false
    }
    private func bulkMoveToInbox(expanded: [TaskItem]) {
        let ids = selectedIds
        for t in expanded where ids.contains(t.id) {
            state.moveToInbox(t)
        }
        selectedIds = []
        isBulk = false
    }

    private func dateLong(_ ds: String) -> String {
        guard let d = ds.asISODateOnlyUTC else { return ds }
        let f = DateFormatter()
        f.timeZone = .init(secondsFromGMT: 0)
        f.dateFormat = "MMMM d, yyyy"
        return f.string(from: d)
    }
}

// MARK: - Archives (with Select mode)

private struct ArchivesView: View {
    @ObservedObject var state: AppState
    @State private var isBulk = false
    @State private var selectedIds: Set<Int> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Task Archives").font(.title2).bold()
                Spacer()
                Button(isBulk ? "Cancel" : "Select") {
                    isBulk.toggle(); selectedIds.removeAll()
                }
                Button("Back to Calendar") {
                    state.isArchiveViewActive = false
                }
                .buttonStyle(.borderedProminent)
            }

            Picker("Section", selection: $state.activeArchiveTab) {
                ForEach(ArchiveTab.allCases) { tab in
                    Text(label(tab)).tag(tab)
                }
            }
            .pickerStyle(.segmented)

            // Bulk actions bar
            if isBulk {
                HStack {
                    Button("Select All") {
                        let list = state.archivedTasks.filter { $0.archiveReason == state.activeArchiveTab.rawValue }
                        selectedIds = Set(list.map { $0.id })
                    }
                    Spacer()
                    Button {
                        // restore selected
                        let list = state.archivedTasks.filter { selectedIds.contains($0.id) }
                        for a in list { state.restoreTask(a) }
                        selectedIds.removeAll(); isBulk = false
                    } label: { Label("Restore", systemImage: "arrow.uturn.left") }
                    Button(role: .destructive) {
                        for id in selectedIds { state.deletePermanently(id) }
                        selectedIds.removeAll(); isBulk = false
                    } label: { Label("Delete", systemImage: "trash") }
                }
                .font(.subheadline)
            }

            let list = state.archivedTasks.filter { $0.archiveReason == state.activeArchiveTab.rawValue }
            if list.isEmpty {
                CompatEmptyState(title: "This archive is empty", systemImage: "tray")
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                List {
                    ForEach(list) { t in
                        HStack {
                            if isBulk {
                                Toggle("", isOn: Binding(
                                    get: { selectedIds.contains(t.id) },
                                    set: { v in if v { selectedIds.insert(t.id) } else { selectedIds.remove(t.id) } }
                                )).labelsHidden()
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(t.text).font(.body)
                                    .strikethrough(t.archiveReason == "completed")
                                Text("Archived: \(formatDateTime(t.archivedAt))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if !isBulk {
                                HStack(spacing: 8) {
                                    Button { state.restoreTask(t) } label: {
                                        Label("Restore", systemImage: "arrow.uturn.left")
                                    }
                                    Button(role: .destructive) {
                                        state.deletePermanently(t.id)
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func label(_ tab: ArchiveTab) -> String {
        switch tab {
        case .not_started: return "To Do"
        case .started:     return "Started"
        case .completed:   return "Completed"
        case .deleted:     return "Deleted"
        }
    }
}

// MARK: - Stats (Summary ↔︎ Chart)

private struct StatsView: View {
    @ObservedObject var state: AppState

    var body: some View {
        // time window: last 8 weeks for chart/summary
        let cal = Calendar(identifier: .iso8601)
        let now = Date()
        let startOfWeek = cal.date(from: cal.dateComponents([.yearForWeekOfYear,.weekOfYear], from: now)) ?? now
        let startRange = cal.date(byAdding: .day, value: -7*7, to: startOfWeek) ?? now // 8 weeks window
        let range = startRange...now

        let (period, buckets) = state.stats(for: range, granularity: "week")

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("Task Statistics").font(.title2).bold()
                Spacer()
                Picker("View", selection: $state.statsViewType) {
                    Text("Summary").tag(StatsViewType.summary)
                    Text("Bar Chart").tag(StatsViewType.barchart)
                }
                .pickerStyle(.segmented)

                Button("Back to Calendar") {
                    state.isStatsViewActive = false
                }
                .buttonStyle(.borderedProminent)
            }

            if state.statsViewType == .summary {
                // KPI tiles
                HStack {
                    statCard(title: "Completed", value: period.completed, tint: .green)
                    statCard(title: "Open", value: period.open, tint: .orange)
                    statCard(title: "Total", value: period.total, tint: .primary)
                    let rate = period.total > 0 ? Int(round(Double(period.completed) / Double(period.total) * 100.0)) : 0
                    statCard(title: "Completion Rate", value: rate, suffix: "%", tint: .green)
                }

                // Ratings breakdown
                GroupBox("Ratings (in window)") {
                    HStack {
                        statCard(title: "👍 Done", value: period.likedCompleted, tint: .green)
                        statCard(title: "👎 Done", value: period.dislikedCompleted, tint: .red)
                        statCard(title: "👍 Open", value: period.likedOpen, tint: .blue)
                        statCard(title: "👎 Open", value: period.dislikedOpen, tint: .orange)
                    }
                }

            } else {
                // Bar chart view
                GroupBox("Weekly breakdown (last 8 weeks)") {
                    if #available(iOS 16.0, *) {
                        // Convert buckets (key = week start yyyy-MM-dd) to sorted series
                        let keys = buckets.keys.sorted()
                        let series = keys.map { k -> (label: String, c: Int, o: Int) in
                            let weekNum = Calendar(identifier: .iso8601).component(.weekOfYear, from: k.asISODateOnlyUTC ?? now)
                            let b = buckets[k] ?? (0,0)
                            return ("CW \(weekNum)", b.completed, b.open)
                        }
                        Chart {
                            ForEach(series, id: \.label) { w in
                                BarMark(x: .value("Week", w.label), y: .value("Completed", w.c))
                                BarMark(x: .value("Week", w.label), y: .value("Open", w.o))
                                    .foregroundStyle(.orange)
                            }
                        }
                        .frame(height: 240)
                    } else {
                        Text("Charts require iOS 16+.").frame(height: 60)
                    }
                }
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func statCard(title: String, value: Int, suffix: String = "", tint: Color) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text("\(value)\(suffix)").font(.title3).bold().foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
    }
}

// MARK: - Small UI helpers

private struct TogglePill: View {
    let label: String
    @Binding var isOn: Bool
    var tint: Color = .blue

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Text(label).font(.caption).bold()
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(isOn ? tint : Color(.secondarySystemBackground))
                .foregroundStyle(isOn ? Color.white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private func formatDateTime(_ d: Date?) -> String {
    guard let d = d else { return "—" }
    let f = DateFormatter()
    f.dateStyle = .medium
    f.timeStyle = .short
    return f.string(from: d)
}
