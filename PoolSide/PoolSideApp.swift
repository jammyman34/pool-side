import SwiftUI
import SwiftData

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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(viewModel)
                // Light theme to match design
        }
        .modelContainer(sharedModelContainer)
    }
}
