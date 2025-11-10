//
//  ContentView.swift
//  RoutineCamera
//
//  Created by hyunho lee on 11/11/25.
//

import SwiftUI

struct MealSection: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let color: Color
}

struct ContentView: View {
    let mealSections = [
        MealSection(title: "아침", icon: "sunrise.fill", color: .orange),
        MealSection(title: "점심", icon: "sun.max.fill", color: .yellow),
        MealSection(title: "저녁", icon: "moon.stars.fill", color: .purple)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ForEach(mealSections) { section in
                    MealSectionView(section: section)
                }
            }
            .padding()
        }
    }
}

struct MealSectionView: View {
    let section: MealSection
    @State private var showingImagePicker = false
    @State private var selectedImage: UIImage?

    var body: some View {
        VStack(spacing: 12) {
            // 헤더
            HStack {
                Image(systemName: section.icon)
                    .font(.title2)
                    .foregroundColor(section.color)
                Text(section.title)
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
            }
            .padding(.horizontal)

            // 카메라/이미지 영역
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.gray.opacity(0.1))
                    .frame(height: 250)

                if let image = selectedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 250)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.gray)
                        Text("사진 추가")
                            .foregroundColor(.gray)
                    }
                }
            }
            .onTapGesture {
                showingImagePicker = true
            }

            // 메모 영역
            VStack(alignment: .leading, spacing: 8) {
                Text("메모")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                TextEditor(text: .constant(""))
                    .frame(height: 80)
                    .padding(8)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white)
                .shadow(color: section.color.opacity(0.2), radius: 8, x: 0, y: 4)
        )
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(selectedImage: $selectedImage)
        }
    }
}

// ImagePicker wrapper for UIImagePickerController
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Environment(\.presentationMode) var presentationMode

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .camera
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
            if let image = info[.originalImage] as? UIImage {
                parent.selectedImage = image
            }
            parent.presentationMode.wrappedValue.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}

#Preview {
    ContentView()
}
