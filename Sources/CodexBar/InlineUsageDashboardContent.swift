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
