import SwiftData
import SwiftUI

@main
struct RobotForEldersApp: App {

    /// The memory store. **On-device only** — face embeddings are biometric data, and conversation transcripts and
    /// cognitive metrics are health-related data, so none of it leaves the device
    /// (`Docs/03_product-design.md` section 9). That's why CloudKit sync is not turned on.
    private let container: ModelContainer

    init() {
        let schema = Schema([
            Elder.self, Session.self, Utterance.self,
            Fact.self, FactRevision.self, RecallAnchor.self, MetricSample.self,
            SpeechSample.self
        ])
        let configuration = ModelConfiguration(schema: schema,
                                               isStoredInMemoryOnly: false,
                                               cloudKitDatabase: .none)
        do {
            container = try ModelContainer(for: schema, configurations: configuration)
        } catch {
            // If the store can't be opened, neither session records nor openers are possible. Quietly continuing
            // with an empty state would run with "last time" gone, so stopping here is better.
            fatalError("Could not open the memory store: \(error)")
        }
        SeedData.seedIfEmpty(container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .statusBarHidden()
                .persistentSystemOverlays(.hidden)
                // Whatever the device language or region, this app runs only in English (en-US).
                // Pin it so date and number formats don't shift with system settings.
                .environment(\.locale, Locale(identifier: "en_US"))
        }
        .modelContainer(container)
    }
}
