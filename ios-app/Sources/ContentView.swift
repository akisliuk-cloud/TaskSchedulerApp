// ios-app/Sources/ContentView.swift
import SwiftUI
import Charts

// MARK: - Tabs
private enum MainTab: Hashable { case home, stats, camera, archive, settings }

// MARK: - Root
struct ContentView: View {
    @StateObject private var state = AppState()

    // Nav + header/search
    @State private var tab: MainTab = .home
    @State private var isSearchVisible = false

    // Day modal
    @State private var showingDay: CalendarDay? = nil

    // Collapsible sections
    @State private var isCalendarExpanded = true
    @State private var isInboxExpanded = true

    // New task
    @State private var newTaskText = ""

    // Snackbar (undo)
    @State private var snackbarMessage: String = ""
    @State private var showSnackbar = false
    @State private var snackbarUndoAction: (() -> Void)? = nil

    // Calendar filter cache (icon menu writes into state.calendarFilters)
    @State private var filterOpen = true
    @State private var filterStarted = true
    @State private var filterDone = true

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 12) {
                header

                if isSearchVisible {
                    TextField("Search tasks…", text: $state.searchQuery)
                        .textFieldStyle(.roundedBorder)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                Group {
                    switch tab {
                    case .home:
                        HomeScreen(
                            state: state,
                            isCalendarExpanded: $isCalendarExpanded,
                            isInboxExpanded: $isInboxExpanded,
                            onShowDay: { showingDay = $0 },
                            onAddTask: addTaskWithUndo(_:),
                            filterOpen: $filterOpen,
                            filterStarted: $filterStarted,
                            filterDone: $filterDone,
                            showUndo: showUndo(_:undo:)
                        )
                    case .stats:
                        StatsScreen(state: state)
                    case .archive:
                        ArchivesScreen(state: state)
                    case .camera:
                        CameraPlaceholder()
                    case .settings:
                        SettingsScreen()
                    }
                }

                bottomBar
            }
            .padding([.horizontal, .top])
            .padding(.bottom, 8)

            if showSnackbar {
                SnackbarView(message: snackbarMessage) {
                    snackbarUndoAction?()
                    hideSnackbar()
                } onDismiss: { hideSnackbar() }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .padding(.bottom, 60)
            }
        }
        .sheet(item: $showingDay) { day in
            DayModalView(day: day, state: state) { kind, _ in
                switch kind {
                case .archive:      showUndo("Task archived")     { state.undoToLastSnapshot() }
                case .delete:       showUndo("Task deleted")      { state.undoToLastSnapshot() }
                case .duplicate:    showUndo("Task duplicated")   { state.undoToLastSnapshot() }
                case .moveToInbox:  showUndo("Moved to Inbox")    { state.undoToLastSnapshot() }
                case .reschedule:   showUndo("Task rescheduled")  { state.undoToLastSnapshot() }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: Header
    private var header: some View {
        HStack(spacing: 12) {
            Text("Taskmate")
                .font(.title.bold()) // slightly smaller than largeTitle
            Spacer()
        }
    }

    // MARK: Bottom bar
    private var bottomBar: some View {
        HStack {
            BarIcon(system: "house", isActive: tab == .home) {
                tab = .home; isSearchVisible = false
            }
            BarIcon(system: "chart.bar.xaxis", isActive: tab == .stats) {
                tab = .stats; isSearchVisible = false
            }
            BarIcon(system: "camera", isActive: tab == .camera) {
                tab = .camera; isSearchVisible = false
            }
            BarIcon(system: "archivebox", isActive: tab == .archive) {
                tab = .archive; isSearchVisible = false
            }
            BarIcon(system: "magnifyingglass", isActive: isSearchVisible) {
                withAnimation { isSearchVisible.toggle() }
            }
            BarIcon(system: "gearshape", isActive: tab == .settings) {
                tab = .settings; isSearchVisible = false
            }
        }
        .padding(.horizontal)
        .frame(height: 52)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: Undo helpers
    private func showUndo(_ message: String, undo: @escaping () -> Void) {
        snackbarMessage = message
        snackbarUndoAction = undo
        withAnimation { showSnackbar = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { hideSnackbar() }
    }
    private func hideSnackbar() {
        withAnimation { showSnackbar = false }
        snackbarUndoAction = nil
    }

    private func addTaskWithUndo(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        state.snapshotForUndo()
        state.addTask(text: text)
        showUndo("Task added") { state.undoToLastSnapshot() }
    }
}

// MARK: - Home Screen (Calendar + Task List)
private struct HomeScreen: View {
    @ObservedObject var state: AppState
    @Binding var isCalendarExpanded: Bool
    @Binding var isInboxExpanded: Bool

    var onShowDay: (CalendarDay) -> Void
    var onAddTask: (String) -> Void

    @Binding var filterOpen: Bool
    @Binding var filterStarted: Bool
    @Binding var filterDone: Bool

    var showUndo: (_ msg: String, _ undo: @escaping () -> Void) -> Void

    @State private var newTaskText = ""

    var body: some View {
        VStack(spacing: 12) {
            SectionCard(title: "Daily Calendar",
                        isExpanded: $isCalendarExpanded,
                        trailing: { calendarControls }) {
                if isCalendarExpanded { calendarPanel }
            }

            SectionCard(title: "Task List",
                        isExpanded: $isInboxExpanded,
                        trailing: { InboxHeaderControls(state: state) }) {
                if isInboxExpanded { inboxPanel }
            }

            if state.isBulkSelectActiveInbox, !state.selectedInboxTaskIds.isEmpty {
                BulkBar(selectedCount: state.selectedInboxTaskIds.count,
                        onArchive: {
                            state.snapshotForUndo()
                            state.archiveSelectedInbox()
                            showUndo("Tasks archived") { state.undoToLastSnapshot() }
                        },
                        onDelete: {
                            state.snapshotForUndo()
                            state.deleteSelectedInbox()
                            showUndo("Tasks deleted") { state.undoToLastSnapshot() }
                        })
                .transition(.move(edge: .bottom))
            }
        }
    }

    // MARK: Calendar controls (icon only)
    private var calendarControls: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation {
                    state.calendarStartDate = Calendar.current.date(byAdding: .day, value: -3, to: Date()) ?? Date()
                }
            } label: { Image(systemName: "calendar") }
            .buttonStyle(.bordered)

            Menu {
                Toggle("Open", isOn: Binding(
                    get: { filterOpen },
                    set: { v in filterOpen = v; state.calendarFilters[.notStarted] = v }
                ))
                Toggle("Started", isOn: Binding(
                    get: { filterStarted },
                    set: { v in filterStarted = v; state.calendarFilters[.started] = v }
                ))
                Toggle("Done", isOn: Binding(
                    get: { filterDone },
                    set: { v in filterDone = v; state.calendarFilters[.completed] = v }
                ))
            } label: { Image(systemName: "line.3.horizontal.decrease.circle") }
            .buttonStyle(.bordered)

            Button {
                withAnimation {
                    state.calendarViewMode = (state.calendarViewMode == .card ? .list : .card)
                }
            } label: { Image(systemName: state.calendarViewMode == .card ? "square.grid.2x2" : "list.bullet") }
            .buttonStyle(.bordered)
        }
    }

    // MARK: Calendar
    private var calendarPanel: some View {
        let days = state.calendarDays()
        let expanded = state.visibleCalendarTasks(for: days)
        let tasksByDay = Dictionary(grouping: expanded) { $0.date ?? "" }

        return Group {
            if state.calendarViewMode == .card {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(days) { day in
                            let list = (tasksByDay[day.dateString] ?? [])
                                .filter { state.calendarFilters[$0.status] ?? true }
                            DayCard(day: day, tasks: list) { onShowDay(day) }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(height: 170)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(days) { day in
                            let list = (tasksByDay[day.dateString] ?? [])
                                .filter { state.calendarFilters[$0.status] ?? true }
                            if state.searchQuery.isEmpty && list.isEmpty {
                                EmptyView()
                            } else {
                                DayRow(day: day, tasks: list) { onShowDay(day) }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(minHeight: 200, maxHeight: 260)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
        )
    }

    // MARK: Inbox
    private var inboxPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("Add a new task…", text: $newTaskText, onCommit: {
                    onAddTask(newTaskText); newTaskText = ""
                })
                .textFieldStyle(.roundedBorder)
                Button {
                    onAddTask(newTaskText); newTaskText = ""
                } label: { Image(systemName: "plus") }
                .buttonStyle(.borderedProminent)
            }

            if state.unassignedTasks.isEmpty {
                CompatEmptyState(title: "No unassigned tasks", systemImage: "tray")
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(state.unassignedTasks) { t in
                        InboxRow(
                            t: t,
                            isSelecting: state.isBulkSelectActiveInbox,
                            isChecked: state.selectedInboxTaskIds.contains(t.id),
                            onToggleCheck: {
                                if state.selectedInboxTaskIds.contains(t.id) {
                                    state.selectedInboxTaskIds.remove(t.id)
                                } else {
                                    state.selectedInboxTaskIds.insert(t.id)
                                }
                            },
                            onMoreAction: { action in
                                switch action {
                                case .delete:
                                    state.snapshotForUndo()
                                    state.deleteToTrash(t)
                                    showUndo("Task deleted") { state.undoToLastSnapshot() }
                                case .duplicate:
                                    state.snapshotForUndo()
                                    state.duplicate(t)
                                    showUndo("Task duplicated") { state.undoToLastSnapshot() }
                                case .archive:
                                    state.snapshotForUndo()
                                    state.archiveTask(t)
                                    showUndo("Task archived") { state.undoToLastSnapshot() }
                                case .edit:
                                    // Hook your edit sheet if desired
                                    break
                                case .moveToInbox:
                                    // already inbox
                                    break
                                }
                            },
                            onRate: { r in state.rate(t, rating: r, instanceDate: nil) },
                            onSetRecurrence: { rec in state.updateRecurrence(t, to: rec) }
                        )
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
        )
    }
}

// MARK: - Section Card
private struct SectionCard<Content: View, Trailing: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    let trailing: () -> Trailing
    let content: () -> Content

    init(title: String,
         isExpanded: Binding<Bool>,
         trailing: @escaping () -> Trailing,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self._isExpanded = isExpanded
        self.trailing = trailing
        self.content = content
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Button {
                    withAnimation { isExpanded.toggle() }
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.subheadline)
                }
                .buttonStyle(.plain)

                Text(title).font(.title3.bold())
                Spacer()
                trailing()
            }
            content()
        }
    }
}

// MARK: - Small bottom bar icon
private struct BarIcon: View {
    let system: String
    let isActive: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isActive ? Color.accentColor : Color.primary)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 8)
    }
}

// MARK: - Calendar Day card / row
private struct DayCard: View {
    let day: CalendarDay
    let tasks: [TaskItem]
    var onTap: () -> Void

    var body: some View {
        let isToday = day.dateString == ISO8601.dateOnly.string(from: Date())
        let done = tasks.filter { $0.status == .completed }.count
        let started = tasks.filter { $0.status == .started }.count
        let open = tasks.filter { $0.status == .notStarted }.count

        VStack(alignment: .leading, spacing: 6) {
            Text(day.dayName).font(.caption).foregroundStyle(isToday ? .blue : .secondary)
            Text("\(day.dayOfMonth)").font(.title2).fontWeight(.semibold)
                .foregroundStyle(isToday ? .blue : .primary)
            Spacer()
            VStack(alignment: .leading, spacing: 4) {
                if done > 0 { badge("\(done) done", .green) }
                if started > 0 { badge("\(started) started", .orange) }
                if open > 0 { badge("\(open) open", .blue) }
            }
        }
        .padding(10)
        .frame(width: 112, height: 150)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isToday ? .blue : Color.gray.opacity(0.2), lineWidth: isToday ? 2 : 1)
                )
                .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 1)
        )
        .onTapGesture { onTap() }
    }

    @ViewBuilder private func badge(_ text: String, _ color: Color) -> some View {
        Text(text).font(.caption2).bold()
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.15))
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
        let open = tasks.filter { $0.status == .notStarted }.count

        HStack {
            Text(dateLong(day.dateString))
                .font(.subheadline).fontWeight(.semibold)
                .foregroundStyle(isToday ? .blue : .primary)
            Spacer()
            HStack(spacing: 6) {
                if open > 0 { chip("\(open)", .blue) }
                if started > 0 { chip("\(started)", .orange) }
                if done > 0 { chip("\(done)", .green) }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(isToday ? .blue : Color.gray.opacity(0.2)))
                .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
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
            .background(color.opacity(0.15))
            .foregroundStyle(color).clipShape(Capsule())
    }
}

// MARK: - Inbox Row
private enum InboxRowAction { case delete, duplicate, archive, edit, moveToInbox }

private struct InboxRow: View {
    let t: TaskItem
    let isSelecting: Bool
    let isChecked: Bool
    let onToggleCheck: () -> Void
    let onMoreAction: (InboxRowAction) -> Void
    let onRate: (TaskRating?) -> Void
    let onSetRecurrence: (Recurrence) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if isSelecting {
                Button(action: onToggleCheck) {
                    Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 6) {
                    Text(t.text).font(.body.weight(.semibold))
                    if t.isRecurring {
                        Image(systemName: "repeat").foregroundStyle(.secondary).imageScale(.small)
                    }
                    Spacer()
                    Menu {
                        Button("Edit") { onMoreAction(.edit) }
                        Button("Duplicate") { onMoreAction(.duplicate) }
                        Button("Archive") { onMoreAction(.archive) }
                        Button(role: .destructive) { onMoreAction(.delete) } label: { Text("Delete") }
                    } label: { Image(systemName: "ellipsis.circle").imageScale(.large) }
                }

                if let ds = t.date, !ds.isEmpty {
                    Text("Scheduled for \(ds)").font(.caption).foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    Menu {
                        Button("Never")   { onSetRecurrence(.never) }
                        Button("Daily")   { onSetRecurrence(.daily) }
                        Button("Weekly")  { onSetRecurrence(.weekly) }
                        Button("Monthly") { onSetRecurrence(.monthly) }
                    } label: { Image(systemName: "repeat") }

                    Button {
                        let current = t.completedOverrides?[t.date ?? ""]?.rating
                        let next: TaskRating? = {
                            switch current {
                            case nil: return .liked
                            case .liked: return .disliked
                            case .disliked: return nil
                            }
                        }()
                        onRate(next)
                    } label: {
                        let r = t.completedOverrides?[t.date ?? ""]?.rating
                        Image(systemName:
                                r == .liked ? "hand.thumbsup.fill" :
                                r == .disliked ? "hand.thumbsdown.fill" :
                                "hand.thumbsup")
                    }
                }
                .tint(.primary.opacity(0.85))
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.2)))
        )
    }
}

// MARK: - Day Modal
private enum DayActionKind { case archive, delete, duplicate, moveToInbox, reschedule }

private struct DayModalView: View {
    let day: CalendarDay
    @ObservedObject var state: AppState
    var onAction: (DayActionKind, TaskItem) -> Void

    @State private var isSelecting = false
    @State private var selectedIds = Set<Int>()

    var body: some View {
        let expanded = state.visibleCalendarTasks(for: [day])
        VStack(alignment: .leading, spacing: 12) {
            header(expanded: expanded)
            if expanded.isEmpty {
                CompatEmptyState(title: "No tasks for this day", systemImage: "calendar")
            } else {
                ScrollView { tasksList(expanded: expanded) }
            }
            if isSelecting, !selectedIds.isEmpty { bulkBar(expanded: expanded) }
        }
        .padding()
    }

    @ViewBuilder private func header(expanded: [TaskItem]) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(day.dayName).font(.title2).bold()
                Text(dateLong(day.dateString)).foregroundStyle(.secondary)
            }
            Spacer()
            Button(isSelecting ? "Cancel" : "Select") {
                withAnimation { isSelecting.toggle(); selectedIds.removeAll() }
            }
        }
    }

    @ViewBuilder private func tasksList(expanded: [TaskItem]) -> some View {
        VStack(spacing: 8) {
            ForEach(expanded) { t in
                TaskLine(
                    t: t,
                    dayString: day.dateString,
                    isSelecting: isSelecting,
                    isChecked: selectedIds.contains(t.id),
                    onToggleCheck: {
                        if selectedIds.contains(t.id) { selectedIds.remove(t.id) } else { selectedIds.insert(t.id) }
                    },
                    onStatus: { s in state.updateStatus(t, to: s, instanceDate: day.dateString) },
                    onSetRecurrence: { r in state.updateRecurrence(t, to: r) },
                    onRate: {
                        let current = t.completedOverrides?[day.dateString]?.rating
                        let next: TaskRating? = {
                            switch current {
                            case nil: return .liked
                            case .liked: return .disliked
                            case .disliked: return nil
                            }
                        }()
                        state.rate(t, rating: next, instanceDate: day.dateString)
                    },
                    onMore: { action in
                        state.snapshotForUndo()
                        switch action {
                        case .archive:
                            state.archiveTask(t); onAction(.archive, t)
                        case .duplicate:
                            state.duplicate(t); onAction(.duplicate, t)
                        case .moveToInbox:
                            state.moveToInbox(t); onAction(.moveToInbox, t)
                        case .delete:
                            state.deleteToTrash(t); onAction(.delete, t)
                        case .edit:
                            break
                        }
                    }
                )
            }
        }
    }

    @ViewBuilder private func bulkBar(expanded: [TaskItem]) -> some View {
        HStack {
            Text("\(selectedIds.count) selected").font(.subheadline).bold()
            Spacer()
            Button {
                state.snapshotForUndo()
                for t in expanded where selectedIds.contains(t.id) { state.moveToInbox(t) }
                selectedIds.removeAll(); isSelecting = false
                if let first = expanded.first { onAction(.moveToInbox, first) }
            } label: { Label("Move to Inbox", systemImage: "tray") }

            Button {
                state.snapshotForUndo()
                for t in expanded where selectedIds.contains(t.id) { state.archiveTask(t) }
                selectedIds.removeAll(); isSelecting = false
                if let first = expanded.first { onAction(.archive, first) }
            } label: { Label("Archive", systemImage: "archivebox") }
            .buttonStyle(.borderedProminent)

            Button(role: .destructive) {
                state.snapshotForUndo()
                for t in expanded where selectedIds.contains(t.id) { state.deleteToTrash(t) }
                selectedIds.removeAll(); isSelecting = false
                if let first = expanded.first { onAction(.delete, first) }
            } label: { Label("Delete", systemImage: "trash") }
        }
        .padding(.top, 6)
    }

    private func dateLong(_ ds: String) -> String {
        guard let d = ds.asISODateOnlyUTC else { return ds }
        let f = DateFormatter()
        f.timeZone = .init(secondsFromGMT: 0)
        f.dateFormat = "MMMM d, yyyy"
        return f.string(from: d)
    }
}

private struct TaskLine: View {
    let t: TaskItem
    let dayString: String
    let isSelecting: Bool
    let isChecked: Bool
    let onToggleCheck: () -> Void
    let onStatus: (TaskStatus) -> Void
    let onSetRecurrence: (Recurrence) -> Void
    let onRate: () -> Void
    let onMore: (InboxRowAction) -> Void

    var body: some View {
        VStack(spacing: 8) {
            headerRow
            statusRow
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.2)))
    }

    private var headerRow: some View {
        HStack(alignment: .top, spacing: 12) {
            if isSelecting {
                Button(action: onToggleCheck) {
                    Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(t.text).font(.body.bold())
                    if t.isRecurring { Image(systemName: "repeat").foregroundStyle(.secondary) }
                    Spacer()

                    Menu {
                        Button("Never") { onSetRecurrence(.never) }
                        Button("Daily") { onSetRecurrence(.daily) }
                        Button("Weekly") { onSetRecurrence(.weekly) }
                        Button("Monthly") { onSetRecurrence(.monthly) }
                    } label: { Image(systemName: "repeat") }

                    Button(action: onRate) {
                        let r = t.completedOverrides?[dayString]?.rating
                        Image(systemName:
                                r == .liked ? "hand.thumbsup.fill" :
                                r == .disliked ? "hand.thumbsdown.fill" :
                                "hand.thumbsup")
                    }

                    Menu {
                        Button("Edit") { onMore(.edit) }
                        Button("Duplicate") { onMore(.duplicate) }
                        Button("Archive") { onMore(.archive) }
                        Button("Move to Inbox") { onMore(.moveToInbox) }
                        Button(role: .destructive) { onMore(.delete) } label: { Text("Delete") }
                    } label: { Image(systemName: "ellipsis.circle").imageScale(.large) }
                }
            }
        }
    }

    private var statusRow: some View {
        HStack(spacing: 6) {
            Button("Open") { onStatus(.notStarted) }
                .buttonStyle(.bordered)
                .tint(t.status == .notStarted ? .blue : .gray.opacity(0.5))
                .font(.caption)

            Button("Started") { onStatus(.started) }
                .buttonStyle(.bordered)
                .tint(t.status == .started ? .orange : .gray.opacity(0.5))
                .font(.caption)

            Button("Done") { onStatus(.completed) }
                .buttonStyle(.bordered)
                .tint(t.status == .completed ? .green : .gray.opacity(0.5))
                .font(.caption)
        }
    }
}

// MARK: - Archives
private struct ArchivesScreen: View {
    @ObservedObject var state: AppState
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Archives").font(.title2).bold()

            Picker("Section", selection: $state.activeArchiveTab) {
                ForEach(ArchiveTab.allCases) { tab in
                    Text(label(tab)).tag(tab)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Spacer()
                Button(role: .destructive) {
                    state.emptyArchive(reason: state.activeArchiveTab)
                } label: { Label("Empty \(label(state.activeArchiveTab))", systemImage: "trash") }
            }

            let list = state.archivedTasks.filter { $0.archiveReason == state.activeArchiveTab.rawValue }
            if list.isEmpty {
                CompatEmptyState(title: "This archive is empty", systemImage: "tray")
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                List {
                    ForEach(list) { t in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(t.text).font(.body)
                                    .strikethrough(t.archiveReason == "completed")
                                Text("Archived: \(formatDateTime(t.archivedAt))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            HStack(spacing: 8) {
                                Button { state.restoreTask(t) } label: { Label("Restore", systemImage: "arrow.uturn.left") }
                                Button(role: .destructive) { state.deletePermanently(t.id) } label: { Image(systemName: "trash") }
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .padding()
    }

    private func label(_ tab: ArchiveTab) -> String {
        switch tab {
        case .not_started: return "Open"
        case .started:     return "Started"
        case .completed:   return "Completed"
        case .deleted:     return "Deleted"
        }
    }
}

// MARK: - Stats
private struct StatsScreen: View {
    @ObservedObject var state: AppState
    var body: some View {
        let (series, _) = state.weeklySeries(lastWeeks: 8)
        let counts = (
            completed: series.reduce(0) { $0 + $1.completed },
            started: series.reduce(0) { $0 + $1.open } - 0,
            open: series.reduce(0) { $0 + $1.open },
            total: series.reduce(0) { $0 + $1.completed + $1.open }
        )

        return VStack(alignment: .leading, spacing: 12) {
            Text("Stats").font(.title2).bold()

            KPIBars(completed: counts.completed, started: counts.started, open: counts.open, total: counts.total)

            GroupBox("Last 8 weeks") {
                if #available(iOS 16.0, *) {
                    Chart {
                        ForEach(series, id: \.label) { w in
                            BarMark(x: .value("Week", w.label), y: .value("Completed", w.completed))
                            BarMark(x: .value("Week", w.label), y: .value("Open", w.open))
                                .foregroundStyle(.orange)
                        }
                    }
                    .frame(height: 220)
                } else {
                    Text("Charts requires iOS 16+.").frame(height: 60)
                }
            }
        }
        .padding()
    }
}

// MARK: - Settings
private struct SettingsScreen: View {
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    VStack { Spacer(minLength: 0) }
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(Color.gray.opacity(0.2)))
                        .overlay(Image(systemName: "person.fill").foregroundStyle(.secondary))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Adrian Kisliuk").font(.headline)
                        Text("a.kisliuk@gmail.com").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                Divider()

                List {
                    NavigationLink("Manage Teams") { PlaceholderSettingsDetail(title: "Manage Teams") }
                    NavigationLink("Subscription") { PlaceholderSettingsDetail(title: "Subscription") }
                    NavigationLink("Billing") { PlaceholderSettingsDetail(title: "Billing") }
                    NavigationLink("Languages") { PlaceholderSettingsDetail(title: "Languages") }
                    NavigationLink("Privacy Policy") { PlaceholderSettingsDetail(title: "Privacy Policy") }
                    NavigationLink("Terms of Use") { PlaceholderSettingsDetail(title: "Terms of Use") }
                    NavigationLink("Theme") { ThemeSettingsView() }
                    Button("Log in/out") { }
                }
                .listStyle(.insetGrouped)

                Spacer()
            }
            .padding()
            .navigationTitle("Settings")
        }
    }
}

private struct PlaceholderSettingsDetail: View {
    let title: String
    var body: some View {
        VStack { Text(title).font(.title2).bold(); Spacer() }
            .padding()
    }
}

private struct ThemeSettingsView: View {
    @State private var chosen: String = "System Mode"
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Theme", selection: $chosen) {
                Text("Dark").tag("Dark")
                Text("Light").tag("Light")
                Text("System Mode").tag("System Mode")
            }
            .pickerStyle(.inline)

            Text("Selecting Dark or Light will apply immediately. System Mode follows device settings.")
                .font(.footnote).foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
        .navigationTitle("Theme")
        .onChange(of: chosen) { _, _ in } // iOS 17 signature
    }
}

// MARK: - Small helpers

private struct CameraPlaceholder: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera").font(.system(size: 48, weight: .regular))
            Text("Camera").font(.headline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

private struct InboxHeaderControls: View {
    @ObservedObject var state: AppState
    var body: some View {
        HStack(spacing: 8) {
            Button(state.isBulkSelectActiveInbox ? "Cancel" : "Select") {
                withAnimation { state.toggleBulkSelectInbox() }
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Toggle bulk select")
        }
    }
}

private struct KPIBars: View {
    let completed: Int
    let started: Int
    let open: Int
    let total: Int

    private var safeTotal: CGFloat {
        let s = completed + started + open
        return CGFloat(max(total, s, 1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geo in
                let width = geo.size.width
                let cW = width * (CGFloat(completed) / safeTotal)
                let sW = width * (CGFloat(started) / safeTotal)
                let oW = width * (CGFloat(open) / safeTotal)

                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 6).fill(Color.green.opacity(completed > 0 ? 0.9 : 0.2)).frame(width: cW, height: 12)
                    RoundedRectangle(cornerRadius: 0).fill(Color.orange.opacity(started > 0 ? 0.9 : 0.2)).frame(width: sW, height: 12)
                    RoundedRectangle(cornerRadius: 6).fill(Color.blue.opacity(open > 0 ? 0.9 : 0.2)).frame(width: oW, height: 12)
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .frame(height: 14)

            HStack(spacing: 16) {
                legendDot(color: .green, label: "Completed \(completed)")
                legendDot(color: .orange, label: "Started \(started)")
                legendDot(color: .blue, label: "Open \(open)")
                Spacer()
                Text("Total \(total)").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.caption)
        }
    }
}

private struct SnackbarView: View {
    let message: String
    let onUndo: () -> Void
    let onDismiss: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            Text(message)
            Spacer()
            Button("Undo", action: onUndo).buttonStyle(.bordered)
            Button(action: onDismiss) { Image(systemName: "xmark") }.buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.horizontal)
    }
}

private struct CompatEmptyState: View {
    let title: String
    let systemImage: String
    var body: some View {
        if #available(iOS 17.0, *) {
            ContentUnavailableView(title, systemImage: systemImage)
        } else {
            VStack(spacing: 12) {
                Image(systemName: systemImage).font(.system(size: 40)).foregroundColor(.secondary)
                Text(title).font(.headline).foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private func formatDateTime(_ d: Date?) -> String {
    guard let d = d else { return "—" }
    let f = DateFormatter()
    f.dateStyle = .medium; f.timeStyle = .short
    return f.string(from: d)
}
