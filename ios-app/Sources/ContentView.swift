import SwiftUI
import Foundation
import Charts

// MARK: - View-specific Models (Moved here to resolve build error)
struct CalendarDay: Identifiable, Hashable {
    var id = UUID()
    var dateString: String
    var dayName: String
    var dayOfMonth: Int
}

// MARK: - Main App View
struct ContentView: View {
    @StateObject private var state = AppState()
    @State private var showingSettings = false
    @State private var showingEditTaskSheet = false
    @State private var taskToEdit: TaskItem?

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                HeaderView(
                    isSearchVisible: $state.isSearchVisible,
                    searchText: $state.searchQuery
                )
                .padding([.horizontal, .top])
                
                TabView(selection: $state.activeTab) {
                    HomeView(state: state, editAction: { task in
                        taskToEdit = task
                        showingEditTaskSheet = true
                    })
                    .tag(Tab.home)
                    
                    StatsView(state: state)
                    .tag(Tab.stats)

                    // Placeholder for Camera
                    Color.clear.tag(Tab.camera)

                    ArchivesView(state: state)
                    .tag(Tab.archive)
                    
                    // Search is handled by the header
                    Color.clear.tag(Tab.search)
                }
                
                CustomTabBar(activeTab: $state.activeTab, showSettings: { showingSettings = true })
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            
            // Undo Snackbar
            if let message = state.snackbarMessage {
                SnackbarView(message: message, onUndo: state.performUndo)
            }
        }
        .sheet(isPresented: $showingSettings) { SettingsSheet() }
        .sheet(isPresented: $showingEditTaskSheet) {
            if let task = taskToEdit {
                TaskEditSheet(state: state, task: task)
            }
        }
    }
}

// MARK: - Subviews for Main Layout

private struct HeaderView: View {
    @Binding var isSearchVisible: Bool
    @Binding var searchText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Taskmate")
                .font(.title2)
                .bold()
            
            if isSearchVisible {
                TextField("Search tasks...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut, value: isSearchVisible)
    }
}

private struct CustomTabBar: View {
    @Binding var activeTab: Tab
    var showSettings: () -> Void
    
    var body: some View {
        HStack {
            ForEach(Tab.allCases) { tab in
                Button {
                    // Toggle search visibility when search tab is tapped
                    if tab == .search {
                        // This will be handled by observing activeTab change
                    } else if tab == .settings {
                        showSettings()
                    }
                    
                    // Always update the active tab
                    activeTab = tab
                    
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 22))
                        Text(tab.rawValue.capitalized)
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundColor(activeTab == tab ? .accentColor : .secondary)
                }
            }
        }
        .padding(.top, 8)
        .padding(.bottom)
        .background(.bar)
    }
}


private struct HomeView: View {
    @ObservedObject var state: AppState
    var editAction: (TaskItem) -> Void
    @State private var showingDay: CalendarDay? = nil
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                CalendarPanel(state: state) { day in
                    showingDay = day
                }
                
                InboxPanel(state: state, editAction: editAction)
            }
            .padding()
        }
        .sheet(item: $showingDay) { day in
            DayModalView(day: day, state: state, editAction: editAction)
                .presentationDetents([.medium, .large])
        }
    }
}


// MARK: - Calendar Panel
private struct CalendarPanel: View {
    @ObservedObject var state: AppState
    var openDay: (CalendarDay) -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Button {
                    withAnimation { state.isCalendarCollapsed.toggle() }
                } label: {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(state.isCalendarCollapsed ? 0 : 90))
                }
                .buttonStyle(.plain)

                Text("Daily Calendar").font(.title3).bold()
                Spacer()
                
                Button {
                    withAnimation {
                        let today = Date()
                        state.calendarStartDate = Calendar.current.date(byAdding: .day, value: -3, to: today) ?? today
                    }
                } label: { Image(systemName: "calendar.circle") }
                
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
                } label: { Image(systemName: "line.3.horizontal.decrease.circle") }
                
                Button {
                    state.calendarViewMode = (state.calendarViewMode == .card) ? .list : .card
                } label: {
                    Image(systemName: state.calendarViewMode == .card ? "list.bullet" : "rectangle.grid.1x2")
                }
            }
            .buttonStyle(.bordered)
            .imageScale(.large)
            .padding(.horizontal)

            if !state.isCalendarCollapsed {
                let days = state.calendarDays()
                let tasksByDay = Dictionary(grouping: state.visibleCalendarTasks(for: days)) { $0.date ?? "" }
                
                if state.calendarViewMode == .card {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(days) { day in
                                let tasks = (tasksByDay[day.dateString] ?? []).filter { state.calendarFilters[$0.status] ?? true }
                                DayCard(day: day, tasks: tasks) { openDay(day) }
                                    .onDrop(of: [.plainText], isTargeted: nil) { providers in
                                        handleDropToDay(day: day, providers: providers)
                                    }
                            }
                        }
                        .padding(.horizontal)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(days) { day in
                                let tasks = (tasksByDay[day.dateString] ?? []).filter { state.calendarFilters[$0.status] ?? true }
                                if state.searchQuery.isEmpty && tasks.isEmpty {
                                    EmptyView()
                                } else {
                                    DayRow(day: day, tasks: tasks) { openDay(day) }
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    .frame(maxHeight: 260)
                }
            }
        }
        .padding(.vertical)
        .background(Color(.systemBackground))
        .cornerRadius(14)
    }
    
    private func handleDropToDay(day: CalendarDay, providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: "public.plain-text", options: nil) { data, _ in
            guard let d = data as? Data, let idStr = String(data: d, encoding: .utf8), let id = Int(idStr) else { return }
            DispatchQueue.main.async {
                if let t = state.tasks.first(where: { $0.id == id }) {
                    state.reschedule(t, to: day.dateString)
                }
            }
        }
        return true
    }
}

// MARK: - Inbox Panel
private struct InboxPanel: View {
    @ObservedObject var state: AppState
    var editAction: (TaskItem) -> Void
    @State private var newTaskText = ""

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Button {
                    withAnimation { state.isInboxCollapsed.toggle() }
                } label: {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(state.isInboxCollapsed ? 0 : 90))
                }
                .buttonStyle(.plain)

                Text("Task Inbox").font(.title3).bold()
                if !state.unassignedTasks.isEmpty {
                    Text("\(state.unassignedTasks.count)").font(.caption).bold()
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.secondary.opacity(0.2)))
                }
                Spacer()
                Button(state.isBulkSelectActiveInbox ? "Cancel" : "Select") {
                    state.isBulkSelectActiveInbox.toggle()
                    state.selectedInboxTaskIds.removeAll()
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)

            if !state.isInboxCollapsed {
                HStack(spacing: 8) {
                    TextField("Add a new task…", text: $newTaskText, onCommit: addTask)
                        .textFieldStyle(.roundedBorder)
                    Button(action: addTask) { Image(systemName: "plus") }
                        .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal)

                if state.unassignedTasks.isEmpty {
                    CompatEmptyState(title: "No unassigned tasks", systemImage: "tray")
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    List {
                        ForEach($state.tasks.filter { $0.wrappedValue.date == nil }) { $task in
                             InboxTaskRow(task: $task, state: state, isSelecting: state.isBulkSelectActiveInbox, isSelected: state.selectedInboxTaskIds.contains(task.id), editAction: editAction)
                                .onTapGesture {
                                    if state.isBulkSelectActiveInbox {
                                        if state.selectedInboxTaskIds.contains(task.id) {
                                            state.selectedInboxTaskIds.remove(task.id)
                                        } else {
                                            state.selectedInboxTaskIds.insert(task.id)
                                        }
                                    }
                                }
                                .onDrag { NSItemProvider(object: NSString(string: "\(task.id)")) }
                        }
                        .onMove(perform: state.reorderInboxTasks)
                    }
                    .listStyle(.inset)
                    .frame(minHeight: 140, maxHeight: 300)
                }
                
                if state.isBulkSelectActiveInbox && !state.selectedInboxTaskIds.isEmpty {
                    BulkActionBar(archiveAction: state.archiveSelectedInbox, deleteAction: state.deleteSelectedInbox)
                        .padding(.horizontal)
                }
            }
        }
        .padding(.vertical)
        .background(Color(.systemBackground))
        .cornerRadius(14)
    }

    private func addTask() {
        state.addTask(text: newTaskText, notes: nil, assignedTo: nil)
        newTaskText = ""
    }
}

// MARK: - Task Rows & Cards
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
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(isToday ? .blue : Color.clear, lineWidth: 2))
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
    let day: CalendarDay, tasks: [TaskItem], onTap: () -> Void
    var body: some View {
        let isToday = day.dateString == ISO8601.dateOnly.string(from: Date())
        HStack {
            Text(dateLong(day.dateString)).font(.subheadline).fontWeight(.semibold)
            Spacer()
        }
        .padding(8)
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(isToday ? .blue : .clear))
        .onTapGesture { onTap() }
    }
    private func dateLong(_ ds: String) -> String {
        guard let d = ds.asISODateOnlyUTC else { return ds }
        return d.formatted(.dateTime.weekday(.long).month(.long).day())
    }
}

private struct InboxTaskRow: View {
    @Binding var task: TaskItem
    @ObservedObject var state: AppState
    let isSelecting: Bool
    let isSelected: Bool
    let editAction: (TaskItem) -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            if isSelecting {
                Image(systemName: isSelected ? "checkmark.square" : "square")
            }
            
            VStack(alignment: .leading, spacing: 5) {
                Text(task.text).bold()
                if let dateStr = task.date, let date = dateStr.asISODateOnlyUTC {
                    Text("Scheduled: \(date.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption).foregroundColor(.secondary)
                } else {
                     Text("Unscheduled")
                        .font(.caption).foregroundColor(.secondary)
                }
                
                HStack {
                    if task.isRecurring { Image(systemName: "repeat").foregroundColor(.secondary) }
                    // Rating and other controls can be added here
                }
            }
            
            Spacer()
            
            Menu {
                Button("Edit") { editAction(task) }
                Button("Duplicate") { state.duplicate(task) }
                Button("Archive") { state.archiveTask(task) }
                Button("Delete", role: .destructive) { state.deleteToTrash(task) }
            } label: {
                Image(systemName: "ellipsis.circle").imageScale(.large)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}


// MARK: - Modals and Sheets

private struct DayModalView: View {
    let day: CalendarDay
    @ObservedObject var state: AppState
    let editAction: (TaskItem) -> Void
    @State private var isBulk = false
    @State private var selectedIds = Set<Int>()

    var body: some View {
        let expanded = state.visibleCalendarTasks(for: [day])
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text(day.dayName).font(.title2).bold()
                    Text(day.dateString.asISODateOnlyUTC?.formatted(date: .long, time: .omitted) ?? "").foregroundStyle(.secondary)
                }
                Spacer()
                Button(isBulk ? "Cancel" : "Select") { isBulk.toggle(); selectedIds = [] }
            }

            if expanded.isEmpty {
                CompatEmptyState(title: "No tasks for this day", systemImage: "calendar")
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(expanded) { t in modalTaskRow(t) }
                    }
                }
            }

            if isBulk, !selectedIds.isEmpty {
                BulkActionBar(archiveAction: { bulkAction(expanded: expanded) { state.archiveTask($0) } },
                              deleteAction: { bulkAction(expanded: expanded) { state.deleteToTrash($0) } })
            }
        }
        .padding()
    }

    @ViewBuilder private func modalTaskRow(_ t: TaskItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if isBulk {
                    Button {
                        if selectedIds.contains(t.id) { selectedIds.remove(t.id) } else { selectedIds.insert(t.id) }
                    } label: { Image(systemName: selectedIds.contains(t.id) ? "checkmark.square" : "square") }
                }
                Text(t.text).font(.body).bold()
                if t.isRecurring { Image(systemName: "repeat") }
                Spacer()
                Menu {
                    Button("Edit") { editAction(t) }
                    Button("Move to Inbox") { state.moveToInbox(t) }
                    Button("Delete", role: .destructive) { state.deleteToTrash(t) }
                } label: { Image(systemName: "ellipsis.circle") }
            }
            if let n = t.notes, !n.isEmpty { Text(n).font(.subheadline).foregroundStyle(.secondary) }
            HStack(spacing: 12) {
                Picker("Status", selection: Binding(get: { t.status }, set: { state.updateStatus(t, to: $0, instanceDate: day.dateString) })) {
                    Text("Open").tag(TaskStatus.notStarted)
                    Text("Started").tag(TaskStatus.started)
                    Text("Done").tag(TaskStatus.completed)
                }
                .pickerStyle(.segmented)
                
                Button(action: { state.cycleRating(for: t, instanceDate: day.dateString) }) {
                    let rating = (t.isInstance ? state.tasks.first { $0.id == t.parentId }?.completedOverrides?[day.dateString]?.rating : t.rating)
                    switch rating {
                    case .liked: Image(systemName: "hand.thumbsup.fill").foregroundColor(.green)
                    case .disliked: Image(systemName: "hand.thumbsdown.fill").foregroundColor(.red)
                    case .none: Image(systemName: "hand.thumbsup").foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(10).background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
    }
    
    private func bulkAction(expanded: [TaskItem], action: (TaskItem) -> Void) {
        let ids = selectedIds
        for t in expanded where ids.contains(t.id) { action(t) }
        selectedIds = []; isBulk = false
    }
}

private struct TaskEditSheet: View {
    @ObservedObject var state: AppState
    let task: TaskItem
    @Environment(\.dismiss) private var dismiss

    @State private var text: String
    @State private var notes: String
    @State private var date: Date
    @State private var hasDate: Bool
    @State private var assignedTo: String
    
    init(state: AppState, task: TaskItem) {
        self.state = state
        self.task = task
        _text = State(initialValue: task.text)
        _notes = State(initialValue: task.notes ?? "")
        if let dateStr = task.date, let d = dateStr.asISODateOnlyUTC {
            _date = State(initialValue: d)
            _hasDate = State(initialValue: true)
        } else {
            _date = State(initialValue: Date())
            _hasDate = State(initialValue: false)
        }
        _assignedTo = State(initialValue: task.assignedTo ?? "")
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Task Details") {
                    TextField("Title", text: $text)
                    TextField("Notes", text: $notes, axis: .vertical)
                }
                
                Section("Assignment") {
                    Text("Created by: \(task.createdBy)")
                    TextField("Assigned to", text: $assignedTo)
                }
                
                Section("Scheduling") {
                    Toggle("Schedule Task", isOn: $hasDate.animation())
                    if hasDate {
                        DatePicker("Date", selection: $date, displayedComponents: .date)
                    }
                }
            }
            .navigationTitle("Edit Task")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save(); dismiss() } }
            }
        }
    }
    
    private func save() {
        state.updateTask(task,
                         text: text,
                         notes: notes,
                         date: hasDate ? ISO8601.dateOnly.string(from: date) : nil,
                         status: task.status,
                         recurrence: task.recurrence ?? .never,
                         assignedTo: assignedTo.isEmpty ? nil : assignedTo
        )
    }
}

// MARK: - Other main views (Stats, Archives)
private struct StatsView: View {
    @ObservedObject var state: AppState
    var body: some View { Text("Statistics View").frame(maxWidth: .infinity, maxHeight: .infinity) }
}

private struct ArchivesView: View {
    @ObservedObject var state: AppState
    var body: some View { Text("Archives View").frame(maxWidth: .infinity, maxHeight: .infinity) }
}

// MARK: - Settings Sheet & Subviews
private struct SettingsSheet: View {
    @State private var colorScheme: ColorSchemeOption = .system
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    HStack(spacing: 16) {
                        Image(systemName: "person.circle.fill")
                            .resizable().scaledToFit().frame(width: 60)
                            .foregroundColor(.secondary)
                        VStack(alignment: .leading) {
                            Text("Adrian Kisliuk").bold()
                            Text("a.kisliuk@gmail.com").foregroundStyle(.secondary)
                        }
                    }
                }
                
                Section {
                    NavigationLink("Theme") { ThemeSelectionView(colorScheme: $colorScheme) }
                    Button("Manage Teams") {}
                    Button("Subscription") {}
                    Button("Billing") {}
                }
                
                Section {
                    Button("Languages") {}
                    Button("Privacy Policy") {}
                    Button("Terms of Use") {}
                }
                
                Section {
                    Button("Log in/out") {}
                }
            }
            .navigationTitle("Settings")
        }
    }
}

private enum ColorSchemeOption: String { case light, dark, system }
private struct ThemeSelectionView: View {
    @Binding var colorScheme: ColorSchemeOption
    
    var body: some View {
        Form {
            Picker("Theme", selection: $colorScheme) {
                Text("Light").tag(ColorSchemeOption.light)
                Text("Dark").tag(ColorSchemeOption.dark)
                Text("System Mode").tag(ColorSchemeOption.system)
            }
            .pickerStyle(.inline)
        }
        .navigationTitle("Theme")
    }
}

// MARK: - Reusable UI Components
private struct SnackbarView: View {
    let message: String
    let onUndo: () -> Void
    @State private var isVisible = false

    var body: some View {
        HStack {
            Text(message)
            Spacer()
            Button("Undo") { onUndo() }
                .bold()
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(10)
        .shadow(radius: 5)
        .padding()
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .onAppear { withAnimation { isVisible = true } }
        .onChange(of: message) { _ in
            isVisible = true
        }
    }
}

private struct BulkActionBar: View {
    var archiveAction: () -> Void
    var deleteAction: () -> Void

    var body: some View {
        HStack {
            Spacer()
            Button(action: archiveAction) { Label("Archive", systemImage: "archivebox") }
            Button(role: .destructive, action: deleteAction) { Label("Delete", systemImage: "trash") }
        }
        .buttonStyle(.bordered)
        .padding(.vertical, 4)
    }
}

private struct CompatEmptyState: View {
    let title: String, systemImage: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage).font(.system(size: 40)).foregroundColor(.secondary)
            Text(title).font(.headline).multilineTextAlignment(.center).foregroundColor(.secondary)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Enums and Helpers
enum Tab: String, CaseIterable, Identifiable {
    case home, stats, camera, archive, search, settings
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .home: return "house"
        case .stats: return "chart.bar.xaxis"
        case .camera: return "camera"
        case .archive: return "archivebox"
        case .search: return "magnifyingglass"
        case .settings: return "gear"
        }
    }
}

