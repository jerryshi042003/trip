import SwiftUI
import CoreLocation
import AVKit
import UIKit

@main
struct TripApp: App {
    @StateObject private var store = TripStore()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .task { await store.refresh() }
                .onChange(of: phase) { _, p in if p == .active { Task { await store.refresh() } } }
        }
    }
}

struct RootView: View {
    private enum TripSection: Hashable { case itinerary, plans, tom, places, people, media, japanShopMap }

    @EnvironmentObject var store: TripStore
    @State private var path: [TripSection] = []

    var body: some View {
        NavigationStack(path: $path) {
            ManilaToday()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu("More") {
                            Button("Itinerary") { path.append(.itinerary) }
                            Button("Trip plans") { path.append(.plans) }
                            Button("Tom’s trip") { path.append(.tom) }
                            Divider()
                            Button("Places") { path.append(.places) }
                            Button("Japan shop map") { path.append(.japanShopMap) }
                            Button("People") { path.append(.people) }
                            if !(store.data?.media ?? []).isEmpty {
                                Button("Media") { path.append(.media) }
                            }
                            Divider()
                            ShareLink("Share Trip", item: Links.tomPlan)
                        }
                        .accessibilityIdentifier("trip-menu")
                    }
                }
                .navigationDestination(for: TripSection.self) { section in
                    switch section {
                    case .itinerary: JerryItinerary()
                    case .plans: PlanView(who: "jerry")
                    case .tom: PlanView(who: "tom")
                    case .places: PlacesView()
                    case .japanShopMap: JapanShopMap()
                    case .people: PeopleView()
                    case .media: MediaView()
                    }
                }
        }
    }
}

// MARK: - Links

enum Links {
    static let tomPlan = URL(string: "https://jerryshi042003.github.io/trip/tom/")!
    static let editTomNotes = URL(string: "https://github.com/jerryshi042003/trip/edit/main/docs/tom-notes.txt")!
    static let editPlan = URL(string: "https://github.com/jerryshi042003/trip/edit/main/docs/trip.json")!
    static let googleMaps = URL(string: "https://www.google.com/maps/")!

    static func maps(_ p: Place, _ c: CLLocationCoordinate2D?) -> URL {
        let q = (p.ja ?? p.addr).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let c { return URL(string: "maps://?ll=\(c.latitude),\(c.longitude)&q=\(q)")! }
        return URL(string: "maps://?q=\(q)")!
    }
    static func google(_ p: Place) -> URL {
        let q = (p.ja ?? p.addr).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://www.google.com/maps/search/?api=1&query=\(q)")!
    }
}

// MARK: - Plan

struct ManilaToday: View {
    @EnvironmentObject private var store: TripStore

    var body: some View {
        let next = store.data?.travelers["jerry"]?.todos?
            .first { $0.region == "Manila" && $0.category == "Next" }?.items.first
        List {
            if let next {
                Section {
                    if let url = next.link {
                        TripSourceButton(url: url) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(next.title).font(.headline)
                                Text(next.detail).font(.body).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .foregroundStyle(.primary)
                    } else {
                        TripDashboardRow(item: next, places: [:])
                    }
                }
            }
        }
        .navigationTitle("Manila")
        .refreshable { await store.refresh() }
    }
}

struct JerryItinerary: View {
    @EnvironmentObject private var store: TripStore

    var body: some View {
        let trips = store.data?.travelers["jerry"]?.plan ?? []
        let places = Dictionary(uniqueKeysWithValues: (store.data?.places ?? []).map { ($0.id, $0) })
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(trips) { item in
                    if let place = item.place.flatMap({ places[$0] }) {
                        Link(destination: Links.maps(place, store.coordinate(for: place))) {
                            PlanRow(item: item, chevron: true)
                        }
                        .padding(.vertical, 12)
                    } else {
                        PlanRow(item: item, chevron: false)
                            .padding(.vertical, 12)
                    }
                    Divider()
                }
            }
            .padding(.horizontal)
        }
        .navigationTitle("Itinerary")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PlanView: View {
    @EnvironmentObject var store: TripStore
    let who: String

    var body: some View {
        let t = store.data?.travelers[who]
        let places = Dictionary(uniqueKeysWithValues: (store.data?.places ?? []).map { ($0.id, $0) })
        let dashboard = (t?.todos ?? []).filter { $0.region != nil }
        List {
            if dashboard.isEmpty {
                if let t {
                    let sections = t.todos ?? []
                    if who == "tom" {
                        itinerary(t.plan, places: places)
                        Section("Tom’s updates") {
                            ForEach(Array(store.tomNotes.enumerated()), id: \.offset) { _, note in Text(note) }
                            Link("Edit updates", destination: Links.editTomNotes)
                            Link("Edit full plan", destination: Links.editPlan)
                        }
                        taskSections(sections.filter { $0.title == "Before departure" })
                        Section {
                            NavigationLink("Trip notes & drafts") {
                                List {
                                    taskSections(sections.filter { $0.title != "Before departure" })
                                    calendar(t)
                                    bucket(t)
                                }
                                .navigationTitle("Trip notes & drafts")
                            }
                        }
                    } else {
                        taskSections(sections)
                        calendar(t)
                        itinerary(t.plan, places: places)
                        bucket(t)
                    }
                }
            } else {
                let regions = dashboard.compactMap(\.region).reduce(into: [String]()) { names, name in
                    if !names.contains(name) { names.append(name) }
                }
                ForEach(regions, id: \.self) { region in
                    NavigationLink(region) {
                        List {
                            ForEach(dashboard.filter { $0.region == region }) { section in
                                Section(section.title) {
                                    ForEach(section.items) { item in
                                        TripDashboardRow(item: item, places: places)
                                    }
                                }
                            }
                        }
                        .navigationTitle(region)
                    }
                    .accessibilityIdentifier("trip-region-\(region)")
                }
            }
        }
        .navigationTitle(who == "tom" ? "Tom’s trip" : "Trip plans")
        .refreshable { await store.refresh() }
    }

    private func taskSections(_ sections: [TripTaskSection]) -> some View {
        ForEach(sections) { section in
            Section(section.title) {
                ForEach(section.items) { item in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title)
                                Text(item.detail).font(.subheadline).foregroundStyle(.secondary)
                            }
                            if let link = item.link {
                                Spacer(minLength: 4)
                                TripSourceButton(url: link) { Image(systemName: "globe") }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel("Open link for \(item.title)")
                            }
                        }
                        if let draft = item.draft {
                            DisclosureGroup("Draft message") {
                                Text(draft).textSelection(.enabled)
                                Button("Copy draft") { UIPasteboard.general.string = draft }
                                    .buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }
        }
    }

    private func itinerary(_ plan: [PlanItem], places: [String: Place]) -> some View {
        Section {
            itineraryRows(plan, places: places)
        } header: {
            Text("Itinerary")
        }
    }

    private func itineraryRows(_ plan: [PlanItem], places: [String: Place], standalone: Bool = false) -> some View {
        ForEach(plan) { item in
            let p = item.place.flatMap { places[$0] }
            Group {
                if let p { Link(destination: Links.maps(p, store.coordinate(for: p))) { PlanRow(item: item, chevron: true) } }
                else { PlanRow(item: item, chevron: false) }
            }
            .padding(.vertical, standalone ? 12 : 0)
            if standalone { Divider() }
        }
    }

    @ViewBuilder private func calendar(_ traveler: Traveler) -> some View {
        if let data = store.data {
            Section("Calendar") { TripCalendar(data: data, traveler: traveler) }
        }
    }

    @ViewBuilder private func bucket(_ traveler: Traveler) -> some View {
        if let items = traveler.bucket, !items.isEmpty {
            Section("Bucket list") { ForEach(items, id: \.self) { Text($0) } }
        }
    }
}

struct TripDashboardRow: View {
    @EnvironmentObject var store: TripStore
    let item: TripTask
    let places: [String: Place]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let photos = item.photos, !photos.isEmpty {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(photos) { photo in
                            VStack(alignment: .leading, spacing: 4) {
                                AsyncImage(url: mediaURL(photo.url)) { image in
                                    image.resizable().scaledToFill()
                                } placeholder: {
                                    Rectangle().fill(.quaternary)
                                }
                                .frame(height: 142)
                                .frame(maxWidth: .infinity)
                                .clipped()
                                .clipShape(.rect(cornerRadius: 10))
                                .accessibilityHidden(true)
                                if !item.title.hasPrefix(photo.caption) {
                                    Text(photo.caption).font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                            .containerRelativeFrame(.horizontal) { width, _ in
                                photos.count == 1 ? width : width * 0.87
                            }
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .accessibilityLabel("\(item.title) photos")
            }
            if let icon = item.icon, let link = item.link {
                Link(destination: link) {
                    HStack(spacing: 12) {
                        AsyncImage(url: mediaURL(icon)) { image in
                            image.resizable()
                        } placeholder: {
                            Rectangle().fill(.quaternary)
                        }
                        .frame(width: 46, height: 46)
                        .clipShape(.rect(cornerRadius: 10))
                        .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(item.title) · App Store").font(.headline)
                            Text(item.detail).font(.callout)
                        }
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(.primary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
            } else {
                if let meta = item.meta {
                    Text(meta).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                }
                Text(item.title).font(.headline)
                Text(item.detail).font(.callout)
                let place = item.place.flatMap { places[$0] }
                if item.link != nil || place != nil {
                    HStack(spacing: 16) {
                        if let link = item.link {
                            TripSourceButton(url: link) { Text(item.linkLabel ?? "Details") }
                                .buttonStyle(.borderless)
                        }
                        if let place {
                            Link("Maps", destination: mapURL(place)).buttonStyle(.borderless)
                                .accessibilityLabel("Directions to \(place.name)")
                        }
                    }
                    .font(.callout)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func mediaURL(_ path: String) -> URL? {
        URL(string: path, relativeTo: TripStore.remote)
    }

    private func mapURL(_ place: Place) -> URL {
        if let id = item.from, let origin = places[id] {
            var url = URLComponents(string: "https://www.google.com/maps/dir/")!
            url.queryItems = [URLQueryItem(name: "api", value: "1"),
                              URLQueryItem(name: "origin", value: origin.addr),
                              URLQueryItem(name: "destination", value: "\(place.name), \(place.addr)"),
                              URLQueryItem(name: "travelmode", value: "two-wheeler")]
            if let result = url.url { return result }
        }
        return Links.maps(place, store.coordinate(for: place))
    }
}

struct PlanRow: View {
    @Environment(\.dynamicTypeSize) private var textSize
    let item: PlanItem
    let chevron: Bool
    var body: some View {
        let layout = textSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        layout {
            Text(item.date).font(.subheadline).foregroundStyle(.secondary)
                .frame(width: textSize.isAccessibilitySize ? nil : 96, alignment: .leading).monospacedDigit()
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).foregroundStyle(.primary)
                if let s = item.sub, !s.isEmpty { Text(s).font(.subheadline).foregroundStyle(.secondary) }
            }
            if !textSize.isAccessibilitySize {
                Spacer(minLength: 0)
                if chevron { Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary) }
            }
        }
    }
}

// MARK: - Places

struct PlacesView: View {
    @EnvironmentObject var store: TripStore

    var body: some View {
        List(store.data?.listedPlaces ?? []) { place in
            PlaceRow(place: place)
        }
        .navigationTitle("Places")
        .refreshable { await store.refresh() }
    }
}

struct PlaceRow: View {
    @EnvironmentObject var store: TripStore
    let place: Place
    var body: some View {
        HStack(spacing: 12) {
            if let photo = place.photo, let url = URL(string: photo) {
                AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { Color.secondary.opacity(0.15) }
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(place.name)
                Text(place.addr).font(.subheadline).foregroundStyle(.secondary)
                if let ja = place.ja { Text(ja).font(.subheadline).textSelection(.enabled) }
            }
            Spacer(minLength: 0)
            if let ja = place.ja {
                Button { UIPasteboard.general.string = ja } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(CircleButton())
                    .accessibilityLabel("Copy Japanese address")
            }
            Link(destination: Links.maps(place, store.coordinate(for: place))) { Image(systemName: "map") }
                .buttonStyle(CircleButton())
                .accessibilityLabel("Open in Apple Maps")
        }
        .contextMenu {
            Link("Open in Google Maps", destination: Links.google(place))
            Button("Copy address") { UIPasteboard.general.string = place.ja ?? place.addr }
        }
    }
}

// MARK: - People

struct PeopleView: View {
    @EnvironmentObject var store: TripStore
    var body: some View {
        let people = store.data?.listedPeople ?? []
        List {
            if !people.isEmpty {
                Section("Trip contacts") { ForEach(people) { PersonRow(person: $0) } }
            }
            Section("Emergency") { ForEach(store.data?.emergency ?? []) { PersonRow(person: $0) } }
        }
        .navigationTitle("People")
        .refreshable { await store.refresh() }
    }
}

struct PersonRow: View {
    @Environment(\.dynamicTypeSize) private var textSize
    let person: Person
    var body: some View {
        let layout = textSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(spacing: 8))
        layout {
            VStack(alignment: .leading, spacing: 2) {
                Text(person.name)
                let sub = [person.role, person.phoneLabel ?? person.phone, person.email].compactMap { $0 }.joined(separator: " · ")
                if !sub.isEmpty { Text(sub).font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled) }
            }
            if !textSize.isAccessibilitySize { Spacer(minLength: 0) }
            HStack(spacing: 2) {
                if let p = person.phone, let u = URL(string: "tel:\(p)") {
                    Link(destination: u) { Image(systemName: "phone.fill") }.accessibilityLabel("Call")
                }
                if let w = person.whatsapp, let u = URL(string: "https://wa.me/\(w)") {
                    Link(destination: u) { Image(systemName: "message.fill") }.accessibilityLabel("WhatsApp")
                }
                if let e = person.email, let u = URL(string: "mailto:\(e)") {
                    Link(destination: u) { Image(systemName: "envelope.fill") }.accessibilityLabel("Email")
                }
                if let ig = person.ig, let u = URL(string: "https://ig.me/m/\(ig)") {
                    Link(destination: u) { Text("IG").font(.caption.weight(.bold)) }.accessibilityLabel("Instagram")
                }
                if let fb = person.fb, let u = URL(string: fb) {
                    Link(destination: u) { Text("FB").font(.caption.weight(.bold)) }.accessibilityLabel("Facebook")
                }
                if let w = person.web, let u = URL(string: w) {
                    Link(destination: u) { Image(systemName: "globe") }.accessibilityLabel("Website")
                }
            }
            .buttonStyle(CircleButton())
        }
    }
}

private struct TripSourceButton<Label: View>: View {
    let url: URL
    @ViewBuilder let label: () -> Label

    var body: some View {
        if InAppVideo(url: url) != nil {
            InAppVideoButton(url: url, label: label)
        } else {
            Link(destination: url, label: label)
        }
    }
}

// MARK: - Media

struct MediaView: View {
    @EnvironmentObject var store: TripStore
    var body: some View {
        List(store.data?.media ?? []) { m in
            let local = store.localMedia[m.url]
            NavigationLink {
                MediaDetail(media: m, url: local ?? URL(string: m.url)!)
            } label: {
                HStack {
                    Image(systemName: m.kind == "image" ? "photo" : "play.rectangle.fill").foregroundStyle(.tint)
                    Text(m.title)
                    Spacer()
                    if local == nil { ProgressView().controlSize(.small) }
                }
            }
        }
        .navigationTitle("Media")
        .refreshable { await store.refresh() }
    }
}

struct MediaDetail: View {
    let media: Media
    let url: URL
    var body: some View {
        Group {
            if media.kind == "image" {
                if let d = try? Data(contentsOf: url), let img = UIImage(data: d) {
                    Image(uiImage: img).resizable().scaledToFit()
                } else { AsyncImage(url: url) { $0.resizable().scaledToFit() } placeholder: { ProgressView() } }
            } else {
                VideoPlayer(player: AVPlayer(url: url)).ignoresSafeArea(edges: .bottom)
            }
        }
        .navigationTitle(media.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }
}

// MARK: - Style

struct CircleButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.tint)
            .frame(width: 44, height: 44)
            .background(Circle().fill(Color(.tertiarySystemFill)).frame(width: 34, height: 34))
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}
