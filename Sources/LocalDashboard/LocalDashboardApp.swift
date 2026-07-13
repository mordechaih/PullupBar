import SwiftUI

@main
struct LocalDashboardApp: App {
    var body: some Scene {
        MenuBarExtra("LocalDashboard", systemImage: "gauge.medium") {
            Text("LocalDashboard")
                .padding()
        }
    }
}
