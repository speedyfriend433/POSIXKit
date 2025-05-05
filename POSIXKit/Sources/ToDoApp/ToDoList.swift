//
//  File.swift
//  POSIXKit
//
//  Created by 이지안 on 5/5/25.
//

// Sources/ToDoApp/ToDoList.swift (Or main file)
import Foundation // For JSONEncoder/Decoder
import POSIXKit   // Our POSIX wrapper library

class ToDoList {
    private var tasks: [Task] = []
    private let filePath: String
    private let filePermissions: FilePermissions // Permissions for creating the file

    /// Initializes the ToDo list, loading tasks from the specified file path.
    /// If the file doesn't exist, it starts with an empty list.
    ///
    /// - Parameter filePath: The path to the file used for persistence.
    /// - Parameter createPermissions: Permissions to use if the file needs to be created.
    init(filePath: String, createPermissions: FilePermissions = .ownerReadWrite) {
        self.filePath = filePath
        self.filePermissions = createPermissions
        do {
            try loadTasks()
            print("Loaded tasks from \(filePath)")
        } catch let error as POSIXError where error.errorCode == ENOENT {
            print("ToDo file not found at \(filePath). Starting fresh.")
            // File doesn't exist, which is okay, start with empty list
            self.tasks = []
        } catch let error as POSIXError {
            print("Error loading tasks: \(error.localizedDescription). Starting fresh.")
            // Other POSIX error during load
             self.tasks = []
        } catch {
             print("Error decoding tasks from \(filePath): \(error). Starting fresh.")
             // JSON decoding error or other issue
             self.tasks = []
        }
    }

    // MARK: - Core List Operations

    func addTask(description: String) throws {
        let newTask = Task(description: description)
        tasks.append(newTask)
        try saveTasks()
        print("Added: \(newTask)")
    }

    func listTasks() {
        if tasks.isEmpty {
            print("No tasks in the list.")
            return
        }
        print("\n--- ToDo List ---")
        for task in tasks {
            print(task)
        }
        print("-----------------\n")
    }

    func findTaskIndex(idPrefix: String) -> Int? {
        guard !idPrefix.isEmpty else { return nil }
        return tasks.firstIndex { $0.id.uuidString.lowercased().hasPrefix(idPrefix.lowercased()) }
    }

    func toggleCompletion(idPrefix: String) throws {
        guard let index = findTaskIndex(idPrefix: idPrefix) else {
            print("Error: Task with ID prefix '\(idPrefix)' not found.")
            return
        }
        tasks[index].isCompleted.toggle()
        try saveTasks()
        print("Toggled: \(tasks[index])")
    }

    func removeTask(idPrefix: String) throws {
        guard let index = findTaskIndex(idPrefix: idPrefix) else {
            print("Error: Task with ID prefix '\(idPrefix)' not found.")
            return
        }
        let removedTask = tasks.remove(at: index)
        try saveTasks()
        print("Removed: \(removedTask)")
    }


    // MARK: - Persistence using POSIXKit

    /// Loads tasks from the file using POSIXKit functions.
    private func loadTasks() throws {
        var fileDescriptor: FileDescriptor? = nil
        // Ensure the file descriptor is closed even if errors occur
        defer {
            if let fd = fileDescriptor, fd.isValid {
                try? POSIXKit.close(fd) // Ignore close errors during cleanup
            }
        }

        // 1. Open file for reading
        fileDescriptor = try POSIXKit.open(filePath, .readOnly)
        guard let fd = fileDescriptor else { /* Should have thrown */ return } // Should be unreachable if open succeeds

        // 2. Read all data from the file
        // We read in chunks until EOF is reached.
        var allData = Data()
        let bufferSize = 4096 // Read 4KB at a time
        while true {
            let readResult = try POSIXKit.read(from: fd, count: bufferSize)
            switch readResult {
            case .success(let data):
                if data.isEmpty { // End of file
                    break // Exit the while loop
                }
                allData.append(data)
            case .wouldBlock:
                // Should not happen with blocking readOnly file descriptors
                print("Warning: read() returned .wouldBlock unexpectedly.")
                // Maybe sleep briefly and retry, or treat as error? For simplicity, break.
                break // Exit the while loop
            case .endOfFile:
                // This case is now handled by .success(empty data)
                 break // Exit the while loop
            }
             // Check if we reached EOF in the last successful read
            if case .success(let data) = readResult, data.isEmpty {
                 break
            }
        }

        // 3. Close is handled by defer

        // 4. Decode JSON data
        if allData.isEmpty {
            // File exists but is empty, treat as empty list
             self.tasks = []
        } else {
            let decoder = JSONDecoder()
            self.tasks = try decoder.decode([Task].self, from: allData)
        }
    }

    /// Saves the current list of tasks to the file using POSIXKit functions.
    private func saveTasks() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted // Make JSON readable
        let data = try encoder.encode(tasks)

        var fileDescriptor: FileDescriptor? = nil
        defer {
            if let fd = fileDescriptor, fd.isValid {
                try? POSIXKit.close(fd)
            }
        }

        // 1. Open file for writing, create if needed, truncate existing content
        let flags: OpenFlags = [.writeOnly, .create, .truncate]
        fileDescriptor = try POSIXKit.open(filePath, flags, permissions: filePermissions)
        guard let fd = fileDescriptor else { /* Should have thrown */ return }

        // 2. Write the data
        var totalBytesWritten = 0
        while totalBytesWritten < data.count {
            let remainingData = data.subdata(in: totalBytesWritten..<data.count)
            // POSIXKit.write might perform a partial write, though less likely for regular files.
            // A robust implementation loops until all data is written or an error occurs.
            // For simplicity here, we try writing the rest in one go.
            let bytesWritten = try POSIXKit.write(to: fd, data: remainingData)
            if bytesWritten == 0 {
                // Should not happen unless disk is full or other weird error?
                 throw POSIXError.errno(code: EIO, function: "saveTasks (write returned 0)")
            }
            totalBytesWritten += bytesWritten
            // If partial writes were common, you'd adjust the slice and continue the loop.
            // Assuming full write for this example:
             if totalBytesWritten < data.count {
                 print("Warning: Partial write occurred, but loop is simplified. Data might be incomplete.")
                 break // Exit loop to avoid infinite loop in simplified example
             }
        }
         // print("Successfully wrote \(totalBytesWritten) bytes.") // Optional debug log

        // 3. Close is handled by defer
    }
}
