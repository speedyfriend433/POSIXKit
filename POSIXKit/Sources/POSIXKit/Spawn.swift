//
//  File.swift
//  POSIXKit
//
//  Created by 이지안 on 5/5/25.
//

// Sources/POSIXKit/Spawn.swift
import Darwin // or Glibc

// NOTE: Building safe wrappers for file_actions and attributes is complex!
// This is a simplified example assuming NULL for those.

/// Basic wrapper for posix_spawn. DOES NOT handle file actions or attributes yet.
///
/// - Parameters:
///   - path: Path to the executable.
///   - arguments: Array of arguments, including the executable name as argv[0].
///   - environment: Optional dictionary of environment variables. If nil, inherits parent's.
/// - Returns: The Process ID (PID) of the newly spawned process.
/// - Throws: `POSIXError` on failure.
public func posixSpawn(
    path: String,
    arguments: [String],
    environment: [String: String]? = nil // Simplified handling
) throws -> ProcessID {

    var pid: ProcessID = 0

    // 1. Convert Swift arguments/environment to C representations (char * const [])
    // This requires careful memory management!

    // Using withUnsafeCString for path
    try path.withCString { cPath in

        // Convert arguments: [String] -> [UnsafeMutablePointer<CChar>?] -> UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>
        let argv: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) } + [nil] // Must be null-terminated
        defer { argv.forEach { free($0) } } // Free memory allocated by strdup

        // Convert environment (if provided): [String: String] -> ["KEY=VALUE"] -> C array
        var envp: [UnsafeMutablePointer<CChar>?]? = nil
        var envpStorage: [UnsafeMutablePointer<CChar>?]? = nil // Keep reference for freeing
        if let environment = environment {
            envpStorage = environment.map { "\($0.key)=\($0.value)" }.map { strdup($0) } + [nil]
            envp = envpStorage
            defer { envpStorage?.forEach { free($0) } }
        }

        // Get pointers for the C function call
        try argv.withUnsafeBufferPointer { argvPtr in
            let envpPtr: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
            if var envp = envp {
                 envpPtr = UnsafeMutablePointer(mutating: &envp) // Unsafe - better way needed
                // A safer approach involves allocating a buffer for the pointers themselves
            } else {
                // If environment is nil, use environ (requires importing) or handle differently
                // Using nil here for simplicity, though behavior might vary slightly
                envpPtr = nil
            }

             // 2. Call posix_spawn
             // NOTE: Passing NULL for file_actions and attributes for simplicity
             let result = Darwin.posix_spawn(
                 &pid,          // Pointer to pid_t
                 cPath,         // const char *path
                 nil,           // const posix_spawn_file_actions_t *file_actions
                 nil,           // const posix_spawnattr_t *attrp
                 argvPtr.baseAddress!, // char *const argv[]
                 envpPtr // char *const envp[] (or environ)
             )
            // On Linux: Glibc.posix_spawn(...)

            // 3. Check result (posix_spawn returns 0 on success, errno value on failure)
            try POSIXError.CSuccess(result, function: "posix_spawn")
        }
    } // end withCString

    // 4. Return the PID
    return pid
}

// --- Helper functions often needed for C string arrays ---
// (These might live in a separate Utils file)

// Example of a safer way to create C-style argv/envp arrays
// This requires more careful pointer buffer management.
// Consider using ContiguousArray<UnsafeMutablePointer<CChar>?> for better layout guarantees.
