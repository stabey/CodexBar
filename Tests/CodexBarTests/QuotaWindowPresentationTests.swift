import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct QuotaWindowPresentationTests {
    @Test
    func `quota observations preserve capture times and isolate account history`() {
        let captured = Date(timeIntervalSince1970: 1_700_000_000)
        let alice = Self.history(captured: captured, reset: captured.addingTimeInterval(600))
        let bob = Self.history(captured: captured, reset: captured.addingTimeInterval(1200))
        let buckets = PlanUtilizationHistoryBuckets(unscoped: [alice], accounts: ["alice": [alice], "bob": [bob]])
        let original = buckets
        #expect(UsageStore.weeklyQuotaResetObservations(in: buckets, accountKey: "bob") == [
            .init(capturedAt: captured, resetsAt: captured.addingTimeInterval(1200)),
        ])
        #expect(UsageStore.weeklyQuotaResetObservations(in: buckets, accountKey: "missing").isEmpty)
        #expect(UsageStore.weeklyQuotaResetObservations(in: buckets, accountKey: nil) == [
            .init(capturedAt: captured, resetsAt: captured.addingTimeInterval(600)),
        ])
        #expect(buckets == original)
    }

    @Test
    func `partial price is visible without qualifying complete tokens`() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let row = UsageMenuCardView.Model.quotaWindowRow(
            week: .init(
                offset: 0,
                start: start,
                end: start.addingTimeInterval(604_800),
                totalTokens: 600,
                totalCostUSD: 4,
                entryCount: 2,
                tokensAreComplete: true,
                costIsComplete: false,
                boundariesAreEstimated: false),
            cost: "$4.00",
            calendar: .current)
        #expect(row.value == "≥ $4.00 · 600")
        #expect(row.note == "Partial estimate")
    }

    @Test
    func `partial tokens and inferred boundaries are separately visible`() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let row = UsageMenuCardView.Model.quotaWindowRow(
            week: .init(
                offset: 1,
                start: start,
                end: start.addingTimeInterval(604_800),
                totalTokens: 600,
                totalCostUSD: 4,
                entryCount: 2,
                tokensAreComplete: false,
                costIsComplete: true,
                boundariesAreEstimated: true),
            cost: "$4.00",
            calendar: .current)
        #expect(row.value == "$4.00 · ≥ 600")
        #expect(row.note == "Partial estimate")
        #expect(row.range.hasPrefix("Est. "))
        #expect(UsageMenuCardView.Model.quotaMetricValue(nil, complete: false) == "—")
    }

    private static func history(captured: Date, reset: Date) -> PlanUtilizationSeriesHistory {
        .init(name: .weekly, windowMinutes: 10080, entries: [
            .init(capturedAt: captured, usedPercent: 10, resetsAt: reset),
        ])
    }
}
