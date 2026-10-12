import Foundation
import CoreLocation
import Observation

/// Fixed per-shift policy; no location is collected for an idle worker or operator.
/// iOS supplies callbacks at its discretion. The interval throttles uploads, not an OS SLA.
@MainActor @Observable
final class ShiftLocationReporter: NSObject, CLLocationManagerDelegate {
    static let shared = ShiftLocationReporter()
    var message: String?
    private let manager = CLLocationManager()
    private var workerId: Int?
    private var shiftKey: String?
    private var deadline: Date?
    private var interval: TimeInterval = 0
    private var lastSent: Date?
    private var sending = false
    private var expiryTask: Task<Void, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = true
    }

    func beginSession(workerId: Int) { self.workerId = workerId }
    func endSession() { workerId = nil; stop() }

    func configure(shift: Shift?) {
        guard let shift, shift.workerId == workerId, shift.isOpen, shift.locationIntervalSeconds > 0,
              shift.startTime.addingTimeInterval(8 * 3600) > .now else { stop(); return }
        let key = shift.clientUuidString
        if shiftKey != key {
            stop()
            shiftKey = key
            deadline = shift.startTime.addingTimeInterval(8 * 3600)
            let delay = max(0, deadline!.timeIntervalSinceNow)
            expiryTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                self?.stop()
            }
        }
        interval = TimeInterval(shift.locationIntervalSeconds)
        switch manager.authorizationStatus {
        case .notDetermined:
            message = AppLanguage.string("Location is collected during this shift at your company's interval. iOS may delay updates.")
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            message = AppLanguage.string("Location is collected during this shift at your company's interval. iOS may delay updates.")
            manager.allowsBackgroundLocationUpdates = true
            manager.startUpdatingLocation()
        default:
            manager.stopUpdatingLocation()
            message = AppLanguage.string("Location access is off. Enable it in Settings to record your shift location.")
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
        expiryTask?.cancel()
        expiryTask = nil
        shiftKey = nil
        deadline = nil
        lastSent = nil
        message = nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard shiftKey != nil else { return }
        if manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse {
            manager.allowsBackgroundLocationUpdates = true
            manager.startUpdatingLocation()
        } else if manager.authorizationStatus != .notDetermined {
            manager.stopUpdatingLocation()
            message = AppLanguage.string("Location access is off. Enable it in Settings to record your shift location.")
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let key = shiftKey, let deadline, Date.now < deadline else { stop(); return }
        guard !sending, let location = locations.last, location.horizontalAccuracy >= 0,
              abs(location.timestamp.timeIntervalSinceNow) < 60,
              lastSent.map({ location.timestamp.timeIntervalSince($0) >= interval }) ?? true else { return }
        sending = true
        let sample = LocationSample(sample_uuid: UUID().uuidString.lowercased(), captured_at: location.timestamp,
                                    latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
                                    accuracy_m: location.horizontalAccuracy)
        Task {
            defer { sending = false }
            guard shiftKey == key else { return }
            do {
                let _: LocationAck = try await apiPost("/shifts/\(key)/locations", sample)
                guard shiftKey == key else { return }
                lastSent = location.timestamp
                message = AppLanguage.string("Location is collected during this shift at your company's interval. iOS may delay updates.")
            } catch let failure as APIFailure {
                guard shiftKey == key else { return }
                if failure.code == "shift_not_active" || failure.code == "location_tracking_disabled" { stop() }
                else {
                    // Failed/stale samples are never replayed as current. Try a new fix after the interval.
                    lastSent = location.timestamp
                    message = AppLanguage.string("Location could not be sent. A fresh location will be tried at the next interval.")
                }
            } catch {
                if shiftKey == key { lastSent = location.timestamp }
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard shiftKey != nil else { return }
        message = AppLanguage.string("Location is temporarily unavailable. Keep location access enabled.")
    }
}

private struct LocationSample: Encodable {
    let sample_uuid: String
    let captured_at: Date
    let latitude: Double
    let longitude: Double
    let accuracy_m: Double
}
private struct LocationAck: Decodable { let accepted: Bool }
