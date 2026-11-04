//
//  MealLocationProvider.swift
//  RoutineCamera
//
//  사진을 찍은 곳을 기록한다 (설정 > 사진 저장 > "찍은 곳 함께 남기기" 를 켰을 때만).
//  카메라 화면이 열리면 위치를 잡기 시작해, "사용하기" 를 누르는 순간 기다리지 않고 바로 쓴다.
//  위치는 내 기기 · 내 iCloud 백업 · 사진앱 사본에만 남고 친구에게 올리는 기록에는 넣지 않는다.
//

import Foundation
import Combine
import CoreLocation
import MapKit
import UIKit

@MainActor
final class MealLocationProvider: NSObject, ObservableObject {
    static let shared = MealLocationProvider()

    @Published private(set) var authorizationStatus: CLAuthorizationStatus

    private let manager = CLLocationManager()
    private var lastLocation: CLLocation?
    private var isUpdating = false

    /// 이보다 오래된 위치는 찍은 곳으로 쓰지 않는다 (다른 곳에서 잡힌 위치일 수 있다)
    private static let freshness: TimeInterval = 10 * 60

    private override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    var isDenied: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    /// 설정에서 켰고 권한도 있을 때만 위치를 남긴다
    var isRecording: Bool {
        SettingsManager.shared.recordPlace && isAuthorized
    }

    /// 설정을 켤 때 — 아직 묻지 않았으면 권한을 묻는다
    func requestAuthorizationIfNeeded() {
        if authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    /// 카메라 화면이 열릴 때 위치를 잡기 시작한다
    func startForCapture() {
        guard isRecording, !isUpdating else { return }
        isUpdating = true
        manager.startUpdatingLocation()
    }

    /// 카메라 화면이 닫힐 때 위치 잡기를 멈춘다 (배터리)
    func stopForCapture() {
        guard isUpdating else { return }
        isUpdating = false
        manager.stopUpdatingLocation()
    }

    /// 지금 찍은 사진에 붙일 위치 — 최근에 잡힌 것이 없으면 nil (찍기를 기다리게 하지 않는다)
    func captureLocation() -> CLLocation? {
        guard isRecording, let lastLocation,
              abs(lastLocation.timestamp.timeIntervalSinceNow) < Self.freshness else { return nil }
        return lastLocation
    }

    // MARK: - 이름 붙이기 · 지도

    /// 좌표를 사람이 읽는 이름으로 (예: "성수동2가"). 못 바꾸면 nil
    static func placeName(for location: CLLocation) async -> String? {
        guard let request = MKReverseGeocodingRequest(location: location),
              let item = try? await request.mapItems.first else { return nil }
        if let short = item.addressRepresentations?.cityWithContext(.short), !short.isEmpty {
            if let name = item.name, !name.isEmpty, !short.contains(name) {
                return "\(name), \(short)"
            }
            return short
        }
        return item.name ?? item.address?.shortAddress
    }

    /// 기록에 남긴 곳을 지도 앱으로 연다
    static func openInMaps(_ place: MealPlace) {
        let location = CLLocation(latitude: place.latitude, longitude: place.longitude)
        let item = MKMapItem(location: location, address: nil)
        item.name = place.name
        item.openInMaps()
    }

    static func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

extension MealLocationProvider: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, location.horizontalAccuracy >= 0 else { return }
        Task { @MainActor in
            self.lastLocation = location
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("📍 [MealLocationProvider] 위치를 못 잡았습니다: \(error.localizedDescription)")
    }
}
