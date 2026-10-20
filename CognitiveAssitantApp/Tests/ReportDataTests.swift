import Foundation
import Testing
@testable import RobotForElders

/// The wording a report shows **must follow the data.** It used to say "8 consecutive weeks of decline"
/// even when things were improving.
@Suite("ReportData — no invented trends")
struct ReportDataTests {

    private func weeksAgo(_ n: Int) -> Date {
        Calendar.current.date(byAdding: .weekOfYear, value: -n, to: .now)!
    }

    @Test("Folds into weeks and averages within the same week")
    func foldsByWeek() {
        let samples: [(at: Date, percent: Double)] = [
            (weeksAgo(0), 60), (weeksAgo(0), 80),
            (weeksAgo(2), 50)
        ]
        let points = ReportData.weekly(samples: samples, weeks: 4)
        #expect(points.count == 4)
        #expect(points.last?.percent == 70)     // this week = (60+80)/2
        #expect(points[1].percent == 50)        // 2 weeks ago
        // A week with no samples is absent, not 0.
        #expect(points[0].percent == nil)
        #expect(points[2].percent == nil)
    }

    @Test("A single point isn't called a trend")
    func oneWeekIsNotATrend() {
        let points = ReportData.weekly(samples: [(weeksAgo(0), 58)], weeks: 8)
        #expect(ReportData.trend(points).contains("no trend"))
        #expect(ReportData.isFalling(points) == false)
    }

    @Test("If nothing was measured, it says so")
    func noMeasurement() {
        let points = ReportData.weekly(samples: [], weeks: 8)
        #expect(ReportData.trend(points) == "No measurement yet")
    }

    @Test("Down if it went down, up if it went up")
    func directionFollowsTheData() {
        let falling = ReportData.weekly(
            samples: [(weeksAgo(3), 88), (weeksAgo(0), 58)], weeks: 8)
        #expect(ReportData.trend(falling).hasPrefix("Down"))
        #expect(ReportData.isFalling(falling))

        let rising = ReportData.weekly(
            samples: [(weeksAgo(3), 58), (weeksAgo(0), 88)], weeks: 8)
        #expect(ReportData.trend(rising).hasPrefix("Up"))
        #expect(ReportData.isFalling(rising) == false)
    }

    @Test("A wobble of a few points isn't called a decline")
    func smallChangeIsSteady() {
        let points = ReportData.weekly(
            samples: [(weeksAgo(3), 80), (weeksAgo(0), 78)], weeks: 8)
        #expect(ReportData.trend(points).hasPrefix("Steady"))
        #expect(ReportData.isFalling(points) == false)
    }

    // MARK: - Weekly digest

    @Test("With nothing to report, not a single row is made")
    func quietWeekProducesNothing() {
        let notes = ReportData.notes(name: "Dorothy Miller",
                                     recall: [], speech: [],
                                     driftedFacts: [],
                                     needsAddress: false,
                                     daysSinceLastSession: 2)
        #expect(notes.isEmpty)
    }

    @Test("When the recall rate drops, it recommends a consultation without diagnosing")
    func fallingRecallIsFlagged() {
        let recall = ReportData.weekly(
            samples: [(weeksAgo(4), 88), (weeksAgo(0), 58)], weeks: 8)
        let notes = ReportData.notes(name: "Dorothy Miller",
                                     recall: recall, speech: [],
                                     driftedFacts: [],
                                     needsAddress: false,
                                     daysSinceLastSession: 1)
        let note = try? #require(notes.first)
        #expect(note?.kind == .followUp)
        #expect(note?.body.contains("not a diagnosis") == true)
    }

    @Test("Good news goes in the same list too")
    func goodNewsIsIncluded() {
        let speech = ReportData.weekly(
            samples: [(weeksAgo(4), 40), (weeksAgo(0), 62)], weeks: 8)
        let notes = ReportData.notes(name: "Betty Clark",
                                     recall: [], speech: speech,
                                     driftedFacts: [],
                                     needsAddress: false,
                                     daysSinceLastSession: 1)
        #expect(notes.contains { $0.kind == .good })
    }

    @Test("Without a form of address, staff are asked for one")
    func missingAddressIsAsked() {
        let notes = ReportData.notes(name: "Margaret Walsh",
                                     recall: [], speech: [],
                                     driftedFacts: [],
                                     needsAddress: true,
                                     daysSinceLastSession: 1)
        #expect(notes.contains { $0.kind == .ask })
    }

    @Test("Topics whose answers changed come with a note not to correct them")
    func driftNoteSaysDoNotCorrect() {
        let notes = ReportData.notes(name: "Dorothy Miller",
                                     recall: [], speech: [],
                                     driftedFacts: ["the orchard"],
                                     needsAddress: false,
                                     daysSinceLastSession: 1)
        let note = notes.first { $0.title.contains("story changed") }
        #expect(note?.body.contains("do not correct") == true)
    }

    @Test("Reports when someone hasn't been seen for a long time")
    func longGapIsFlagged() {
        let notes = ReportData.notes(name: "Frank Sullivan",
                                     recall: [], speech: [],
                                     driftedFacts: [],
                                     needsAddress: false,
                                     daysSinceLastSession: 30)
        #expect(notes.contains { $0.title.contains("not seen") })
    }

    // MARK: - Tidying the list

    @Test("The same request isn't repeated once per person")
    func addressAsksAreMergedIntoOne() {
        let notes = ["Dorothy Miller", "Betty Clark", "Robert Hayes"].flatMap { name in
            ReportData.notes(name: name, recall: [], speech: [],
                             driftedFacts: [], needsAddress: true,
                             daysSinceLastSession: 1)
        }
        #expect(notes.count == 3)

        let merged = ReportData.merged(notes)
        #expect(merged.count == 1)
        #expect(merged[0].topic == .address)
        // All three names must be in one line so it's clear who they are.
        #expect(merged[0].body.contains("Dorothy Miller"))
        #expect(merged[0].body.contains("Betty Clark"))
        #expect(merged[0].body.contains("Robert Hayes"))
    }

    @Test("With only one person, the name is used as is")
    func singleAddressAskKeepsTheName() {
        let notes = ReportData.notes(name: "Margaret Walsh", recall: [], speech: [],
                                     driftedFacts: [], needsAddress: true,
                                     daysSinceLastSession: 1)
        let merged = ReportData.merged(notes)
        #expect(merged.count == 1)
        #expect(merged[0].title.contains("Margaret Walsh"))
    }

    @Test("Changes come above requests")
    func changesComeBeforeChores() {
        let recall = ReportData.weekly(
            samples: [(weeksAgo(4), 88), (weeksAgo(0), 58)], weeks: 8)
        let notes = ReportData.notes(name: "Dorothy Miller", recall: recall, speech: [],
                                     driftedFacts: [], needsAddress: true,
                                     daysSinceLastSession: 40)
        let merged = ReportData.merged(notes)
        // If requests pile up on top, the changes that actually matter get pushed down out of sight.
        #expect(merged.first?.kind == .followUp)
        #expect(merged.last?.kind == .ask)
    }
}
