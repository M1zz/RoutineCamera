//
//  ColumnView.swift
//  RoutineCamera
//
//  Created by hyunho lee on 11/11/25.
//

import SwiftUI

struct ColumnView: View {
    let column: Column
    let tasks: [Task]
    let onAddTask: () -> Void
    let onDeleteTask: (Task) -> Void
    let onMoveTask: (Task, UUID) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Column Header
            HStack {
                Text(column.title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(column.color)
                
                Spacer()
                
                Text("\(tasks.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(column.color.opacity(0.2))
                    .cornerRadius(12)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            
            // Tasks
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(tasks) { task in
                        TaskCardView(
                            task: task,
                            onDelete: { onDeleteTask(task) }
                        )
                    }
                }
                .padding(.horizontal, 12)
            }
            
            // Add Task Button
            Button(action: onAddTask) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("작업 추가")
                }
                .font(.subheadline)
                .foregroundColor(column.color)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(column.color.opacity(0.1))
                .cornerRadius(8)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 16)
        }
        .frame(width: 280)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        )
    }
}