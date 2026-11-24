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
    let region: String?
    let category: String?
}

struct TripTask: Codable, Identifiable {
    var id: String { title }
    let title: String
    let detail: String
    let link: URL?
    let draft: String?
    let linkLabel: String?
    let meta: String?
    let place: String?
    let from: String?
    let icon: String?
    let photos: [TripPhoto]?
}

struct TripPhoto: Codable, Identifiable {
    var id: String { url }
    let url: String
    let caption: String
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
    var photo: String?
    var been: Bool?
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
    private static let notesRemote = remote.deletingLastPathComponent().appendingPathComponent("tom-notes.txt")

    @Published var data: TripData?
    @Published var lastSync: Date?
    @Published var coords: [String: CLLocationCoordinate2D] = [:]
    @Published var localMedia: [String: URL] = [:]
    @Published private(set) var tomNotes: [String] = []
    private var refreshTask: Task<Void, Never>?

    private let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    private var cacheURL: URL { docs.appendingPathComponent("trip.json") }
    private var notesURL: URL { docs.appendingPathComponent("tom-notes.txt") }
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
        if let notes = try? String(contentsOf: notesURL, encoding: .utf8) { tomNotes = Self.notes(in: notes) }
        indexLocalMedia()
    }

    func refresh() async {
        if let refreshTask {
            await refreshTask.value
            return
        }
        let task = Task { await refreshFeed() }
        refreshTask = task
        defer { refreshTask = nil }
        await task.value
    }

    private func refreshFeed() async {
        async let notes: Void = refreshTomNotes()
        var req = URLRequest(url: Self.remote)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 15
        let result = try? await URLSession.shared.data(for: req)
        guard let (d, resp) = result,
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let t = try? JSONDecoder().decode(TripData.self, from: d) else { await notes; return }
        try? d.write(to: cacheURL, options: .atomic)
        data = t
        lastSync = Date()
        await notes
        await geocodeMissing()
        await downloadMedia()
    }

    private func refreshTomNotes() async {
        let request = URLRequest(url: Self.notesRemote, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let text = String(data: data, encoding: .utf8) else { return }
        try? data.write(to: notesURL, options: .atomic)
        tomNotes = Self.notes(in: text)
    }

    private static func notes(in text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
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


// Lenient decoding: one malformed item in trip.json is skipped instead of making the
// whole feed fail to decode (which would leave the app stuck on its last cached copy).

private struct SkipItem: Decodable { init(from decoder: Decoder) throws {} }

extension KeyedDecodingContainer {
    /// Decodes an array, dropping elements that fail. Missing or non-array values give [].
    func lossyArray<T: Decodable>(_ type: T.Type, forKey key: Key) -> [T] {
        guard var c = try? nestedUnkeyedContainer(forKey: key) else { return [] }
        var out: [T] = []
        while !c.isAtEnd {
            if let v = try? c.decode(T.self) { out.append(v) } else { _ = try? c.decode(SkipItem.self) }
        }
        return out
    }
    func optionalLossyArray<T: Decodable>(_ type: T.Type, forKey key: Key) -> [T]? {
        contains(key) ? lossyArray(type, forKey: key) : nil
    }
    func string(_ key: Key, default value: String = "") -> String {
        (try? decodeIfPresent(String.self, forKey: key)) ?? value
    }
    func optionalString(_ key: Key) -> String? {
        try? decodeIfPresent(String.self, forKey: key)
    }
}

extension TripData {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        updated = c.optionalString(.updated)
        var t: [String: Traveler] = [:]
        if let raw = try? c.nestedContainer(keyedBy: AnyKey.self, forKey: .travelers) {
            for k in raw.allKeys { if let v = try? raw.decode(Traveler.self, forKey: k) { t[k.stringValue] = v } }
        }
        travelers = t
        places = c.lossyArray(Place.self, forKey: .places)
        people = c.lossyArray(Person.self, forKey: .people)
        emergency = c.lossyArray(Person.self, forKey: .emergency)
        media = c.optionalLossyArray(Media.self, forKey: .media)
    }
}

struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

extension Traveler {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = c.string(.name)
        plan = c.lossyArray(PlanItem.self, forKey: .plan)
        todos = c.optionalLossyArray(TripTaskSection.self, forKey: .todos)
        bucket = c.optionalLossyArray(String.self, forKey: .bucket)
        `where` = c.optionalString(.where)
    }
}

extension TripTaskSection {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = c.string(.title)
        items = c.lossyArray(TripTask.self, forKey: .items)
        region = c.optionalString(.region)
        category = c.optionalString(.category)
    }
}

extension TripTask {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decode(String.self, forKey: .title)
        detail = c.string(.detail)
        link = c.optionalString(.link).flatMap { URL(string: $0.trimmingCharacters(in: .whitespaces)) }
        draft = c.optionalString(.draft)
        linkLabel = c.optionalString(.linkLabel)
        meta = c.optionalString(.meta)
        place = c.optionalString(.place)
        from = c.optionalString(.from)
        icon = c.optionalString(.icon)
        photos = c.optionalLossyArray(TripPhoto.self, forKey: .photos)
    }
}

extension PlanItem {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = c.string(.date)
        title = try c.decode(String.self, forKey: .title)
        sub = c.optionalString(.sub)
        place = c.optionalString(.place)
    }
}

extension Place {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        city = c.string(.city)
        name = c.string(.name, default: id)
        addr = c.string(.addr)
        ja = c.optionalString(.ja)
        lat = try? c.decodeIfPresent(Double.self, forKey: .lat)
        lon = try? c.decodeIfPresent(Double.self, forKey: .lon)
        photo = c.optionalString(.photo)
        been = try? c.decodeIfPresent(Bool.self, forKey: .been)
    }
}
