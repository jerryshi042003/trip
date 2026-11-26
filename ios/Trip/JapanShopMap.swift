import MapKit
import SwiftUI

struct JapanShopMap: View {
    @EnvironmentObject private var store: TripStore
    @State private var selectedID = Shop.stops[0].id
    @State private var hoveredID: String?
    @State private var pendingDirections: MKDirections?
    @State private var estimates: [String: MKDirections.ETAResponse] = [:]

    private static let origin = CLLocationCoordinate2D(latitude: 35.68126, longitude: 139.76671)
    private static let region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 35.624, longitude: 139.843),
        span: MKCoordinateSpan(latitudeDelta: 0.29, longitudeDelta: 0.43)
    )

    private var products: [TripTask] {
        store.data?.travelers["jerry"]?.todos?
            .first { $0.region == "Japan" && $0.title == "Tabi socks" }?.items ?? []
    }

    var body: some View {
        let shops = Shop.stops.filter { shop in products.contains { $0.place == shop.id } }
        let activeID = hoveredID ?? selectedID
        let active = shops.first { $0.id == activeID } ?? shops.first

        Group {
            if let active {
                VStack(spacing: 0) {
                    Map(initialPosition: .region(Self.region), interactionModes: [.pan, .zoom]) {
                        ForEach(shops) { shop in
                            Annotation(shop.label, coordinate: shop.coordinate, anchor: .bottom) {
                                pin(shop, active: active.id == shop.id)
                            }
                            .annotationTitles(.hidden)
                        }
                    }
                    .mapStyle(.standard(pointsOfInterest: .excludingAll))
                    .accessibilityIdentifier("japan-shop-map")
                    shopDetails(active)
                }
                .task(id: active.id) { await loadEstimate(for: active) }
            } else {
                ContentUnavailableView("Shop details unavailable", systemImage: "map")
            }
        }
        .onDisappear { pendingDirections?.cancel() }
        .navigationTitle("Japan shop map")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func pin(_ shop: Shop, active: Bool) -> some View {
        Button {
            selectedID = shop.id
        } label: {
            Text(shop.label)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(active ? Color.accentColor : Color(uiColor: .systemBackground), in: .rect(cornerRadius: 8))
                .foregroundStyle(active ? Color.white : Color.primary)
                .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("shop-\(shop.id)")
        .accessibilityAddTraits(active ? .isSelected : [])
        .onHover { hovering in
            if hovering {
                hoveredID = shop.id
            } else if hoveredID == shop.id {
                hoveredID = nil
            }
        }
    }

    private func shopDetails(_ shop: Shop) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(shop.name)
                    .font(.headline)
                    .accessibilityIdentifier("shop-detail-name")
                Spacer(minLength: 8)
                Button("Directions", systemImage: "arrow.turn.up.right") {
                    let options = [MKLaunchOptionsDirectionsModeKey: shop.walking
                                   ? MKLaunchOptionsDirectionsModeWalking : MKLaunchOptionsDirectionsModeTransit]
                    MKMapItem.openMaps(with: [
                        mapItem("Tokyo Station", coordinate: Self.origin),
                        mapItem(shop.name, coordinate: shop.coordinate)
                    ], launchOptions: options)
                }
                .labelStyle(.iconOnly)
                .font(.title3)
                .accessibilityLabel("Directions in Apple Maps to \(shop.name)")
            }

            Text(distanceText(for: shop))
                .font(.subheadline)
                .accessibilityIdentifier("shop-detail-distance")

            Divider()

            ForEach(products.filter { $0.place == shop.id }) { product in
                HStack(alignment: .firstTextBaseline) {
                    Text(product.title)
                    Spacer(minLength: 10)
                    if let price = product.meta?.split(separator: " · ").first {
                        Text(String(price))
                            .monospacedDigit()
                            .fixedSize(horizontal: true, vertical: false)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.subheadline)
            }

            Text(shop.stockNote)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background)
    }

    private func distanceText(for shop: Shop) -> String {
        if let estimate = estimates[shop.id] {
            let minutes = max(1, Int((estimate.expectedTravelTime / 60).rounded()))
            let method = shop.walking ? "walk" : "transit"
            return "\(minutes) min \(method) · \(formattedDistance(estimate.distance)) from Tokyo Station"
        }
        let origin = CLLocation(latitude: Self.origin.latitude, longitude: Self.origin.longitude)
        let destination = CLLocation(latitude: shop.coordinate.latitude, longitude: shop.coordinate.longitude)
        return "\(formattedDistance(origin.distance(from: destination))) straight-line from Tokyo Station"
    }

    private func formattedDistance(_ meters: CLLocationDistance) -> String {
        if meters < 1000 { return "\(Int((meters / 10).rounded()) * 10) m" }
        return "\((meters / 1000).formatted(.number.precision(.fractionLength(1)))) km"
    }

    private func loadEstimate(for shop: Shop) async {
        pendingDirections?.cancel()
        guard estimates[shop.id] == nil else { return }
        let request = MKDirections.Request()
        request.source = mapItem("Tokyo Station", coordinate: Self.origin)
        request.destination = mapItem(shop.name, coordinate: shop.coordinate)
        request.transportType = shop.walking ? .walking : .transit
        let directions = MKDirections(request: request)
        pendingDirections = directions
        let result = try? await directions.calculateETA()
        if pendingDirections === directions { pendingDirections = nil }
        guard !Task.isCancelled, let result, result.distance > 0 else { return }
        estimates[shop.id] = result
    }

    private func mapItem(_ name: String, coordinate: CLLocationCoordinate2D) -> MKMapItem {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        item.name = name
        return item
    }
}

private struct Shop: Identifiable {
    let id: String
    let label: String
    let name: String
    let coordinate: CLLocationCoordinate2D
    var walking = false
    let stockNote: String

    static let stops = [
        Shop(id: "windsor-shinjuku", label: "Windsor\nShinjuku", name: "Windsor Shinjuku",
             coordinate: .init(latitude: 35.6933456, longitude: 139.6984301),
             stockNote: "Oedo Line Exit D4 · prices from Windsor’s listings"),
        Shop(id: "tabio-daimaru-tokyo", label: "Tabio\nDaimaru", name: "Tabio MEN · Daimaru Tokyo",
             coordinate: .init(latitude: 35.68126, longitude: 139.76882), walking: true,
             stockNote: "Daimaru 7F · check branch stock"),
        Shop(id: "lafino-funabashi", label: "LAFINO\nFunabashi", name: "LAFINO Funabashi",
             coordinate: .init(latitude: 35.7066389, longitude: 139.9882889),
             stockNote: "White pair by order · call before going"),
        Shop(id: "xebio-kawasaki", label: "Xebio\nKawasaki", name: "Xebio Kawasaki Le Front",
             coordinate: .init(latitude: 35.5293483, longitude: 139.6967751),
             stockNote: "Le Front 7F–8F · check this model and size")
    ]
}
