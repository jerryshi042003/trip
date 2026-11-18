import Foundation
import CoreLocation

struct TripData: Codable {
    var updated: String?
    var travelers: [String: Traveler]
    var places: [Place]
    var people: [Person]
    var emergency: [Person]
    var media: [Media]?
}

struct Traveler: Codable {
    var name: String
    var plan: [PlanItem]
    var todos: [TripTaskSection]?
    var bucket: [String]?
    var `where`: String?
}

struct TripTaskSection: Codable, Identifiable {
    var id: String { title }
    let title: String
    let items: [TripTask]
}

struct TripTask: Codable, Identifiable {
    var id: String { title }
    let title: String
    let detail: String
    let link: URL?
    let draft: String?
}

struct PlanItem: Codable, Identifiable {
    var id: String { date + title }
    var date: String
    var title: String
    var sub: String?
    var place: String?
}

struct Place: Codable, Identifiable {
    var id: String
    var city: String
    var name: String
    var addr: String
    var ja: String?
    var lat: Double?
    var lon: Double?
}

struct Person: Codable, Identifiable {
    var id: String { name }
    var contactGroup: String {
        guard let group, !group.isEmpty else { return "Contacts" }
        return group
    }
    var name: String
    var role: String?
    var group: String?
    var phone: String?
    var phoneLabel: String?
    var whatsapp: String?
    var email: String?
    var ig: String?
    var fb: String?
    var web: String?
}

struct Media: Codable, Identifiable {
    var id: String { url }
    var title: String
    var url: String
    var kind: String?   // "video" or "image"
    var who: String?
}

@MainActor
final class TripStore: ObservableObject {
    static let remote = URL(string: "https://jerryshi042003.github.io/trip/trip.json")!

    @Published var data: TripData?
    @Published var lastSync: Date?
    @Published var coords: [String: CLLocationCoordinate2D] = [:]
    @Published var localMedia: [String: URL] = [:]

    private let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    private var cacheURL: URL { docs.appendingPathComponent("trip.json") }
    private var coordsURL: URL { docs.appendingPathComponent("coords.json") }
    private var mediaDir: URL { docs.appendingPathComponent("media", isDirectory: true) }

    init() {
        try? FileManager.default.createDirectory(at: mediaDir, withIntermediateDirectories: true)
        // Offline first: last synced copy, else the copy shipped with the app.
        if let d = try? Data(contentsOf: cacheURL), let t = try? JSONDecoder().decode(TripData.self, from: d) {
            data = t
            lastSync = (try? FileManager.default.attributesOfItem(atPath: cacheURL.path)[.modificationDate]) as? Date
        } else if let u = Bundle.main.url(forResource: "trip", withExtension: "json"),
                  let d = try? Data(contentsOf: u), let t = try? JSONDecoder().decode(TripData.self, from: d) {
            data = t
        }
        if let d = try? Data(contentsOf: coordsURL), let c = try? JSONDecoder().decode([String: [Double]].self, from: d) {
            coords = c.compactMapValues { $0.count == 2 ? CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1]) : nil }
        }
        indexLocalMedia()
    }

    func refresh() async {
        var req = URLRequest(url: Self.remote)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 15
        guard let (d, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let t = try? JSONDecoder().decode(TripData.self, from: d) else { return }
        try? d.write(to: cacheURL, options: .atomic)
        data = t
        lastSync = Date()
        await geocodeMissing()
        await downloadMedia()
    }

    // MARK: Places

    func coordinate(for p: Place) -> CLLocationCoordinate2D? {
        if let lat = p.lat, let lon = p.lon { return CLLocationCoordinate2D(latitude: lat, longitude: lon) }
        return coords[p.id]
    }

    private func geocodeMissing() async {
        guard let places = data?.places else { return }
        let geocoder = CLGeocoder()
        var changed = false
        for p in places where p.lat == nil && coords[p.id] == nil {
            if let mark = try? await geocoder.geocodeAddressString(p.addr).first, let loc = mark.location {
                coords[p.id] = loc.coordinate
                changed = true
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        if changed {
            let raw = coords.mapValues { [$0.latitude, $0.longitude] }
            if let d = try? JSONEncoder().encode(raw) { try? d.write(to: coordsURL, options: .atomic) }
        }
    }

    // MARK: Media (downloaded once, kept on the phone)

    private func fileName(for url: String) -> String {
        let ext = URL(string: url)?.pathExtension ?? "bin"
        let safe = url.unicodeScalars.reduce(UInt64(5381)) { ($0 << 5) &+ $0 &+ UInt64($1.value) }
        return "\(safe).\(ext.isEmpty ? "bin" : ext)"
    }

    private func indexLocalMedia() {
        guard let items = data?.media else { return }
        for m in items {
            let f = mediaDir.appendingPathComponent(fileName(for: m.url))
            if FileManager.default.fileExists(atPath: f.path) { localMedia[m.url] = f }
        }
    }

    private func downloadMedia() async {
        guard let items = data?.media else { return }
        for m in items where localMedia[m.url] == nil {
            guard let u = URL(string: m.url) else { continue }
            if let (tmp, resp) = try? await URLSession.shared.download(from: u), (resp as? HTTPURLResponse)?.statusCode == 200 {
                let dest = mediaDir.appendingPathComponent(fileName(for: m.url))
                try? FileManager.default.removeItem(at: dest)
                if (try? FileManager.default.moveItem(at: tmp, to: dest)) != nil { localMedia[m.url] = dest }
            }
        }
    }
}
