import ErstModel
import SwiftUI

/// How a day, week, or month was spent.
public struct ActivityScreen: View {
    @StateObject private var model: ActivityModel
    private let chartHeightPoints: CGFloat = 214
    private let listRowLimitCount = 5

    public init(service: any MemoryService, period: ActivityModel.Period = .day) {
        _model = StateObject(wrappedValue: ActivityModel(service: service, period: period))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxLarge) {
            ActivityToolbar(model: model)
                .erstArrival(0, from: .above, blurs: false)
            ActivitySummary(model: model)
                .erstArrival(1)
            ActivityHourChart(buckets: model.chartBuckets, labels: model.chartLabels)
                .frame(height: chartHeightPoints)
                .erstArrival(2)
            HStack(alignment: .top, spacing: Spacing.xxxLarge) {
                ActivityList(
                    title: "Apps",
                    rows: model.report?.apps.prefix(listRowLimitCount).map(ActivityListRowData.app) ?? [],
                    color: .erstButter
                )
                ActivityList(
                    title: "Websites",
                    rows: model.report?.websites.prefix(listRowLimitCount).map(ActivityListRowData.site)
                        ?? [],
                    color: .erstOrange
                )
            }
            .erstArrival(3)
            Spacer(minLength: 0)
        }
        .padding(Spacing.xxxLarge)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .erstArrivalStage()
        .windowMaterial()
        .preferredColorScheme(.dark)
        .task {
            Typography.registerFonts()
            await model.load()
        }
    }
}
