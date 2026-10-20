import Foundation
import SwiftData
import Testing
@testable import RobotForElders

/// The memory store for tests. **Doesn't touch the disk.**
///
/// Testing with real device data breaks two things at once — the tests depend on someone else's records,
/// and the tests change someone else's records. The container here lives only in memory and is created fresh for each test.
enum TestStore {

    static func make() throws -> MemoryStore {
        let schema = Schema([
            Elder.self, Session.self, Utterance.self,
            Fact.self, FactRevision.self, RecallAnchor.self, MetricSample.self,
            SpeechSample.self
        ])
        let configuration = ModelConfiguration(schema: schema,
                                               isStoredInMemoryOnly: true,
                                               cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: configuration)
        return MemoryStore(context: ModelContext(container))
    }

    /// A time a few days ago. Used in tests dealing with delays and trends.
    static func daysAgo(_ days: Int, from now: Date = .now) -> Date {
        now.addingTimeInterval(-Double(days) * 86_400)
    }

    static func minutesAgo(_ minutes: Int, from now: Date = .now) -> Date {
        now.addingTimeInterval(-Double(minutes) * 60)
    }
}
