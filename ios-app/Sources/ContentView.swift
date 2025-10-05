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

struct ContentView: View {
    @StateObject private var state = AppState()

    // Global UI
    enum Tab { case home, stats, camera, archive, search, settings }
    @State private var tab: Tab = .home
    @State private var showSearchBar = false
    @State private var isDarkMode = false

    // Sheets
    @State private var showingDay: CalendarDay? = nil
    @State private var isModalBulkSelect = false
    @State private var selectedModalIds = Set<Int>()
    @State private var showEditSheet: Bool = false
    @State private var editingTaskForSheet: TaskItem? = nil
    @State private var showSettings: Bool = false
    @State private var showThemeSheet: Bool = false

    // Collapsible sections
    @State private var isCalendarExpanded = true
    @State private var isInboxExpanded = true

    // Snackbar (undo)
    @State private var snackbarText: String = ""
    @State private var showSnackbar: Bool = false

    // Stats period controls
    enum Period: String, CaseIterable { case weekly, monthly, quarterly, semester, yearly, custom }
    @State private var statsPeriod: Period = .weekly
    @State private var customStart: Date = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var customEnd: Date = Date()

    // Search text (shared across tabs)
    @State private var searchText: String = ""

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 12) {
                // Header
                header

                // Search bar under header (toggled from bottom Search button)
                if showSearchBar {
                    TextField("Search tasks…", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: searchText) { state.searchQuery = searchText }
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.horizontal, 2)
                }

                // Main content per tab
                Group {
                    switch tab {
                    case .home, .search:
                        HomeScreen(
                            state: state,
                            isCalendarExpanded: $isCalendarExpanded,
                            isInboxExpanded: $isInboxExpanded,
                            openDay: { showingDay = $0 },
                            onIntent: handleIntentAndSnack
                        )
                    case .archive:
                        ArchivesView2(
                            state: state,
                            onIntent: handleIntentAndSnack
                        )
                    case .stats:
                        StatsView2(
                            state: state,
                            period: $statsPeriod,
                            customStart: $customStart,
                            customEnd: $customEnd
                        )
                    case .camera:
                        CameraPlaceholder()
                    case .settings:
                        // open as sheet for better UX, but if tab == .settings show empty space
                        EmptyView()
                            .onAppear { showSettings = true }
                    }
                }
                .animation(.default, value: tab)

                Spacer(minLength: 0)
            }
            .padding()
            .preferredColorScheme(isDarkMode ? .dark : .light)
            .sheet(item: $showingDay) { day in
                DayModalView2(
                    day: day,
                    state: state,
                    isBulk: $isModalBulkSelect,
                    selectedIds: $selectedModalIds,
                    onIntent: handleIntentAndSnack,
                    onEdit: { task in
                        editingTaskForSheet = task
                        showEditSheet = true
                    }
                )
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showEditSheet) {
                if let task = editingTaskForSheet {
                    EditTaskSheet(
                        state: state,
                        task: task,
                        onDismiss: { showEditSheet = false },
                        onSaved: { updated in
                            // Persist meta and task changes already handled inside sheet
                            showEditSheet = false
                        }
                    )
                    .presentationDetents([.large])
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsSheet(
                    isDarkMode: $isDarkMode,
                    onClose: { showSettings = false },
                    onOpenTheme: { showThemeSheet = true }
                )
                .presentationDetents([.large])
            }
            .sheet(isPresented: $showThemeSheet) {
                ThemeSheet(isDarkMode: $isDarkMode, onClose: { showThemeSheet = false })
                    .presentationDetents([.fraction(0.35)])
            }

            // Bottom bar
            BottomBar(selected: $tab, isDarkMode: $isDarkMode, onTap: { tapped in
                switch tapped {
                case .home:
                    tab = .home; showSearchBar = false
                case .stats:
                    tab = .stats; showSearchBar = false
                case .camera:
                    tab = .camera // does nothing but highlight
                case .archive:
                    tab = .archive; showSearchBar = false
                case .search:
                    // toggle the search bar, keep current tab if .search is tapped again
                    showSearchBar.toggle()
                    if showSearchBar {
                        // keep tab as-is (search works everywhere)
                    } else {
                        // hiding search bar: no-op
                    }
                case .settings:
                    tab = .settings // sheet opens in onAppear
                }
            })

            // Snackbar
            if showSnackbar {
                Snackbar(text: snackbarText, onUndo: {
                    state.undoToLastSnapshot()
                    withAnimation { showSnackbar = false }
                }, onDismiss: {
                    withAnimation { showSnackbar = false }
                })
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .padding(.bottom, 60) // above bottom bar
            }
        }
    }

    // MARK: Header
    private var header: some View {
        HStack {
            Text("Taskmate")
                .font(.title) // slightly smaller than large title
                .bold()
            Spacer()
        }
    }

    // MARK: Intent handler w/ snackbar
    private func handleIntentAndSnack(_ intent: UserIntent) {
        // Take snapshot BEFORE mutating so undo works
        state.snapshotForUndo()

        switch intent {
        case .archive(let task):
            state.archiveTask(task)
            snackbar("Archived “\(task.text)”")
        case .deleteToTrash(let task):
            state.deleteToTrash(task)
            snackbar("Deleted “\(task.text)”")
        case .duplicate(let task):
            state.duplicate(task)
            snackbar("Duplicated “\(task.text)”")
        case .moveToInbox(let task):
            state.moveToInbox(task)
            snackbar("Moved “\(task.text)” to Inbox")
        case .bulkArchive(let tasks):
            tasks.forEach { state.archiveTask($0) }
            snackbar("Archived \(tasks.count) task(s)")
        case .bulkDelete(let tasks):
            tasks.forEach { state.deleteToTrash($0) }
            snackbar("Deleted \(tasks.count) task(s)")
        }
    }

    private func snackbar(_ message: String) {
        snackbarText = message
        withAnimation { showSnackbar = true }
        // auto-hide after a few seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            withAnimation { showSnackbar = false }
        }
    }
}

// MARK: - Intent enum to route actions into snackbar/undo
enum UserIntent {
    case archive(TaskItem)
    case deleteToTrash(TaskItem)
    case duplicate(TaskItem)
    case moveToInbox(TaskItem)
    case bulkArchive([TaskItem])
    case bulkDelete([TaskItem])
}

// MARK: - Bottom bar
private struct BottomBar: View {
    @Binding var selected: ContentView.Tab
    @Binding var isDarkMode: Bool
    let onTap: (ContentView.Tab) -> Void

    private func item(_ tab: ContentView.Tab, _ system: String, _ label: String) -> some View {
        Button {
            onTap(tab)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: system)
                    .imageScale(.large)
                    .foregroundStyle(selected == tab ? Color.blue : Color.primary)
                Text(label).font(.caption2)
            }
            .frame(maxWidth: .infinity)
        }
    }

    var body: some View {
        HStack {
            item(.home, "house", "Home")
            item(.stats, "chart.bar", "Stats")
            item(.camera, "camera", "Camera") // just highlights
            item(.archive, "archivebox", "Archive")
            item(.search, "magnifyingglass", "Search")
            item(.settings, "gearshape", "Settings")
        }
        .padding(.vertical, 8)
        .background(.thinMaterial)
    }
}

// MARK: - Home screen (Calendar + Inbox, collapsible)
private struct HomeScreen: View {
    @ObservedObject var state: AppState
    @Binding var isCalendarExpanded: Bool
    @Binding var isInboxExpanded: Bool

    var openDay: (CalendarDay) -> Void
    var onIntent: (UserIntent) -> Void

    var body: some View {
        VStack(spacing: 10) {
            // Calendar header
            SectionHeader(
                title: "Daily Calendar",
                expanded: $isCalendarExpanded,
                trailing: { CalendarHeaderControls(state: state) }
            )

            if isCalendarExpanded {
                CalendarPanel2(state: state, openDay: openDay)
            }

            // Inbox header with Select
            SectionHeader(
                title: "Task List",
                expanded: $isInboxExpanded,
                trailing: { InboxHeaderControls(state: state) }
            )

            if isInboxExpanded {
                InboxPanel2(state: state, onIntent: onIntent)
            }
        }
    }
}

// MARK: - Section header with chevron
private struct SectionHeader<Trailing: View>: View {
    let title: String
    @Binding var expanded: Bool
    let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation { expanded.toggle() }
            } label: {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .imageScale(.medium)
            }
            .buttonStyle(.plain)

            Text(title).font(.title3).bold()
            Spacer()
            trailing()
        }
    }
}

// MARK: - Calendar header controls (icons only)
private struct CalendarHeaderControls: View {
    @ObservedObject var state: AppState

    var body: some View {
        HStack(spacing: 8) {
            // View toggle icon (list ↔︎ card)
            Button {
                withAnimation {
                    state.calendarViewMode = (state.calendarViewMode == .card ? .list : .card)
                }
            } label: {
                Image(systemName: state.calendarViewMode == .card ? "square.grid.2x2" : "list.bullet")
            }
            .buttonStyle(.bordered)

            // Filter (funnel)
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
                Image(systemName: "line.3.horizontal.decrease.circle") // funnel-ish
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(.bordered)

            // Today icon only
            Button {
                withAnimation {
                    state.calendarStartDate = Calendar.current.date(byAdding: .day, value: -3, to: Date()) ?? Date()
                }
            } label: { Image(systemName: "calendar.badge.clock") }
            .buttonStyle(.borderedProminent)
        }
    }
}

// MARK: - Calendar panel (white cards/list)
private struct CalendarPanel2: View {
    @ObservedObject var state: AppState
    var openDay: (CalendarDay) -> Void

    var body: some View {
        let days = state.calendarDays()
        let expanded = state.visibleCalendarTasks(for: days)
        let tasksByDay = Dictionary(grouping: expanded) { $0.date ?? "" }

        VStack(alignment: .leading, spacing: 10) {
            if state.calendarViewMode == .card {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(days) { day in
                                let list = (tasksByDay[day.dateString] ?? [])
                                    .filter { state.calendarFilters[$0.status] ?? true }
                                DayCard2(day: day, tasks: list) { openDay(day) }
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
                                    DayRow2(day: day, tasks: list) { openDay(day) }
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
        .padding()
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
                    state.reschedule(t, to: day.dateString)
                }
            }
        }
        return true
    }
}

private struct DayCard2: View {
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
                .fill(Color.white)
                .shadow(radius: 1, y: 1)
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

private struct DayRow2: View {
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
                .shadow(radius: 1, y: 1)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(isToday ? .blue : .clear))
        )
        .onTapGesture { onTap() }
    }

    private func dateLong(_ ds: String) -> String {
        guard let d = ds.asISODateOnlyUTC else { return ds }
        let f = DateFormatter(); f.timeZone = .init(secondsFromGMT: 0); f.dateFormat = "EEEE, MMMM d"
        return f.string(from: d)
    }

    @ViewBuilder private func chip(_ text: String, _ color: Color) -> some View {
        Text(text).font(.caption2).bold()
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.18))
            .foregroundStyle(color).clipShape(Capsule())
    }
}

// MARK: - Inbox panel v2 (Select mode, bulk bar, reorder with blue line, edit via sheet)
private struct InboxPanel2: View {
    @ObservedObject var state: AppState
    var onIntent: (UserIntent) -> Void

    @State private var newTaskText = ""
    @State private var isSelecting = false
    @State private var selectedIds = Set<Int>()
    @State private var dropTarget: Int? = nil // for blue line indicator
    @State private var showEditSheet = false
    @State private var editingTask: TaskItem? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            inputRow

            Group {
                if state.unassignedTasks.isEmpty {
                    CompatEmptyState(title: "No unassigned tasks", systemImage: "tray")
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    List {
                        ForEach(state.unassignedTasks) { t in
                            inboxRow(t)
                                .overlay(alignment: .top) {
                                    if dropTarget == t.id {
                                        Rectangle().fill(Color.blue).frame(height: 2)
                                    }
                                }
                                .onDrag { NSItemProvider(object: NSString(string: "\(t.id)")) }
                                .onDrop(of: [.plainText], isTargeted: nil, perform: { providers in
                                    handleInboxDrop(on: t, providers: providers)
                                })
                        }
                    }
                    .listStyle(.inset)
                    .frame(minHeight: 160, maxHeight: 320)
                }
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .safeAreaInset(edge: .bottom, content: {
            if isSelecting && !selectedIds.isEmpty {
                BulkBar(
                    count: selectedIds.count,
                    onArchive: {
                        let tasks = state.unassignedTasks.filter { selectedIds.contains($0.id) }
                        onIntent(.bulkArchive(tasks))
                        isSelecting = false; selectedIds.removeAll()
                    },
                    onDelete: {
                        let tasks = state.unassignedTasks.filter { selectedIds.contains($0.id) }
                        onIntent(.bulkDelete(tasks))
                        isSelecting = false; selectedIds.removeAll()
                    }
                )
            }
        })
    }

    private var inputRow: some View {
        HStack(spacing: 8) {
            TextField("Add a new task…", text: $newTaskText, onCommit: addTask)
                .textFieldStyle(.roundedBorder)
            Button(action: addTask) {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderedProminent)

            Spacer()

            Button(isSelecting ? "Cancel" : "Select") {
                isSelecting.toggle()
                selectedIds.removeAll()
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder private func inboxRow(_ t: TaskItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if isSelecting {
                Button {
                    if selectedIds.contains(t.id) { selectedIds.remove(t.id) } else { selectedIds.insert(t.id) }
                } label: {
                    Image(systemName: selectedIds.contains(t.id) ? "checkmark.square" : "square")
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(t.text).font(.body).bold()
                    if t.isRecurring { Image(systemName: "repeat") }
                    Spacer()

                    // Recurrence menu (icon only)
                    Menu {
                        Button("Never") { state.updateRecurrence(t, to: .never) }
                        Button("Daily") { state.updateRecurrence(t, to: .daily) }
                        Button("Weekly") { state.updateRecurrence(t, to: .weekly) }
                        Button("Monthly") { state.updateRecurrence(t, to: .monthly) }
                    } label: { Image(systemName: "repeat") }

                    // Thumb rating button (cycle neutral → like → dislike → neutral)
                    Button {
                        toggleRating(for: t, on: nil) // inbox (no instance date)
                    } label: {
                        thumbImage(for: t, on: nil)
                    }

                    // 3-dot menu
                    Menu {
                        Button { editingTask = t; showEditSheet = true } label: { Label("Edit", systemImage: "pencil") }
                        Button(role: .destructive) { onIntent(.deleteToTrash(t)) } label: { Label("Delete", systemImage: "trash") }
                        Button { onIntent(.duplicate(t)) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                        Button { onIntent(.archive(t)) } label: { Label("Archive", systemImage: "archivebox") }
                    } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton)
                }

                // Scheduled date display (instead of created time)
                if let ds = t.date, !ds.isEmpty {
                    Text("Scheduled: \(ds)").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            if let task = editingTask {
                EditTaskSheet(
                    state: state,
                    task: task,
                    onDismiss: { showEditSheet = false },
                    onSaved: { _ in showEditSheet = false }
                )
                .presentationDetents([.large])
            }
        }
    }

    private func addTask() {
        guard !newTaskText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        state.addTask(text: newTaskText)
        newTaskText = ""
    }

    private func handleInboxDrop(on target: TaskItem, providers: [NSItemProvider]) -> Bool {
        dropTarget = target.id
        guard let provider = providers.first else { dropTarget = nil; return false }
        provider.loadItem(forTypeIdentifier: "public.plain-text", options: nil) { data, _ in
            DispatchQueue.main.async { dropTarget = nil }
            guard
                let d = data as? Data,
                let idStr = String(data: d, encoding: .utf8),
                let draggedId = Int(idStr),
                let fromIndex = state.tasks.firstIndex(where: { $0.id == draggedId }),
                let toIndex = state.tasks.firstIndex(where: { $0.id == target.id })
            else { return }
            DispatchQueue.main.async {
                guard state.tasks[fromIndex].date == nil, state.tasks[toIndex].date == nil else { return }
                let item = state.tasks.remove(at: fromIndex)
                state.tasks.insert(item, at: toIndex)
            }
        }
        return true
    }

    private func toggleRating(for t: TaskItem, on instanceDate: String?) {
        let current: TaskRating? = {
            if let ds = instanceDate { return t.completedOverrides?[ds]?.rating }
            let key = t.date ?? ""
            return t.completedOverrides?[key]?.rating
        }()
        let next: TaskRating? = {
            switch current {
            case nil: return .liked
            case .some(.liked): return .disliked
            case .some(.disliked): return nil
            }
        }()
        state.rate(t, rating: next, instanceDate: instanceDate)
    }

    @ViewBuilder private func thumbImage(for t: TaskItem, on instanceDate: String?) -> some View {
        let rating: TaskRating? = {
            if let ds = instanceDate { return t.completedOverrides?[ds]?.rating }
            let key = t.date ?? ""
            return t.completedOverrides?[key]?.rating
        }()
        Image(systemName:
                rating == .liked ? "hand.thumbsup.fill" :
                rating == .disliked ? "hand.thumbsdown.fill" :
                "hand.thumbsup") // neutral as sideways isn’t available; using outline thumb
    }
}

// Bulk action bar for select mode
private struct BulkBar: View {
    let count: Int
    let onArchive: () -> Void
    let onDelete: () -> Void
    var body: some View {
        HStack {
            Text("\(count) selected").bold()
            Spacer()
            Button("Archive", action: onArchive).buttonStyle(.bordered)
            Button("Delete", role: .destructive, action: onDelete).buttonStyle(.borderedProminent)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Day Modal v2 (Edit option, Delete wording, thumb as button)
private struct DayModalView2: View {
    let day: CalendarDay
    @ObservedObject var state: AppState
    @Binding var isBulk: Bool
    @Binding var selectedIds: Set<Int>

    var onIntent: (UserIntent) -> Void
    var onEdit: (TaskItem) -> Void

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
                        Button("Delete", role: .destructive) { bulkDelete(expanded: expanded) }
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

                // Repeat (icon)
                Menu {
                    Button("Never") { state.updateRecurrence(t, to: .never) }
                    Button("Daily") { state.updateRecurrence(t, to: .daily) }
                    Button("Weekly") { state.updateRecurrence(t, to: .weekly) }
                    Button("Monthly") { state.updateRecurrence(t, to: .monthly) }
                } label: { Image(systemName: "repeat") }

                // Thumb rating button cycles
                Button {
                    toggleRating(for: t, on: day.dateString)
                } label: {
                    thumbImage(for: t, on: day.dateString)
                }

                // 3-dots (Edit + Delete wording)
                Menu {
                    Button { onEdit(t) } label: { Label("Edit", systemImage: "pencil") }
                    Button(role: .destructive) { onIntent(.deleteToTrash(t)) } label: { Label("Delete", systemImage: "trash") }
                    Button { onIntent(.moveToInbox(t)) } label: { Label("Move to Inbox", systemImage: "tray") }
                    Button { onIntent(.duplicate(t)) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                    Button { onIntent(.archive(t)) } label: { Label("Archive", systemImage: "archivebox") }
                } label: { Image(systemName: "ellipsis.circle") }
            }

            if let n = t.notes, !n.isEmpty {
                Text(n).font(.subheadline).foregroundStyle(.secondary)
            }

            // Status buttons (smaller, colored when active)
            HStack(spacing: 8) {
                Button("Open") { state.updateStatus(t, to: .notStarted, instanceDate: day.dateString) }
                    .buttonStyle(.bordered).tint(t.status == .notStarted ? .blue : .secondary)
                Button("Started") { state.updateStatus(t, to: .started, instanceDate: day.dateString) }
                    .buttonStyle(.bordered).tint(t.status == .started ? .orange : .secondary)
                Button("Done") { state.updateStatus(t, to: .completed, instanceDate: day.dateString) }
                    .buttonStyle(.bordered).tint(t.status == .completed ? .green : .secondary)
            }
            .font(.caption)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white).shadow(radius: 1, y: 1))
    }

    private func toggleRating(for t: TaskItem, on instanceDate: String?) {
        let current: TaskRating? = {
            if let ds = instanceDate { return t.completedOverrides?[ds]?.rating }
            let key = t.date ?? ""
            return t.completedOverrides?[key]?.rating
        }()
        let next: TaskRating? = {
            switch current {
            case nil: return .liked
            case .some(.liked): return .disliked
            case .some(.disliked): return nil
            }
        }()
        state.rate(t, rating: next, instanceDate: instanceDate)
    }

    @ViewBuilder private func thumbImage(for t: TaskItem, on instanceDate: String?) -> some View {
        let rating: TaskRating? = {
            if let ds = instanceDate { return t.completedOverrides?[ds]?.rating }
            let key = t.date ?? ""
            return t.completedOverrides?[key]?.rating
        }()
        Image(systemName:
                rating == .liked ? "hand.thumbsup.fill" :
                rating == .disliked ? "hand.thumbsdown.fill" :
                "hand.thumbsup")
    }

    private func bulkArchive(expanded: [TaskItem]) {
        let ids = selectedIds
        let ts = expanded.filter { ids.contains($0.id) }
        onIntent(.bulkArchive(ts))
        selectedIds = []; isBulk = false
    }
    private func bulkDelete(expanded: [TaskItem]) {
        let ids = selectedIds
        let ts = expanded.filter { ids.contains($0.id) }
        onIntent(.bulkDelete(ts))
        selectedIds = []; isBulk = false
    }
    private func bulkMoveToInbox(expanded: [TaskItem]) {
        let ids = selectedIds
        let ts = expanded.filter { ids.contains($0.id) }
        ts.forEach { onIntent(.moveToInbox($0)) }
        selectedIds = []; isBulk = false
    }

    private func dateLong(_ ds: String) -> String {
        guard let d = ds.asISODateOnlyUTC else { return ds }
        let f = DateFormatter(); f.timeZone = .init(secondsFromGMT: 0); f.dateFormat = "MMMM d, yyyy"
        return f.string(from: d)
    }
}

// MARK: - Archives screen (title change, no “Back to Calendar”, select UI)
private struct ArchivesView2: View {
    @ObservedObject var state: AppState
    var onIntent: (UserIntent) -> Void

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
                            toRestore.forEach { state.restoreTask($0) }
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

// MARK: - Stats screen (title “Stats”, period picker, KPI bars, completed list, ratings incl. deleted)
private struct StatsView2: View {
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

            // KPI bars
            let counts = aggregateCounts(in: range)
            KPIBars(completed: counts.completed, started: counts.started, open: counts.open, total: counts.total)

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
        // Archived “deleted” items don’t currently store ratings → 0
        return (oL, oD, dL, dD, delL, delD)
    }
}

// MARK: - Settings
private struct SettingsSheet: View {
    @Binding var isDarkMode: Bool
    let onClose: () -> Void
    let onOpenTheme: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Profile header
                HStack(alignment: .center, spacing: 12) {
                    // Placeholder avatar
                    ZStack {
                        Circle().fill(Color.secondary.opacity(0.2))
                        Image(systemName: "person.fill").imageScale(.large)
                    }
                    .frame(width: 56, height: 56)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Adrian Kisliuk").bold()
                        Text("a.kisliuk@gmail.com").foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding()
                Divider()

                List {
                    Button("Manage Teams") {}
                    Button("Subscription") {}
                    Button("Billing") {}
                    Button("Languages") {}
                    Button("Privacy Policy") {}
                    Button("Terms of Use") {}
                    Button("Theme") { onOpenTheme() }
                    Button("Log in/out") {}
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close", action: onClose)
                }
            }
        }
    }
}

private struct ThemeSheet: View {
    @Binding var isDarkMode: Bool
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Button("Dark") { isDarkMode = true }
                    .buttonStyle(.borderedProminent)
                Button("Light") { isDarkMode = false }
                    .buttonStyle(.bordered)
                Button("System Mode") { /* no-op */ }
                    .buttonStyle(.bordered)
                Spacer()
            }
            .padding()
            .navigationTitle("Theme")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close", action: onClose)
                }
            }
        }
    }
}

// MARK: - Edit Task Sheet (adds “Assign to”, shows Created by/Assigned to)
private struct EditTaskSheet: View {
    @ObservedObject var state: AppState
    let task: TaskItem
    let onDismiss: () -> Void
    let onSaved: (TaskItem) -> Void

    @State private var text: String
    @State private var notes: String
    @State private var date: String
    @State private var status: TaskStatus
    @State private var recurrence: Recurrence
    @State private var assignedTo: String
    let createdBy: String

    init(state: AppState, task: TaskItem, onDismiss: @escaping () -> Void, onSaved: @escaping (TaskItem) -> Void) {
        self.state = state
        self.task = task
        self.onDismiss = onDismiss
        self.onSaved = onSaved
        _text = State(initialValue: task.text)
        _notes = State(initialValue: task.notes ?? "")
        _date = State(initialValue: task.date ?? "")
        _status = State(initialValue: task.status)
        _recurrence = State(initialValue: task.recurrence ?? .never)
        let meta = state.taskMeta[task.id] ?? AppState.TaskMeta()
        _assignedTo = State(initialValue: meta.assignedTo)
        createdBy = meta.createdBy
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Title", text: $text)
                    TextField("Notes", text: $notes)
                    TextField("Schedule (yyyy-MM-dd)", text: $date)
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
                Section("Assignment") {
                    HStack { Text("Created by"); Spacer(); Text(createdBy).foregroundStyle(.secondary) }
                    HStack {
                        Text("Assigned to")
                        Spacer()
                        TextField("Name or email", text: $assignedTo)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
            .navigationTitle("Edit Task")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel", action: onDismiss) }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        // Save changes
                        if let i = state.tasks.firstIndex(where: { $0.id == task.id }) {
                            state.tasks[i].text = text.trimmingCharacters(in: .whitespaces)
                            state.tasks[i].notes = notes.trimmingCharacters(in: .whitespaces)
                            state.tasks[i].date = date.isEmpty ? nil : date
                            state.updateStatus(state.tasks[i], to: status)
                            state.updateRecurrence(state.tasks[i], to: recurrence)
                        }
                        state.taskMeta[task.id] = AppState.TaskMeta(createdBy: createdBy, assignedTo: assignedTo)
                        onSaved(task)
                    }
                }
            }
        }
    }
}

// MARK: - Snackbar
private struct Snackbar: View {
    let text: String
    let onUndo: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack {
            Text(text).lineLimit(2)
            Spacer()
            Button("Undo", action: onUndo)
            Button(action: onDismiss) {
                Image(systemName: "xmark").imageScale(.small)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(radius: 2, y: 1)
        .padding(.horizontal)
    }
}

// MARK: - Small helpers
private func formatDateTime(_ d: Date?) -> String {
    guard let d = d else { return "—" }
    let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short
    return f.string(from: d)
}
