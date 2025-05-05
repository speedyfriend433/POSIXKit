//
//  File.swift
//  POSIXKit
//
//  Created by 이지안 on 5/5/25.
//

// Sources/POSIXKit/FileFlags.swift
import Darwin // or Glibc

/// Flags for opening files, corresponding to `O_*` constants.
public struct OpenFlags: OptionSet, Sendable {
    public let rawValue: Int32
    public init(rawValue: Int32) { self.rawValue = rawValue }

    // Access modes (should only set one of these)
    public static let readOnly   = OpenFlags(rawValue: O_RDONLY)
    public static let writeOnly  = OpenFlags(rawValue: O_WRONLY)
    public static let readWrite  = OpenFlags(rawValue: O_RDWR)

    // Creation/modification flags
    public static let create     = OpenFlags(rawValue: O_CREAT)
    public static let exclusive  = OpenFlags(rawValue: O_EXCL)  // Use with .create
    public static let truncate   = OpenFlags(rawValue: O_TRUNC)
    public static let append     = OpenFlags(rawValue: O_APPEND)
    public static let noCTTY     = OpenFlags(rawValue: O_NOCTTY) // Don't make controlling terminal

    // Status flags (can often be set with open or later with fcntl)
    public static let nonBlocking = OpenFlags(rawValue: O_NONBLOCK)
    public static let noFollow   = OpenFlags(rawValue: O_NOFOLLOW) // Don't follow symlinks
    public static let sync       = OpenFlags(rawValue: O_SYNC)     // Synchronous I/O
    #if !os(macOS) && !os(iOS) && !os(tvOS) && !os(watchOS) // Linux specific common flags
    public static let directory  = OpenFlags(rawValue: O_DIRECTORY)
    public static let closeOnExec = OpenFlags(rawValue: O_CLOEXEC)
    #endif

    // Helper to extract the access mode component
    public var accessMode: OpenFlags {
        return self.intersection([.readOnly, .writeOnly, .readWrite])
    }
}

/// Represents file permissions (mode_t). Often used with `O_CREAT`.
public struct FilePermissions: RawRepresentable, Sendable {
    public let rawValue: mode_t
    public init(rawValue: mode_t) { self.rawValue = rawValue }

    // Common permission presets (use octal literals)
    public static let ownerReadWrite: FilePermissions = FilePermissions(rawValue: 0o600) // rw-------
    public static let ownerAll: FilePermissions = FilePermissions(rawValue: 0o700)       // rwx------
    public static let groupRead: FilePermissions = FilePermissions(rawValue: 0o040)        // ---r-----
    public static let groupWrite: FilePermissions = FilePermissions(rawValue: 0o020)       // ----w----
    public static let groupExecute: FilePermissions = FilePermissions(rawValue: 0o010)     // -----x---
    public static let othersRead: FilePermissions = FilePermissions(rawValue: 0o004)      // ------r--
    // ... add more combinations as needed

    public static let defaultFile: FilePermissions = FilePermissions(rawValue: 0o644) // rw-r--r--
    public static let defaultDirectory: FilePermissions = FilePermissions(rawValue: 0o755) // rwxr-xr-x
}
