import SwiftUI
import MapKit
import AVKit

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
    @EnvironmentObject var store: TripStore
    @AppStorage("who") private var who = "jerry"

    var body: some View {
        TabView {
            NavigationStack { PlanView(who: $who) }
                .tabItem { Label("Plan", systemImage: "calendar") }
            NavigationStack { PlacesView() }
                .tabItem { Label("Places", systemImage: "mappin.and.ellipse") }
            NavigationStack { PeopleView() }
                .tabItem { Label("People", systemImage: "person.2") }
            NavigationStack { WhereView() }
                .tabItem { Label("Where", systemImage: "location") }
            if !(store.data?.media ?? []).isEmpty {
                NavigationStack { MediaView() }
                    .tabItem { Label("Media", systemImage: "play.rectangle") }
            }
        }
    }
}

// MARK: - Links

enum Links {
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
                ForEach(t?.plan ?? []) { item in
                    let p = item.place.flatMap { places[$0] }
                    Group {
                        if let p { Link(destination: Links.maps(p, store.coordinate(for: p))) { PlanRow(item: item, chevron: true) } }
                        else { PlanRow(item: item, chevron: false) }
                    }
                }
            }
            if let b = t?.bucket, !b.isEmpty {
                Section("Bucket list") { ForEach(b, id: \.self) { Text($0) } }
            }
        }
        .navigationTitle("Trip")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Picker("", selection: $who) {
                    ForEach((store.data?.travelers ?? [:]).keys.sorted(), id: \.self) { k in
                        Text(store.data?.travelers[k]?.name ?? k).tag(k)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
            }
        }
        .refreshable { await store.refresh() }
    }
}

struct PlanRow: View {
    let item: PlanItem
    let chevron: Bool
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(item.date).font(.subheadline).foregroundStyle(.secondary).frame(width: 104, alignment: .leading).monospacedDigit()
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).foregroundStyle(.primary)
                if let s = item.sub, !s.isEmpty { Text(s).font(.subheadline).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
            if chevron { Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary) }
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
        let shown = places.filter { $0.city == (city.isEmpty ? cities.first ?? "" : city) }
        List {
            Section {
                Picker("City", selection: $city) { ForEach(cities, id: \.self) { Text($0).tag($0) } }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
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
        .onAppear { if city.isEmpty { city = cities.first ?? "" } }
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
            }
            Link(destination: Links.maps(place, store.coordinate(for: place))) { Image(systemName: "map") }
                .buttonStyle(CircleButton())
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
        List {
            Section("Contacts") { ForEach(store.data?.people ?? []) { PersonRow(person: $0) } }
            Section("Emergency") { ForEach(store.data?.emergency ?? []) { PersonRow(person: $0) } }
        }
        .navigationTitle("People")
        .refreshable { await store.refresh() }
    }
}

struct PersonRow: View {
    let person: Person
    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(person.name)
                let sub = [person.role, person.phoneLabel ?? person.phone, person.email].compactMap { $0 }.joined(separator: " · ")
                if !sub.isEmpty { Text(sub).font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled) }
            }
            Spacer(minLength: 0)
            if let p = person.phone, let u = URL(string: "tel:\(p)") { Link(destination: u) { Image(systemName: "phone.fill") }.buttonStyle(CircleButton()) }
            if let w = person.whatsapp, let u = URL(string: "https://wa.me/\(w)") { Link(destination: u) { Image(systemName: "message.fill") }.buttonStyle(CircleButton()) }
            else if let p = person.phone, p.count > 6, let u = URL(string: "sms:\(p)") { Link(destination: u) { Image(systemName: "message.fill") }.buttonStyle(CircleButton()) }
            if let e = person.email, let u = URL(string: "mailto:\(e)") { Link(destination: u) { Image(systemName: "envelope.fill") }.buttonStyle(CircleButton()) }
            if let ig = person.ig, let u = URL(string: "https://ig.me/m/\(ig)") { Link(destination: u) { Text("IG").font(.caption.weight(.bold)) }.buttonStyle(CircleButton()) }
            if let fb = person.fb, let u = URL(string: fb) { Link(destination: u) { Text("FB").font(.caption.weight(.bold)) }.buttonStyle(CircleButton()) }
            if let w = person.web, let u = URL(string: w) { Link(destination: u) { Image(systemName: "globe") }.buttonStyle(CircleButton()) }
        }
    }
}

// MARK: - Where

struct WhereView: View {
    @EnvironmentObject var store: TripStore
    var body: some View {
        let ts = (store.data?.travelers ?? [:]).sorted { $0.key < $1.key }
        List {
            ForEach(ts, id: \.key) { _, t in
                if let w = t.where, !w.isEmpty, let u = URL(string: w) {
                    Link(destination: u) {
                        HStack { Circle().fill(.green).frame(width: 9, height: 9); Text(t.name).foregroundStyle(.primary); Spacer(); Text("Live").foregroundStyle(.secondary) }
                    }
                } else {
                    HStack { Circle().fill(.quaternary).frame(width: 9, height: 9); Text(t.name); Spacer(); Text("Not shared").foregroundStyle(.secondary) }
                }
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
    }
}

// MARK: - Style

struct CircleButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.tint)
            .frame(width: 34, height: 34)
            .background(Circle().fill(Color(.tertiarySystemFill)))
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}
