import Foundation

struct GeoResult {
    let latitude: Double
    let longitude: Double
    let provider: String
}

enum GeocodeError: LocalizedError {
    case network(String)
    case server(Int)

    var errorDescription: String? {
        switch self {
        case .network(let m): return "Network error: \(m)"
        case .server(let code): return "Geocoding service returned HTTP \(code)"
        }
    }
}

/// Keeps requests to the public Nominatim service at or below one per second, as its usage policy requires.
actor GeocodeThrottle {
    private var nextSlot = Date.distantPast

    func wait(interval: TimeInterval) async {
        let now = Date()
        let slot = max(now, nextSlot)
        nextSlot = slot.addingTimeInterval(interval)
        let delay = slot.timeIntervalSince(now)
        if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
    }
}

/// Online city geocoding. Primary: OpenStreetMap Nominatim. Fallback: Open-Meteo geocoding API.
/// Neither needs an API key.
enum Geocoder {
    private static let throttle = GeocodeThrottle()
    private static let userAgent = "DCMap/1.0 (macOS desktop app; data-center topology viewer)"

    /// Returns nil when the services answered but found nothing. Throws when no service could be reached.
    static func lookup(city: String, country: String, fallbackName: String = "") async throws -> GeoResult? {
        let place = city.isEmpty ? fallbackName : city
        guard !place.isEmpty else { return nil }

        var failure: Error?
        do {
            if let r = try await nominatim(place: place, country: country, structured: !city.isEmpty) { return r }
        } catch { failure = error }

        do {
            if let r = try await openMeteo(place: place, country: country) { return r }
        } catch { failure = failure ?? error }

        if let f = failure { throw f }
        return nil
    }

    // MARK: Nominatim

    private struct NominatimItem: Decodable {
        let lat: String
        let lon: String
    }

    private static func nominatim(place: String, country: String, structured: Bool) async throws -> GeoResult? {
        for attempt in 0..<2 {
            if attempt == 0 && !structured { continue }
            var comps = URLComponents(string: "https://nominatim.openstreetmap.org/search")!
            var items = [URLQueryItem(name: "format", value: "jsonv2"),
                         URLQueryItem(name: "limit", value: "1"),
                         URLQueryItem(name: "accept-language", value: "en")]
            if attempt == 0 {
                items.append(URLQueryItem(name: "city", value: place))
                if !country.isEmpty { items.append(URLQueryItem(name: "country", value: country)) }
            } else {
                items.append(URLQueryItem(name: "q", value: [place, country].filter { !$0.isEmpty }.joined(separator: ", ")))
            }
            comps.queryItems = items
            guard let url = comps.url else { continue }

            var req = URLRequest(url: url)
            req.timeoutInterval = 20
            req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            req.setValue("application/json", forHTTPHeaderField: "Accept")

            await throttle.wait(interval: 1.1)
            let data = try await fetch(req)
            if let first = (try? JSONDecoder().decode([NominatimItem].self, from: data))?.first,
               let lat = Double(first.lat), let lon = Double(first.lon) {
                return GeoResult(latitude: lat, longitude: lon, provider: "OpenStreetMap Nominatim")
            }
        }
        return nil
    }

    // MARK: Open-Meteo

    private struct MeteoResponse: Decodable {
        struct Item: Decodable {
            let latitude: Double
            let longitude: Double
            let country: String?
            let country_code: String?
        }
        let results: [Item]?
    }

    private static func openMeteo(place: String, country: String) async throws -> GeoResult? {
        var comps = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        comps.queryItems = [URLQueryItem(name: "name", value: place),
                            URLQueryItem(name: "count", value: "10"),
                            URLQueryItem(name: "language", value: "en"),
                            URLQueryItem(name: "format", value: "json")]
        guard let url = comps.url else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let data = try await fetch(req)
        guard let results = (try? JSONDecoder().decode(MeteoResponse.self, from: data))?.results, !results.isEmpty else { return nil }

        let wanted = normalize(country)
        let match = results.first { r in
            guard !wanted.isEmpty else { return false }
            return normalize(r.country ?? "") == wanted || normalize(r.country_code ?? "") == wanted
        } ?? (wanted.isEmpty ? results.first : nil)
        guard let hit = match else { return nil }   // a same-named city in another country is not a match
        return GeoResult(latitude: hit.latitude, longitude: hit.longitude, provider: "Open-Meteo")
    }

    // MARK: HTTP

    private static func fetch(_ req: URLRequest) async throws -> Data {
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw GeocodeError.server(http.statusCode)
            }
            return data
        } catch let e as GeocodeError {
            throw e
        } catch {
            throw GeocodeError.network(error.localizedDescription)
        }
    }
}
