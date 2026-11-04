import Foundation
import CoreLocation
import SwiftUI

enum QuakeSource: String, CaseIterable {
    case afad = "AFAD", kandilli = "Kandilli", emsc = "EMSC", usgs = "USGS"
    var priority: Int {
        switch self {
        case .afad: return 0
        case .kandilli: return 1
        case .emsc: return 2
        case .usgs: return 3
        }
    }
}

struct Quake: Identifiable, Hashable {
    let id: String
    let source: QuakeSource
    let time: Date
    let lat: Double
    let lon: Double
    let depth: Double
    let mag: Double
    let place: String

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }

    var color: Color {
        if mag < 3 { return .green }
        if mag < 4 { return .yellow }
        if mag < 5 { return .orange }
        return .red
    }
}

/// Türkiye ve çevresi (Android sürümündeki "Bölgem" varsayılanı ile aynı mantık).
func inTurkeyRegion(_ q: Quake) -> Bool {
    q.lat >= 34 && q.lat <= 43.5 && q.lon >= 24 && q.lon <= 46
}

func distanceKm(_ a: Quake, _ b: Quake) -> Double {
    let r = 6371.0
    let dLat = (b.lat - a.lat) * .pi / 180
    let dLon = (b.lon - a.lon) * .pi / 180
    let x = sin(dLat / 2) * sin(dLat / 2) +
        cos(a.lat * .pi / 180) * cos(b.lat * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
    return 2 * r * asin(min(1, sqrt(x)))
}

enum Sources {
    static func get(_ s: String) async throws -> Data {
        guard let u = URL(string: s) else { throw URLError(.badURL) }
        var r = URLRequest(url: u)
        r.timeoutInterval = 20
        r.setValue("DepremKalkani-iOS/1.0", forHTTPHeaderField: "User-Agent")
        let (d, resp) = try await URLSession.shared.data(for: r)
        if let h = resp as? HTTPURLResponse, !(200..<300).contains(h.statusCode) {
            throw URLError(.badServerResponse)
        }
        return d
    }

    static func df(_ format: String, _ tz: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: tz)
        f.dateFormat = format
        return f
    }

    static func num(_ v: Any?) -> Double? {
        if let s = v as? String { return Double(s) }
        if let n = v as? NSNumber { return n.doubleValue }
        return nil
    }

    // MARK: AFAD
    static func afad() async throws -> [Quake] {
        let f = df("yyyy-MM-dd'T'HH:mm:ss", "UTC")
        let now = Date()
        let start = f.string(from: now.addingTimeInterval(-3 * 86400))
        let end = f.string(from: now.addingTimeInterval(86400))
        let url = "https://deprem.afad.gov.tr/apiv2/event/filter?start=\(start)&end=\(end)&orderby=timedesc&limit=500&format=json"
        let data = try await get(url)
        guard let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        var out: [Quake] = []
        for o in arr {
            guard let ds = o["date"] as? String,
                  let t = f.date(from: String(ds.prefix(19))),
                  let mag = num(o["magnitude"]),
                  let lat = num(o["latitude"]),
                  let lon = num(o["longitude"]) else { continue }
            var prov = (o["province"] as? String) ?? ""
            if prov == "null" { prov = "" }
            var dist = (o["district"] as? String) ?? ""
            if dist == "null" { dist = "" }
            let loc = (o["location"] as? String) ?? ""
            let place = (!dist.isEmpty && !prov.isEmpty) ? "\(dist) (\(prov))" : loc
            let eid = (o["eventID"] as? String) ?? String(Int(t.timeIntervalSince1970))
            out.append(Quake(id: "AFAD-\(eid)", source: .afad, time: t, lat: lat, lon: lon,
                             depth: num(o["depth"]) ?? 0, mag: mag, place: place.isEmpty ? loc : place))
        }
        return out
    }

    // MARK: Kandilli
    static func kandilli() async throws -> [Quake] {
        let data: Data
        do { data = try await get("https://www.koeri.boun.edu.tr/scripts/lst0.asp") }
        catch { data = try await get("http://www.koeri.boun.edu.tr/scripts/lst0.asp") }
        let enc = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.isoLatin5.rawValue)))
        let text = String(data: data, encoding: enc) ?? String(data: data, encoding: .isoLatin1) ?? ""
        let f = df("yyyy.MM.dd HH:mm:ss", "Europe/Istanbul")
        var out: [Quake] = []
        for raw in text.components(separatedBy: .newlines) {
            let tk = raw.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard tk.count >= 9, tk[0].count == 10, tk[0].contains(".") else { continue }
            guard let t = f.date(from: "\(tk[0]) \(tk[1])"),
                  let lat = Double(tk[2]), let lon = Double(tk[3]), let depth = Double(tk[4]) else { continue }
            let md = Double(tk[5]), ml = Double(tk[6]), mw = Double(tk[7])
            guard let mag = [ml, mw, md].compactMap({ $0 }).first(where: { $0 > 0 }) else { continue }
            var rest = Array(tk[8...])
            if let i = rest.firstIndex(where: { $0.hasPrefix("REVIZE") || $0 == "İlksel" || $0 == "Ilksel" }) {
                rest = Array(rest[..<i])
            }
            let place = rest.joined(separator: " ").capitalized(with: Locale(identifier: "tr_TR"))
            out.append(Quake(id: "KDL-\(Int(t.timeIntervalSince1970))-\(tk[2])", source: .kandilli, time: t,
                             lat: lat, lon: lon, depth: depth, mag: mag, place: place))
        }
        return out
    }

    // MARK: EMSC
    static func emsc() async throws -> [Quake] {
        let data = try await get("https://www.seismicportal.eu/fdsnws/event/1/query?limit=300&format=json&orderby=time&minmag=2.5")
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let feats = root["features"] as? [[String: Any]] else { return [] }
        let iso1 = ISO8601DateFormatter()
        iso1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso2 = ISO8601DateFormatter()
        var out: [Quake] = []
        for ft in feats {
            guard let p = ft["properties"] as? [String: Any],
                  let ts = p["time"] as? String,
                  let t = iso1.date(from: ts) ?? iso2.date(from: ts),
                  let mag = num(p["mag"]), let lat = num(p["lat"]), let lon = num(p["lon"]) else { continue }
            let uid = (p["unid"] as? String) ?? String(Int(t.timeIntervalSince1970))
            let region = ((p["flynn_region"] as? String) ?? "").capitalized(with: Locale(identifier: "tr_TR"))
            out.append(Quake(id: "EMSC-\(uid)", source: .emsc, time: t, lat: lat, lon: lon,
                             depth: abs(num(p["depth"]) ?? 0), mag: mag, place: region))
        }
        return out
    }

    // MARK: USGS
    static func usgs() async throws -> [Quake] {
        let data = try await get("https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/2.5_week.geojson")
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let feats = root["features"] as? [[String: Any]] else { return [] }
        var out: [Quake] = []
        for ft in feats {
            guard let p = ft["properties"] as? [String: Any],
                  let g = ft["geometry"] as? [String: Any],
                  let c = g["coordinates"] as? [Any], c.count >= 2,
                  let ms = num(p["time"]), let mag = num(p["mag"]),
                  let lon = num(c[0]), let lat = num(c[1]) else { continue }
            let depth = c.count > 2 ? (num(c[2]) ?? 0) : 0
            let id = (ft["id"] as? String) ?? String(Int(ms))
            out.append(Quake(id: "USGS-\(id)", source: .usgs, time: Date(timeIntervalSince1970: ms / 1000),
                             lat: lat, lon: lon, depth: depth, mag: mag, place: (p["place"] as? String) ?? ""))
        }
        return out
    }

    /// Aynı depremi birden çok kaynak bildirirse yalnızca önceliği yüksek olanı tutar (AFAD > Kandilli > EMSC > USGS).
    static func merge(_ lists: [[Quake]]) -> [Quake] {
        let all = lists.flatMap { $0 }.sorted { $0.source.priority < $1.source.priority }
        var kept: [Quake] = []
        for q in all {
            let dup = kept.contains { abs($0.time.timeIntervalSince(q.time)) < 90 && distanceKm($0, q) < 60 }
            if !dup { kept.append(q) }
        }
        return kept.sorted { $0.time > $1.time }
    }
}
