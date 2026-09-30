import Foundation
import Observation
import SwiftUI

struct WeatherConditions: Equatable {
    let temperature: Int
    let symbol: String
    let summary: String
    let place: String
}

/// Current weather for the city chosen in Settings, from Open-Meteo. The city name is typed by the
/// person, so no location permission is needed.
@MainActor
@Observable
final class WeatherModel {
    private(set) var conditions: WeatherConditions?

    /// Replaced in tests.
    @ObservationIgnored var fetch: (URL) async -> Data? = WeatherModel.fetchFromNetwork
    @ObservationIgnored var usesFahrenheit = Locale.current.measurementSystem == .us
    @ObservationIgnored var refreshInterval: Duration = .seconds(30 * 60)
    @ObservationIgnored var typingPause: Duration = .milliseconds(800)
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var place: Place?

    struct Place: Equatable {
        let name: String
        let latitude: Double
        let longitude: Double
    }

    /// Starts, changes, or stops (an empty city) the weather. Waits for a pause in typing.
    func configure(city: String) {
        task?.cancel()
        place = nil
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
            temperature: Int(temperature.rounded()), symbol: description.symbol, summary: description.summary, place: place.name
        )
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
