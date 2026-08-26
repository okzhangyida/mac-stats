import Foundation

struct HistoryBuffer {
    private(set) var points: [MetricPoint] = []
    let retentionInterval: TimeInterval
    let maximumPoints: Int

    init(retentionInterval: TimeInterval = 120, maximumPoints: Int = 180) {
        self.retentionInterval = retentionInterval
        self.maximumPoints = maximumPoints
    }

    mutating func append(_ value: Double, at date: Date = Date()) {
        points.append(MetricPoint(date: date, value: value))
        let cutoff = date.addingTimeInterval(-retentionInterval)
        points.removeAll { $0.date < cutoff }
        if points.count > maximumPoints {
            points.removeFirst(points.count - maximumPoints)
        }
    }
}
