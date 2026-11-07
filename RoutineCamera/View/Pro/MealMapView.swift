//
//  MealMapView.swift
//  RoutineCamera
//
//  세끼 프로 — 찍은 곳을 남긴 기록을 지도 위에 모아 본다.
//

import SwiftUI
import MapKit
import RoutineCameraCore

struct MealMapView: View {
    @ObservedObject var mealStore: MealRecordStore
    @State private var selectedID: UUID?

    private var placed: [MealRecord] {
        mealStore.records.filter { $0.isComplete && $0.place != nil }.sorted { $0.sortDate > $1.sortDate }
    }

    var body: some View {
        let placed = placed
        Group {
            if placed.isEmpty {
                ContentUnavailableView {
                    Label("찍은 곳이 있는 기록이 아직 없어요", systemImage: "map")
                } description: {
                    Text("설정 > 사진 저장에서 '찍은 곳 함께 남기기'를 켜면 다음 사진부터 지도에 모여요.")
                }
            } else {
                Map(selection: $selectedID) {
                    ForEach(placed) { record in
                        if let place = record.place {
                            Annotation(record.mealType.displayName,
                                       coordinate: CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)) {
                                pin(record, isSelected: record.id == selectedID)
                            }
                            .tag(record.id)
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    if let record = placed.first(where: { $0.id == selectedID }) {
                        card(record)
                            .padding()
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: selectedID)
            }
        }
        .navigationTitle("식사 지도")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func pin(_ record: MealRecord, isSelected: Bool) -> some View {
        let size: CGFloat = isSelected ? 56 : 44
        return Group {
            if let data = record.thumbnailImageData {
                MealThumbnail(id: record.id, data: data, maxPixel: 168) { Color(.systemGray5) }
            } else {
                ZStack {
                    Color(.systemBackground)
                    Image(systemName: record.mealType.symbolName)
                        .foregroundStyle(record.mealType.symbolColor)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(.white, lineWidth: 3))
        .shadow(radius: 3)
    }

    private func card(_ record: MealRecord) -> some View {
        HStack(spacing: 12) {
            if let data = record.thumbnailImageData {
                MealThumbnail(id: record.id, data: data, maxPixel: 192) { Color(.systemGray5) }
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: "\(record.mealType.displayName) · \(record.sortDate.formatted(date: .abbreviated, time: .shortened))")
                    .font(.subheadline.weight(.semibold))
                if let name = record.place?.name {
                    Label(name, systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let memo = record.memo, !memo.isEmpty {
                    Text(memo)
                        .font(.caption)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}
