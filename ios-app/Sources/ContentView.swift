// ios-app/Sources/ContentView.swift
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

    // Sheets / modals
    @State private var showingDay: CalendarDay? = nil
    @State private var isModalBulkSelect = false
    @State private var selectedModalIds = Set<Int>()
    @State private var showingMenu = false
    @State private var isDarkMode = false
    @State private var showingSearch = false // kept for header; bottom search uses inline bar

    // Collapse states
    @State private var isCalendarCollapsed = false
    @State private var isInboxCollapsed = false

    // Bottom navigation
    enum BottomTab { case home, stats, camera, archive, search }
    @State private var selectedTab: BottomTab = .home

    // Stats period controls
    enum Period: String, CaseIterable { case weekly, monthly, quarterly, semester, yearly, custom }
    @State private var statsPeriod: Period = .weekly
    @State private var customStart: Date = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var customEnd: Date = Date()

    var body: some View {
        VStack(spacing: 16) {
            header

            // Inline search bar — appears globally when Search tab is selected
            if selectedTab == .search {
                InlineSearchBar(
                    text: $state.searchQuery,
                    onClearAndHide: {
                        state.searchQuery = ""
                        selectedTab = .home // hide search bar per your spec
                    }
                )
            }

            mainPanels
        }
        .padding()
        .frame(maxHeight: .infinity, alignment: .top) // top-pinned app
        .preferredColorScheme(isDarkMode ? .dark : .light)
        .safeAreaInset(edge: .bottom) {
            BottomNavBar(
                selected: selectedTab,
                onSelect: selectTab(_:))
        }
        .sheet(item: $showingDay) { day in
            DayModalView(day: day, state: state,
                         isBulk: $isModalBulkSelect,
                         selectedIds: $selectedModalIds)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingSearch) {
            // Header search (legacy behavior, unchanged). Bottom "Search" uses inline bar.
            SearchSheet(searchText: $state.searchQuery)
                .presentationDetents([.fraction(0.25), .medium])
        }
        .sheet(isPresented: $showingMenu) {
            MenuSheet(
                searchText: $state.searchQuery,
                isDarkMode: $isDarkMode,
                gotoHome: {
                    // From menu: go Home but DO NOT reset collapse states
                    state.isArchiveViewActive = false
                    state.isStatsViewActive = false
                    selectedTab = .home
                    showingMenu = false
                },
                gotoArchives: {
                    state.isArchiveViewActive = true
                    state.isStatsViewActive = false
                    selectedTab = .archive // do not auto-sync when header buttons used; but via menu it's explicit
                    showingMenu = false
                },
                gotoStats: {
                    state.isStatsViewActive = true
                    state.isArchiveViewActive = false
                    selectedTab = .stats
                    showingMenu = false
                }
            )
            .presentationDetents([.fraction(0.45), .large])
        }
    }

    // MARK: Header (compact — icons only on right)
    private var header: some View {
        HStack(spacing: 12) {
            Text("TaskMate")
                .font(.title)
                .bold()

            Spacer()

            HStack(spacing: 10) {
                // Keep legacy header search (sheet). Bottom-bar Search uses inline bar.
                Button { showingSearch = true } label: { Image(systemName: "magnifyingglass").imageScale(.large) }
                    .accessibilityLabel("Search")

                Button {
                    state.isStatsViewActive.toggle()
                    if state.isStatsViewActive { state.isArchiveViewActive = false }
                    // Per your spec, bottom bar selection should NOT auto-sync when header toggles.
                } label: { Image(systemName: "chart.bar").imageScale(.large) }
                    .accessibilityLabel("Stats")

                Button {
                    state.isArchiveViewActive.toggle()
                    if state.isArchiveViewActive { state.isStatsViewActive = false }
                    // No auto-sync to bottom-bar selection when header toggles.
                } label: { Image(systemName: "archivebox").imageScale(.large) }
                    .accessibilityLabel("Archives")

                Button { showingMenu = true } label: { Image(systemName: "line.3.horizontal").imageScale(.large) }
                    .accessibilityLabel("Menu")
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: Main panels
    private var mainPanels: some View {
        // Layout rules:
        // - Default (both expanded): Inbox fills the remainder.
        // - Calendar collapsed: Inbox fills remainder (shows more tasks).
        // - Inbox collapsed: Calendar fills remainder (List shows more; Card stretches).
        // - Both collapsed: Inbox card fills remaining space, content hidden.
        let bothCollapsed = isCalendarCollapsed && isInboxCollapsed
        let expandCalendar = (!isCalendarCollapsed && isInboxCollapsed && !state.isArchiveViewActive && !state.isStatsViewActive)
        let expandInboxDefault = (!isInboxCollapsed && !(state.isArchiveViewActive || state.isStatsViewActive))
        let expandInboxWhenBothCollapsed = bothCollapsed && !(state.isArchiveViewActive || state.isStatsViewActive)
        let expandInbox = expandInboxDefault || expandInboxWhenBothCollapsed

        return VStack(spacing: 12) {
            Group {
                if state.isStatsViewActive {
                    StatsView(state: state, period: $statsPeriod, customStart: $customStart, customEnd: $customEnd)
                } else if state.isArchiveViewActive {
                    ArchivesView(state: state)
                } else {
                    CalendarPanel(
                        state: state,
                        collapsed: $isCalendarCollapsed,
                        shouldFill: expandCalendar
                    ) { day in
                        showingDay = day
                    }
                    .frame(maxHeight: expandCalendar ? .infinity : nil, alignment: .top)
                }
            }

            if !(state.isArchiveViewActive || state.isStatsViewActive) {
                InboxPanel(
                    state: state,
                    collapsed: $isInboxCollapsed,
                    shouldFill: expandInbox
                )
                .frame(maxHeight: expandInbox ? .infinity : nil, alignment: .top)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Bottom bar selection handler
    private func selectTab(_ tab: BottomTab) {
        selectedTab = tab
        switch tab {
        case .home:
            // Navigate to Home (Calendar + Inbox), DO NOT reset collapse states
            state.isStatsViewActive = false
            state.isArchiveViewActive = false
        case .stats:
            state.isStatsViewActive = true
            state.isArchiveViewActive = false
        case .archive:
            state.isArchiveViewActive = true
            state.isStatsViewActive = false
        case .search:
            // Just show inline search bar globally; no other nav change
            break
        case .camera:
            // Do nothing except selection (blue state)
            break
        }
    }
}

// MARK: - Inline Search Bar (global, below header)
private struct InlineSearchBar: View {
    @Binding var text: String
    var onClearAndHide: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .imageScale(.medium)
                .foregroundStyle(.secondary)

            TextField("Search tasks…", text: $text)
                .textFieldStyle(.roundedBorder)

            if !text.isEmpty {
                Button {
                    onClearAndHide()
                } label: {
                    Image(systemName: "xmark.circle.fill").imageScale(.medium)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search and hide")
            } else {
                Button {
                    onClearAndHide()
                } label: {
                    Text("Cancel")
                }
                .accessibilityLabel("Hide search")
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Bottom Nav Bar
private struct BottomNavBar: View {
    let selected: ContentView.BottomTab
    let onSelect: (ContentView.BottomTab) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                item(.home, label: "Home", systemImage: "house")
                item(.stats, label: "Stats", systemImage: "chart.bar")
                item(.camera, label: "Camera", systemImage: "camera")
                item(.archive, label: "Archive", systemImage: "archivebox")
                item(.search, label: "Search", systemImage: "magnifyingglass")
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 10) // comfy tap target
            .background(.ultraThinMaterial)
        }
    }

    @ViewBuilder
    private func item(_ tab: ContentView.BottomTab, label: String, systemImage: String) -> some View {
        let isSel = (selected == tab)
        Button {
            onSelect(tab)
        } label: {
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                    .imageScale(.large)
                Text(label)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(isSel ? Color.blue : Color.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// =========================
// The rest of your file is unchanged, except where noted earlier
// =========================

// MARK: - Calendar panel
private struct CalendarPanel: View {
    @ObservedObject var state: AppState
    @Binding var collapsed: Bool
    var shouldFill: Bool
    var openDay: (CalendarDay) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Fixed header
            HStack {
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) { collapsed.toggle() }
                } label: {
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(collapsed ? -90 : 0)) // right when collapsed
                        .animation(.easeInOut, value: collapsed)
                        .imageScale(.medium)
                        .padding(.trailing, 2)
                }
                .accessibilityLabel(collapsed ? "Expand Daily Calendar" : "Collapse Daily Calendar")

                Text("Daily Calendar").font(.title3).bold()
                Spacer()

                // View menu
                Menu {
                    Picker("View", selection: $state.calendarViewMode) {
                        Text("Cards").tag(CalendarViewMode.card)
                        Text("List").tag(CalendarViewMode.list)
                    }
                } label: { Label("View", systemImage: "rectangle.3.offgrid") }
                .menuStyle(.borderlessButton)
                .buttonStyle(.bordered)

                // Filter menu
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
                } label: { Label("Filter", systemImage: "line.3.horizontal.decrease.circle") }
                .menuStyle(.borderlessButton)
                .buttonStyle(.bordered)

                Divider().frame(height: 22)

                Button("Today") {
                    withAnimation {
                        state.calendarStartDate = Calendar.current.date(byAdding: .day, value: -3, to: Date()) ?? Date()
                    }
                }
                .buttonStyle(.borderedProminent)
            }

            // Content collapses upward
            if !collapsed {
                let days = state.calendarDays()
                let expanded = state.visibleCalendarTasks(for: days)
                let tasksByDay = Dictionary(grouping: expanded) { $0.date ?? "" }

                if state.calendarViewMode == .card {
                    // Horizontal cards: stretch vertically when shouldFill is true
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(days) { day in
                                    let list = (tasksByDay[day.dateString] ?? [])
                                        .filter { state.calendarFilters[$0.status] ?? true }
                                    DayCard(
                                        day: day,
                                        tasks: list,
                                        bg: Color(UIColor.systemGray6)
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
                        .frame(maxHeight: shouldFill ? .infinity : nil, alignment: .top)
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
                } else {
                    // LIST mode: allow vertical growth when the inbox is collapsed.
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
                                            bg: Color(UIColor.systemGray6)
                                        ) { openDay(day) }
                                        .id(dayListID(day.dateString))
                                    }
                                }
                                if expanded.filter({ state.calendarFilters[$0.status] ?? true }).isEmpty {
                                    CompatEmptyState(title: "No scheduled tasks in this period match your filters", systemImage: "calendar")
                                        .padding(.top, 16)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .top)
                            .onAppear {
                                let today = ISO8601.dateOnly.string(from: Date())
                                withAnimation { proxy.scrollTo(dayListID(today), anchor: .top) }
                            }
                        }
                        .frame(maxHeight: shouldFill ? .infinity : 260, alignment: .top)
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .move(edge: .top).combined(with: .opacity)
                        ))
                    }
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

// MARK: - Inbox panel
private struct InboxPanel: View {
    @ObservedObject var state: AppState
    @Binding var collapsed: Bool
    var shouldFill: Bool

    // Local states
    @State private var newTaskText = ""
    @State private var editingTaskId: Int? = nil
    @State private var editText = ""
    @State private var editNotes = ""
    @State private var editDate: String = ""
    @State private var editStatus: TaskStatus = .notStarted
    @State private var editRecurrence: Recurrence = .never

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Fixed header
            header

            // Content collapses downward
            if !collapsed {
                VStack(alignment: .leading, spacing: 8) {
                    inputRow

                    if state.unassignedTasks.isEmpty {
                        CompatEmptyState(title: "No unassigned tasks", systemImage: "tray")
                            .frame(maxWidth: .infinity, minHeight: 120, alignment: .top)
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
                        .frame(minHeight: 140, maxHeight: shouldFill ? .infinity : 300, alignment: .top)
                    }

                    if state.isBulkSelectActiveInbox, !state.selectedInboxTaskIds.isEmpty {
                        HStack {
                            Text("\(state.selectedInboxTaskIds.count) selected").font(.subheadline).bold()
                            Spacer()
                            Menu("Actions") {
                                Button("Archive") { state.archiveSelectedInbox() }
                                Button("Delete", role: .destructive) { state.deleteSelectedInbox() }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(.top, 6)
                    }
                }
                .frame(maxHeight: shouldFill ? .infinity : nil, alignment: .top)
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .move(edge: .bottom).combined(with: .opacity)
                ))
            } else if shouldFill {
                // When collapsed AND we should fill (e.g., both collapsed),
                // stretch the card to the bottom while keeping tasks hidden.
                Spacer(minLength: 0)
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .onDrop(of: [.plainText], isTargeted: nil, perform: { providers in
            guard let provider = providers.first else { return false }
            provider.loadItem(forTypeIdentifier: "public.plain-text", options: nil) { data, _ in
                guard
                    let d = data as? Data,
                    let idStr = String(data: d, encoding: .utf8),
                    let id = Int(idStr),
                    let t = state.tasks.first(where: { $0.id == id })
                else { return }
                DispatchQueue.main.async { state.moveToInbox(t) }
            }
            return true
        })
        .frame(maxHeight: shouldFill ? .infinity : nil, alignment: .top)
    }

    private var header: some View {
        HStack {
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) { collapsed.toggle() }
            } label: {
                Image(systemName: "chevron.down")
                    .rotationEffect(.degrees(collapsed ? -90 : 0)) // right when collapsed
                    .animation(.easeInOut, value: collapsed)
                    .imageScale(.medium)
                    .padding(.trailing, 2)
            }
            .accessibilityLabel(collapsed ? "Expand Task Inbox" : "Collapse Task Inbox")

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
    }

    private var inputRow: some View {
        HStack(spacing: 8) {
            TextField("Add a new task…", text: $newTaskText, onCommit: addTask)
                .textFieldStyle(.roundedBorder)
            Button(action: addTask) { Image(systemName: "plus") }
                .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder private func inboxRow(_ t: TaskItem) -> some View {
        let isEditing = editingTaskId == t.id
        HStack(alignment: .top, spacing: 10) {
            if state.isBulkSelectActiveInbox {
                Button {
                    if state.selectedInboxTaskIds.contains(t.id) {
                        state.selectedInboxTaskIds.remove(t.id)
                    } else {
                        state.selectedInboxTaskIds.insert(t.id)
                    }
                } label: {
                    Image(systemName: state.selectedInboxTaskIds.contains(t.id) ? "checkmark.square" : "square")
                }
            }

            if isEditing {
                InboxEditForm(
                    t: t,
                    editText: $editText,
                    editNotes: $editNotes,
                    editDate: $editDate,
                    editStatus: $editStatus,
                    editRecurrence: $editRecurrence,
                    onCancel: { editingTaskId = nil },
                    onSave: { saveEdits(t) }
                )
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(t.text).font(.subheadline)
                    if let notes = t.notes, !notes.isEmpty {
                        Text(notes).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Menu {
                    Button(role: .destructive) { state.deleteToTrash(t) } label: { Label("Delete", systemImage: "trash") }
                    Button { state.duplicate(t) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                    Button { state.archiveTask(t) } label: { Label("Archive", systemImage: "archivebox") }
                } label: {
                    Image(systemName: "ellipsis.circle").imageScale(.large).padding(4)
                }
                .menuStyle(.borderlessButton)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { beginEdit(t) }
    }

    private func addTask() {
        state.addTask(text: newTaskText)
        newTaskText = ""
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
                let item = state.tasks.remove(at: fromIndex)
                state.tasks.insert(item, at: toIndex)
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
                        Button("Delete Permanently", role: .destructive) { bulkDelete(expanded: expanded) }
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
                    } label: { Image(systemName: "checkmark.square") }
                }
                Text(t.text).font(.body).bold()
                if t.isRecurring { Image(systemName: "repeat") }
                Spacer()

                Menu {
                    Button("Never") { state.updateRecurrence(t, to: .never) }
                    Button("Daily") { state.updateRecurrence(t, to: .daily) }
                    Button("Weekly") { state.updateRecurrence(t, to: .weekly) }
                    Button("Monthly") { state.updateRecurrence(t, to: .monthly) }
                } label: { Image(systemName: "repeat") }

                Menu {
                    Button("Like") { state.rate(t, rating: .liked, instanceDate: day.dateString) }
                    Button("Dislike") { state.rate(t, rating: .disliked, instanceDate: day.dateString) }
                    Button("Clear") { state.rate(t, rating: nil, instanceDate: day.dateString) }
                } label: { Image(systemName: "hand.thumbsup") }

                Menu {
                    Button(role: .destructive) { state.deleteToTrash(t) } label: { Label("Delete", systemImage: "trash") }
                    Button { state.moveToInbox(t) } label: { Label("Move to Inbox", systemImage: "tray") }
                    Button { state.duplicate(t) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                    Button { state.archiveTask(t) } label: { Label("Archive", systemImage: "archivebox") }
                } label: { Image(systemName: "ellipsis.circle") }
            }

            if let n = t.notes, !n.isEmpty {
                Text(n).font(.subheadline).foregroundStyle(.secondary)
            }

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
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(UIColor.systemGray6)))
    }

    private func bulkArchive(expanded: [TaskItem]) {
        let ids = selectedIds
        for t in expanded where ids.contains(t.id) { state.archiveTask(t) }
        selectedIds = []; isBulk = false
    }
    private func bulkDelete(expanded: [TaskItem]) {
        let ids = selectedIds
        for t in expanded where ids.contains(t.id) { state.deleteToTrash(t) }
        selectedIds = []; isBulk = false
    }
    private func bulkMoveToInbox(expanded: [TaskItem]) {
        let ids = selectedIds
        for t in expanded where ids.contains(t.id) { state.moveToInbox(t) }
        selectedIds = []; isBulk = false
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
                                } label: { Image(systemName: "checkmark.square") }
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
                } label: { Label("Period", systemImage: "calendar") }
                .buttonStyle(.bordered)
            }

            // KPI bars
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

            // Ratings breakdown
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

    // Helpers defined inside to avoid scope errors
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
        return (oL, oD, dL, dD, delL, delD)
    }
}

// KPI bars component
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

// MARK: - Search & Menu Sheets (legacy header search kept)
private struct SearchSheet: View {
    @Binding var searchText: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Search").font(.headline)
            TextField("Search tasks…", text: $searchText)
                .textFieldStyle(.roundedBorder)
            Spacer()
        }
        .padding()
    }
}

private struct MenuSheet: View {
    @Binding var searchText: String
    @Binding var isDarkMode: Bool
    let gotoHome: () -> Void
    let gotoArchives: () -> Void
    let gotoStats: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Capsule().fill(Color.secondary.opacity(0.3)).frame(width: 40, height: 5).padding(.top, 8)
            HStack {
                Text("Menu").font(.headline)
                Spacer()
                Toggle(isOn: $isDarkMode) { Text("Dark Mode") }
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            TextField("Search…", text: $searchText)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 18) {
                Button(action: gotoHome) { VStack { Image(systemName: "house"); Text("Home").font(.caption) } }
                Button(action: gotoArchives) { VStack { Image(systemName: "archivebox"); Text("Archives").font(.caption) } }
                Button(action: gotoStats) { VStack { Image(systemName: "chart.bar"); Text("Stats").font(.caption) } }
            }
            .buttonStyle(.bordered)
            Spacer()
        }
        .padding()
    }
}

// MARK: - Inbox edit form
private struct InboxEditForm: View {
    let t: TaskItem
    @Binding var editText: String
    @Binding var editNotes: String
    @Binding var editDate: String
    @Binding var editStatus: TaskStatus
    @Binding var editRecurrence: Recurrence
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Task title", text: $editText).textFieldStyle(.roundedBorder)
            TextField("Notes", text: $editNotes).textFieldStyle(.roundedBorder)
            HStack {
                Picker("Status", selection: $editStatus) {
                    Text("Open").tag(TaskStatus.notStarted)
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
                Button("Cancel", action: onCancel)
                Spacer()
                Button("Save", action: onSave)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

// MARK: - Small helpers
private func formatDateTime(_ d: Date?) -> String {
    guard let d = d else { return "—" }
    let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short
    return f.string(from: d)
}
