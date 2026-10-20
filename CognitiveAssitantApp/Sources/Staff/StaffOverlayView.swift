import SwiftUI

/// Staff-only overlay attached to the **bottom** of the session screen (360pt tall).
///
/// On the landscape canvas it was a 344pt side panel on the right. Moving to portrait (834 wide),
/// keeping it at the side would shrink the elder stage to 490pt, so it was laid down as a horizontal panel at the bottom.
/// Metrics are the left column, the quiet record the right column.
///
/// Principle 01 — questions, scores and timers never appear on the elder screen.
/// All metrics show up only in this panel and in after-the-fact reports.
struct StaffOverlayView: View {
    var personName: String
    var personMeta: String
    var metrics: [Metric]
    var log: [LogEntry]

    /// Fixed width of the metrics column. The quiet record takes the rest.
    private let metricColumnWidth: CGFloat = 340

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            HStack(alignment: .top, spacing: 26) {
                metricList
                    .frame(width: metricColumnWidth, alignment: .leading)
                Rectangle()
                    .fill(Theme.cream(0.09))
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
                silentLog
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 22)
        .frame(width: DesignSpec.width, height: 360, alignment: .topLeading)
        .background(Color(hex: 0x080A0E).opacity(0.6))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.cream(0.09))
                .frame(height: 1)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("STAFF OVERLAY · NOT SHOWN TO ELDER")
                .font(.kr(11, .semibold))
                .letterSpacing(0.12, 11)
                .foregroundStyle(Theme.blue)
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text("\(personName) · session in progress")
                    .font(.kr(17, .bold))
                    .foregroundStyle(Theme.faceText)
                Spacer(minLength: 8)
                Text(personMeta)
                    .font(.kr(12))
                    .foregroundStyle(Theme.cream(0.4))
            }
        }
    }

    private var metricList: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(metrics) { metric in
                MetricBar(metric: metric)
            }
        }
    }

    private var silentLog: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SILENT LOG")
                .font(.kr(12, .semibold))
                .letterSpacing(0.08, 12)
                .foregroundStyle(Theme.cream(0.45))

            VStack(alignment: .leading, spacing: 8) {
                ForEach(log) { entry in
                    LogRow(entry: entry)
                        .transition(.fadeUp)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipped()
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .animation(.easeOut(duration: 0.3), value: log)
    }
}

/// One metric — name · value · bar · description.
struct MetricBar: View {
    var metric: Metric

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(metric.label)
                    .font(.kr(13, .semibold))
                    .foregroundStyle(Theme.cream(0.85))
                Spacer(minLength: 8)
                Text(metric.value)
                    .font(.kr(13, .bold))
                    .foregroundStyle(metric.color)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Theme.cream(0.1))
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(metric.color)
                        .frame(width: geo.size.width * metric.percent / 100)
                }
            }
            .frame(height: 6)
            .animation(.easeOut(duration: 0.4), value: metric.percent)

            Text(metric.note)
                .font(.kr(11))
                .foregroundStyle(Theme.cream(0.35))
        }
    }
}

/// One line of the quiet record.
struct LogRow: View {
    var entry: LogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.tag)
                .font(.kr(11, .semibold))
                .letterSpacing(0.06, 11)
                .foregroundStyle(entry.color)
            Text(entry.text)
                .font(.kr(13))
                .foregroundStyle(Theme.cream(0.75))
                .cssLineHeight(1.5, 13)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Theme.cream(0.06))
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0,
                                          bottomTrailingRadius: 8, topTrailingRadius: 8,
                                          style: .continuous))
        .overlay(alignment: .leading) {
            Rectangle().fill(entry.color).frame(width: 2)
        }
    }
}
