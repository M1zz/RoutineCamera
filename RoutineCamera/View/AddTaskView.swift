//
//  AddTaskView.swift
//  RoutineCamera
//
//  Created by hyunho lee on 11/11/25.
//

import SwiftUI

struct AddTaskView: View {
    @Binding var taskTitle: String
    @Binding var taskDescription: String
    let onSave: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("작업 제목")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    TextField("작업 제목을 입력하세요", text: $taskTitle)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("작업 설명")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    TextEditor(text: $taskDescription)
                        .frame(height: 100)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("새 작업 추가")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarActions {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("취소", action: onCancel)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("저장") {
                        onSave()
                    }
                    .disabled(taskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

// Extension to fix toolbar syntax
private extension View {
    func navigationBarActions(@ToolbarContentBuilder content: () -> some ToolbarContent) -> some View {
        self.toolbar(content: content)
    }
}