//
//  CameraCapture.swift
//  RoutineCamera
//

import SwiftUI
import AVFoundation
import Photos

struct CustomCameraView: View {
    @Binding var selectedImage: UIImage?
    let isActive: Bool
    @Environment(\.dismiss) var dismiss
    @State private var capturedImage: UIImage?
    @State private var showingPreview = false
    @StateObject private var cameraManager = CameraManager()
    @State private var currentDateTime = Date()

    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        if showingPreview, let image = capturedImage {
            // 미리보기 화면
            PreviewView(
                image: image,
                onRetake: {
                    showingPreview = false
                    capturedImage = nil
                },
                onConfirm: {
                    // 이미 날짜/시간이 추가된 이미지 사용
                    selectedImage = image

                    // 설정에 따라 사진을 "세끼" 앨범에 저장
                    if SettingsManager.shared.autoSaveToPhotoLibrary {
                        saveImageToAlbum(image)
                    }

                    dismiss()
                }
            )
        } else {
            // 카메라 화면
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    // 상단 정사각형 카메라 프리뷰
                    ZStack {
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
            DispatchQueue.main.async {
                // 캡처 즉시 날짜/시간 추가
                if let image = image {
                    self.capturedImage = self.addDateTimeToImage(image)
                }
                self.showingPreview = true
            }
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
                    let albumChangeRequest = PHAssetCollectionChangeRequest(for: album)
                    albumChangeRequest?.addAssets([assetRequest.placeholderForCreatedAsset!] as NSArray)
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
                                let albumChangeRequest = PHAssetCollectionChangeRequest(for: album)
                                albumChangeRequest?.addAssets([assetRequest.placeholderForCreatedAsset!] as NSArray)
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

        // 이미지에 텍스트 추가
        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)

        // 원본 이미지 그리기
        image.draw(in: CGRect(origin: CGPoint.zero, size: image.size))

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

        // Context의 그림자 설정 (프리뷰와 동일한 shadow 효과)
        guard let context = UIGraphicsGetCurrentContext() else {
            return image
        }

        // 그림자 효과 적용 (프리뷰의 두 번 shadow와 동일)
        context.setShadow(offset: CGSize(width: 0, height: 0), blur: 3, color: UIColor.black.cgColor)
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)

        // 흰색 텍스트 그리기
        dateString.draw(in: dateRect, withAttributes: textAttributes)
        timeString.draw(in: timeRect, withAttributes: textAttributes)

        // 최종 이미지 생성
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return newImage ?? image
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
class CameraManager: NSObject, ObservableObject {
    let captureSession = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var captureCompletion: ((UIImage?) -> Void)?
    private var isSessionRunning = false

    override init() {
        super.init()
        setupCamera()
    }
    
    private func setupCamera() {
        captureSession.sessionPreset = .photo
        
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            print("카메라를 찾을 수 없습니다.")
            return
        }
        
        do {
            let cameraInput = try AVCaptureDeviceInput(device: camera)
            
            if captureSession.canAddInput(cameraInput) {
                captureSession.addInput(cameraInput)
            }
            
            if captureSession.canAddOutput(photoOutput) {
                captureSession.addOutput(photoOutput)
            }
            
            // 최대 해상도 캡처 (iOS 16+ maxPhotoDimensions)
            if let maxDim = camera.activeFormat.supportedMaxPhotoDimensions.last {
                photoOutput.maxPhotoDimensions = maxDim
            }

        } catch {
            print("카메라 설정 오류: \(error)")
        }
    }
    
    func startSession() {
        guard !isSessionRunning else {
            print("📸 [CameraManager] 세션이 이미 실행 중 - 시작 요청 무시")
            return
        }

        print("📸 [CameraManager] 세션 시작 요청")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            if !self.captureSession.isRunning {
                self.captureSession.startRunning()
                print("📸 [CameraManager] 세션 시작 완료")
            }

            DispatchQueue.main.async {
                self.isSessionRunning = true
            }
        }
    }

    func stopSession() {
        guard isSessionRunning else {
            print("📸 [CameraManager] 세션이 이미 중지됨 - 중지 요청 무시")
            return
        }

        print("📸 [CameraManager] 세션 중지 요청")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
                print("📸 [CameraManager] 세션 중지 완료")
            }

            DispatchQueue.main.async {
                self.isSessionRunning = false
            }
        }
    }
    
    func capturePhoto(completion: @escaping (UIImage?) -> Void) {
        captureCompletion = completion
        
        let settings = AVCapturePhotoSettings()
        settings.maxPhotoDimensions = photoOutput.maxPhotoDimensions

        photoOutput.capturePhoto(with: settings, delegate: self)
    }
}

extension CameraManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let imageData = photo.fileDataRepresentation(),
              let image = UIImage(data: imageData) else {
            captureCompletion?(nil)
            return
        }
        
        // 1:1 비율로 크롭
        let croppedImage = cropToSquare(image: image)
        captureCompletion?(croppedImage)
    }
    
    private func cropToSquare(image: UIImage) -> UIImage {
        // CGImage를 사용하여 정확하게 크롭
        guard let cgImage = image.cgImage else { return image }

        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let minDimension = min(width, height)

        // 중앙에서 정사각형 크롭
        let cropRect = CGRect(
            x: (width - minDimension) / 2,
            y: (height - minDimension) / 2,
            width: minDimension,
            height: minDimension
        )

        // CGImage로 크롭
        guard let croppedCGImage = cgImage.cropping(to: cropRect) else { return image }

        // 원본 이미지의 orientation을 유지하여 UIImage 생성
        let croppedImage = UIImage(cgImage: croppedCGImage, scale: image.scale, orientation: image.imageOrientation)

        return croppedImage
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
                // 정사각형으로 크롭
                parent.selectedImage = cropToSquare(image: originalImage)
            }

            parent.presentationMode.wrappedValue.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.presentationMode.wrappedValue.dismiss()
        }

        // 이미지를 정사각형으로 크롭
        private func cropToSquare(image: UIImage) -> UIImage {
            guard let cgImage = image.cgImage else { return image }

            let width = CGFloat(cgImage.width)
            let height = CGFloat(cgImage.height)
            let minDimension = min(width, height)

            // 중앙에서 정사각형 크롭
            let cropRect = CGRect(
                x: (width - minDimension) / 2,
                y: (height - minDimension) / 2,
                width: minDimension,
                height: minDimension
            )

            // CGImage로 크롭
            guard let croppedCGImage = cgImage.cropping(to: cropRect) else { return image }

            // 원본 이미지의 orientation을 유지하여 UIImage 생성
            let croppedImage = UIImage(cgImage: croppedCGImage, scale: image.scale, orientation: image.imageOrientation)

            return croppedImage
        }
    }
}

// 음식 태그 표시 뷰
