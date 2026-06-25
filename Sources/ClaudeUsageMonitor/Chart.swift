import SwiftUI
import Charts

enum BurstWindow: String, CaseIterable, Identifiable {
    case session = "세션(5h)"
    case week = "주간"
    var id: String { rawValue }
}

enum BurstGranularity: String, CaseIterable, Identifiable {
    case minute = "분"
    case hour = "시간"
    case day = "일"
    var id: String { rawValue }

    var bucket: TimeInterval {
        switch self {
        case .minute: return 60
        case .hour:   return 3600
        case .day:    return 86400
        }
    }
    /// How far back the chart looks.
    var span: TimeInterval {
        switch self {
        case .minute: return 2 * 3600        // last 2 hours, per-minute
        case .hour:   return 24 * 3600        // last day, per-hour
        case .day:    return 30 * 86400       // last 30 days, per-day
        }
    }
    var axisFormat: Date.FormatStyle {
        switch self {
        case .minute: return .dateTime.hour().minute()
        case .hour:   return .dateTime.hour()
        case .day:    return .dateTime.month().day()
        }
    }
}

enum BurstMetric: String, CaseIterable, Identifiable {
    case level = "사용률"
    case rate  = "소진속도"
    var id: String { rawValue }
}

struct ChartPoint: Identifiable {
    var id: Date { time }
    let time: Date
    let value: Double
}

enum BurstAggregator {
    static func points(snapshots: [Snapshot],
                       window: BurstWindow,
                       granularity: BurstGranularity,
                       metric: BurstMetric) -> [ChartPoint] {
        let start = Date().addingTimeInterval(-granularity.span)
        let series: [(Date, Double)] = snapshots
            .filter { $0.timestamp >= start }
            .compactMap { s in
                let v = (window == .session) ? s.fiveHour : s.sevenDay
                guard let v else { return nil }
                return (s.timestamp, v)
            }
            .sorted { $0.0 < $1.0 }

        guard !series.isEmpty else { return [] }

        let bucket = granularity.bucket
        func bucketStart(_ d: Date) -> Date {
            let t = d.timeIntervalSince1970
            return Date(timeIntervalSince1970: (t / bucket).rounded(.down) * bucket)
        }

        switch metric {
        case .level:
            // Peak utilization within each time bucket.
            var byBucket: [Date: Double] = [:]
            for (t, v) in series {
                let b = bucketStart(t)
                byBucket[b] = max(byBucket[b] ?? 0, v)
            }
            return byBucket.keys.sorted().map { ChartPoint(time: $0, value: byBucket[$0]!) }

        case .rate:
            // Consumption velocity: sum of positive deltas per bucket.
            // Negative deltas are window resets and are ignored.
            guard series.count >= 2 else { return [] }
            var byBucket: [Date: Double] = [:]
            for i in 1..<series.count {
                let delta = series[i].1 - series[i - 1].1
                if delta > 0 {
                    byBucket[bucketStart(series[i].0), default: 0] += delta
                }
            }
            return byBucket.keys.sorted().map { ChartPoint(time: $0, value: byBucket[$0]!) }
        }
    }
}

struct BurstChartView: View {
    let snapshots: [Snapshot]
    @State private var window: BurstWindow = .session
    @State private var granularity: BurstGranularity = .minute
    @State private var metric: BurstMetric = .level

    private var points: [ChartPoint] {
        BurstAggregator.points(snapshots: snapshots, window: window,
                               granularity: granularity, metric: metric)
    }

    private var yDomain: ClosedRange<Double> {
        if metric == .level { return 0...100 }
        let maxV = points.map(\.value).max() ?? 1
        return 0...max(1, maxV * 1.15)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("사용량 추이")
                .font(.system(size: 13, weight: .semibold))

            Picker("", selection: $granularity) {
                ForEach(BurstGranularity.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack(spacing: 8) {
                Picker("", selection: $window) {
                    ForEach(BurstWindow.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                Picker("", selection: $metric) {
                    ForEach(BurstMetric.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
            }
            .font(.system(size: 11))

            chart
        }
    }

    @ViewBuilder private var chart: some View {
        if points.count < 2 {
            VStack(spacing: 6) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
                Text("데이터 수집 중…\n폴링이 쌓이면 추이가 표시됩니다.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 130)
        } else {
            Chart(points) { p in
                AreaMark(x: .value("시간", p.time), y: .value("값", p.value))
                    .foregroundStyle(.linearGradient(
                        colors: [.blue.opacity(0.35), .blue.opacity(0.02)],
                        startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("시간", p.time), y: .value("값", p.value))
                    .foregroundStyle(.blue)
                    .interpolationMethod(.monotone)
            }
            .chartYScale(domain: yDomain)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine()
                    AxisValueLabel(format: granularity.axisFormat)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let d = value.as(Double.self) {
                            Text(metric == .level ? "\(Int(d))%" : "\(Int(d))")
                        }
                    }
                }
            }
            .frame(height: 130)
        }
    }
}
