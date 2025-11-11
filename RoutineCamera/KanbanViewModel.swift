//
//  KanbanViewModel.swift
//  RoutineCamera
//
//  Created by hyunho lee on 11/11/25.
//

import Foundation
import SwiftUI
import Combine

// MARK: - Models
struct Board: Identifiable {
    let id = UUID()
    var title: String
    var columns: [Column]
}

struct Column: Identifiable {
    let id = UUID()
    var title: String
    var order: Int
    var color: Color
}

struct Task: Identifiable {
    let id = UUID()
    var title: String
    var description: String
    var columnId: UUID
    var createdAt: Date
    var order: Int
}

// MARK: - ViewModel
class KanbanViewModel: ObservableObject {
    @Published var board: Board
    @Published var tasks: [Task] = []
    
    init() {
        // Create 3x10 grid with empty columns
        var columns: [Column] = []
        
        // Create 30 columns (3 rows × 10 columns)
        for column in 0..<10 {
            for row in 0..<3 {
                let order = column * 3 + row
                
                columns.append(Column(
                    title: "",
                    order: order,
                    color: .clear
                ))
            }
        }
        
        self.board = Board(
            title: "",
            columns: columns
        )
        
        self.tasks = []
    }
    
    func tasks(for columnId: UUID) -> [Task] {
        return tasks.filter { $0.columnId == columnId }.sorted(by: { $0.order < $1.order })
    }
    
    func addTask(title: String, description: String, to columnId: UUID) {
        let existingTasks = tasks(for: columnId)
        let newOrder = existingTasks.count
        
        let newTask = Task(
            title: title,
            description: description,
            columnId: columnId,
            createdAt: Date(),
            order: newOrder
        )
        
        tasks.append(newTask)
    }
    
    func deleteTask(_ task: Task) {
        tasks.removeAll { $0.id == task.id }
    }
    
    func moveTask(_ task: Task, to newColumnId: UUID) {
        guard let taskIndex = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        
        let existingTasksInNewColumn = tasks(for: newColumnId)
        let newOrder = existingTasksInNewColumn.count
        
        tasks[taskIndex].columnId = newColumnId
        tasks[taskIndex].order = newOrder
    }
}