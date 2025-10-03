import Foundation

enum SampleData {
    /// Some realistic starter tasks (mirrors your React data shape)
    static let tasks: [TaskItem] = {
        let today = Date().isoDayString
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!.isoDayString
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!.isoDayString

        var items: [TaskItem] = [
            TaskItem(
                text: "Plan team lunch for next week",
                notes: "Need to decide on a location and send out a poll.",
                date: today,
                status: .notStarted
            ),
            TaskItem(
                text: "Prepare slides for Monday's presentation",
                notes: "Focus on Q3 performance metrics.",
                date: tomorrow,
                status: .started,
                createdAt: Date().addingTimeInterval(-2*24*3600),
                startedAt: Date().addingTimeInterval(-1*24*3600)
            ),
            TaskItem(
                text: "Submit weekly progress report",
                notes: "Report was submitted yesterday morning.",
                date: yesterday,
                status: .completed,
                createdAt: Date().addingTimeInterval(-4*24*3600),
                startedAt: Date().addingTimeInterval(-1.5*24*3600),
                completedAt: Date().addingTimeInterval(-1*24*3600),
                rating: .liked
            ),
            TaskItem(
                text: "Review new design mockups",
                notes: "Check for mobile responsiveness.",
                date: tomorrow,
                status: .notStarted
            ),
            TaskItem(
                text: "Debug issue #5821 on the staging server",
                notes: "The login page is throwing a 500 error.",
                date: tomorrow,
                status: .started,
                createdAt: Date().addingTimeInterval(-12*3600),
                startedAt: Date().addingTimeInterval(-6*3600)
            ),
            TaskItem(
                text: "Daily Standup Meeting",
                notes: "",
                date: Date().addingTimeInterval(-30*24*3600).isoDayString,
                status: .notStarted,
                recurrence: .daily,
                completedOverrides: [:]
            )
        ]

        // Add a handful of extra inbox items (no date)
        items.append(contentsOf: [
            TaskItem(text: "Write documentation for the new SDK"),
            TaskItem(text: "Onboard new marketing intern", notes: "Prepare checklist"),
            TaskItem(text: "Create A/B test for landing page"),
        ])

        return items
    }()
}
