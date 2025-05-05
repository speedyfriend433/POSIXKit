//
//  File.swift
//  POSIXKit
//
//  Created by 이지안 on 5/5/25.
//

// Sources/POSIXKit/Wait.swift
import Darwin // or Glibc
import Dispatch
import Foundation
import Darwin.C

public typealias ProcessID = pid_t // Use the C type directly or wrap it

// OptionSet for waitpid options
public struct WaitOptions: OptionSet, Sendable {
    public let rawValue: Int32
    public init(rawValue: Int32) { self.rawValue = rawValue }

    public static let noHang         = WaitOptions(rawValue: WNOHANG)
    public static let untraced       = WaitOptions(rawValue: WUNTRACED)
    // Add other options like WCONTINUED if needed
    #if os(Linux) // Linux specific example
    public static let all            = WaitOptions(rawValue: __WALL)
    #endif
}

// Enum/Struct to interpret the status code returned by waitpid
public struct WaitStatus: Sendable {
    let rawValue: Int32

    init(_ status: Int32) {
        self.rawValue = status
    }

    public var isExited: Bool { Darwin.WIFEXITED(rawValue) } // Check spelling: WIFEXITED
    public var exitCode: Int32? { isExited ? Darwin.WEXITSTATUS(rawValue) : nil } // Check spelling: WEXITSTATUS

    public var isSignaled: Bool { Darwin.WIFSIGNALED(rawValue) } // Check spelling: WIFSIGNALED
    public var terminationSignal: Int32? { isSignaled ? Darwin.WTERMSIG(rawValue) : nil } // Check spelling: WTERMSIG

    public var isStopped: Bool { Darwin.WIFSTOPPED(rawValue) } // Check spelling: WIFSTOPPED
    public var stopSignal: Int32? { isStopped ? Darwin.WSTOPSIG(rawValue) : nil } // Check spelling: WSTOPSIG
}

/// Waits for a specific process or any child process to change state.
/// Corresponds to the waitpid(2) C function.
///
/// - Parameters:
///   - pid: The process ID to wait for.
///     - `> 0`: Wait for the specific process ID.
///     - `-1`: Wait for any child process.
///     - `0`: Wait for any child process in the same process group.
///     - `< -1`: Wait for any child process whose process group ID equals `abs(pid)`.
///   - options: A set of options controlling the behavior (e.g., `.noHang`).
/// - Returns: A tuple containing the process ID that changed state and its `WaitStatus`,
///            or `nil` if `.noHang` was specified and no child has changed state yet.
/// - Throws: `POSIXError` if the `waitpid` call fails.
public func waitpid(_ pid: ProcessID, options: WaitOptions = []) throws -> (pid: ProcessID, status: WaitStatus)? {
    var status: Int32 = 0
    let resultPid = Darwin.waitpid(pid, &status, options.rawValue)
    // On Linux: Glibc.waitpid(...)

    if resultPid == -1 {
        // Error occurred
        try POSIXError.throwFromErrno(function: "waitpid")
    } else if resultPid == 0 {
        // Only happens if WNOHANG was specified and no child changed state
        guard options.contains(.noHang) else {
            // Should not happen if WNOHANG wasn't set, treat as an unexpected error
             throw POSIXError.errno(code: EINVAL, function: "waitpid (unexpected 0 result)")
        }
        return nil
    } else {
        // Success: a child changed state
        return (pid: resultPid, status: WaitStatus(status))
    }
}
