import SwiftUI
import MapKit
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
    private enum TripTab: String, CaseIterable {
        case plan = "Plan", places = "Places", people = "People", `where` = "Where", media = "Media"

        var icon: String {
            switch self {
            case .plan: "calendar"
            case .places: "mappin.and.ellipse"
            case .people: "person.2"
            case .where: "location"
            case .media: "play.rectangle"
            }
        }
    }

    @EnvironmentObject var store: TripStore
    @AppStorage("who") private var who = "jerry"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var tab: TripTab = .plan

    private var showsMedia: Bool { !(store.data?.media ?? []).isEmpty }

    var body: some View {
        TabView(selection: $tab) {
            Tab("Plan", systemImage: TripTab.plan.icon, value: .plan) {
                NavigationStack { PlanView(who: $who).toolbar(.hidden, for: .tabBar) }
            }
            Tab("Places", systemImage: TripTab.places.icon, value: .places) {
                NavigationStack { PlacesView().toolbar(.hidden, for: .tabBar) }
            }
            Tab("People", systemImage: TripTab.people.icon, value: .people) {
                NavigationStack { PeopleView().toolbar(.hidden, for: .tabBar) }
            }
            Tab("Where", systemImage: TripTab.where.icon, value: .where) {
                NavigationStack { WhereView().toolbar(.hidden, for: .tabBar) }
            }
            if showsMedia {
                Tab("Media", systemImage: TripTab.media.icon, value: .media) {
                    NavigationStack { MediaView().toolbar(.hidden, for: .tabBar) }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { sectionBar }
        .onChange(of: showsMedia) { _, visible in
            if !visible && tab == .media { tab = .plan }
        }
    }

    private var sectionBar: some View {
        HStack(spacing: 0) {
            ForEach(TripTab.allCases.filter { $0 != .media || showsMedia }, id: \.self) { section in
                let selected = section == tab
                Button {
                    tab = section
                } label: {
                    VStack(spacing: 4) {
                        Capsule()
                            .fill(selected ? Color.accentColor : Color.clear)
                            .frame(width: 16, height: 2)
                        Image(systemName: section.icon).font(.system(size: 18, weight: .medium))
                        Text(section.rawValue).font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .contentShape(Rectangle())
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: selected)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(section.rawValue)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("section-\(section.rawValue)")
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .background {
            Group {
                if reduceTransparency { Color(.systemBackground) }
                else { Rectangle().fill(.regularMaterial) }
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .top) { Divider() }
    }
}

// MARK: - Links

enum Links {
    static let tomPlan = URL(string: "https://jerryshi042003.github.io/trip/?who=tom")!
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

struct PlanView: View {
    @EnvironmentObject var store: TripStore
    @Binding var who: String

    var body: some View {
        let t = store.data?.travelers[who]
        let places = Dictionary(uniqueKeysWithValues: (store.data?.places ?? []).map { ($0.id, $0) })
        List {
            Section {
                HStack(spacing: 8) {
                    Picker("Traveler", selection: $who) {
                        ForEach((store.data?.travelers ?? [:]).keys.sorted(), id: \.self) { key in
                            Text(store.data?.travelers[key]?.name ?? key).tag(key)
                        }
                    }
                    .pickerStyle(.segmented)
                    ShareLink(item: Links.tomPlan) {
                        Image(systemName: "square.and.arrow.up")
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Share Tom’s Trip link")
                    .accessibilityIdentifier("share-tom-trip")
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
            }
            if who == "tom" {
                Section("Tom’s updates") {
                    ForEach(Array(store.tomNotes.enumerated()), id: \.offset) { _, note in Text(note) }
                    Link("Edit updates", destination: Links.editTomNotes)
                    Link("Edit full plan", destination: Links.editPlan)
                }
            }
            ForEach(t?.todos ?? []) { section in
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
                                    Link(destination: link) { Image(systemName: "globe") }
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
            if let d = store.data, let t {
                Section("Calendar") { TripCalendar(data: d, traveler: t) }
            }
            Section {
                ForEach(t?.plan ?? []) { item in
                    let p = item.place.flatMap { places[$0] }
                    Group {
                        if let p { Link(destination: Links.maps(p, store.coordinate(for: p))) { PlanRow(item: item, chevron: true) } }
                        else { PlanRow(item: item, chevron: false) }
                    }
                }
            } header: {
                Text("Itinerary")
            }
            if let b = t?.bucket, !b.isEmpty {
                Section("Bucket list") { ForEach(b, id: \.self) { Text($0) } }
            }
        }
        .navigationTitle("Trip")
        .refreshable { await store.refresh() }
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
    @State private var city = ""

    var body: some View {
        let places = store.data?.places ?? []
        let cities = places.map(\.city).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        let selection = Binding(get: { cities.contains(city) ? city : cities.first ?? "" }, set: { city = $0 })
        let shown = places.filter { $0.city == selection.wrappedValue }
        List {
            if !cities.isEmpty {
                Section {
                    Picker("City", selection: selection) { ForEach(cities, id: \.self) { Text($0).tag($0) } }
                        .pickerStyle(.segmented)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                }
            }
            let pins = shown.compactMap { p in store.coordinate(for: p).map { (p, $0) } }
            if !pins.isEmpty {
                Section {
                    Map {
                        ForEach(pins, id: \.0.id) { p, c in Marker(p.name, coordinate: c) }
                    }
                    .frame(height: 220)
                    .listRowInsets(EdgeInsets())
                }
            }
            Section {
                ForEach(shown) { p in PlaceRow(place: p) }
            }
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
        let people = store.data?.people ?? []
        let grouped = Dictionary(grouping: people, by: \.contactGroup)
        var seen = Set<String>()
        let groupOrder = people.map(\.contactGroup).filter { seen.insert($0).inserted }
        List {
            ForEach(groupOrder, id: \.self) { name in
                Section(name) { ForEach(grouped[name] ?? []) { PersonRow(person: $0) } }
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
                } else if let p = person.phone, p.count > 6, let u = URL(string: "sms:\(p)") {
                    Link(destination: u) { Image(systemName: "message.fill") }.accessibilityLabel("Text message")
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

// MARK: - Where

struct WhereView: View {
    @EnvironmentObject var store: TripStore
    var body: some View {
        List {
            Section("Share with each other") {
                Text("In Google Maps, tap your profile picture, then Location sharing → New share.")
                Text("Choose Until you turn this off and select the other person’s Gmail address. Each person does this once.")
                Link("Open Google Maps", destination: Links.googleMaps)
            }
            if let s = store.lastSync {
                Section { Text("Synced \(s.formatted(date: .abbreviated, time: .shortened))").font(.footnote).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("Where")
        .refreshable { await store.refresh() }
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
