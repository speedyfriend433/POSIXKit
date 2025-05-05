//
//  File.swift
//  POSIXKit
//
//  Created by 이지안 on 5/5/25.
//

// Sources/POSIXKit/FileOperations.swift

import Darwin // or Glibc on Linux
import Foundation // For Data

// MARK: - Read Result Enum

public enum ReadResult: Sendable {
    case success(Data)
    case wouldBlock   // Indicates EAGAIN/EWOULDBLOCK occurred
    case endOfFile    // Indicates read returned 0
}

// MARK: - File Operations

/// Opens or creates a file. Corresponds to the open(2) C function.
///
/// - Parameters:
///   - path: The path to the file.
///   - flags: Options specifying access mode and behavior (e.g., `.readOnly`, `.create`).
///   - permissions: File permissions to set if the file is created (`.create` flag). Ignored otherwise.
///                Defaults typically depend on the system's umask. Use `FilePermissions` presets.
/// - Returns: A `FileDescriptor` for the opened file.
/// - Throws: `POSIXError` if the operation fails.
public func open(_ path: String, _ flags: OpenFlags, permissions: FilePermissions? = nil) throws -> FileDescriptor {
    let fdRaw: Int32
    try path.withCString { cPath in
        if flags.contains(.create), let perms = permissions {
            // open(path, flags, mode)
            fdRaw = Darwin.open(cPath, flags.rawValue, perms.rawValue)
            // On Linux: Glibc.open(cPath, flags.rawValue, perms.rawValue)
        } else {
            // open(path, flags) - mode is ignored if O_CREAT is not set
            fdRaw = Darwin.open(cPath, flags.rawValue)
             // On Linux: Glibc.open(cPath, flags.rawValue)
        }
    }
    // Check for error (-1)
    let checkedFd = try POSIXError.CResult(fdRaw, function: "open(\"\(path)\")")
    return FileDescriptor(rawValue: checkedFd)
}

/// Closes a file descriptor. Corresponds to the close(2) C function.
///
/// - Parameter fd: The `FileDescriptor` to close.
/// - Throws: `POSIXError` if the operation fails.
public func close(_ fd: FileDescriptor) throws {
    guard fd.isValid else {
        // Optionally throw or just return if closing an invalid FD
        // print("Warning: Attempted to close an invalid file descriptor.")
        return
    }
    let result = Darwin.close(fd.rawValue)
    // On Linux: Glibc.close(fd.rawValue)

    // Check for -1, ignore EBADF if we know fd was already invalid (handled above)
    if result == -1 && Darwin.errno != EBADF {
         // On Linux: Glibc.errno
        try POSIXError.throwFromErrno(function: "close(\(fd.rawValue))")
    }
    // Consider the fd invalid after close, even if close fails (best effort)
}

/// Reads data from a file descriptor, supporting non-blocking I/O.
///
/// - Parameters:
///   - fd: The `FileDescriptor` to read from. Must be opened with `O_NONBLOCK` for `.wouldBlock` to be returned.
///   - count: The maximum number of bytes to read.
/// - Returns: A `ReadResult` enum:
///   - `.success(Data)`: Contains the bytes read (can be less than `count`).
///   - `.wouldBlock`: Returned if the operation would block (requires `O_NONBLOCK`).
///   - `.endOfFile`: Returned if `read` returns 0.
/// - Throws: `POSIXError` for errors other than `EAGAIN`/`EWOULDBLOCK`.
public func read(from fd: FileDescriptor, count: Int) throws -> ReadResult {
    guard fd.isValid else { throw POSIXError.errno(code: EBADF, function: "read (invalid fd)") }
    guard count >= 0 else {
        throw POSIXError.errno(code: EINVAL, function: "read (negative count)")
    }
    guard count > 0 else { return .success(Data()) } // Reading zero bytes is success with empty data

    // Allocate a buffer
    let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: count, alignment: MemoryLayout<UInt8>.alignment)
    defer { buffer.deallocate() } // Ensure buffer is freed

    let bytesRead = Darwin.read(fd.rawValue, buffer.baseAddress!, count)
    // On Linux: Glibc.read(fd.rawValue, buffer.baseAddress!, count)

    if bytesRead == -1 {
        let currentErrno = Darwin.errno // Capture errno immediately
         // On Linux: Glibc.errno
        if currentErrno == EAGAIN || currentErrno == EWOULDBLOCK {
            return .wouldBlock
        } else {
            throw POSIXError.errno(code: currentErrno, function: "read")
        }
    } else if bytesRead == 0 {
        return .endOfFile
    } else {
        // Success, return the data read
        // Create Data from the portion of the buffer that was actually filled
        return .success(Data(bytes: buffer.baseAddress!, count: bytesRead))
    }
}

/// Writes data to a file descriptor. Corresponds to the write(2) C function.
///
/// Note: This function attempts to write the entire `Data` block but may perform
/// a partial write under certain conditions (e.g., interrupted by a signal,
/// pipe buffer full, disk full). It returns the actual number of bytes written.
/// For guaranteed writing of all data, the caller may need to loop, checking the
/// return value and retrying with the remaining data.
///
/// - Parameters:
///   - fd: The `FileDescriptor` to write to.
///   - data: The `Data` to write.
/// - Returns: The number of bytes actually written. This may be less than `data.count`.
/// - Throws: `POSIXError` if a write error occurs (including `EAGAIN`/`EWOULDBLOCK` for non-blocking FDs).
public func write(to fd: FileDescriptor, data: Data) throws -> Int {
     guard fd.isValid else { throw POSIXError.errno(code: EBADF, function: "write (invalid fd)") }
    let count = data.count
    guard count > 0 else { return 0 } // Nothing to write

    // Get a pointer to the data's bytes
    let bytesWritten = try data.withUnsafeBytes { (bufferPointer: UnsafeRawBufferPointer) -> Int in
        // Use baseAddress directly, it's Optional but Data guards against empty bufferPointer here
        let result = Darwin.write(fd.rawValue, bufferPointer.baseAddress!, count)
        // On Linux: Glibc.write(fd.rawValue, bufferPointer.baseAddress!, count)

        if result == -1 {
            // Error occurred (could be EAGAIN/EWOULDBLOCK for non-blocking)
            try POSIXError.throwFromErrno(function: "write")
        }
        // Return the actual number of bytes written
        return result // result is ssize_t, compatible with Int
    }
    return bytesWritten
}

/// Writes a String to a file descriptor using UTF-8 encoding.
/// See `write(to:data:)` for notes on partial writes.
///
/// - Parameters:
///   - fd: The `FileDescriptor` to write to.
///   - string: The `String` to write.
/// - Returns: The number of bytes actually written.
/// - Throws: `POSIXError` if a write error occurs or if the string cannot be UTF-8 encoded.
public func write(to fd: FileDescriptor, string: String) throws -> Int {
     guard fd.isValid else { throw POSIXError.errno(code: EBADF, function: "write (invalid fd)") }
    // Convert String to Data using UTF-8
    guard let data = string.data(using: .utf8) else {
        // Handle encoding error
        throw POSIXError.errno(code: EILSEQ, function: "write (string encoding failed)")
    }
    return try write(to: fd, data: data)
}
