import CoreLocation
import Security
import SwiftUI
import UIKit

/// Shares this iPhone's location with the Trip map (api/location) while the toggle is on.
/// Pairing comes from the private setup link: trip://pair?traveler=tom&token=<43 chars>.
@MainActor
final class LocationSharer: NSObject, ObservableObject {
    static let shared = LocationSharer()

    private static let endpoint = URL(string: "https://jerry-trip.vercel.app/api/location")!
    private static let travelers = ["jerry", "tom"]
    private static let sharingKey = "shareLocation"

    @Published private(set) var traveler: String?
    @Published private(set) var sharing = UserDefaults.standard.bool(forKey: sharingKey)
    @Published private(set) var lastSent: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var authorization: CLAuthorizationStatus

    private let manager = CLLocationManager()
    private var token: String?
    private var session: AnyObject?          // CLBackgroundActivitySession
    private var lastSentLocation: CLLocation?
    private var posting = false

    private override init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        // No distance filter: iOS keeps delivering fixes while the phone sits still, which keeps
        // the app awake in the background so the heartbeat below can post (throttled in shouldSend).
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = false
        manager.activityType = .other
        if let saved = Keychain.read(), let (who, secret) = Self.parse(saved) {
            traveler = who; token = secret
        }
        UIDevice.current.isBatteryMonitoringEnabled = true
    }

    /// Called at launch (including a background relaunch after a significant location change).
    func resumeIfNeeded() {
        if sharing, token != nil { start() }
    }

    // MARK: Pairing

    @discardableResult
    func handle(_ url: URL) -> Bool {
        // trip://share?on=0|1 turns sharing off or on for the paired person (Shortcuts, tests).
        if url.scheme == "trip", url.host() == "share", token != nil,
           let on = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "on" })?.value {
            setSharing(on == "1")
            return true
        }
        guard url.scheme == "trip", url.host() == "pair",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let who = items.first(where: { $0.name == "traveler" })?.value,
              let secret = items.first(where: { $0.name == "token" })?.value,
              Self.parse("\(who):\(secret)") != nil else { return false }
        Keychain.save("\(who):\(secret)")
        traveler = who; token = secret
        setSharing(true)
        return true
    }

    private static func parse(_ value: String) -> (String, String)? {
        let parts = value.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, travelers.contains(parts[0]),
              parts[1].range(of: #"^[A-Za-z0-9_-]{43}$"#, options: .regularExpression) != nil else { return nil }
        return (parts[0], parts[1])
    }

    // MARK: Sharing

    func setSharing(_ on: Bool) {
        sharing = on
        UserDefaults.standard.set(on, forKey: Self.sharingKey)
        if on { start() } else { stop() }
    }

    private func start() {
        guard token != nil else { return }
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization(); return
        case .denied, .restricted: lastError = "Location is off for Trip in Settings"; return
        case .authorizedWhenInUse: manager.requestAlwaysAuthorization()
        default: break
        }
        lastError = nil
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        if session == nil { session = CLBackgroundActivitySession() }
        manager.startUpdatingLocation()
        manager.startMonitoringSignificantLocationChanges()
    }

    private func stop() {
        manager.stopUpdatingLocation()
        manager.stopMonitoringSignificantLocationChanges()
        (session as? CLBackgroundActivitySession)?.invalidate()
        session = nil
        lastSentLocation = nil
        Task { await clear() }
    }

    /// Moving: about every 60 s, or after 25 m (at most every 15 s).
    /// Still: a heartbeat every 3 min so the pin never looks stale.
    private func shouldSend(_ location: CLLocation) -> Bool {
        guard let last = lastSentLocation, let sent = lastSent else { return true }
        let elapsed = Date().timeIntervalSince(sent), moved = location.distance(from: last)
        return (moved >= 25 && elapsed >= 15) || (moved >= 10 && elapsed >= 60) || elapsed >= 180
    }

    private func send(_ location: CLLocation) async {
        guard sharing, !posting, let request = request(method: "POST", location: location) else { return }
        posting = true
        let task = UIApplication.shared.beginBackgroundTask(withName: "trip-location")
        defer { posting = false; UIApplication.shared.endBackgroundTask(task) }
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else {
                lastError = status == 401 ? "Setup link expired: ask Jerry for a new one" : "Couldn't send (\(status))"
                return
            }
            lastSent = Date(); lastSentLocation = location; lastError = nil
        } catch {
            lastError = "Waiting for signal"   // retried on the next location fix
        }
    }

    private func clear() async {
        guard let request = request(method: "DELETE", location: nil) else { return }
        _ = try? await URLSession.shared.data(for: request)
        lastSent = nil
    }

    private func request(method: String, location: CLLocation?) -> URLRequest? {
        guard let traveler, let token else { return nil }
        var request = URLRequest(url: Self.endpoint, timeoutInterval: 20)
        request.httpMethod = method
        request.setValue("Basic " + Data("\(traveler):\(token)".utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
        if let location {
            var body: [String: Any] = [
                "_type": "location",   // the API keeps OwnTracks' message format
                "lat": location.coordinate.latitude,
                "lon": location.coordinate.longitude,
                "tst": Int(location.timestamp.timeIntervalSince1970),
            ]
            let level = UIDevice.current.batteryLevel
            if level >= 0 { body["batt"] = Int((level * 100).rounded()) }
            if UserDefaults.standard.bool(forKey: "locationTest") { body["test"] = true }
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        return request
    }
}

extension LocationSharer: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorization = manager.authorizationStatus
            if sharing { start() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, location.horizontalAccuracy >= 0, location.horizontalAccuracy < 200 else { return }
        Task { @MainActor in
            if shouldSend(location) { await send(location) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

/// Toggle and status shown on the Where tab for the paired person.
struct ShareLocationSection: View {
    @ObservedObject private var sharer = LocationSharer.shared

    var body: some View {
        if let who = sharer.traveler {
            Section {
                Toggle("Share my location", isOn: Binding(get: { sharer.sharing }, set: { sharer.setSharing($0) }))
                    .accessibilityIdentifier("share-location-toggle")
                TimelineView(.periodic(from: .now, by: 30)) { _ in
                    Text(status(who)).font(.subheadline).foregroundStyle(.secondary)
                        .accessibilityIdentifier("share-location-status")
                }
                if sharer.sharing, sharer.authorization == .authorizedWhenInUse {
                    Link("Set Location to Always", destination: URL(string: UIApplication.openSettingsURLString)!)
                }
            }
        }
    }

    private func status(_ who: String) -> String {
        let permission: String
        switch sharer.authorization {
        case .authorizedAlways: permission = "Location: Always"
        case .authorizedWhenInUse: permission = "Location: While Using"
        case .denied, .restricted: permission = "Location: Off"
        default: permission = "Location: not asked yet"
        }
        if let error = sharer.lastError { return error + " · " + permission }
        guard sharer.sharing else { return "Off · sharing as \(who.capitalized) · " + permission }
        guard let sent = sharer.lastSent else { return "Sharing · waiting for location · " + permission }
        let minutes = Int(Date().timeIntervalSince(sent) / 60)
        return "Sharing · sent " + (minutes < 1 ? "just now" : "\(minutes) min ago") + " · " + permission
    }
}

private enum Keychain {
    private static let service = "com.shishi88.trip.location"

    static func save(_ value: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                   kSecAttrAccount as String: "credential"]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    static func read() -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: "credential", kSecReturnData as String: true]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
