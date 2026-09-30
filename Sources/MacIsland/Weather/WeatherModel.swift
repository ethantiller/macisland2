import Foundation
import Observation
import SwiftUI

/// One of the next hours, in the place's own time: the hour of the day (0 to 23), so a label never shifts with this
/// Mac's time zone.
struct WeatherHour: Equatable {
    let hour: Int
    let temperature: Int
    let symbol: String
}

/// One day of the forecast: a short weekday name ("Today" first), the conditions, and the high and low.
struct WeatherDay: Equatable {
    let label: String
    let symbol: String
    let high: Int
    let low: Int
}

struct WeatherConditions: Equatable {
    let temperature: Int
    let symbol: String
    let summary: String
    let place: String
    /// The five hours after this one, and five days starting today. Empty when the forecast didn't come with them.
    var hours: [WeatherHour] = []
    var days: [WeatherDay] = []
}

/// Current weather for the city chosen in Settings, from Open-Meteo. The city name is typed by the
/// person, so no location permission is needed.
@MainActor
@Observable
final class WeatherModel {
    private(set) var conditions: WeatherConditions?

    /// Replaced in tests.
    @ObservationIgnored var fetch: (URL) async -> Data? = WeatherModel.fetchFromNetwork
    /// Follows macOS's own Temperature choice (System Settings, Language & Region), so it is not a setting here.
    @ObservationIgnored var usesFahrenheit = WeatherModel.systemUsesFahrenheit()
    @ObservationIgnored var refreshInterval: Duration = .seconds(30 * 60)
    /// Called with when rain is due to start, at most once per rain spell.
    @ObservationIgnored var onRainSoon: ((Date) -> Void)?
    @ObservationIgnored var now: () -> Date = Date.init
    @ObservationIgnored private var spell = RainSpell()
    @ObservationIgnored var typingPause: Duration = .milliseconds(800)
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var place: Place?

    struct Place: Equatable {
        let name: String
        let latitude: Double
        let longitude: Double
    }

    /// `AppleTemperatureUnit` is "Celsius" or "Fahrenheit" when the person chose one; otherwise the region decides.
    nonisolated static func usesFahrenheit(preference: String?, region: Locale.MeasurementSystem) -> Bool {
        switch preference {
        case "Fahrenheit": true
        case "Celsius": false
        default: region == .us
        }
    }

    nonisolated static func systemUsesFahrenheit() -> Bool {
        usesFahrenheit(
            preference: UserDefaults.standard.string(forKey: "AppleTemperatureUnit"),
            region: Locale.current.measurementSystem)
    }

    /// Starts, changes, or stops (an empty city) the weather. Waits for a pause in typing.
    func configure(city: String) {
        task?.cancel()
        place = nil
        spell = RainSpell()
        let name = Self.searchName(from: city)
        guard !name.isEmpty else {
            withAnimation(Theme.Motion.resize) { conditions = nil }
            return
        }
        task = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: typingPause)
            while !Task.isCancelled {
                await refresh(name: name)
                try? await Task.sleep(for: refreshInterval)
            }
        }
    }

    /// Stops asking. The model keeps what it has.
    func stop() {
        task?.cancel()
        task = nil
    }

    func refresh(name: String) async {
        if place == nil {
            guard let url = Self.geocodingURL(city: name), let data = await fetch(url) else { return }
            place = Self.parsePlace(data)
        }
        guard let place, let url = Self.forecastURL(place: place, fahrenheit: usesFahrenheit),
            let data = await fetch(url), !Task.isCancelled
        else { return }
        let new = Self.parseConditions(data, place: place)
        withAnimation(Theme.Motion.resize) { conditions = new }
        announceRainIfDue(Self.parseRain(data))
    }

    private func announceRainIfDue(_ samples: [RainSample]) {
        let current = now()
        let start = RainRule.start(samples: samples, now: current)
        let wet = RainRule.isWet(samples: samples, now: current)
        if spell.shouldAnnounce(start: start, wetNow: wet, now: current), let start { onRainSoon?(start) }
    }

    // MARK: Requests and parsing

    /// "Paris, France" searches for "Paris": the geocoder matches city names, not addresses.
    nonisolated static func searchName(from city: String) -> String {
        city.split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
    }

    nonisolated static func geocodingURL(city: String) -> URL? {
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")
        components?.queryItems = [
            URLQueryItem(name: "name", value: city),
            URLQueryItem(name: "count", value: "1"),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "format", value: "json"),
        ]
        return components?.url
    }

    nonisolated static func forecastURL(place: Place, fahrenheit: Bool) -> URL? {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(place.latitude)),
            URLQueryItem(name: "longitude", value: String(place.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "minutely_15", value: "precipitation"),
            URLQueryItem(name: "forecast_minutely_15", value: "8"),
            URLQueryItem(name: "hourly", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "forecast_hours", value: "6"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "forecast_days", value: "5"),
            URLQueryItem(name: "temperature_unit", value: fahrenheit ? "fahrenheit" : "celsius"),
            URLQueryItem(name: "timezone", value: "auto"),
        ]
        return components?.url
    }

    nonisolated static func parsePlace(_ data: Data) -> Place? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let first = (root["results"] as? [[String: Any]])?.first,
            let latitude = first["latitude"] as? Double, let longitude = first["longitude"] as? Double
        else { return nil }
        return Place(name: first["name"] as? String ?? "", latitude: latitude, longitude: longitude)
    }

    nonisolated static func parseConditions(_ data: Data, place: Place) -> WeatherConditions? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let current = root["current"] as? [String: Any],
            let temperature = current["temperature_2m"] as? Double, let code = current["weather_code"] as? Int
        else { return nil }
        let isDay = (current["is_day"] as? Int ?? 1) == 1
        let description = describe(code: code, isDay: isDay)
        return WeatherConditions(
            temperature: Int(temperature.rounded()), symbol: description.symbol, summary: description.summary,
            place: place.name, hours: parseHours(root), days: parseDays(root)
        )
    }

    /// The five hours after the current one (the forecast starts at the current hour).
    nonisolated static func parseHours(_ root: [String: Any]) -> [WeatherHour] {
        guard let block = root["hourly"] as? [String: Any], let times = block["time"] as? [String],
            let temperatures = block["temperature_2m"] as? [Any], let codes = block["weather_code"] as? [Any]
        else { return [] }
        let isDay = block["is_day"] as? [Any] ?? []
        var hours: [WeatherHour] = []
        for index in times.indices.dropFirst() where hours.count < 5 {
            // "2026-09-30T14:00" is already the place's own time, so the hour is what follows the T.
            guard temperatures.indices.contains(index), codes.indices.contains(index),
                let temperature = (temperatures[index] as? NSNumber)?.doubleValue,
                let code = (codes[index] as? NSNumber)?.intValue,
                let hour = times[index].split(separator: "T").last.flatMap({ Int($0.prefix(2)) })
            else { continue }
            let day = isDay.indices.contains(index) ? ((isDay[index] as? NSNumber)?.intValue ?? 1) == 1 : true
            hours.append(
                WeatherHour(
                    hour: hour, temperature: Int(temperature.rounded()),
                    symbol: describe(code: code, isDay: day).symbol))
        }
        return hours
    }

    /// Five days from today: "Today", then the short weekday names.
    nonisolated static func parseDays(_ root: [String: Any]) -> [WeatherDay] {
        guard let block = root["daily"] as? [String: Any], let dates = block["time"] as? [String],
            let codes = block["weather_code"] as? [Any], let highs = block["temperature_2m_max"] as? [Any],
            let lows = block["temperature_2m_min"] as? [Any]
        else { return [] }
        var days: [WeatherDay] = []
        for (index, text) in dates.enumerated() where days.count < 5 {
            guard codes.indices.contains(index), highs.indices.contains(index), lows.indices.contains(index),
                let code = (codes[index] as? NSNumber)?.intValue,
                let high = (highs[index] as? NSNumber)?.doubleValue,
                let low = (lows[index] as? NSNumber)?.doubleValue
            else { continue }
            days.append(
                WeatherDay(
                    label: days.isEmpty ? "Today" : weekdayName(ofDate: text),
                    symbol: describe(code: code, isDay: true).symbol, high: Int(high.rounded()),
                    low: Int(low.rounded())))
        }
        return days
    }

    /// "Mon" for "2026-09-28": the date is the place's own calendar day, so this Mac's time zone doesn't matter.
    private nonisolated static func weekdayName(ofDate text: String) -> String {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return "" }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
        else { return "" }
        return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][calendar.component(.weekday, from: date) - 1]
    }

    /// The quarter-hour precipitation, in the place's own time zone (`utc_offset_seconds` says which).
    nonisolated static func parseRain(_ data: Data) -> [RainSample] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let block = root["minutely_15"] as? [String: Any],
            let times = block["time"] as? [String], let amounts = block["precipitation"] as? [Any]
        else { return [] }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        formatter.timeZone = TimeZone(secondsFromGMT: root["utc_offset_seconds"] as? Int ?? 0)
        return zip(times, amounts).compactMap { time, amount in
            formatter.date(from: time).map {
                RainSample(time: $0, millimeters: (amount as? NSNumber)?.doubleValue ?? 0)
            }
        }
    }

    /// WMO weather codes, as Open-Meteo reports them.
    nonisolated static func describe(code: Int, isDay: Bool) -> (symbol: String, summary: String) {
        switch code {
        case 0: (isDay ? "sun.max.fill" : "moon.stars.fill", "Clear")
        case 1: (isDay ? "sun.max.fill" : "moon.stars.fill", "Mostly Clear")
        case 2: (isDay ? "cloud.sun.fill" : "cloud.moon.fill", "Partly Cloudy")
        case 3: ("cloud.fill", "Overcast")
        case 45, 48: ("cloud.fog.fill", "Fog")
        case 51...57: ("cloud.drizzle.fill", "Drizzle")
        case 61, 63, 66: ("cloud.rain.fill", "Rain")
        case 65, 67: ("cloud.heavyrain.fill", "Heavy Rain")
        case 71...77, 85, 86: ("cloud.snow.fill", "Snow")
        case 80...82: ("cloud.heavyrain.fill", "Showers")
        case 95...99: ("cloud.bolt.rain.fill", "Thunderstorm")
        default: ("cloud.fill", "Cloudy")
        }
    }

    private nonisolated static func fetchFromNetwork(_ url: URL) async -> Data? {
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("MacIsland/0.1", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
            (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        return data
    }
}

/// The current conditions in one glance: symbol and temperature.
struct WeatherGlance: View {
    let conditions: WeatherConditions

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: conditions.symbol)
                .font(.system(size: 13, weight: .medium))
                .symbolRenderingMode(.multicolor)
                .frame(width: Theme.Metrics.glyphSlot)
                .accessibilityHidden(true)
            Text("\(conditions.temperature)°")
                .font(Theme.Typography.compactNumeral)
                .foregroundStyle(Theme.Palette.primary)
        }
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(conditions.summary), \(conditions.temperature) degrees in \(conditions.place)")
    }
}
