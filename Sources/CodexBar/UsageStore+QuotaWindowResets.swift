import CodexBarCore
import Foundation

extension UsageStore {
    /// Weekly reset timestamps already stored for quota-window cost. Read-only: menu rendering
    /// must not run `planUtilizationHistorySelection`, which can migrate account buckets and
    /// bump `planUtilizationHistoryRevision` as a side effect.
    func weeklyQuotaWindowResetObservations(
        for provider: UsageProvider,
        snapshot: UsageSnapshot? = nil,
        historySelection: PlanUtilizationHistorySelection? = nil) -> [CostUsageQuotaResetObservation]
    {
        if let historySelection {
            return Self.weeklyResetObservations(from: historySelection.histories)
        }
        let buckets = self.planUtilizationHistory[provider.instanceID] ?? PlanUtilizationHistoryBuckets()
        let accountKey = snapshot.flatMap {
            Self.planUtilizationIdentityAccountKey(provider: provider, snapshot: $0)
        } ?? buckets.preferredAccountKey
        return Self.weeklyQuotaResetObservations(in: buckets, accountKey: accountKey)
    }

    static func weeklyQuotaResetObservations(
        in buckets: PlanUtilizationHistoryBuckets,
        accountKey: String?) -> [CostUsageQuotaResetObservation]
    {
        self.weeklyResetObservations(from: buckets.histories(for: accountKey))
    }

    static func weeklyResetObservations(from histories: [PlanUtilizationSeriesHistory])
    -> [CostUsageQuotaResetObservation] {
        histories.first { $0.name == .weekly }?.entries.compactMap { entry in
            entry.resetsAt.map { CostUsageQuotaResetObservation(capturedAt: entry.capturedAt, resetsAt: $0) }
        } ?? []
    }
}
