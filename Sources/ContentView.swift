import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 48))
                Text("Hello, Task Scheduler!")
                    .font(.title2).bold()
                Text("If you see this inside Appetize, the pipeline works 🎉")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .navigationTitle("Home")
        }
    }
}
