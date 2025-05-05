//
//  File.swift
//  POSIXKit
//
//  Created by 이지안 on 5/5/25.
//

// Sources/POSIXKit/POSIXError.swift
import Darwin // or Glibc on Linux
import Foundation // For strerror

public enum POSIXError: Error, LocalizedError {
    case errno(code: Int32, function: String? = nil)

    public var errorCode: Int32 {
        switch self {
        case .errno(let code, _):
            return code
        }
    }

    public var errorDescription: String? {
        let baseMessage: String
        if let cString = strerror(self.errorCode) {
            baseMessage = String(cString: cString)
        } else {
            baseMessage = "Unknown POSIX Error"
        }

        switch self {
        case .errno(let code, let function):
            if let function = function {
                return "\(function) failed: \(baseMessage) (errno \(code))"
            } else {
                return "\(baseMessage) (errno \(code))"
            }
        }
    }

    // Helper to throw an error based on the current errno value
    internal static func throwFromErrno(function: String = #function) throws -> Never {
        throw POSIXError.errno(code: Darwin.errno, function: function)
        // On Linux: Glibc.errno
    }

    // Helper to check C function results (-1 usually indicates error)
    @discardableResult
    internal static func CResult<T: FixedWidthInteger>(
        _ result: T,
        function: String = #function
    ) throws -> T {
        if result == -1 {
            try throwFromErrno(function: function)
        }
        return result
    }

     // Helper to check C function results (0 usually indicates success for non-returning functions)
    internal static func CSuccess(
        _ result: Int32,
        function: String = #function
    ) throws {
        if result != 0 {
            // Some functions return the error code directly (like posix_spawn)
            // Others return non-zero for other errors, still check errno
            let code = (result > 0 && result < Int32.max) ? result : Darwin.errno
             // On Linux: Glibc.errno
            throw POSIXError.errno(code: code, function: function)
        }
    }
}
