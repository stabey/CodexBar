import CodexBarCore
import SwiftUI

struct InlineUsageDashboardModel: Equatable {
    struct KPI: Equatable {
        let title: String
        let value: String
        let emphasis: Bool
    }

    struct Point: Equatable, Identifiable {
        let id: String
        let label: String
        let value: Double?
        let accessibilityValue: String
    }

    enum ValueStyle: Equatable {
        case currencyUSD
        case currency(symbol: String)
        case tokens
        case points
    }

    struct QuotaWindow: Equatable, Identifiable {
        let id: String
        let title: String
        let range: String
        let value: String
    }

    let accessibilityLabel: String
    let valueStyle: ValueStyle
    let kpis: [KPI]
    let points: [Point]
    let detailLines: [String]
    /// Codex/Claude weekly quota windows, newest first. Empty for other cost dashboards.
    var quotaWindows: [QuotaWindow] = []
    /// Provider branding color used to fill the mini usage bars. When nil the bars fall back to a
    /// neutral palette derived from `valueStyle`.
    var barColor: Color?
    /// ISO 4217 currency code for cost dashboards. When non-nil, `MiniUsageBars` shows a max-cost scale label.
    /// Nil for token/points dashboards.
    var currencyCode: String?
}

extension UsageMenuCardView.Model {
    static func apiProviderUsageNotes(input: Input) -> [String]? {
        let menuCard = ProviderDescriptorRegistry.descriptor(for: input.provider).presentation.menuCard
        switch menuCard.usageNotes(context: ProviderUsageNotesContext(
            snapshot: input.snapshot,
            isRefreshing: input.isRefreshing,
            costSummaryInlineEnabled: input.costSummaryInlineEnabled,
            showOptionalUsage: input.showOptionalCreditsAndExtraUsage))
        {
        case let .openAIAPI(usage):
            return self.openAIAPIUsageNotes(usage)
        case let .localized(keys):
            return keys.map { L($0) }
        case .unhandled:
            return nil
        }
    }

    static func openAIAPIUsageNotes(_ usage: OpenAIAPIUsageSnapshot) -> [String] {
        let today = usage.currentDay
        let seven = usage.last7Days
        let thirty = usage.last30Days
        let historyLabel = usage.historyWindowLabel
        let todayNote = String(
            format: L("Today: %@ · %@ tokens"),
            UsageFormatter.usdString(today.costUSD),
            UsageFormatter.tokenCountString(today.totalTokens))
        let sevenDayNote = "7d: \(UsageFormatter.usdString(seven.costUSD)) · " +
            "\(UsageFormatter.tokenCountString(seven.requests)) \(L(\"requests\"))"
        let thirtyDayNote =
            "\(historyLabel): \(UsageFormatter.tokenCountString(thirty.totalTokens)) \(L(\"tokens\")) · " +
            "\(UsageFormatter.tokenCountString(thirty.requests)) \(L(\"requests\"))"
        var notes: [String] = [
            todayNote,
            sevenDayNote,
            thirtyDayNote,
        ]
        if let topModel = usage.topModels.first {
            notes.append("\(L(\"Top model\")): \(topModel.name)")
        }
        return notes
    }

    static func inlineUsageDashboard(input: Input) -> InlineUsageDashboardModel? {
        guard var model = self.resolveInlineUsageDashboard(input: input) else { return nil }
        model.barColor = Self.inlineDashboardBarColor(for: input.provider)
        return model
    }

    /// Provider branding color for the inline usage bars, matching the provider's switcher tab and
    /// detailed cost-history chart.
    static func inlineDashboardBarColor(for provider: UsageProvider) -> Color {
        let color = ProviderAccentPalette.color(for: provider)
        return Color(red: color.red, green: color.green, blue: color.blue)
    }

    private static func resolveInlineUsageDashboard(input: Input) -> InlineUsageDashboardModel? {
        let menuCard = ProviderDescriptorRegistry.descriptor(for: input.provider).presentation.menuCard
        if menuCard.usesProviderCostHistoryAsPrimaryDashboard,
           input.costSummaryInlineEnabled,
           let tokenSnapshot = primaryCostHistorySnapshot(input: input),
           !tokenSnapshot.daily.isEmpty
        {
            return self.costHistoryInlineDashboard(
                provider: input.provider,
                snapshot: tokenSnapshot,
                comparisonPeriodsEnabled: input.costComparisonPeriodsEnabled,
                preferredCurrencyCode: input.preferredCurrencyCode,
                calendar: input.costUsageBucketCalendar,
                weeklyWindow: input.snapshot?.secondary,
                observedNextResets: input.observedWeeklyNextResets,
                observedResetInstants: Self.redeemedWeeklyResetInstants(from: input.snapshot),
                now: input.now)
        }
        if menuCard.supportsInlineTokenCostDashboard,
           input.costSummaryInlineEnabled,
           let tokenSnapshot = input.tokenSnapshot,
           !tokenSnapshot.daily.isEmpty || tokenSnapshot.meteredCostUSD != nil
        {
            return Self.costHistoryInlineDashboard(
                provider: input.provider,
                snapshot: tokenSnapshot,
                comparisonPeriodsEnabled: input.costComparisonPeriodsEnabled,
                preferredCurrencyCode: input.preferredCurrencyCode,
                calendar: input.costUsageBucketCalendar,
                weeklyWindow: input.snapshot?.secondary,
                observedNextResets: input.observedWeeklyNextResets,
                observedResetInstants: Self.redeemedWeeklyResetInstants(from: input.snapshot),
                now: input.now)
        }
        return nil
    }

    static func usesProviderCostHistoryAsPrimaryDashboard(_ provider: UsageProvider) -> Bool {
        ProviderDescriptorRegistry.descriptor(for: provider).presentation.menuCard
            .usesProviderCostHistoryAsPrimaryDashboard
    }

    static func primaryCostHistorySnapshot(input: Input) -> CostUsageTokenSnapshot? {
        ProviderDescriptorRegistry.descriptor(for: input.provider).presentation.menuCard.primaryCostHistory(
            snapshot: input.snapshot,
            tokenSnapshot: input.tokenSnapshot)
    }

    static func showsQuotaWeekCost(for provider: UsageProvider) -> Bool {
        provider == .codex || provider == .claude
    }

    private static func costHistoryInlineDashboard(
        provider: UsageProvider,
        snapshot: CostUsageTokenSnapshot,
        comparisonPeriodsEnabled: Bool,
        preferredCurrencyCode: String,
        calendar: Calendar,
        weeklyWindow: RateWindow?,
        observedNextResets: [Date] = [],
        observedResetInstants: [Date] = [],
        now: Date? = nil) -> InlineUsageDashboardModel
    {
        let displayCurrencyCode = UsageFormatter.convertedCost(
            0,
            preferredCurrency: preferredCurrencyCode,
            providerCurrency: snapshot.currencyCode).currencyCode
        func convertedValue(_ value: Double) -> Double {
            UsageFormatter.convertedCost(
                value,
                preferredCurrency: preferredCurrencyCode,
                providerCurrency: snapshot.currencyCode).value
        }
        func convertedString(_ value: Double) -> String {
            UsageFormatter.convertedCostString(
                value,
                preferredCurrency: preferredCurrencyCode,
                providerCurrency: snapshot.currencyCode)
        }

        let historyDays = max(1, min(365, snapshot.historyDays))
        let defaultHistoryTitle = snapshot.historyLabel
            ?? (historyDays == 1
                ? L("Today")
                : historyDays == 30
                ? L("30d cost")
                : "\(String(format: L(\"Last %d days\"), historyDays)) \(L(\"Cost\"))")
        let tokenCost = ProviderDescriptorRegistry.descriptor(for: provider).tokenCost
        let quotaWeeks = Self.showsQuotaWeekCost(for: provider) && historyDays >= 7
            ? snapshot.quotaWeekSummaries(
                resetAt: CostUsageTokenSnapshot.quotaWeekReset(from: weeklyWindow),
                windowMinutes: weeklyWindow?.windowMinutes,
                observedNextResets: observedNextResets,
                observedResetInstants: observedResetInstants,
                now: now,
                calendar: calendar)
            : []
        let currentWeek = quotaWeeks.first { $0.isCurrent }
        var model = InlineUsageDashboardModel(
            accessibilityLabel: L("%@: %@", ProviderDefaults.metadata[provider]?.displayName ?? provider.rawValue, L("30d cost")),
            valueStyle: .currencyUSD,
            kpis: [],
            points: [],
            detailLines: [])
        model.quotaWindows = quotaWeeks.compactMap { week in
            guard week.isCurrent || week.entryCount > 0 else { return nil }
            return Self.quotaWindowRow(week: week, cost: week.totalCostUSD.map { UsageFormatter.convertedCostString($0, preferredCurrency: preferredCurrencyCode, providerCurrency: snapshot.currencyCode) } ?? "—", calendar: calendar)
        }
        model.currencyCode = displayCurrencyCode
        return model
    }

    private static func redeemedWeeklyResetInstants(from snapshot: UsageSnapshot?) -> [Date] {
        snapshot?.codexResetCredits?.credits.compactMap { credit in
            guard credit.status == .redeemed else { return nil }
            return credit.redeemedAt
        } ?? []
    }

    private static func quotaWindowRow(
        week: CostUsageQuotaWeek,
        cost: String,
        calendar: Calendar) -> InlineUsageDashboardModel.QuotaWindow
    {
        let value: String = if let totalTokens = week.totalTokens {
            "\(cost) · \(UsageFormatter.tokenCountString(totalTokens))"
        } else {
            cost
        }
        return InlineUsageDashboardModel.QuotaWindow(
            id: "\(week.offset)-\(Int(week.start.timeIntervalSince1970))",
            title: Self.quotaWeekHistoryLabel(week: week),
            range: Self.quotaWindowRangeLabel(start: week.start, end: week.end, calendar: calendar),
            value: value)
    }

    static func quotaWindowRangeLabel(
        start: Date,
        end: Date,
        calendar: Calendar,
        locale: Locale = codexBarLocalizedResourceLocale()) -> String
    {
        let startDay = calendar.dateComponents([.year, .month, .day], from: start)
        let endDay = calendar.dateComponents([.year, .month, .day], from: end)
        let sameDay = startDay.year == endDay.year
            && startDay.month == endDay.month
            && startDay.day == endDay.day
        let sameYear = startDay.year == endDay.year
        func formatter(template: String) -> DateFormatter {
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.setLocalizedDateFormatFromTemplate(template)
            return formatter
        }
        if sameDay {
            let startText = formatter(template: "MMMdjmm").string(from: start)
            let endText = formatter(template: "jmm").string(from: end)
            return "\(startText) – \(endText)"
        }
        let template = sameYear ? "MMMdjmm" : "yMMMdjmm"
        let rangeFormatter = formatter(template: template)
        return "\(rangeFormatter.string(from: start)) – \(rangeFormatter.string(from: end))"
    }

    private static func quotaWeekHistoryLabel(week: CostUsageQuotaWeek) -> String {
        switch week.offset {
        case 0:
            return L("This week")
        case 1:
            return week.isNominalWeek ? L("Last week") : L("Previous window")
        default:
            return week.isNominalWeek
                ? L("%d weeks ago", week.offset)
                : L("%d windows ago", week.offset)
        }
    }
}

struct InlineUsageDashboardContent: View {
    private let model: InlineUsageDashboardModel
    @Environment(\.menuItemHighlighted) private var isHighlighted

    init(model: InlineUsageDashboardModel) {
        self.model = model
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !self.model.quotaWindows.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("Recent windows"))
                        .font(.caption2)
                    ForEach(self.model.quotaWindows) { window in
                        VStack(alignment: .leading, spacing: 1) {
                            HStack {
                                Text(window.title)
                                Spacer()
                                Text(window.value)
                            }
                            Text(window.range)
                                .font(.caption2)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct InlineUsageBarLayout {
    let spacing: CGFloat
    let barWidth: CGFloat
    init(width: CGFloat, count: Int) {
        let count = max(1, count)
        let width = max(0, width)
        self.spacing = count == 1 ? 0 : min(2, width / CGFloat(count) / 4)
        self.barWidth = max(0, (width - self.spacing * CGFloat(count - 1)) / CGFloat(count))
    }
}
