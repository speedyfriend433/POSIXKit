//
//  File.swift
//  POSIXKit
//
//  Created by 이지안 on 5/5/25.
//

// Sources/ToDoApp/Task.swift (Or place within your main file for simplicity)
import Foundation // For UUID, Codable

struct Task: Identifiable, Codable, CustomStringConvertible {
    let id: UUID
    var description: String
    var isCompleted: Bool

    init(id: UUID = UUID(), description: String, isCompleted: Bool = false) {
        self.id = id
        self.description = description
        self.isCompleted = isCompleted
    }

    // For easy printing
    var description: String {
        let status = isCompleted ? "[x]" : "[ ]"
        return "\(status) \(description) (id: \(id.uuidString.prefix(8)))"
    }
}
