import Foundation
import AnyLanguageModel

/// Fetches historical hourly temperatures for a location from the Open-Meteo archive API.
///
/// Returns a daily summary (min / mean / max) for the requested range, plus the
/// hourly readings when the range is short enough to keep the output compact.
public struct HistoricWeatherTool: Tool {

    public let name = "historic_weather"

    public let description = """
        Get historical hourly air temperatures (2 m above ground, °C) for a location \
        and date range. Use this for questions about past weather. \
        Returns daily min / mean / max temperatures; hourly readings are included \
        only for ranges of up to 3 days, so request just the days you need \
        when asked about a specific time. \
        Dates are in ISO 8601 format (YYYY-MM-DD) and times are in GMT.
        """

    @Generable
    public struct Arguments {
        @Guide(description: "Latitude of the location in decimal degrees, e.g. 52.52 for Berlin.")
        public var latitude: Double
        @Guide(description: "Longitude of the location in decimal degrees, e.g. 13.41 for Berlin.")
        public var longitude: Double
        @Guide(description: "First day of the range, formatted YYYY-MM-DD.")
        public var startDate: String
        @Guide(description: "Last day of the range (inclusive), formatted YYYY-MM-DD.")
        public var endDate: String
    }

    /// Ranges up to this many days also include every hourly reading.
    static let maxDaysWithHourlyDetail = 3

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func call(arguments: Arguments) async throws -> String {
        let (data, _) = try await session.data(from: try url(for: arguments))

        if let failure = try? JSONDecoder().decode(ArchiveError.self, from: data), failure.error {
            throw ToolError.executionFailed("Open-Meteo request failed: \(failure.reason)")
        }
        let archive: ArchiveResponse = try JSONDecoder().decode(ArchiveResponse.self, from: data)
        return format(archive)
    }
  
    // MARK: - Private helpers

    private func url(for arguments: Arguments) throws -> URL {
        var components = URLComponents(string: "https://archive-api.open-meteo.com/v1/archive")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(arguments.latitude)),
            URLQueryItem(name: "longitude", value: String(arguments.longitude)),
            URLQueryItem(name: "start_date", value: arguments.startDate),
            URLQueryItem(name: "end_date", value: arguments.endDate),
            URLQueryItem(name: "hourly", value: "temperature_2m"),
        ]
        guard let url = components.url else { throw ToolError.invalidInput }
        return url
    }

    private func format(_ archive: ArchiveResponse) -> String {
        let unit = archive.hourlyUnits.temperature2m
        // Pair each timestamp with its reading; the archive reports `null` for missing hours.
        let readings = zip(archive.hourly.time, archive.hourly.temperature2m)
            .compactMap { time, value in value.map { (time: time, value: $0) } }

        guard !readings.isEmpty else {
            return "No temperature data available for this location and date range."
        }

        // Timestamps look like "2025-01-01T13:00"; the first 10 characters are the date.
        var days: [(date: String, values: [Double])] = []
        for reading in readings {
            let date = String(reading.time.prefix(10))
            if days.last?.date == date {
                days[days.count - 1].values.append(reading.value)
            } else {
                days.append((date, [reading.value]))
            }
        }

        var lines = ["Location: \(archive.latitude), \(archive.longitude) (timezone \(archive.timezone))"]
        lines.append("Daily temperature (min / mean / max, \(unit)):")
        for day in days {
            let mean = day.values.reduce(0, +) / Double(day.values.count)
            lines.append("\(day.date): \(day.values.min()!) / \(mean.rounded(toPlaces: 1)) / \(day.values.max()!)")
        }

        if days.count <= Self.maxDaysWithHourlyDetail {
            lines.append("Hourly temperature (\(unit)):")
            lines += readings.map { "\($0.time): \($0.value)" }
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Open-Meteo response types

private struct ArchiveResponse: Decodable {
    struct Hourly: Decodable {
        let time: [String]
        let temperature2m: [Double?]

        enum CodingKeys: String, CodingKey {
            case time
            case temperature2m = "temperature_2m"
        }
    }

    struct HourlyUnits: Decodable {
        let temperature2m: String

        enum CodingKeys: String, CodingKey {
            case temperature2m = "temperature_2m"
        }
    }

    let latitude: Double
    let longitude: Double
    let timezone: String
    let hourly: Hourly
    let hourlyUnits: HourlyUnits

    enum CodingKeys: String, CodingKey {
        case latitude, longitude, timezone, hourly
        case hourlyUnits = "hourly_units"
    }
}

private struct ArchiveError: Decodable {
    let error: Bool
    let reason: String
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10, Double(places))
        return (self * factor).rounded() / factor
    }
}
