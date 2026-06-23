import SwiftUI
import SwiftData
import UIKit

@main
struct PoolSideApp: App {

    @State private var viewModel = PoolViewModel()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([PoolTest.self, Treatment.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        configureSegmentedControlAppearance()
    }

    private func configureSegmentedControlAppearance() {
        let teal = UIColor(named: "PoolTeal") ?? UIColor.systemTeal
        let proxy = UISegmentedControl.appearance()
        proxy.selectedSegmentTintColor = teal
        proxy.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
        proxy.setTitleTextAttributes([.foregroundColor: UIColor.black], for: .normal)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(viewModel)
                // Light theme to match design
        }
        .modelContainer(sharedModelContainer)
    }
}
