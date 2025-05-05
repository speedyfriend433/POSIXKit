//
//  File.swift
//  POSIXKit
//
//  Created by 이지안 on 5/5/25.
//

import Darwin // or Glibc

public struct DirectoryEntry {
    public let name: String
    // Could potentially add type (file, dir, symlink) by checking d_type if available
    // or by calling stat/lstat, but that adds overhead.
    // public let type: ...
}

/// Provides an iterator for directory entries using opendir/readdir.
public struct DirectoryIterator: IteratorProtocol {
    public typealias Element = DirectoryEntry

    // Store as the specific pointer type, not OpaquePointer
    private let dirPointer: UnsafeMutablePointer<DIR>? // Use optional for failed open
    private var hasClosed: Bool = false

    internal init?(path: String) {
        // opendir returns UnsafeMutablePointer<DIR>?
        let dirp = path.withCString { opendir($0) }
        guard dirp != nil else { return nil } // Check for nil instead of casting
        self.dirPointer = dirp // Assign directly
    }

    public mutating func next() -> DirectoryEntry? { // Mark as mutating
        guard !hasClosed, let currentDirPointer = self.dirPointer else { return nil } // Safely unwrap

        while true {
            errno = 0
            // Pass the unwrapped UnsafeMutablePointer<DIR>
            guard let entryPointer = Darwin.readdir(currentDirPointer) else {
                if errno != 0 {
                   print("Warning: readdir failed: \(POSIXError.errno(code: errno).localizedDescription)")
                }
                self.close() // Call the mutating close method
                return nil
            }

            // Use the entryPointer directly
            let name = withUnsafeBytes(of: &entryPointer.pointee.d_name) { rawBufferPointer -> String in
                 // Using tuple element name '.0' to access the buffer base address
                 // This assumes d_name is a tuple like in some Darwin versions.
                 // If d_name is a fixed-size array, accessing its base address might differ.
                 // Let's try accessing the tuple element directly if it's a tuple:
                 // Or simpler, use the pointer directly if d_name is char[]
                 let namePtr = UnsafeRawPointer(entryPointer).advanced(by: MemoryLayout<dirent>.offset(of: \dirent.d_name)!)
                                                              .assumingMemoryBound(to: CChar.self)

                 // Safer way: use String(cString:) directly on the pointer to d_name
                 return String(cString: namePtr) // Use the derived namePtr

                 // --- Old code, potentially problematic depending on d_name type ---
                 // Find the null terminator
                 // let len = strnlen(rawBufferPointer.baseAddress!, Int(NAME_MAX) + 1)
                 // return String(cString: rawBufferPointer.bindMemory(to: CChar.self).baseAddress!)
                 // --- End Old code ---
            }


            if name == "." || name == ".." {
                continue
            }

            return DirectoryEntry(name: name)
        }
    }

    // Mark as mutating because it modifies self.hasClosed
    public mutating func close() {
        if !hasClosed, let currentDirPointer = self.dirPointer {
             // Pass the unwrapped UnsafeMutablePointer<DIR>
            Darwin.closedir(currentDirPointer)
            hasClosed = true // Modify the property
        }
    }
}

/// A sequence wrapper for iterating directory contents. Ensures `closedir` is called.
public struct DirectoryContents: Sequence {
    public typealias Iterator = DirectoryIterator

    private let path: String

    internal init(path: String) {
        self.path = path
    }

    public func makeIterator() -> DirectoryIterator {
        // If iterator creation fails, it returns nil, which makeIterator
        // should ideally handle, perhaps by returning an empty iterator
        // or allowing the caller to handle the optional. For simplicity,
        // we might force-unwrap or provide a throwing version.
        guard let iterator = DirectoryIterator(path: path) else {
             // This approach leaks the POSIXError info. A throwing makeIterator
             // isn't standard, so maybe listDirectory should throw.
             fatalError("Failed to open directory: \(path). Errno: \(errno)") // Or handle differently
        }
        return iterator
    }
}

/// Lists the contents of a directory, excluding "." and "..".
///
/// - Parameter path: The path to the directory.
/// - Returns: A `DirectoryContents` sequence that can be iterated over.
/// - Throws: `POSIXError` if the directory cannot be opened.
public func listDirectory(atPath path: String) throws -> DirectoryContents {
    // Check if opendir works before returning the Sequence struct
    guard let dirp = path.withCString({ opendir($0) }) else {
        try POSIXError.throwFromErrno(function: "opendir(\(path))")
    }
    // We opened it successfully, close this handle immediately.
    // The DirectoryIterator will open its own handle when iteration starts.
    closedir(dirp)

    return DirectoryContents(path: path)
}
