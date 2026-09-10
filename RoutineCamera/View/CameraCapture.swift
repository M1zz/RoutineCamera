//
//  CameraCapture.swift
//  RoutineCamera
//

import SwiftUI
import AVFoundation
import Photos
import ImageIO

// MARK: - 사진 크기 줄이기

/// 기록에 담는 사진 크기와, 화면에 그릴 때 원본보다 작게 푸는 도구.
/// 48MP 원본을 그대로 담으면 한 장이 10MB 가까이 되고, 찍고·저장하고·그릴 때마다
/// 메모리가 수백 MB 씩 치솟아 앱이 종료됐다.
/// 카메라 콜백(백그라운드 큐)에서도 부르므로 메인 액터에 묶지 않는다.
nonisolated enum MealImageResizer {
    /// 기록에 저장하는 정사각형 사진의 한 변 (px)
    static let storedSide: CGFloat = 2048

    /// JPEG/HEIC 바이트를 긴 변이 maxPixel 이하인 이미지로 바로 푼다 (원본 크기로 풀지 않음)
    static func downsampledImage(from data: Data, maxPixel: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        return downsampledImage(from: source, maxPixel: maxPixel)
    }

    /// 촬영 원본 바이트 → 가운데를 자른 정사각형, 한 변 storedSide 이하
    static func storedSquareImage(from data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        // 짧은 변이 storedSide 가 되도록 긴 변 한도를 잡는다
        var maxPixel = storedSide
        if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
           let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
           min(width, height) > 0 {
            maxPixel = (storedSide * CGFloat(max(width, height) / min(width, height))).rounded(.up)
        }
        guard let image = downsampledImage(from: source, maxPixel: maxPixel) else { return nil }
        return squareImage(image)
    }

    /// 가운데를 정사각형으로 자르고 한 변을 storedSide 이하로 줄인다 (사진 방향 반영)
    static func squareImage(_ image: UIImage) -> UIImage {
        let side = min(image.size.width, image.size.height)
        guard side > 0 else { return image }

        // 사진앨범의 큰 원본은 먼저 작게 풀어 두고 그린다
        var source = image
        let sidePixels = side * image.scale
        if sidePixels > storedSide {
            let ratio = storedSide / sidePixels
            let thumbnailSize = CGSize(width: image.size.width * image.scale * ratio,
                                       height: image.size.height * image.scale * ratio)
            source = image.preparingThumbnail(of: thumbnailSize) ?? image
        }

        let sourceSide = min(source.size.width, source.size.height)
        let targetSide = min(sourceSide * source.scale, storedSide)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: targetSide, height: targetSide), format: format)
        return renderer.image { _ in
            let scale = targetSide / sourceSide
            let drawSize = CGSize(width: source.size.width * scale, height: source.size.height * scale)
            let origin = CGPoint(x: (targetSide - drawSize.width) / 2, y: (targetSide - drawSize.height) / 2)
            source.draw(in: CGRect(origin: origin, size: drawSize))
        }
    }

    private static func downsampledImage(from source: CGImageSource, maxPixel: CGFloat) -> UIImage? {
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

struct CustomCameraView: View {
    @Binding var selectedImage: UIImage?
    let isActive: Bool
    @State private var capturedImage: UIImage?
    @StateObject private var cameraManager = CameraManager()
    @State private var currentDateTime = Date()

    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        if let image = capturedImage {
            // 미리보기 화면
            PreviewView(
                image: image,
                onRetake: {
                    capturedImage = nil
                },
                onConfirm: {
                    // 이미 날짜/시간이 추가된 이미지 사용.
                    // 시트는 CameraPickerView 가 selectedImage 변화를 받아 한 번만 닫는다.
                    selectedImage = image

                    // 설정에 따라 사진을 "세끼" 앨범에 저장
                    if SettingsManager.shared.autoSaveToPhotoLibrary {
                        saveImageToAlbum(image)
                    }
                }
            )
        } else {
            // 카메라 화면
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    // 상단 정사각형 카메라 프리뷰
                    ZStack {
                        if cameraManager.isAccessDenied {
                            CameraPermissionNotice()
                        } else {
                            CameraPreview(cameraManager: cameraManager)

                            // 날짜/시간 오버레이
                            VStack {
                                Spacer()

                                HStack {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(dateString)
                                            .font(.system(size: min(geometry.size.width * 0.06, 24), weight: .bold))
                                            .foregroundColor(.white)
                                            .shadow(color: .black, radius: 3, x: 0, y: 0)
                                            .shadow(color: .black, radius: 3, x: 0, y: 0)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.5)

                                        Text(timeString)
                                            .font(.system(size: min(geometry.size.width * 0.06, 24), weight: .bold))
                                            .foregroundColor(.white)
                                            .shadow(color: .black, radius: 3, x: 0, y: 0)
                                            .shadow(color: .black, radius: 3, x: 0, y: 0)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.5)
                                    }
                                    .padding(.leading, min(geometry.size.width * 0.08, 30))
                                    .padding(.bottom, min(geometry.size.width * 0.08, 30))

                                    Spacer()
                                }
                            }
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.width)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .overlay(
                        // 정사각형 촬영 프레임 경계 표시 (배경과 같은 검정이라 테두리로 구분)
                        RoundedRectangle(cornerRadius: 18)
                            .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                    )
                    .padding(.top, 8)

                    Spacer()

                    // 셔터 버튼 (취소는 상단 헤더에 있으므로 여기서는 셔터만 중앙에)
                    Button(action: capturePhoto) {
                        ZStack {
                            Circle()
                                .strokeBorder(Color.white, lineWidth: 3.5)
                                .frame(width: shutterSize(geometry), height: shutterSize(geometry))

                            Circle()
                                .fill(Color.white)
                                .frame(width: shutterSize(geometry) - 14, height: shutterSize(geometry) - 14)
                        }
                    }
                    // 권한이 없거나 찍는 중에는 누르지 못하게 (연속 탭으로 촬영이 겹치지 않도록)
                    .disabled(cameraManager.isAccessDenied || cameraManager.isCapturing)
                    .opacity(cameraManager.isAccessDenied ? 0.3 : 1)
                    .accessibilityLabel("사진 촬영")

                    Spacer()
                }
                .background(Color.black)
            }
            .ignoresSafeArea()
            .onReceive(timer) { _ in
                currentDateTime = Date()
            }
            .onChange(of: isActive) { oldValue, newValue in
                if newValue {
                    // 카메라 탭으로 돌아올 때 세션 시작
                    print("📸 [CustomCameraView] 카메라 활성화 - 세션 시작")
                    cameraManager.startSession()
                } else {
                    // 다른 탭으로 이동할 때 세션 중지
                    print("📸 [CustomCameraView] 카메라 비활성화 - 세션 중지")
                    cameraManager.stopSession()
                }
            }
            .onAppear {
                if isActive {
                    print("📸 [CustomCameraView] 초기 로드 - 세션 시작")
                    cameraManager.startSession()
                }
            }
            .onDisappear {
                print("📸 [CustomCameraView] 뷰 사라짐 - 세션 중지")
                cameraManager.stopSession()
            }
        }
    }

    // 셔터 버튼 크기 (화면 폭 비례, 최대 78)
    private func shutterSize(_ geometry: GeometryProxy) -> CGFloat {
        min(geometry.size.width * 0.2, 78)
    }

    var dateString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy년 MM월 dd일 EEEE"
        return formatter.string(from: currentDateTime)
    }

    var timeString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: currentDateTime)
    }

    private func capturePhoto() {
        // 카메라에서 사진 캡처
        cameraManager.capturePhoto { image in
            // 캡처 즉시 날짜/시간 추가 (촬영에 실패하면 카메라 화면에 그대로 머문다)
            guard let image = image else { return }
            self.capturedImage = self.addDateTimeToImage(image)
        }
    }

    // 이미지를 앨범에 저장
    private func saveImageToAlbum(_ image: UIImage) {
        // 현재 앨범 타입에 따른 앨범 이름
        let albumName: String
        switch SettingsManager.shared.albumType {
        case .diet:
            albumName = "세끼식단"
        case .exercise:
            albumName = "세끼운동"
        }

        // 사진 라이브러리 접근 권한 확인
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                print("사진 라이브러리 접근 권한이 없습니다.")
                return
            }

            // 먼저 앨범이 있는지 확인
            let fetchOptions = PHFetchOptions()
            fetchOptions.predicate = NSPredicate(format: "title = %@", albumName)
            let collection = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: fetchOptions)

            if let album = collection.firstObject {
                // 기존 앨범에 이미지 추가
                PHPhotoLibrary.shared().performChanges({
                    let assetRequest = PHAssetChangeRequest.creationRequestForAsset(from: image)
                    guard let placeholder = assetRequest.placeholderForCreatedAsset else { return }
                    let albumChangeRequest = PHAssetCollectionChangeRequest(for: album)
                    albumChangeRequest?.addAssets([placeholder] as NSArray)
                }) { success, error in
                    if success {
                        print("이미지가 \(albumName) 앨범에 저장되었습니다.")
                    } else {
                        print("이미지 저장 실패: \(error?.localizedDescription ?? "알 수 없는 오류")")
                    }
                }
            } else {
                // 새 앨범 생성
                var albumPlaceholder: PHObjectPlaceholder?
                PHPhotoLibrary.shared().performChanges({
                    let createAlbumRequest = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: albumName)
                    albumPlaceholder = createAlbumRequest.placeholderForCreatedAssetCollection
                }) { success, error in
                    if success, let placeholder = albumPlaceholder {
                        // 앨범이 생성되면 이미지 추가
                        let fetchResult = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [placeholder.localIdentifier], options: nil)
                        if let album = fetchResult.firstObject {
                            PHPhotoLibrary.shared().performChanges({
                                let assetRequest = PHAssetChangeRequest.creationRequestForAsset(from: image)
                                guard let assetPlaceholder = assetRequest.placeholderForCreatedAsset else { return }
                                let albumChangeRequest = PHAssetCollectionChangeRequest(for: album)
                                albumChangeRequest?.addAssets([assetPlaceholder] as NSArray)
                            }) { success, error in
                                if success {
                                    print("이미지가 새로 생성된 \(albumName) 앨범에 저장되었습니다.")
                                } else {
                                    print("새 앨범에 이미지 저장 실패: \(error?.localizedDescription ?? "알 수 없는 오류")")
                                }
                            }
                        }
                    } else {
                        print("앨범 생성 실패: \(error?.localizedDescription ?? "알 수 없는 오류")")
                    }
                }
            }
        }
    }

    // 이미지에 날짜와 시간을 추가하는 함수
    private func addDateTimeToImage(_ image: UIImage) -> UIImage {
        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "ko_KR")

        // 날짜 포맷 (년 월 일 요일)
        dateFormatter.dateFormat = "yyyy년 MM월 dd일 EEEE"
        let dateString = dateFormatter.string(from: now)

        // 시간 포맷
        dateFormatter.dateFormat = "HH:mm:ss"
        let timeString = dateFormatter.string(from: now)

        // 텍스트 속성 설정 (프리뷰와 동일하게)
        let fontSize = min(image.size.width, image.size.height) * 0.06
        let font = UIFont.boldSystemFont(ofSize: fontSize)

        let textAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor.white,
            .font: font
        ]

        // 텍스트 크기 계산
        let dateSize = dateString.size(withAttributes: textAttributes)
        let timeSize = timeString.size(withAttributes: textAttributes)

        // 텍스트 위치 계산 (왼쪽 아래) - 이미지 크기에 비례하도록 margin 계산
        let margin = min(image.size.width, image.size.height) * 0.08
        let lineSpacing: CGFloat = 6
        let dateRect = CGRect(
            x: margin,
            y: image.size.height - dateSize.height - timeSize.height - lineSpacing - margin,
            width: dateSize.width,
            height: dateSize.height
        )

        let timeRect = CGRect(
            x: margin,
            y: image.size.height - timeSize.height - margin,
            width: timeSize.width,
            height: timeSize.height
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)

        return renderer.image { rendererContext in
            // 원본 이미지 그리기
            image.draw(in: CGRect(origin: CGPoint.zero, size: image.size))

            // 그림자 효과 적용 (프리뷰의 두 번 shadow와 동일)
            let context = rendererContext.cgContext
            context.setShadow(offset: CGSize(width: 0, height: 0), blur: 3, color: UIColor.black.cgColor)
            context.setAllowsAntialiasing(true)
            context.setShouldAntialias(true)

            // 흰색 텍스트 그리기
            dateString.draw(in: dateRect, withAttributes: textAttributes)
            timeString.draw(in: timeRect, withAttributes: textAttributes)
        }
    }
}

// 카메라 권한이 꺼져 있을 때 — 까만 화면 대신 이유와 해결 방법을 보여준다
private struct CameraPermissionNotice: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.fill")
                .font(.system(size: 36))
                .foregroundColor(.white.opacity(0.7))
                .accessibilityHidden(true)

            Text("카메라 권한이 꺼져 있어요")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)

            Text("설정에서 카메라를 켜면 바로 찍을 수 있어요.\n사진앨범에서 고르거나 사진 없이 기록할 수도 있어요.")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.75))
                .multilineTextAlignment(.center)

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("설정 열기")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.blue))
            }
            .accessibilityHint("두 번 탭하면 설정 앱에서 카메라 권한을 켤 수 있습니다")
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}

// 미리보기 화면
struct PreviewView: View {
    let image: UIImage
    let onRetake: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // 이미지 미리보기
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                Spacer()

                HStack(spacing: 12) {
                    // 다시 찍기 버튼
                    Button("다시 찍기") {
                        onRetake()
                    }
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 13).fill(Color.white.opacity(0.18)))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                    // 확인 버튼
                    Button("사용하기") {
                        onConfirm()
                    }
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 13).fill(Color.blue))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
        }
    }
}
import Combine

// 카메라 매니저
// 세션 설정·시작·중지·촬영은 전용 직렬 큐에서만 한다.
// 여러 스레드에서 startRunning/stopRunning 이 겹치거나, 카메라 입력이 붙지 않은 출력(권한 거부·시작 전)으로
// 촬영을 요청하면 AVFoundation 이 예외를 던져 앱이 종료된다.
// 화면 상태(@Published)는 메인에서만, AVFoundation 객체는 sessionQueue 에서만 만진다.
class CameraManager: NSObject, ObservableObject {
    nonisolated(unsafe) let captureSession = AVCaptureSession()
    nonisolated(unsafe) private let photoOutput = AVCapturePhotoOutput()
    nonisolated private let sessionQueue = DispatchQueue(label: "com.ysoup.RoutineCamera.camera-session")
    nonisolated(unsafe) private var captureCompletion: ((UIImage?) -> Void)?  // sessionQueue → 델리게이트
    nonisolated(unsafe) private var isConfigured = false                     // sessionQueue 에서만 접근
    private var wantsRunning = false  // 권한 응답이 늦게 와도 이미 닫힌 화면에서 켜지지 않게

    @Published private(set) var authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @Published private(set) var isCapturing = false

    var isAccessDenied: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    func startSession() {
        wantsRunning = true
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        authorizationStatus = status

        switch status {
        case .authorized:
            print("📸 [CameraManager] 세션 시작 요청")
            sessionQueue.async { [weak self] in
                guard let self = self else { return }
                self.configureIfNeeded()
                if self.isConfigured && !self.captureSession.isRunning {
                    self.captureSession.startRunning()
                    print("📸 [CameraManager] 세션 시작 완료")
                }
            }
        case .notDetermined:
            print("📸 [CameraManager] 카메라 권한 요청")
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
                    if granted && self.wantsRunning {
                        self.startSession()
                    }
                }
            }
        default:
            print("⚠️ [CameraManager] 카메라 권한 없음 - 세션을 시작하지 않음")
        }
    }

    func stopSession() {
        wantsRunning = false
        sessionQueue.async { [weak self] in
            guard let self = self, self.captureSession.isRunning else { return }
            self.captureSession.stopRunning()
            print("📸 [CameraManager] 세션 중지 완료")
        }
    }

    /// 촬영. 세션이 돌고 있지 않거나(권한 없음·시작 전) 이미 찍는 중이면 찍지 않는다.
    /// 완료 콜백은 메인에서 불리고, 실패하면 nil 이 온다.
    func capturePhoto(completion: @escaping (UIImage?) -> Void) {
        guard !isCapturing else { return }
        isCapturing = true

        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            guard self.captureSession.isRunning,
                  let connection = self.photoOutput.connection(with: .video),
                  connection.isEnabled, connection.isActive else {
                print("⚠️ [CameraManager] 카메라 연결이 없어 촬영하지 않음")
                DispatchQueue.main.async {
                    self.isCapturing = false
                    completion(nil)
                }
                return
            }

            let settings = AVCapturePhotoSettings()
            settings.maxPhotoDimensions = self.photoOutput.maxPhotoDimensions
            self.captureCompletion = completion
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    // sessionQueue 에서만 호출
    nonisolated private func configureIfNeeded() {
        guard !isConfigured else { return }

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            print("카메라를 찾을 수 없습니다.")
            return
        }

        do {
            let cameraInput = try AVCaptureDeviceInput(device: camera)

            captureSession.beginConfiguration()
            captureSession.sessionPreset = .photo
            let canAttach = captureSession.canAddInput(cameraInput) && captureSession.canAddOutput(photoOutput)
            if canAttach {
                captureSession.addInput(cameraInput)
                captureSession.addOutput(photoOutput)
            }
            captureSession.commitConfiguration()

            guard canAttach else {
                print("카메라 설정 오류: 입력/출력을 연결할 수 없습니다.")
                return
            }

            // 저장할 크기(한 변 2048px)를 만들 수 있는 가장 작은 해상도로 찍는다.
            // 48MP 로 찍으면 한 장을 푸는 데만 수백 MB 가 든다.
            if let dimensions = Self.preferredPhotoDimensions(camera.activeFormat.supportedMaxPhotoDimensions) {
                photoOutput.maxPhotoDimensions = dimensions
            }
            isConfigured = true
        } catch {
            print("카메라 설정 오류: \(error)")
        }
    }

    nonisolated private static func preferredPhotoDimensions(_ supported: [CMVideoDimensions]) -> CMVideoDimensions? {
        let sorted = supported.sorted { Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height) }
        let needed = Int32(MealImageResizer.storedSide)
        return sorted.first { min($0.width, $0.height) >= needed } ?? sorted.last
    }
}

// AVFoundation 이 백그라운드 큐에서 부르므로 메인 액터에 묶지 않는다
nonisolated extension CameraManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        // 원본 크기로 풀지 않고, 1:1 로 자른 저장용 크기로 바로 만든다
        let image = photo.fileDataRepresentation().flatMap { MealImageResizer.storedSquareImage(from: $0) }
        if image == nil {
            print("❌ [CameraManager] 촬영 실패: \(error?.localizedDescription ?? "이미지 데이터 없음")")
        }

        let completion = captureCompletion
        captureCompletion = nil
        DispatchQueue.main.async {
            self.isCapturing = false
            completion?(image)
        }
    }
}

// 카메라 프리뷰
struct CameraPreview: UIViewRepresentable {
    let cameraManager: CameraManager

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        view.clipsToBounds = true

        let previewLayer = AVCaptureVideoPreviewLayer(session: cameraManager.captureSession)
        previewLayer.videoGravity = .resizeAspectFill

        view.layer.addSublayer(previewLayer)

        // 세션은 CustomCameraView에서 관리하므로 여기서 시작하지 않음

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if let previewLayer = uiView.layer.sublayers?.first as? AVCaptureVideoPreviewLayer {
            DispatchQueue.main.async {
                // 정사각형 뷰에 맞춰서 프리뷰 레이어를 설정
                // resizeAspectFill을 사용하여 캡처와 동일한 중앙 크롭 효과
                previewLayer.frame = uiView.bounds
            }
        }
    }
}

// ImagePicker wrapper for UIImagePickerController (사진 보관함용)
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    let sourceType: UIImagePickerController.SourceType
    @Environment(\.presentationMode) var presentationMode

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = sourceType
        picker.allowsEditing = false  // 까만 화면 방지를 위해 비활성화
        picker.modalPresentationStyle = .fullScreen

        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let originalImage = info[.originalImage] as? UIImage {
                // 정사각형으로 자르고 저장용 크기로 줄인다.
                // 시트는 CameraPickerView 가 selectedImage 변화를 받아 한 번만 닫는다.
                parent.selectedImage = MealImageResizer.squareImage(originalImage)
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}

// 음식 태그 표시 뷰
