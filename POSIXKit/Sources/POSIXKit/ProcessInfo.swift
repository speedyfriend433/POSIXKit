//
//  File.swift
//  POSIXKit
//
//  Created by 이지안 on 5/5/25.
//

// Sources/POSIXKit/ProcessInfo.swift
import Darwin // or Glibc

// Reuse ProcessID type alias from Wait.swift (or define it here if Wait.swift doesn't exist)
// public typealias ProcessID = pid_t

/// Gets the process ID of the calling process. Corresponds to getpid(2).
/// This function is always successful.
/// - Returns: The `ProcessID` of the current process.
public func getCurrentProcessID() -> ProcessID {
    return Darwin.getpid()
    // On Linux: Glibc.getpid()
}

/// Gets the process ID of the parent of the calling process. Corresponds to getppid(2).
/// This function is always successful.
/// - Returns: The `ProcessID` of the parent process.
public func getParentProcessID() -> ProcessID {
    return Darwin.getppid()
    // On Linux: Glibc.getppid()
}
