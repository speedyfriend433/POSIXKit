//
//  File.swift
//  POSIXKit
//
//  Created by 이지안 on 5/5/25.
//

// Sources/POSIXKit/FileDescriptor.swift
import Darwin // or Glibc

/// Represents a POSIX file descriptor.
public struct FileDescriptor: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: Int32

    public init(rawValue: Int32) {
        self.rawValue = rawValue
    }

    /// Represents an invalid file descriptor, typically -1.
    public static let invalid = FileDescriptor(rawValue: -1)

    /// Standard input file descriptor (stdin, fd 0).
    public static let standardInput = FileDescriptor(rawValue: STDIN_FILENO)
    /// Standard output file descriptor (stdout, fd 1).
    public static let standardOutput = FileDescriptor(rawValue: STDOUT_FILENO)
    /// Standard error file descriptor (stderr, fd 2).
    public static let standardError = FileDescriptor(rawValue: STDERR_FILENO)

    public var isValid: Bool {
        return self.rawValue != -1
    }
}
