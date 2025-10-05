import SwiftUI
import Foundation
import Charts

// MARK: - Small helpers for scroll targets
private func dayCardID(_ dateStr: String) -> String { "card-\(dateStr)" }
private func dayListID(_ dateStr: String) -> String { "list-\(dateStr)" }

// MARK: - Reusable empty state
struct CompatEmptyState: View {
    let title: String
    let systemImage: String
    var body: some View {
        Group {
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
}

// MARK: - ContentView
struct ContentView: View {
    @StateObject private var state = AppState()

    // Sheets / modals
    @State private var showingDay: CalendarDay? = nil
    @State private var isDayBulk = false
    @State private var daySelectedIds = Set<Int>()

    @State private var showSettings = false
    @State private var showTheme = false

    // Header
    @State private var showSearchBar = false

    // Collapsible sections
    @State private var showCalendar = true
    @State private var showInbox = true

    // App appearance
    @State private var colorSchemeOverride: ColorScheme? = nil   // nil == system mode

    // Bottom menu selection
    enum Tab { case home, stats, camera, archive, search, settings }
    @State private var tab: Tab = .home

    // Snackbar / undo
    @State private var snackbarMessage = ""
    @State private var showSnackbar = false
    @State private var snackbarTimer: Timer? = nil

    // Editing
    @State private var editingTask: TaskItem? = nil
    @State private var editingInstanceDate: String? = nil  // for calendar edit

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 12) {
                header
                if showSearchBar {
                    SearchBar(text: $state.searchQuery)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                mainPanels
                    .animation(.easeInOut(duration: 0.2), value: showCalendar)
                    .animation(.easeInOut(duration: 0.2), value: showInbox)
            }
            .padding([.horizontal, .top])
            .preferredColorScheme(colorSchemeOverride)

            bottomTabBar
        }
        .sheet(item: $showingDay) { day in
            DayModalView(
                day: day,
                state: state,
                isBulk: $isDayBulk,
                selectedIds: $daySelectedIds,
                onDelete: { t in performWithUndo("Deleted", { state.deleteToTrash(t) }) },
                onMoveToInbox: { t in performWithUndo("Moved to Inbox", { state.moveToInbox(t) }) },
                onDuplicate: { t in performWithUndo("Duplicated", { state.duplicate(t) }) },
                onArchive: { t in performWithUndo("Archived", { state.archiveTask(t) }) },
                onEdit: { t, ds in editingTask = t; editingInstanceDate = ds }
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(
                isDark: Binding(
                    get: { colorSchemeOverride == .dark },
                    set: { colorSchemeOverride = $0 ? .dark : nil }
                ),
                onOpenTheme: { showTheme = true }
            )
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showTheme) {
            ThemePickerSheet(
                selected: Binding(
                    get: {
                        if colorSchemeOverride == .dark { return .dark }
                        if colorSchemeOverride == .light { return .light }
                        return .system
                    },
                    set: { mode in
                        switch mode {
                        case .dark: colorSchemeOverride = .dark
                        case .light: colorSchemeOverride = .light
                        case .system: colorSchemeOverride = nil
                        }
                    }
                )
            )
            .presentationDetents([.medium])
        }
        .sheet(item: $editingTask) { t in
            TaskEditSheet(
                task: t,
                instanceDate: editingInstanceDate,
                initialMeta: state.taskMeta[t.id] ?? .init(),
                onSave: { updated, meta in
                    if let idx = state.tasks.firstIndex(where: { $0.id == t.id }) {
                        state.tasks[idx] = updated
                        state.taskMeta[t.id] = meta
                    }
                }
            )
            .presentationDetents([.large])
        }
        .overlay(alignment: .bottom) {
            if showSnackbar {
                Snackbar(message: snackbarMessage, onUndo: {
                    state.undoToLastSnapshot()
                    hideSnackbar()
                })
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .padding(.bottom, 70) // above the tab bar
            }
        }
    }

    // MARK: Header
    private var header: some View {
        VStack(spacing: 6) {
            HStack {
                // App name updated + smaller
                Text("Taskmate")
                    .font(.title2).bold()
                Spacer()
            }
        }
    }

    // MARK: Main panels (collapsible + dynamic)
    private var mainPanels: some View {
        VStack(spacing: 12) {
            // Collapsible Daily Calendar
            PanelShell(
                title: "Daily Calendar",
                isExpanded: $showCalendar
            ) {
                CalendarPanel(
                    state: state,
                    openDay: { showingDay = $0 },
                    onRescheduleWithUndo: { task, ds in
                        performWithUndo("Rescheduled", { state.reschedule(task, to: ds) })
                    }
                )
                .frame(maxHeight: 310)
            }
            .opacity((tab == .home) ? 1 : 0)
            .animation(.default, value: tab == .home)

            // Collapsible Task List with trailing "Select"
            PanelShell(
                title: "Task List",
                isExpanded: $showInbox,
                trailing: {
                    Button(state.isBulkSelectActiveInbox ? "Cancel" : "Select") {
                        state.toggleBulkSelectInbox()
                    }
                    .font(.subheadline)
                }
            ) {
                InboxPanel(
                    state: state,
                    onDelete: { t in performWithUndo("Deleted", { state.deleteToTrash(t) }) },
                    onDuplicate: { t in performWithUndo("Duplicated", { state.duplicate(t) }) },
                    onArchive: { t in performWithUndo("Archived", { state.archiveTask(t) }) },
                    onMoveToInbox: { t in performWithUndo("Moved to Inbox", { state.moveToInbox(t) }) },
                    onEdit: { t in editingTask = t; editingInstanceDate = nil },
                    onSnapshot: { state.snapshotForUndo() },
                    onBulkArchive: {
                        performWithUndo("Archived", { state.archiveSelectedInbox() })
                    },
                    onBulkDelete: {
                        performWithUndo("Deleted", { state.deleteSelectedInbox() })
                    }
                )
                .frame(maxHeight: 360)
            }

            // Archives / Stats panels depending on tab
            if tab == .archive {
                ArchivesView(state: state)
            }
            if tab == .stats {
                StatsViewContainer(state: state)
            }
        }
    }

    // MARK: Bottom tab bar (fixed)
    private var bottomTabBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                TabIcon("house", isActive: tab == .home) {
                    tab = .home
                    state.isArchiveViewActive = false
                    state.isStatsViewActive = false
                    showSearchBar = false   // hide search on Home tap
                }
                TabIcon("chart.bar.fill", isActive: tab == .stats) {
                    tab = .stats
                    state.isStatsViewActive = true
                    state.isArchiveViewActive = false
                    showSearchBar = false   // hide search on Stats tap
                }
                TabIcon("camera", isActive: tab == .camera) { tab = .camera } // turns blue only
                TabIcon("archivebox.fill", isActive: tab == .archive) {
                    tab = .archive
                    state.isArchiveViewActive = true
                    state.isStatsViewActive = false
                    showSearchBar = false   // hide search on Archive tap
                }
                TabIcon("magnifyingglass", isActive: tab == .search) {
                    tab = .search
                    showSearchBar = true    // search bar under title, all tabs
                }
                TabIcon("gearshape.fill", isActive: tab == .settings) {
                    tab = .settings
                    showSearchBar = false
                    showSettings = true     // open Settings sheet
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private func TabIcon(_ systemName: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .imageScale(.large)
                .foregroundStyle(isActive ? .blue : .primary)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    // MARK: Undo helpers
    private func performWithUndo(_ message: String, _ mutation: () -> Void) {
        state.snapshotForUndo()
        mutation()
        snackbarMessage = "\(message). Undo?"
        showSnackbar = true
        snackbarTimer?.invalidate()
        snackbarTimer = Timer.scheduledTimer(withTimeInterval: 3.5, repeats: false) { _ in hideSnackbar() }
    }

    private func hideSnackbar() {
        showSnackbar = false
        snackbarTimer?.invalidate()
        snackbarTimer = nil
    }
}

// MARK: - Simple title + chevron collapsible shell (fixed generics)
private struct PanelShell<Content: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    let trailingView: AnyView?
    let content: Content

    // Without trailing
    init(title: String, isExpanded: Binding<Bool>, @ViewBuilder content: () -> Content) {
        self.title = title
        self._isExpanded = isExpanded
        self.trailingView = nil
        self.content = content()
    }

    // With trailing
    init<T: View>(title: String, isExpanded: Binding<Bool>, @ViewBuilder trailing: () -> T, @ViewBuilder content: () -> Content) {
        self.title = title
        self._isExpanded = isExpanded
        self.trailingView = AnyView(trailing())
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button(action: { withAnimation { isExpanded.toggle() } }) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .imageScale(.small)
                        .padding(.trailing, 4)
                }
                .buttonStyle(.plain)
                Text(title).font(.title3).bold()
                Spacer()
                if let trailingView {
                    trailingView
                }
            }
            if isExpanded {
                content
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Search bar (below title)
private struct SearchBar: View {
    @Binding var text: String
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search all tasks…", text: $text)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(UIColor.secondarySystemBackground)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.2)))
    }
}

// MARK: - Calendar panel
private struct CalendarPanel: View {
    @ObservedObject var state: AppState
    var openDay: (CalendarDay) -> Void
    var onRescheduleWithUndo: (TaskItem, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Toolbar row: icons only
            HStack(spacing: 10) {
                // View toggle icon
                Button {
                    withAnimation {
                        state.calendarViewMode = (state.calendarViewMode == .card ? .list : .card)
                    }
                } label: {
                    Image(systemName: state.calendarViewMode == .card ? "square.grid.2x2" : "list.bullet")
                }
                .buttonStyle(.bordered)

                // Filter icon
                Menu {
                    Toggle(isOn: Binding(
                        get: { state.calendarFilters[.notStarted] ?? true },
                        set: { state.calendarFilters[.notStarted] = $0 }
                    )) { Text("Open") }
                    Toggle(isOn: Binding(
                        get: { state.calendarFilters[.started] ?? true },
                        set: { state.calendarFilters[.started] = $0 }
                    )) { Text("Started") }
                    Toggle(isOn: Binding(
                        get: { state.calendarFilters[.completed] ?? true },
                        set: { state.calendarFilters[.completed] = $0 }
                    )) { Text("Done") }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
                .menuStyle(.borderlessButton)
                .buttonStyle(.bordered)

                Spacer()

                // Today icon
                Button {
                    withAnimation {
                        state.calendarStartDate = Calendar.current.date(byAdding: .day, value: -3, to: Date()) ?? Date()
                    }
                } label: {
                    Image(systemName: "calendar.circle")
                }
                .buttonStyle(.borderedProminent)
            }

            let days = state.calendarDays()
            let expanded = state.visibleCalendarTasks(for: days)
            let tasksByDay = Dictionary(grouping: expanded) { $0.date ?? "" }

            if state.calendarViewMode == .card {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(days) { day in
                                let list = (tasksByDay[day.dateString] ?? [])
                                    .filter { state.calendarFilters[$0.status] ?? true }
                                DayCard(
                                    day: day,
                                    tasks: list,
                                    bg: .white
                                ) { openDay(day) }
                                .onDrop(of: [.plainText], isTargeted: nil, perform: { providers in
                                    handleDropToDay(day: day, providers: providers)
                                })
                                .id(dayCardID(day.dateString))
                            }
                        }
                        .padding(.vertical, 2)
                        .onAppear {
                            let today = ISO8601.dateOnly.string(from: Date())
                            withAnimation { proxy.scrollTo(dayCardID(today), anchor: .leading) }
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
                                    DayRow(
                                        day: day,
                                        tasks: list,
                                        bg: .white
                                    ) { openDay(day) }
                                    .id(dayListID(day.dateString))
                                }
                            }
                            if expanded.filter({ state.calendarFilters[$0.status] ?? true }).isEmpty {
                                CompatEmptyState(title: "No scheduled tasks in this period match your filters", systemImage: "calendar")
                                    .padding(.top, 16)
                            }
                        }
                        .onAppear {
                            let today = ISO8601.dateOnly.string(from: Date())
                            withAnimation { proxy.scrollTo(dayListID(today), anchor: .top) }
                        }
                    }
                    .frame(height: 260)
                }
            }
        }
    }

    private func handleDropToDay(day: CalendarDay, providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: "public.plain-text", options: nil) { data, _ in
            guard
                let d = data as? Data,
                let idStr = String(data: d, encoding: .utf8),
                let id = Int(idStr)
            else { return }
            DispatchQueue.main.async {
                if let t = state.tasks.first(where: { $0.id == id }) {
                    onRescheduleWithUndo(t, day.dateString)
                }
            }
        }
        return true
    }
}

// MARK: - Inbox panel
private struct InboxPanel: View {
    @ObservedObject var state: AppState

    // Callbacks with undo support
    let onDelete: (TaskItem) -> Void
    let onDuplicate: (TaskItem) -> Void
    let onArchive: (TaskItem) -> Void
    let onMoveToInbox: (TaskItem) -> Void
    let onEdit: (TaskItem) -> Void
    let onSnapshot: () -> Void
    let onBulkArchive: () -> Void
    let onBulkDelete: () -> Void

    // Drag reorder
    @State private var draggingId: Int? = nil
    @State private var dragOverId: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            inputRow
            listArea
            if state.isBulkSelectActiveInbox && !state.selectedInboxTaskIds.isEmpty {
                BulkActionBar(
                    count: state.selectedInboxTaskIds.count,
                    onArchive: onBulkArchive,
                    onDelete: onBulkDelete
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onDrop(of: [.plainText], isTargeted: nil, perform: { providers in
            // Dropping into empty area moves task back to inbox
            guard let provider = providers.first else { return false }
            provider.loadItem(forTypeIdentifier: "public.plain-text", options: nil) { data, _ in
                guard
                    let d = data as? Data,
                    let idStr = String(data: d, encoding: .utf8),
                    let id = Int(idStr),
                    let t = state.tasks.first(where: { $0.id == id })
                else { return }
                DispatchQueue.main.async { onMoveToInbox(t) }
            }
            return true
        })
    }

    private var header: some View {
        HStack {
            Text("Task List").font(.headline).bold()
            if !state.unassignedTasks.isEmpty {
                Text("\(state.unassignedTasks.count)")
                    .font(.caption).bold()
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.2)))
            }
            Spacer()
        }
    }

    private var inputRow: some View {
        HStack(spacing: 8) {
            TextField("Add a new task…", text: Binding(
                get: { "" },
                set: { if !$0.trimmingCharacters(in: .whitespaces).isEmpty { state.addTask(text: $0) } }
            ))
            .textFieldStyle(.roundedBorder)
            .submitLabel(.done)

            Button { } label: { Image(systemName: "plus") }
                .buttonStyle(.borderedProminent)
                .disabled(true)
                .opacity(0.35)
        }
    }

    private var listArea: some View {
        Group {
            if state.unassignedTasks.isEmpty {
                CompatEmptyState(title: "No unassigned tasks", systemImage: "tray")
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                List {
                    ForEach(state.unassignedTasks) { t in
                        InboxRow(
                            t: t,
                            isBulkSelecting: state.isBulkSelectActiveInbox,
                            isSelected: state.selectedInboxTaskIds.contains(t.id),
                            toggleSelected: {
                                if state.selectedInboxTaskIds.contains(t.id) {
                                    state.selectedInboxTaskIds.remove(t.id)
                                } else {
                                    state.selectedInboxTaskIds.insert(t.id)
                                }
                            },
                            onDelete: { onDelete(t) },
                            onDuplicate: { onDuplicate(t) },
                            onArchive: { onArchive(t) },
                            onEdit: { onEdit(t) },
                            onRateToggle: { newRating in
                                state.rate(t, rating: newRating, instanceDate: t.date)
                            },
                            onRecurrenceChange: { rec in
                                state.updateRecurrence(t, to: rec)
                            }
                        )
                        .listRowInsets(EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10))
                        .overlay(alignment: .top) {
                            if dragOverId == t.id {
                                Rectangle().fill(Color.blue).frame(height: 2).offset(y: -3)
                            }
                        }
                        .onDrag {
                            draggingId = t.id
                            return NSItemProvider(object: NSString(string: "\(t.id)"))
                        }
                        .onDrop(of: [.plainText], delegate: InboxReorderDropDelegate(
                            state: state,
                            draggingId: $draggingId,
                            dragOverId: $dragOverId,
                            targetId: t.id,
                            onSnapshot: onSnapshot
                        ))
                    }
                }
                .listStyle(.inset)
                .frame(minHeight: 140, maxHeight: 320)
            }
        }
    }
}

// MARK: - Inbox row (matches day modal style)
private struct InboxRow: View {
    let t: TaskItem
    let isBulkSelecting: Bool
    let isSelected: Bool
    let toggleSelected: () -> Void
    let onDelete: () -> Void
    let onDuplicate: () -> Void
    let onArchive: () -> Void
    let onEdit: () -> Void
    let onRateToggle: (TaskRating?) -> Void
    let onRecurrenceChange: (Recurrence) -> Void

    @State private var localRating: TaskRating? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if isBulkSelecting {
                    Button(action: toggleSelected) {
                        Image(systemName: isSelected ? "checkmark.square" : "square")
                    }
                }
                Text(t.text).font(.body).bold()
                if t.isRecurring { Image(systemName: "repeat") }
                Spacer()

                // Recurrence menu
                Menu {
                    Button("Never") { onRecurrenceChange(.never) }
                    Button("Daily") { onRecurrenceChange(.daily) }
                    Button("Weekly") { onRecurrenceChange(.weekly) }
                    Button("Monthly") { onRecurrenceChange(.monthly) }
                } label: { Image(systemName: "repeat") }

                // Rating button
                Button {
                    localRating = nextRating(localRating)
                    onRateToggle(localRating)
                } label: {
                    thumbIcon(for: localRating)
                }

                // Three-dot menu with Edit
                Menu {
                    Button { onEdit() } label: { Label("Edit", systemImage: "pencil") }
                    Button { onDuplicate() } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                    Button { onArchive() } label: { Label("Archive", systemImage: "archivebox") }
                    Button(role: .destructive) { onDelete() } label: { Label("Delete", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
            }

            // Scheduled info under name
            Text(t.date.map { "Scheduled: \($0)" } ?? "Not scheduled")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear {
            localRating = t.completedOverrides?[t.date ?? ""]?.rating
        }
    }

    private func nextRating(_ current: TaskRating?) -> TaskRating? {
        switch current {
        case nil: return .liked
        case .liked: return .disliked
        case .disliked: return nil
        }
    }

    @ViewBuilder private func thumbIcon(for rating: TaskRating?) -> some View {
        switch rating {
        case .liked:
            Image(systemName: "hand.thumbsup.fill").foregroundStyle(.blue)
        case .disliked:
            Image(systemName: "hand.thumbsdown.fill").foregroundStyle(.red)
        case nil:
            Image(systemName: "hand.thumbsup").rotationEffect(.degrees(90)).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Drop delegate for inbox reordering
private struct InboxReorderDropDelegate: DropDelegate {
    let state: AppState
    @Binding var draggingId: Int?
    @Binding var dragOverId: Int?
    let targetId: Int
    let onSnapshot: () -> Void

    func validateDrop(info: DropInfo) -> Bool { true }

    func dropEntered(info: DropInfo) { dragOverId = targetId }
    func dropExited(info: DropInfo) { dragOverId = nil }

    func performDrop(info: DropInfo) -> Bool {
        defer { draggingId = nil; dragOverId = nil }
        guard let dragged = draggingId,
              let fromIndex = state.tasks.firstIndex(where: { $0.id == dragged }),
              let toIndex = state.tasks.firstIndex(where: { $0.id == targetId })
        else { return false }
        // Only reorder inbox (unscheduled) tasks
        guard state.tasks[fromIndex].date == nil, state.tasks[toIndex].date == nil else { return false }
        onSnapshot()
        let item = state.tasks.remove(at: fromIndex)
        state.tasks.insert(item, at: toIndex)
        return true
    }
}

// MARK: - Day card & row
private struct DayCard: View {
    let day: CalendarDay
    let tasks: [TaskItem]
    var bg: Color
    var onTap: () -> Void

    var body: some View {
        let isToday = day.dateString == ISO8601.dateOnly.string(from: Date())
        let done = tasks.filter { $0.status == .completed }.count
        let started = tasks.filter { $0.status == .started }.count
        let open = tasks.filter { $0.status == .notStarted }.count

        VStack(alignment: .leading, spacing: 6) {
            Text(day.dayName).font(.caption).foregroundStyle(isToday ? .blue : .secondary)
            Text("\(day.dayOfMonth)").font(.title3).fontWeight(.semibold)
                .foregroundStyle(isToday ? .blue : .primary)
            Spacer()
            VStack(alignment: .leading, spacing: 4) {
                if done > 0 { badge("\(done) done", .green) }
                if started > 0 { badge("\(started) started", .orange) }
                if open > 0 { badge("\(open) open", .blue) }
            }
        }
        .padding(10)
        .frame(width: 110, height: 140)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(bg)
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
            .background(color.opacity(0.18))
            .foregroundStyle(color).clipShape(Capsule())
    }
}

private struct DayRow: View {
    let day: CalendarDay
    let tasks: [TaskItem]
    var bg: Color
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
                .fill(bg)
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
            .background(color.opacity(0.18))
            .foregroundStyle(color).clipShape(Capsule())
    }
}

// MARK: - Day Modal
private struct DayModalView: View {
    let day: CalendarDay
    @ObservedObject var state: AppState
    @Binding var isBulk: Bool
    @Binding var selectedIds: Set<Int>

    let onDelete: (TaskItem) -> Void
    let onMoveToInbox: (TaskItem) -> Void
    let onDuplicate: (TaskItem) -> Void
    let onArchive: (TaskItem) -> Void
    let onEdit: (TaskItem, String) -> Void

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
                            DayModalRow(
                                t: t,
                                dayString: day.dateString,
                                isBulk: isBulk,
                                isSelected: selectedIds.contains(t.id),
                                toggleSelected: {
                                    if selectedIds.contains(t.id) { selectedIds.remove(t.id) } else { selectedIds.insert(t.id) }
                                },
                                onDelete: { onDelete(t) },
                                onMoveToInbox: { onMoveToInbox(t) },
                                onDuplicate: { onDuplicate(t) },
                                onArchive: { onArchive(t) },
                                onEdit: { onEdit(t, day.dateString) },
                                updateStatus: { newStatus in
                                    state.updateStatus(t, to: newStatus, instanceDate: day.dateString)
                                },
                                updateRecurrence: { rec in
                                    state.updateRecurrence(t, to: rec)
                                },
                                rate: { rating in
                                    state.rate(t, rating: rating, instanceDate: day.dateString)
                                }
                            )
                        }
                    }
                }
            }

            if isBulk, !selectedIds.isEmpty {
                HStack {
                    Text("\(selectedIds.count) selected").font(.subheadline).bold()
                    Spacer()
                    Menu("Actions") {
                        Button { bulkMoveToInbox(expanded: expanded) } label: { Label("Move to Inbox", systemImage: "tray") }
                        Button { bulkArchive(expanded: expanded) } label: { Label("Archive", systemImage: "archivebox") }
                        Button("Delete", role: .destructive) { bulkDelete(expanded: expanded) } // wording changed
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.top, 6)
            }
        }
        .padding()
    }

    private func bulkArchive(expanded: [TaskItem]) {
        let ids = selectedIds
        for t in expanded where ids.contains(t.id) { onArchive(t) }
        selectedIds = []; isBulk = false
    }
    private func bulkDelete(expanded: [TaskItem]) {
        let ids = selectedIds
        for t in expanded where ids.contains(t.id) { onDelete(t) }
        selectedIds = []; isBulk = false
    }
    private func bulkMoveToInbox(expanded: [TaskItem]) {
        let ids = selectedIds
        for t in expanded where ids.contains(t.id) { onMoveToInbox(t) }
        selectedIds = []; isBulk = false
    }

    private func dateLong(_ ds: String) -> String {
        guard let d = ds.asISODateOnlyUTC else { return ds }
        let f = DateFormatter(); f.timeZone = .init(secondsFromGMT: 0); f.dateFormat = "MMMM d, yyyy"
        return f.string(from: d)
    }
}

// Row used inside DayModal (separate struct so it can own local state cleanly)
private struct DayModalRow: View {
    let t: TaskItem
    let dayString: String
    let isBulk: Bool
    let isSelected: Bool
    let toggleSelected: () -> Void

    let onDelete: () -> Void
    let onMoveToInbox: () -> Void
    let onDuplicate: () -> Void
    let onArchive: () -> Void
    let onEdit: () -> Void

    let updateStatus: (TaskStatus) -> Void
    let updateRecurrence: (Recurrence) -> Void
    let rate: (TaskRating?) -> Void

    @State private var localRating: TaskRating? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if isBulk {
                    Button(action: toggleSelected) {
                        Image(systemName: isSelected ? "checkmark.square" : "square")
                    }
                }
                Text(t.text).font(.body).bold()
                if t.isRecurring { Image(systemName: "repeat") }
                Spacer()

                // Recurrence menu
                Menu {
                    Button("Never") { updateRecurrence(.never) }
                    Button("Daily") { updateRecurrence(.daily) }
                    Button("Weekly") { updateRecurrence(.weekly) }
                    Button("Monthly") { updateRecurrence(.monthly) }
                } label: { Image(systemName: "repeat") }

                // Rating button (cycles)
                Button {
                    localRating = nextRating(localRating)
                    rate(localRating)
                } label: { thumbIcon(for: localRating) }

                // Edit / actions
                Menu {
                    Button { onEdit() } label: { Label("Edit", systemImage: "pencil") }
                    Button { onDuplicate() } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                    Button { onArchive() } label: { Label("Archive", systemImage: "archivebox") }
                    Button { onMoveToInbox() } label: { Label("Move to Inbox", systemImage: "tray") }
                    Button(role: .destructive) { onDelete() } label: { Label("Delete", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis.circle") }
            }

            if let n = t.notes, !n.isEmpty {
                Text(n).font(.subheadline).foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button("Open") { updateStatus(.notStarted) }
                    .buttonStyle(.bordered).tint(t.status == .notStarted ? .blue : .secondary)
                Button("Started") { updateStatus(.started) }
                    .buttonStyle(.bordered).tint(t.status == .started ? .orange : .secondary)
                Button("Done") { updateStatus(.completed) }
                    .buttonStyle(.bordered).tint(t.status == .completed ? .green : .secondary)
            }
            .font(.caption)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(UIColor.systemGray6)))
        .onAppear {
            localRating = t.completedOverrides?[dayString]?.rating
        }
    }

    private func nextRating(_ current: TaskRating?) -> TaskRating? {
        switch current {
        case nil: return .liked
        case .liked: return .disliked
        case .disliked: return nil
        }
    }

    @ViewBuilder private func thumbIcon(for rating: TaskRating?) -> some View {
        switch rating {
        case .liked:
            Image(systemName: "hand.thumbsup.fill").foregroundStyle(.blue)
        case .disliked:
            Image(systemName: "hand.thumbsdown.fill").foregroundStyle(.red)
        case nil:
            Image(systemName: "hand.thumbsup").rotationEffect(.degrees(90)).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Archives (search-aware)
private struct ArchivesView: View {
    @ObservedObject var state: AppState
    @State private var isSelecting = false
    @State private var selectedIds: Set<Int> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Archives").font(.title2).bold()
                Spacer()
                Button(isSelecting ? "Cancel" : "Select") { isSelecting.toggle(); selectedIds.removeAll() }
            }

            Picker("Section", selection: $state.activeArchiveTab) {
                ForEach(ArchiveTab.allCases) { tab in
                    Text(label(tab)).tag(tab)
                }
            }
            .pickerStyle(.segmented)

            if isSelecting && !selectedIds.isEmpty {
                HStack {
                    Text("\(selectedIds.count) selected").font(.subheadline).bold()
                    Spacer()
                    Menu("Actions") {
                        Button("Restore") {
                            let toRestore = state.archivedTasks.filter { selectedIds.contains($0.id) }
                            for a in toRestore { state.restoreTask(a) }
                            selectedIds.removeAll(); isSelecting = false
                        }
                        Button("Delete Permanently", role: .destructive) {
                            for id in selectedIds { state.deletePermanently(id) }
                            selectedIds.removeAll(); isSelecting = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            let query = state.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let list = state.archivedTasks.filter {
                $0.archiveReason == state.activeArchiveTab.rawValue &&
                (query.isEmpty || $0.text.lowercased().contains(query) || ($0.notes ?? "").lowercased().contains(query))
            }

            if list.isEmpty {
                CompatEmptyState(title: "This archive is empty", systemImage: "tray")
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                List {
                    ForEach(list) { t in
                        HStack(spacing: 8) {
                            if isSelecting {
                                Button {
                                    if selectedIds.contains(t.id) { selectedIds.remove(t.id) } else { selectedIds.insert(t.id) }
                                } label: {
                                    Image(systemName: selectedIds.contains(t.id) ? "checkmark.square" : "square")
                                }
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(t.text).font(.body)
                                    .strikethrough(t.archiveReason == "completed")
                                Text("Archived: \(formatDateTime(t.archivedAt))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if !isSelecting {
                                Menu {
                                    Button { state.restoreTask(t) } label: { Label("Restore", systemImage: "arrow.uturn.left") }
                                    Button(role: .destructive) { state.deletePermanently(t.id) } label: { Label("Delete", systemImage: "trash") }
                                } label: { Image(systemName: "ellipsis.circle") }
                                .menuStyle(.borderlessButton)
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
        case .not_started: return "Open"
        case .started:     return "Started"
        case .completed:   return "Completed"
        case .deleted:     return "Deleted"
        }
    }
}

// MARK: - Stats (search-aware)
private struct StatsViewContainer: View {
    @ObservedObject var state: AppState

    // period
    enum Period: String, CaseIterable { case weekly, monthly, quarterly, semester, yearly, custom }
    @State private var period: Period = .weekly
    @State private var customStart: Date = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var customEnd: Date = Date()

    private func periodRange() -> ClosedRange<Date> {
        let cal = Calendar.current; let now = Date()
        switch period {
        case .weekly:    return (cal.date(byAdding: .day, value: -7, to: now) ?? now)...now
        case .monthly:   return (cal.date(byAdding: .month, value: -1, to: now) ?? now)...now
        case .quarterly: return (cal.date(byAdding: .month, value: -3, to: now) ?? now)...now
        case .semester:  return (cal.date(byAdding: .month, value: -6, to: now) ?? now)...now
        case .yearly:    return (cal.date(byAdding: .year, value: -1, to: now) ?? now)...now
        case .custom:    return min(customStart, customEnd)...max(customStart, customEnd)
        }
    }

    var body: some View {
        let range = periodRange()
        let (series, _) = state.weeklySeries(lastWeeks: 8)

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Stats").font(.title2).bold()
                Spacer()
                Menu {
                    Picker("Period", selection: $period) {
                        ForEach(Period.allCases, id: \.self) { p in
                            Text(p.rawValue.capitalized).tag(p)
                        }
                    }
                    if period == .custom {
                        Divider()
                        DatePicker("From", selection: $customStart, displayedComponents: .date)
                        DatePicker("To", selection: $customEnd, displayedComponents: .date)
                    }
                } label: {
                    Label("Period", systemImage: "calendar")
                }
                .buttonStyle(.bordered)
            }

            // KPI bars (Completed / Started / Open / Total) with search filtering support
            let counts = aggregateCounts(in: range, query: state.searchQuery)
            KPIBars(completed: counts.completed, started: counts.started, open: counts.open, total: counts.total)

            // Bar chart (rolling 8 weeks)
            GroupBox("Last 8 weeks (trend)") {
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

            // Completed tasks in period (search-aware)
            GroupBox("Completed Tasks in Period") {
                let completed = completedTasks(in: range, query: state.searchQuery)
                if completed.isEmpty {
                    Text("No completed tasks in this period.").foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(completed, id: \.id) { t in
                            HStack {
                                Text(t.text).font(.subheadline)
                                Spacer()
                                Text(t.date ?? "").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            // Ratings breakdown (Open, Done, Deleted) (search-aware)
            GroupBox("Ratings in Period") {
                let ratings = ratingsIn(range, query: state.searchQuery)
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Text("Open").frame(width: 80, alignment: .leading); Text("👍 \(ratings.openLiked)"); Text("👎 \(ratings.openDisliked)") }
                    HStack { Text("Done").frame(width: 80, alignment: .leading); Text("👍 \(ratings.doneLiked)"); Text("👎 \(ratings.doneDisliked)") }
                    HStack { Text("Deleted").frame(width: 80, alignment: .leading); Text("👍 \(ratings.deletedLiked)"); Text("👎 \(ratings.deletedDisliked)") }
                }
                .font(.subheadline)
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    // Helpers (search-aware)
    private func matchesQuery(_ t: TaskItem, _ q: String) -> Bool {
        let q = q.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return true }
        if t.text.lowercased().contains(q) { return true }
        if (t.notes ?? "").lowercased().contains(q) { return true }
        return false
    }

    private func within(_ ds: String?, _ range: ClosedRange<Date>) -> Bool {
        ds?.asISODateOnlyUTC.map(range.contains) ?? false
    }

    private func aggregateCounts(in range: ClosedRange<Date>, query: String) -> (completed: Int, started: Int, open: Int, total: Int) {
        var open = 0, started = 0, done = 0
        for t in state.tasks where within(t.date, range) && matchesQuery(t, query) {
            switch t.status { case .notStarted: open += 1; case .started: started += 1; case .completed: done += 1 }
        }
        for a in state.archivedTasks where within(a.date, range) && (a.text.lowercased().contains(query.lowercased()) || query.isEmpty) {
            switch a.archiveReason {
            case "completed": done += 1
            case "started": started += 1
            case "not_started": open += 1
            default: break
            }
        }
        let total = open + started + done
        return (done, started, open, total)
    }

    private func completedTasks(in range: ClosedRange<Date>, query: String) -> [TaskItem] {
        let live = state.tasks
            .filter { $0.status == .completed && within($0.date, range) && matchesQuery($0, query) }
        let archived = state.archivedTasks
            .filter { $0.archiveReason == "completed" && within($0.date, range) && ($0.text.lowercased().contains(query.lowercased()) || query.isEmpty) }
            .map { a in TaskItem(id: a.id, text: a.text, notes: a.notes, date: a.date, status: .completed, recurrence: nil, createdAt: a.createdAt, startedAt: a.startedAt, completedAt: a.completedAt, completedOverrides: nil) }
        return live + archived
    }

    private func ratingsIn(_ range: ClosedRange<Date>, query: String) -> (openLiked: Int, openDisliked: Int, doneLiked: Int, doneDisliked: Int, deletedLiked: Int, deletedDisliked: Int) {
        var oL = 0, oD = 0, dL = 0, dD = 0, delL = 0, delD = 0

        for t in state.tasks where within(t.date, range) && matchesQuery(t, query) {
            let rating = t.completedOverrides?[t.date ?? ""]?.rating
            switch t.status {
            case .notStarted, .started:
                if rating == .liked { oL += 1 }
                if rating == .disliked { oD += 1 }
            case .completed:
                if rating == .liked { dL += 1 }
                if rating == .disliked { dD += 1 }
            }
        }
        // Archived "deleted" items don't carry ratings in current model.
        return (oL, oD, dL, dD, delL, delD)
    }
}

// KPI bars component (progress bars instead of %)
private struct KPIBars: View {
    let completed: Int
    let started: Int
    let open: Int
    let total: Int

    var body: some View {
        VStack(spacing: 10) {
            barRow(title: "Completed", value: completed, tint: .green)
            barRow(title: "Started", value: started, tint: .orange)
            barRow(title: "Open", value: open, tint: .blue)
            barRow(title: "Total", value: total, tint: .primary)
        }
    }

    private func barRow(title: String, value: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(value)").font(.caption).foregroundStyle(.secondary)
            }
            ProgressView(value: total > 0 ? Double(value) / Double(total) : 0).tint(tint)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Settings & Theme
private struct SettingsSheet: View {
    @Binding var isDark: Bool
    let onOpenTheme: () -> Void

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 14) {
                // Profile block (approximate layout)
                HStack {
                    Spacer()
                    HStack(alignment: .top, spacing: 12) {
                        Circle().fill(Color.gray.opacity(0.3))
                            .frame(width: 56, height: 56)
                            .overlay(Text("A").bold())
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Adrian Kisliuk").bold()
                            Text("a.kisliuk@gmail.com").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 6)

                Divider()

                // Buttons list
                List {
                    Button("Manage Teams") {}
                    Button("Subscription") {}
                    Button("Billing") {}
                    Button("Languages") {}
                    Button("Privacy Policy") {}
                    Button("Terms of Use") {}
                    Button("Log in/out") {}
                    Button("Theme") { onOpenTheme() }
                }
                .listStyle(.insetGrouped)
            }
            .padding(.top)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct ThemePickerSheet: View {
    enum ThemeMode { case dark, light, system }
    @Binding var selected: ThemeMode

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Theme").font(.headline)
            Picker("Theme", selection: $selected) {
                Text("Dark").tag(ThemeMode.dark)
                Text("Light").tag(ThemeMode.light)
                Text("System Mode").tag(ThemeMode.system)
            }
            .pickerStyle(.inline)
            .padding(.top, 6)

            Spacer()
        }
        .padding()
    }
}

// MARK: - Task editor (with Assign To + Created By)
private struct TaskEditSheet: View {
    @State var task: TaskItem
    let instanceDate: String?
    @State var meta: AppState.TaskMeta
    let onSave: (TaskItem, AppState.TaskMeta) -> Void

    init(task: TaskItem, instanceDate: String?, initialMeta: AppState.TaskMeta, onSave: @escaping (TaskItem, AppState.TaskMeta) -> Void) {
        self._task = State(initialValue: task)
        self.instanceDate = instanceDate
        self._meta = State(initialValue: initialMeta)
        self.onSave = onSave
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Details")) {
                    TextField("Task title", text: Binding(
                        get: { task.text },
                        set: { task.text = $0 }
                    ))
                    TextField("Notes", text: Binding(
                        get: { task.notes ?? "" },
                        set: { task.notes = $0 }
                    ))
                    TextField("Schedule (yyyy-MM-dd)", text: Binding(
                        get: { task.date ?? "" },
                        set: { task.date = $0.isEmpty ? nil : $0 }
                    ))
                }
                Section(header: Text("Status")) {
                    Picker("Status", selection: Binding(
                        get: { task.status },
                        set: { task.status = $0 }
                    )) {
                        Text("Open").tag(TaskStatus.notStarted)
                        Text("Started").tag(TaskStatus.started)
                        Text("Done").tag(TaskStatus.completed)
                    }
                    .pickerStyle(.segmented)
                }
                Section(header: Text("Recurrence")) {
                    Picker("Repeat", selection: Binding(
                        get: { task.recurrence ?? .never },
                        set: { task.recurrence = ($0 == .never ? nil : $0) }
                    )) {
                        Text("Never").tag(Recurrence.never)
                        Text("Daily").tag(Recurrence.daily)
                        Text("Weekly").tag(Recurrence.weekly)
                        Text("Monthly").tag(Recurrence.monthly)
                    }
                    .pickerStyle(.segmented)
                }
                Section(header: Text("Assignment")) {
                    HStack {
                        Text("Created by")
                        Spacer()
                        Text(meta.createdBy).foregroundStyle(.secondary)
                    }
                    TextField("Assign to", text: Binding(
                        get: { meta.assignedTo },
                        set: { meta.assignedTo = $0 }
                    ))
                }
            }
            .navigationTitle("Edit Task")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { onSave(task, meta) }
                }
            }
        }
    }
}

// MARK: - Snackbar
private struct Snackbar: View {
    let message: String
    let onUndo: () -> Void

    var body: some View {
        HStack {
            Text(message).foregroundStyle(.white)
            Spacer()
            Button("Undo", action: onUndo)
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(.black)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Capsule().fill(Color.black.opacity(0.85)))
        .padding(.horizontal, 16)
    }
}

// MARK: - Bulk action bar (bottom)
private struct BulkActionBar: View {
    let count: Int
    let onArchive: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            Text("\(count) selected").bold()
            Spacer()
            Button(action: onArchive) { Label("Archive", systemImage: "archivebox") }
                .buttonStyle(.bordered)
            Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") }
                .buttonStyle(.borderedProminent)
        }
        .padding(10)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

// MARK: - Small helpers
private func formatDateTime(_ d: Date?) -> String {
    guard let d = d else { return "—" }
    let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short
    return f.string(from: d)
}
