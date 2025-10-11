// ContentView.swift (updated from ContentView_v1.1.swift)
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
    @State private var showingSearch = false

    // NEW: Collapse states
    @State private var isCalendarCollapsed = false
    @State private var isInboxCollapsed = false

    // Stats period controls
    enum Period: String, CaseIterable { case weekly, monthly, quarterly, semester, yearly, custom }
    @State private var statsPeriod: Period = .weekly
    @State private var customStart: Date = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var customEnd: Date = Date()

    var body: some View {
        VStack(spacing: 16) {
            header
            mainPanels
        }
        .padding()
        .preferredColorScheme(isDarkMode ? .dark : .light)
        .sheet(item: $showingDay) { day in
            DayModalView(day: day, state: state,
                         isBulk: $isModalBulkSelect,
                         selectedIds: $selectedModalIds)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingSearch) {
            SearchSheet(searchText: $state.searchQuery)
                .presentationDetents([.fraction(0.25), .medium])
        }
        .sheet(isPresented: $showingMenu) {
            MenuSheet(
                searchText: $state.searchQuery,
                isDarkMode: $isDarkMode,
                gotoHome: {
                    state.isArchiveViewActive = false
                    state.isStatsViewActive = false
                    showingMenu = false
                },
                gotoArchives: {
                    state.isArchiveViewActive = true
                    state.isStatsViewActive = false
                    showingMenu = false
                },
                gotoStats: {
                    state.isStatsViewActive = true
                    state.isArchiveViewActive = false
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
                Button { showingSearch = true } label: {
                    Image(systemName: "magnifyingglass").imageScale(.large)
                }
                .accessibilityLabel("Search")

                Button {
                    state.isStatsViewActive.toggle()
                    if state.isStatsViewActive { state.isArchiveViewActive = false }
                } label: {
                    Image(systemName: "chart.bar").imageScale(.large)
                }
                .accessibilityLabel("Stats")

                Button {
                    state.isArchiveViewActive.toggle()
                    if state.isArchiveViewActive { state.isStatsViewActive = false }
                } label: {
                    Image(systemName: "archivebox").imageScale(.large)
                }
                .accessibilityLabel("Archives")

                Button { showingMenu = true } label: {
                    Image(systemName: "line.3.horizontal").imageScale(.large)
                }
                .accessibilityLabel("Menu")
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: Main panels
    private var mainPanels: some View {
        // Dynamic expansion rules:
        // - Default (both expanded): Inbox expands.
        // - Calendar collapsed: Inbox expands.
        // - Inbox collapsed: Calendar expands.
        // - Both collapsed: neither expands (stacked headers illusion).
        let shouldExpandCalendar = (!isCalendarCollapsed && isInboxCollapsed)
        let shouldExpandInbox = (!isInboxCollapsed && (!state.isArchiveViewActive && !state.isStatsViewActive))

        return VStack(spacing: 12) {
            Group {
                if state.isStatsViewActive {
                    StatsView(
                        state: state,
                        period: $statsPeriod,
                        customStart: $customStart,
                        customEnd: $customEnd
                    )
                } else if state.isArchiveViewActive {
                    ArchivesView(state: state)
                } else {
                    CalendarPanel(
                        state: state,
                        collapsed: $isCalendarCollapsed
                    ) { day in
                        showingDay = day
                    }
                    .frame(maxHeight: shouldExpandCalendar ? .infinity : nil)
                    .animation(.easeInOut, value: isInboxCollapsed)
                    .animation(.easeInOut, value: isCalendarCollapsed)
                }
            }
            if !(state.isArchiveViewActive || state.isStatsViewActive) {
                InboxPanel(
                    state: state,
                    collapsed: $isInboxCollapsed
                )
                .frame(maxHeight: shouldExpandInbox ? .infinity : nil)
                .animation(.easeInOut, value: isInboxCollapsed)
                .animation(.easeInOut, value: isCalendarCollapsed)
            }
        }
    }
}

// MARK: - Calendar panel (extracted)
private struct CalendarPanel: View {
    @ObservedObject var state: AppState
    var openDay: (CalendarDay) -> Void

    // NEW: collapse binding
    @Binding var collapsed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                // NEW: Chevron to the LEFT of section name
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                        collapsed.toggle()
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(collapsed ? -90 : 0))
                        .animation(.easeInOut, value: collapsed)
                        .imageScale(.medium)
                        .padding(.trailing, 2)
                }
                .accessibilityLabel(collapsed ? "Expand Calendar" : "Collapse Calendar")

                Text("Daily Calendar").font(.title3).bold()
                Spacer()

                // View menu
                Menu {
                    Picker("View", selection: $state.calendarViewMode) {
                        Text("Cards").tag(CalendarViewMode.card)
                        Text("List").tag(CalendarViewMode.list)
                    }
                } label: {
                    Label("View", systemImage: "rectangle.3.offgrid")
                }
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
                } label: {
                    Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                }
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

            // NEW: Collapsible content (collapses upwards)
            if !collapsed {
                CalendarContent(state: state, openDay: openDay)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

// Extracted content of calendar to keep the collapse logic clean
private struct CalendarContent: View {
    @ObservedObject var state: AppState
    var openDay: (CalendarDay) -> Void

    var body: some View {
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
                    .onAppear {
                        let today = ISO8601.dateOnly.string(from: Date())
                        withAnimation { proxy.scrollTo(dayListID(today), anchor: .top) }
                    }
                }
                .frame(height: 260)
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
                    state.reschedule(t, to: day.dateString)
                }
            }
        }
        return true
    }
}

// MARK: - Inbox panel (extracted, light to type-check)
private struct InboxPanel: View {
    @ObservedObject var state: AppState

    // NEW: collapse binding
    @Binding var collapsed: Bool

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
            header

            // NEW: Collapsible content (collapses downwards)
            if !collapsed {
                VStack(alignment: .leading, spacing: 8) {
                    inputRow
                    listArea

                    // Bulk action bar (matches daily calendar modal style)
                    if state.isBulkSelectActiveInbox, !state.selectedInboxTaskIds.isEmpty {
                        HStack {
                            Text("\(state.selectedInboxTaskIds.count) selected").font(.subheadline).bold()
                            Spacer()
                            Menu("Actions") {
                                Button("Archive") {
                                    state.archiveSelectedInbox()
                                }
                                Button("Delete", role: .destructive) {
                                    state.deleteSelectedInbox()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(.top, 6)
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .move(edge: .bottom).combined(with: .opacity)
                ))
            }
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
                DispatchQueue.main.async { state.moveToInbox(t) }
            }
            return true
        })
    }

    private var header: some View {
        HStack {
            // NEW: Chevron to the LEFT of section name
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                    collapsed.toggle()
                }
            } label: {
                Image(systemName: "chevron.down")
                    .rotationEffect(.degrees(collapsed ? -90 : 0))
                    .animation(.easeInOut, value: collapsed)
                    .imageScale(.medium)
                    .padding(.trailing, 2)
            }
            .accessibilityLabel(collapsed ? "Expand Inbox" : "Collapse Inbox")

            Text("Task Inbox").font(.title3).bold()
            if !state.unassignedTasks.isEmpty {
                Text("\(state.unassignedTasks.count)")
                    .font(.caption).bold()
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.2)))
            }
            Spacer()

            // Select / Cancel (toggles bulk-select mode)
            Button(state.isBulkSelectActiveInbox ? "Cancel" : "Select") {
                state.toggleBulkSelectInbox()
            }
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
        let isEditing = editingTaskId == t.id
        HStack(alignment: .top, spacing: 10) {
            // NEW: Checkbox left of each task when bulk-select is active
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
                    Button(role: .destructive) { state.deleteToTrash(t) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    Button { state.duplicate(t) } label: {
                        Label("Duplicate", systemImage: "plus.square.on.square")
                    }
                    Button { state.archiveTask(t) } label: {
                        Label("Archive", systemImage: "archivebox")
                    }
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

// MARK: - Day card & row (unchanged)
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

// MARK: - Day Modal (unchanged)
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
                        Button("Delete Permanently", role: .destructive) {
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

// MARK: - Archives / Stats / KPI / Sheets / Edit form / Helpers
// (below this line unchanged from your v1.1)

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

    // ... (helpers unchanged)
}

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

private func formatDateTime(_ d: Date?) -> String {
    guard let d = d else { return "—" }
    let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short
    return f.string(from: d)
}
