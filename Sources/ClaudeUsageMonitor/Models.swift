import Foundation

// MARK: - API response (GET https://api.anthropic.com/api/oauth/usage)
// Shape mirrors Claude Code: { five_hour, seven_day, seven_day_opus }
// each { utilization: 0...100 (percent), resets_at: ISO8601 string }

struct UsageWindow: Decodable, Equatable {
    var utilization: Double?
    var resetsAt: Date?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }

    init(utilization: Double?, resetsAt: Date?) {
        self.utilization = utilization
        self.resetsAt = resetsAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        utilization = try c.decodeIfPresent(Double.self, forKey: .utilization)
        if let s = try c.decodeIfPresent(String.self, forKey: .resetsAt) {
            resetsAt = DateParsing.iso8601(s)
        } else {
            resetsAt = nil
        }
    }
}

struct UsageResponse: Decodable, Equatable {
    var fiveHour: UsageWindow?
    var sevenDay: UsageWindow?
    var sevenDayOpus: UsageWindow?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOpus = "seven_day_opus"
    }
}

enum DateParsing {
    private static let withFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    static func iso8601(_ s: String) -> Date? {
        withFractional.date(from: s) ?? plain.date(from: s)
    }
}

// MARK: - Persisted time-series sample for the burst graph
struct Snapshot: Codable, Identifiable, Equatable {
    var id: Date { timestamp }
    let timestamp: Date
    let fiveHour: Double?
    let sevenDay: Double?
    let sevenDayOpus: Double?
}
