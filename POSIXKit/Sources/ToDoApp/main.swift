//
//  File.swift
//  POSIXKit
//
//  Created by 이지안 on 5/5/25.
//

// Sources/ToDoApp/main.swift
import Foundation
import POSIXKit // Although not directly used here, ensures it links

// --- Configuration ---
let todoFilePath = "./my_todos.json" // Store file in current directory

// --- Instantiate ToDo List ---
// This will load existing tasks or start fresh
let todoList = ToDoList(filePath: todoFilePath)

// --- Command Line Argument Parsing (Basic) ---
let arguments = CommandLine.arguments

guard arguments.count > 1 else {
    print("""
    Usage:
      todo add <description>   - Add a new task
      todo list                - Show all tasks
      todo done <id_prefix>    - Mark task as complete/incomplete
      todo remove <id_prefix>  - Remove a task
    """)
    exit(0) // Exit normally after showing help
}

let command = arguments[1].lowercased()

// --- Execute Command ---
do {
    switch command {
    case "add":
        guard arguments.count > 2 else {
            print("Error: Please provide a description for the task.")
            exit(1)
        }
        // Join remaining arguments to form the description
        let description = arguments.dropFirst(2).joined(separator: " ")
        try todoList.addTask(description: description)

    case "list":
        todoList.listTasks()

    case "done":
        guard arguments.count > 2 else {
            print("Error: Please provide the ID prefix of the task to toggle.")
            exit(1)
        }
        let idPrefix = arguments[2]
        try todoList.toggleCompletion(idPrefix: idPrefix)

    case "remove":
         guard arguments.count > 2 else {
            print("Error: Please provide the ID prefix of the task to remove.")
            exit(1)
        }
        let idPrefix = arguments[2]
        try todoList.removeTask(idPrefix: idPrefix)

    default:
        print("Error: Unknown command '\(command)'")
        // Show usage again
        print("""
        Usage:
          todo add <description>   - Add a new task
          todo list                - Show all tasks
          todo done <id_prefix>    - Mark task as complete/incomplete
          todo remove <id_prefix>  - Remove a task
        """)
        exit(1)
    }
} catch let error as POSIXError {
    print("A file operation error occurred: \(error.localizedDescription)")
    exit(1)
} catch {
    print("An unexpected error occurred: \(error)")
    exit(1)
}
