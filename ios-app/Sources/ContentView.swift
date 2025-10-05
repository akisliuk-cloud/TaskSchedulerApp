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

// MARK: - Root ContentView
struct ContentView: View {
    @StateObject private var state = AppState()

    // Current section
    enum Tab { case home, stats, camera, archives, search, settings }
    @State private var tab: Tab = .home

    // Overlays / sheets
    @State private var showingDay: CalendarDay? = nil
    @State private var isModalBulkSelect = false
    @State private var selectedModalIds = Set<Int>()

    // Settings
    @State private var showSettings = false
    @State private var isDarkMode = false

    // Search bar under the title (appears when bottom Search is active)
    @State private var showSearchBar = false

    // Undo snackbar
    @State private var snackbarText: String = ""
    @State private var snackbarVisible: Bool = false
    @State private var snackbarUndo: (() -> Void)? = nil

    // Stats period controls
    enum Period: String, CaseIterable { case weekly, monthly, quarterly, semester, yearly, custom }
    @State private var statsPeriod: Period = .weekly
    @State private var customStart: Date = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var customEnd: Date = Date()

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 10) {
                header
                if showSearchBar {
                    HStack {
                        Image(systemName: "magnifyingglass")
                        TextField("Search tasks…", text: $state.searchQuery)
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding(.horizontal)
                }

                contentArea
                bottomBar
            }
            .padding(.top, 8)
            .preferredColorScheme(isDarkMode ? .dark : .light)

            // Snackbar overlay
            if snackbarVisible {
                Snackbar(text: snackbarText, onUndo: {
                    snackbarUndo?()
                    hideSnackbar()
                }, onDismiss: {
                    hideSnackbar()
                })
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(10)
            }
        }
        .sheet(item: $showingDay) { day in
            DayModalView(
                day: day,
                state: state,
                isBulk: $isModalBulkSelect,
                selectedIds: $selectedModalIds,
                // Undo hook: snapshot -> do -> snackbar
                onAboutToMutate: snapshotUndo,
                triggerUndoSnack: triggerUndoSnack
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(isDarkMode: $isDarkMode)
                .presentationDetents([.large])
        }
    }

    // MARK: Header (title only)
    private var header: some View {
        HStack(spacing: 12) {
            Text("Taskmate")              // app name
                .font(.title2)            // a bit smaller than .title
                .fontWeight(.semibold)
            Spacer()
        }
        .padding(.horizontal)
    }

    // MARK: Main content switcher
    private var contentArea: some View {
        Group {
            switch tab {
            case .home, .search, .camera: // camera doesn't change content, only highlights in bar
                HomeComposite(
                    state: state,
                    onOpenDay: { showingDay = $0 },
                    onAboutToMutate: snapshotUndo,
                    triggerUndoSnack: triggerUndoSnack
                )
            case .archives:
                ArchivesView(state: state)
            case .stats:
                StatsView(
                    state: state,
                    period: $statsPeriod,
                    customStart: $customStart,
                    customEnd: $customEnd
                )
            case .settings:
                SettingsLanding(openSheet: { showSettings = true })
            }
        }
        .padding(.horizontal)
        .animation(.default, value: tab)
    }

    // MARK: Bottom menu bar
    private var bottomBar: some View {
        HStack {
            barButton(icon: "house", isActive: tab == .home) {
                tab = .home
                showSearchBar = false
                state.isArchiveViewActive = false
                state.isStatsViewActive = false
            }
            barButton(icon: "chart.bar", isActive: tab == .stats) {
                tab = .stats
                showSearchBar = false
                state.isStatsViewActive = true
                state.isArchiveViewActive = false
            }
            barButton(icon: "camera", isActive: tab == .camera) {
                // Only highlight selection per spec
                tab = .camera
                showSearchBar = false
            }
            barButton(icon: "archivebox", isActive: tab == .archives) {
                tab = .archives
                showSearchBar = false
                state.isArchiveViewActive = true
                state.isStatsViewActive = false
            }
            barButton(icon: "magnifyingglass", isActive: tab == .search) {
                // Show search bar regardless of tab; stay on current area if already not home? Spec says searchable across tabs.
                showSearchBar = true
                tab = .search
            }
            barButton(icon: "gearshape", isActive: tab == .settings) {
                tab = .settings
                showSearchBar = false
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
        .padding(.top, 6)
    }

    private func barButton(icon: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .imageScale(.large)
                .foregroundStyle(isActive ? .blue : .primary)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    // MARK: Undo helpers
    private func snapshotUndo() {
        state.snapshotForUndo()
    }
    private func triggerUndoSnack(_ actionText: String) {
        snackbarText = "\(actionText) • Undo?"
        snackbarUndo = { state.undoToLastSnapshot() }
        withAnimation { snackbarVisible = true }
        // Auto-hide after 4s
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            hideSnackbar()
        }
    }
    private func hideSnackbar() {
        withAnimation { snackbarVisible = false }
        snackbarUndo = nil
    }
}

// MARK: - Home composite (Calendar + Inbox, collapsible)
private struct HomeComposite: View {
    @ObservedObject var state: AppState
    var onOpenDay: (CalendarDay) -> Void

    // Undo hooks (from parent)
    var onAboutToMutate: () -> Void
    var triggerUndoSnack: (_ actionText: String) -> Void

    @State private var calendarExpanded = true
    @State private var inboxExpanded = true

    var body: some View {
        VStack(spacing: 12) {

            // Daily Calendar section
            SectionHeader(title: "Daily Calendar", expanded: $calendarExpanded)
            if calendarExpanded {
                CalendarPanel(
                    state: state,
                    openDay: onOpenDay,
                    onAboutToMutate: onAboutToMutate,
                    triggerUndoSnack: triggerUndoSnack
                )
            }

            // Task List section
            SectionHeader(
                title: "Task List",
                expanded: $inboxExpanded,
                showsSelect: true,
                isSelecting: state.isBulkSelectActiveInbox,
                onSelectToggle: { state.toggleBulkSelectInbox() }
            )
            if inboxExpanded {
                InboxPanel(
                    state: state,
                    onAboutToMutate: onAboutToMutate,
                    triggerUndoSnack: triggerUndoSnack
                )
                .overlay(alignment: .bottom) {
                    if state.isBulkSelectActiveInbox && !state.selectedInboxTaskIds.isEmpty {
                        BulkActionBar(
                            count: state.selectedInboxTaskIds.count,
                            onArchive: {
                                onAboutToMutate()
                                state.archiveSelectedInbox()
                                triggerUndoSnack("Archived")
                            },
                            onDelete: {
                                onAboutToMutate()
                                state.deleteSelectedInbox()
                                triggerUndoSnack("Deleted")
                            }
                        )
                        .transition(.move(edge: .bottom))
                        .padding(.horizontal, 8)
                        .padding(.bottom, 2)
                    }
                }
            }
        }
    }
}

// MARK: - Section header with collapsible arrow + optional Select
private struct SectionHeader: View {
    let title: String
    @Binding var expanded: Bool
    var showsSelect: Bool = false
    var isSelecting: Bool = false
    var onSelectToggle: (() -> Void)? = nil

    var body: some View {
        HStack {
            Button {
                withAnimation { expanded.toggle() }
            } label: {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .imageScale(.medium)
            }
            .buttonStyle(.plain)

            Text(title).font(.title3).bold()
            Spacer()

            if showsSelect, let onSelectToggle {
                Button(isSelecting ? "Cancel" : "Select", action: onSelectToggle)
                    .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal)
        .padding(.top, 4)
    }
}

// MARK: - Snackbar
private struct Snackbar: View {
    let text: String
    let onUndo: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(text).lineLimit(1).font(.subheadline)
            Spacer()
            Button("Undo", action: onUndo)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
}

// MARK: - Calendar panel
private struct CalendarPanel: View {
    @ObservedObject var state: AppState
    var openDay: (CalendarDay) -> Void

    // Undo hooks
    var onAboutToMutate: () -> Void
    var triggerUndoSnack: (_ actionText: String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Top controls: icons only
            HStack(spacing: 8) {
                // View picker icon toggler: card/list
                Button {
                    withAnimation {
                        state.calendarViewMode = (state.calendarViewMode == .card ? .list : .card)
                    }
                } label: {
                    Image(systemName: state.calendarViewMode == .card ? "rectangle.grid.2x2" : "list.bullet")
                }
                .buttonStyle(.bordered)

                // Filter menu icon
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
                    Image(systemName: "line.horizontal.3.decrease.circle")
                }
                .buttonStyle(.bordered)

                Divider().frame(height: 22)

                // Today icon
                Button {
                    withAnimation {
                        state.calendarStartDate = Calendar.current.date(byAdding: .day, value: -3, to: Date()) ?? Date()
                    }
                } label: {
                    Image(systemName: "target")
                }
                .buttonStyle(.borderedProminent)

                Spacer()
            }
            .padding(.horizontal)

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
                                    bg: Color(.systemBackground)
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
                                        bg: Color(.systemBackground)
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
        .padding(.vertical, 8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
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
                    onAboutToMutate()
                    state.reschedule(t, to: day.dateString)
                    triggerUndoSnack("Moved")
                }
            }
        }
        return true
    }
}

// MARK: - Inbox panel
private struct InboxPanel: View {
    @ObservedObject var state: AppState

    // Undo hooks
    var onAboutToMutate: () -> Void
    var triggerUndoSnack: (_ actionText: String) -> Void

    // Local states
    @State private var newTaskText = ""
    @State private var editingTaskId: Int? = nil
    @State private var editText = ""
    @State private var editNotes = ""
    @State private var editDate: String = ""
    @State private var editStatus: TaskStatus = .notStarted
    @State private var editRecurrence: Recurrence = .never
    @State private var showEditSheet = false

    // Assign/Created meta
    @State private var createdBy: String = "Adrian Kisliuk"
    @State private var assignedTo: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            inputRow
            listArea
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .onDrop(of: [.plainText], isTargeted: nil, perform: { providers in
            // Dropping into empty space moves task to inbox
            guard let provider = providers.first else { return false }
            provider.loadItem(forTypeIdentifier: "public.plain-text", options: nil) { data, _ in
                guard
                    let d = data as? Data,
                    let idStr = String(data: d, encoding: .utf8),
                    let id = Int(idStr),
                    let t = state.tasks.first(where: { $0.id == id })
                else { return }
                DispatchQueue.main.async {
                    onAboutToMutate()
                    state.moveToInbox(t)
                    triggerUndoSnack("Moved to Inbox")
                }
            }
            return true
        })
        .sheet(isPresented: $showEditSheet) {
            EditTaskSheet(
                title: $editText,
                notes: $editNotes,
                dateStr: $editDate,
                status: $editStatus,
                recurrence: $editRecurrence,
                createdBy: $createdBy,
                assignedTo: $assignedTo,
                onCancel: {
                    showEditSheet = false
                    editingTaskId = nil
                },
                onSave: {
                    guard let id = editingTaskId,
                          let idx = state.tasks.firstIndex(where: { $0.id == id }) else {
                        showEditSheet = false; return
                    }
                    onAboutToMutate()
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
                    // Save assignment meta
                    state.taskMeta[id] = .init(createdBy: createdBy, assignedTo: assignedTo)
                    triggerUndoSnack("Edited")
                    showEditSheet = false
                    editingTaskId = nil
                }
            )
            .presentationDetents([.medium, .large])
        }
    }

    private var inputRow: some View {
        HStack(spacing: 8) {
            TextField("Add a new task…", text: $newTaskText, onCommit: addTask)
                .textFieldStyle(.roundedBorder)
            Button(action: addTask) {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderedProminent)
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
                        inboxRow(t)
                            .onDrag { NSItemProvider(object: NSString(string: "\(t.id)")) }
                            .onDrop(of: [.plainText], isTargeted: nil, perform: { providers in
                                handleInboxDrop(on: t, providers: providers)
                            })
                    }
                }
                .listStyle(.inset)
                .frame(minHeight: 140, maxHeight: 300)
            }
        }
    }

    @ViewBuilder private func inboxRow(_ t: TaskItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if state.isBulkSelectActiveInbox {
                Button {
                    if state.selectedInboxTaskIds.contains(t.id) { state.selectedInboxTaskIds.remove(t.id) }
                    else { state.selectedInboxTaskIds.insert(t.id) }
                } label: {
                    Image(systemName: state.selectedInboxTaskIds.contains(t.id) ? "checkmark.square" : "square")
                }
            }

            // Match look with day modal: bold title, recurrence & rating icons
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(t.text).font(.body).bold()
                    if t.isRecurring { Image(systemName: "repeat").foregroundStyle(.secondary) }
                    // Thumb rating (cycle neutral -> like -> dislike)
                    Button {
                        let ds = t.date ?? ISO8601.dateOnly.string(from: Date())
                        let current = state.tasks.first(where: { $0.id == t.id })?.completedOverrides?[ds]?.rating
                        let next: TaskRating? = (current == nil) ? .liked : (current == .liked ? .disliked : nil)
                        onAboutToMutate()
                        state.rate(t, rating: next, instanceDate: ds)
                        triggerUndoSnack("Rated")
                    } label: {
                        let ds = t.date ?? ISO8601.dateOnly.string(from: Date())
                        let current = state.tasks.first(where: { $0.id == t.id })?.completedOverrides?[ds]?.rating
                        Image(systemName:
                                (current == .liked ? "hand.thumbsup.fill" :
                                    (current == .disliked ? "hand.thumbsdown.fill" : "hand.raised"))
                        )
                        .foregroundStyle(current == .liked ? .green : (current == .disliked ? .red : .secondary))
                    }
                    .buttonStyle(.plain)
                }

                // Scheduled date under name (if any)
                if let ds = t.date, !ds.isEmpty {
                    Text("Scheduled: \(ds)").font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Three-dot menu
            Menu {
                Button { beginEdit(t) } label: { Label("Edit", systemImage: "pencil") }
                Button { onAboutToMutate(); state.archiveTask(t); triggerUndoSnack("Archived") } label: { Label("Archive", systemImage: "archivebox") }
                Button { onAboutToMutate(); state.duplicate(t); triggerUndoSnack("Duplicated") } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                Button(role: .destructive) { onAboutToMutate(); state.deleteToTrash(t); triggerUndoSnack("Deleted") } label: { Label("Delete", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis.circle").imageScale(.large).padding(4)
            }
            .menuStyle(.borderlessButton)
        }
        .contentShape(Rectangle())
    }

    private func addTask() {
        guard !newTaskText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        onAboutToMutate()
        state.addTask(text: newTaskText)
        triggerUndoSnack("Added")
        newTaskText = ""
    }

    private func beginEdit(_ t: TaskItem) {
        editingTaskId = t.id
        editText = t.text
        editNotes = t.notes ?? ""
        editDate = t.date ?? ""
        editStatus = t.status
        editRecurrence = t.recurrence ?? .never
        let meta = state.taskMeta[t.id] ?? .init()
        createdBy = meta.createdBy
        assignedTo = meta.assignedTo
        showEditSheet = true
    }

    private func handleInboxDrop(on target: TaskItem, providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: "public.plain-text", options: nil) { data, _ in
            guard
                let d = data as? Data,
                let idStr = String(data: d, encoding: .utf8),
                let draggedId = Int(idStr),
                let fromIndex = state.tasks.firstIndex(where: { $0.id == draggedId }),
                let toIndex = state.tasks.firstIndex(where: { $0.id == target.id })
            else { return }
            DispatchQueue.main.async {
                guard state.tasks[fromIndex].date == nil, state.tasks[toIndex].date == nil else { return }
                onAboutToMutate()
                let item = state.tasks.remove(at: fromIndex)
                state.tasks.insert(item, at: toIndex)
                triggerUndoSnack("Reordered")
            }
        }
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

    // Undo hooks
    var onAboutToMutate: () -> Void
    var triggerUndoSnack: (_ actionText: String) -> Void

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
                        ForEach(expanded) { t in taskRow(t) }
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
                        Button("Delete", role: .destructive) {
                            bulkDelete(expanded: expanded)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.top, 6)
            }
        }
        .padding()
    }

    @ViewBuilder private func taskRow(_ t: TaskItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if isBulk {
                    Button {
                        if selectedIds.contains(t.id) { selectedIds.remove(t.id) } else { selectedIds.insert(t.id) }
                    } label: {
                        Image(systemName: selectedIds.contains(t.id) ? "checkmark.square" : "square")
                    }
                }
                Text(t.text).font(.body).bold()
                if t.isRecurring { Image(systemName: "repeat") }
                Spacer()

                // Repeat (icon only)
                Menu {
                    Button("Never") { state.updateRecurrence(t, to: .never) }
                    Button("Daily") { state.updateRecurrence(t, to: .daily) }
                    Button("Weekly") { state.updateRecurrence(t, to: .weekly) }
                    Button("Monthly") { state.updateRecurrence(t, to: .monthly) }
                } label: { Image(systemName: "repeat") }

                // Thumb rating button cycling states
                Button {
                    let current = t.completedOverrides?[day.dateString]?.rating
                    let next: TaskRating? = (current == nil) ? .liked : (current == .liked ? .disliked : nil)
                    onAboutToMutate()
                    state.rate(t, rating: next, instanceDate: day.dateString)
                    triggerUndoSnack("Rated")
                } label: {
                    let r = t.completedOverrides?[day.dateString]?.rating
                    Image(systemName:
                            (r == .liked ? "hand.thumbsup.fill" :
                                (r == .disliked ? "hand.thumbsdown.fill" : "hand.raised"))
                    )
                    .foregroundStyle(r == .liked ? .green : (r == .disliked ? .red : .secondary))
                }
                .buttonStyle(.plain)

                // Three-dot actions (with Edit)
                Menu {
                    Button { onAboutToMutate(); state.moveToInbox(t); triggerUndoSnack("Moved to Inbox") } label: { Label("Move to Inbox", systemImage: "tray") }
                    Button { onAboutToMutate(); state.duplicate(t); triggerUndoSnack("Duplicated") } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                    Button { onAboutToMutate(); state.archiveTask(t); triggerUndoSnack("Archived") } label: { Label("Archive", systemImage: "archivebox") }
                    Button(role: .destructive) { onAboutToMutate(); state.deleteToTrash(t); triggerUndoSnack("Deleted") } label: { Label("Delete", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis.circle") }
            }

            if let n = t.notes, !n.isEmpty {
                Text(n).font(.subheadline).foregroundStyle(.secondary)
            }

            // Status buttons with colored tints
            HStack(spacing: 8) {
                Button("Open") {
                    onAboutToMutate()
                    state.updateStatus(t, to: .notStarted, instanceDate: day.dateString)
                    triggerUndoSnack("Marked Open")
                }
                .buttonStyle(.bordered).tint(t.status == .notStarted ? .blue : .secondary)

                Button("Started") {
                    onAboutToMutate()
                    state.updateStatus(t, to: .started, instanceDate: day.dateString)
                    triggerUndoSnack("Marked Started")
                }
                .buttonStyle(.bordered).tint(t.status == .started ? .orange : .secondary)

                Button("Done") {
                    onAboutToMutate()
                    state.updateStatus(t, to: .completed, instanceDate: day.dateString)
                    triggerUndoSnack("Marked Done")
                }
                .buttonStyle(.bordered).tint(t.status == .completed ? .green : .secondary)
            }
            .font(.caption)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemBackground)))
    }

    private func bulkArchive(expanded: [TaskItem]) {
        let ids = selectedIds
        onAboutToMutate()
        for t in expanded where ids.contains(t.id) { state.archiveTask(t) }
        selectedIds = []; isBulk = false
        triggerUndoSnack("Archived")
    }
    private func bulkDelete(expanded: [TaskItem]) {
        let ids = selectedIds
        onAboutToMutate()
        for t in expanded where ids.contains(t.id) { state.deleteToTrash(t) }
        selectedIds = []; isBulk = false
        triggerUndoSnack("Deleted")
    }
    private func bulkMoveToInbox(expanded: [TaskItem]) {
        let ids = selectedIds
        onAboutToMutate()
        for t in expanded where ids.contains(t.id) { state.moveToInbox(t) }
        selectedIds = []; isBulk = false
        triggerUndoSnack("Moved to Inbox")
    }

    private func dateLong(_ ds: String) -> String {
        guard let d = ds.asISODateOnlyUTC else { return ds }
        let f = DateFormatter(); f.timeZone = .init(secondsFromGMT: 0); f.dateFormat = "MMMM d, yyyy"
        return f.string(from: d)
    }
}

// MARK: - Archives
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

            let list = state.archivedTasks.filter { $0.archiveReason == state.activeArchiveTab.rawValue }
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

// MARK: - Stats
private struct StatsView: View {
    @ObservedObject var state: AppState
    @Binding var period: ContentView.Period
    @Binding var customStart: Date
    @Binding var customEnd: Date

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
                        ForEach(ContentView.Period.allCases, id: \.self) { p in
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

            // KPI bars (Completed / Started / Open / Total)
            let counts = aggregateCounts(in: range)
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

            // Completed tasks in period
            GroupBox("Completed Tasks in Period") {
                let completed = completedTasks(in: range)
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

            // Ratings breakdown (Open, Done, Deleted)
            GroupBox("Ratings in Period") {
                let ratings = ratingsIn(range)
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

    // KPI helpers
    private func aggregateCounts(in range: ClosedRange<Date>) -> (completed: Int, started: Int, open: Int, total: Int) {
        func within(_ ds: String?) -> Bool { ds?.asISODateOnlyUTC.map(range.contains) ?? false }
        var open = 0, started = 0, done = 0
        for t in state.tasks where within(t.date) {
            switch t.status { case .notStarted: open += 1; case .started: started += 1; case .completed: done += 1 }
        }
        for a in state.archivedTasks where within(a.date) {
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

    private func completedTasks(in range: ClosedRange<Date>) -> [TaskItem] {
        let live = state.tasks.filter { $0.status == .completed && $0.date?.asISODateOnlyUTC.map(range.contains) == true }
        let archived = state.archivedTasks
            .filter { $0.archiveReason == "completed" && $0.date?.asISODateOnlyUTC.map(range.contains) == true }
            .map { a in TaskItem(id: a.id, text: a.text, notes: a.notes, date: a.date, status: .completed, recurrence: nil, createdAt: a.createdAt, startedAt: a.startedAt, completedAt: a.completedAt, completedOverrides: nil) }
        return live + archived
    }

    private func ratingsIn(_ range: ClosedRange<Date>) -> (openLiked: Int, openDisliked: Int, doneLiked: Int, doneDisliked: Int, deletedLiked: Int, deletedDisliked: Int) {
        func within(_ ds: String?) -> Bool { ds?.asISODateOnlyUTC.map(range.contains) ?? false }
        var oL = 0, oD = 0, dL = 0, dD = 0, delL = 0, delD = 0

        for t in state.tasks where within(t.date) {
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
        // Archived "deleted" items currently don’t carry ratings; left at 0.
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

// MARK: - Settings landing (opens sheet)
private struct SettingsLanding: View {
    let openSheet: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            Text("Settings").font(.title2).bold()
            Button("Open Settings", action: openSheet)
                .buttonStyle(.borderedProminent)
            Spacer()
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Settings sheet (profile + menu)
private struct SettingsSheet: View {
    @Binding var isDarkMode: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Profile header
            HStack(alignment: .center, spacing: 12) {
                // Placeholder profile rectangle with initials
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.2))
                    Text("AK").font(.title2).bold()
                }
                .frame(width: 64, height: 64)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Adrian Kisliuk").font(.headline).bold()
                    Text("a.kisliuk@gmail.com").foregroundStyle(.secondary)
                }
                Spacer()
            }

            Divider()

            Toggle(isOn: $isDarkMode) {
                Label("Theme: Dark / Light", systemImage: "moon.circle")
            }

            Group {
                Button("Manage Teams", action: {})
                Button("Subscription", action: {})
                Button("Billing", action: {})
                Button("Languages", action: {})
                Button("Privacy Policy", action: {})
                Button("Terms of Use", action: {})
                Button("Log in/out", action: {})
            }
            .buttonStyle(.bordered)

            Spacer()
        }
        .padding()
    }
}

// MARK: - Edit Task sheet (used from Inbox)
private struct EditTaskSheet: View {
    @Binding var title: String
    @Binding var notes: String
    @Binding var dateStr: String
    @Binding var status: TaskStatus
    @Binding var recurrence: Recurrence
    @Binding var createdBy: String
    @Binding var assignedTo: String

    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Title", text: $title)
                    TextField("Notes", text: $notes)
                }
                Section("Schedule") {
                    TextField("yyyy-MM-dd", text: $dateStr)
                    Picker("Status", selection: $status) {
                        Text("Open").tag(TaskStatus.notStarted)
                        Text("Started").tag(TaskStatus.started)
                        Text("Done").tag(TaskStatus.completed)
                    }
                    Picker("Repeat", selection: $recurrence) {
                        Text("Never").tag(Recurrence.never)
                        Text("Daily").tag(Recurrence.daily)
                        Text("Weekly").tag(Recurrence.weekly)
                        Text("Monthly").tag(Recurrence.monthly)
                    }
                }
                Section("People") {
                    TextField("Created by", text: $createdBy)
                    TextField("Assigned to", text: $assignedTo)
                }
            }
            .navigationTitle("Edit Task")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: onSave)
                }
            }
        }
    }
}

// MARK: - Bulk action bar (Inbox)
private struct BulkActionBar: View {
    let count: Int
    let onArchive: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("\(count) selected").font(.subheadline).bold()
            Spacer()
            Button("Archive", action: onArchive).buttonStyle(.borderedProminent)
            Button("Delete", role: .destructive, action: onDelete).buttonStyle(.borderedProminent)
        }
        .padding(10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Camera placeholder (no-op selection)
private struct CameraPlaceholder: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera").imageScale(.large)
            Text("Camera is a placeholder").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 140)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding()
    }
}

// MARK: - Small helpers
private func formatDateTime(_ d: Date?) -> String {
    guard let d = d else { return "—" }
    let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short
    return f.string(from: d)
}
