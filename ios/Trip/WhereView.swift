import MapKit
import SwiftUI

private struct LivePoint: Decodable {
    let lat: Double
    let lon: Double
    let tst: TimeInterval
    let batt: Int?
    let test: Bool?

    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
    var minutesOld: Int { max(0, Int(Date().timeIntervalSince1970 - tst) / 60) }
    var isVisible: Bool { CLLocationCoordinate2DIsValid(coordinate) && minutesOld < (test == true ? 10 : 1_440) }
    var summary: String {
        let label = test == true ? "Test location" : minutesOld >= 15 ? "Last seen" : "Updated"
        let age = minutesOld < 1 ? "just now" : "\(minutesOld) min ago"
        return [label, age, batt.map { "\($0)% battery" }].compactMap { $0 }.joined(separator: " · ")
    }
}

private struct LocationFeed: Decodable {
    let locations: [String: LivePoint?]
}

struct WhereView: View {
    private struct Pin: Identifiable {
        let id: String
        let name: String
        let point: LivePoint
    }

    private static let endpoint = URL(string: "https://jerry-trip.vercel.app/api/location")!
    private static let familyLink = URL(string: "https://jerryshi042003.github.io/trip/?view=where")!
    private let travelers = ["jerry", "tom"]
    let isVisible: Bool

    @EnvironmentObject private var store: TripStore
    @Environment(\.scenePhase) private var phase
    @State private var locations: [String: LivePoint?] = [:]
    @State private var loading = true
    @State private var online = false
    @State private var camera: MapCameraPosition = .region(.init(
        center: .init(latitude: 23, longitude: 130),
        span: .init(latitudeDelta: 35, longitudeDelta: 40)
    ))

    private var pins: [Pin] {
        travelers.compactMap { id in
            guard let point = locations[id] ?? nil, point.isVisible else { return nil }
            return Pin(id: id, name: id.capitalized, point: point)
        }
    }

    var body: some View {
        List {
            Section {
                Map(position: $camera) {
                    ForEach(pins) { pin in
                        Marker(pin.name, systemImage: "person.fill", coordinate: pin.point.coordinate)
                            .tint(pin.point.minutesOld >= 15 ? .gray : .accentColor)
                    }
                }
                .frame(height: 330)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .accessibilityIdentifier("live-location-map")

                if loading {
                    Text("Checking locations…").foregroundStyle(.secondary)
                } else if !online {
                    Text("Live refresh unavailable").foregroundStyle(.secondary)
                } else if pins.isEmpty {
                    Text("Pins appear when Jerry or Tom starts sharing.").foregroundStyle(.secondary)
                }
            }
            Section {
                ForEach(travelers, id: \.self) { id in
                    let pin = pins.first { $0.id == id }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(id.capitalized)
                                if let pin { Text(pin.point.summary).font(.subheadline).foregroundStyle(.secondary) }
                                else if !loading { Text(online ? "Not shared yet" : "Location unavailable").font(.subheadline).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            if let pin {
                                let url = URL(string: "https://maps.apple.com/?ll=\(pin.point.lat),\(pin.point.lon)&q=\(pin.name)")!
                                Link(destination: url) {
                                    Label("Open \(pin.name) in Apple Maps", systemImage: "arrow.up.right.square").labelStyle(.iconOnly)
                                        .frame(minWidth: 44, minHeight: 44)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        if let url = Self.googleShare(store.data?.travelers[id]?.where) {
                            Link("Google Maps share", destination: url).frame(minHeight: 44)
                        }
                    }
                    .accessibilityIdentifier("live-location-\(id)")
                }
            }
        }
        .navigationTitle("Where")
        .toolbar { ShareLink(item: Self.familyLink).accessibilityLabel("Share family map") }
        .onChange(of: pins.map(\.id)) { _, ids in
            if !ids.isEmpty { framePins() }
        }
        .task(id: isVisible && phase == .active) {
            guard isVisible, phase == .active else { return }
            while !Task.isCancelled {
                await refresh()
                do { try await Task.sleep(for: .seconds(60)) }
                catch { break }
            }
        }
        .refreshable { await refresh() }
    }

    private func framePins() {
        let rect = pins.reduce(MKMapRect.null) { bounds, pin in
            let center = MKMapPoint(pin.point.coordinate)
            return bounds.union(MKMapRect(x: center.x - 2_000, y: center.y - 2_000, width: 4_000, height: 4_000))
        }
        guard !rect.isNull else { return }
        let padded = rect.insetBy(dx: -rect.width * 0.26, dy: -rect.height * 0.3)
        camera = .region(MKCoordinateRegion(padded))
    }

    private func refresh() async {
        var request = URLRequest(url: Self.endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard !Task.isCancelled else { return }
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            locations = try JSONDecoder().decode(LocationFeed.self, from: data).locations
            online = true
        } catch {
            guard !Task.isCancelled else { return }
            online = false
        }
        loading = false
    }

    private static func googleShare(_ value: String?) -> URL? {
        guard let value, let url = URL(string: value), url.scheme == "https",
              let host = url.host()?.lowercased() else { return nil }
        let fullMapsURL = ["google.com", "www.google.com"].contains(host) && url.path.hasPrefix("/maps")
        return host == "maps.app.goo.gl" || host == "maps.google.com" || fullMapsURL ? url : nil
    }
}
