import Foundation

enum SampleData {
    static func make() -> [TaskItem] {
        var items: [TaskItem] = []
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        
        // Helper to make yyyy-MM-dd
        func day(_ y: Int, _ m: Int, _ d: Int) -> String {
            var comps = DateComponents()
            comps.year = y; comps.month = m; comps.day = d
            let cal = Calendar(identifier: .gregorian)
            let date = cal.date(from: comps) ?? Date()
            return ISO8601DateFormatter().string(from: cal.startOfDay(for: date)).prefix(10).description
        }
        
        let today = Date()
        let cal = Calendar.current
        let todayStr = ISO8601DateFormatter().string(from: cal.startOfDay(for: today)).prefix(10).description
        
        items.append(
            TaskItem(text: "Plan team lunch for next week",
                     notes: "Pick a place & send a poll.",
                     date: todayStr,
                     status: .not_started,
                     recurrence: nil)
        )
        items.append(
            TaskItem(text: "Prepare slides for Monday's presentation",
                     notes: "Focus on Q3 performance.",
                     date: day(2025, 10, 2),
                     status: .started,
                     recurrence: nil,
                     createdAt: Date(timeIntervalSinceNow: -60*60*24*3),
                     startedAt: Date())
        )
        items.append(
            TaskItem(text: "Submit weekly progress report",
                     notes: "Submitted yesterday a.m.",
                     date: day(2025, 10, 1),
                     status: .completed,
                     recurrence: nil,
                     createdAt: Date(timeIntervalSinceNow: -60*60*24*4),
                     startedAt: Date(timeIntervalSinceNow: -60*60*36),
                     completedAt: Date(timeIntervalSinceNow: -60*60*30),
                     rating: .liked)
        )
        items.append(
            TaskItem(text: "Daily Standup Meeting",
                     notes: nil,
                     date: day(2025, 9, 1),
                     status: .not_started,
                     recurrence: .daily)
        )
        return items
    }
}
