//
//  File.swift
//  POSIXKit
//
//  Created by 이지안 on 5/5/25.
//

// Sources/POSIXKit/Pipe.swift
import Darwin // or Glibc

/// Creates a pipe, a unidirectional data channel. Corresponds to the pipe(2) C function.
///
/// A pipe has two ends: a read end and a write end. Data written to the write end
/// can be read from the read end.
///
/// - Returns: A tuple containing the `FileDescriptor` for the read end and the write end.
/// - Throws: `POSIXError` if the pipe creation fails.
public func pipe() throws -> (readEnd: FileDescriptor, writeEnd: FileDescriptor) {
    var fds: [Int32] = [0, 0]

    // pipe() takes a pointer to an array of two Int32s
    let result = Darwin.pipe(&fds)
    // On Linux: Glibc.pipe(&fds)

    try POSIXError.CResult(result, function: "pipe") // Check for -1

    let readFD = FileDescriptor(rawValue: fds[0])
    let writeFD = FileDescriptor(rawValue: fds[1])

    return (readEnd: readFD, writeEnd: writeFD)
}
