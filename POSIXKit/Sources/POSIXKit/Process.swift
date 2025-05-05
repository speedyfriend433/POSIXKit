//
//  File.swift
//  POSIXKit
//
//  Created by 이지안 on 5/5/25.
//

import Darwin
import Foundation

// MARK: - C Interop Helpers (Internal)

/// Helper utilities for converting Swift types to C representations for POSIX calls.
/// Warning: Memory management here is simplified. Robust implementation requires
/// careful handling of buffer allocation for pointer arrays.
internal enum CInterop {

    /// Represents allocated C-style char** array. Needs careful memory management.
    struct CStringArray {
        /// Array of pointers created via `strdup`. Each must be `free`d.
        let strdupPointers: [UnsafeMutablePointer<CChar>?]
        /// A buffer holding the pointers themselves, ready for C functions. Must be `deallocate`d.
        let pointerBuffer: UnsafeMutableBufferPointer<UnsafeMutablePointer<CChar>?>

        var unsafeBaseAddress: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>? {
            return pointerBuffer.baseAddress
        }

        func deallocate() {
            // Free each string allocated by strdup
            strdupPointers.forEach { free($0) }
            // Free the buffer that held the pointers
            pointerBuffer.deallocate()
        }
    }

    /// Creates C argv array (char * const []). Caller must call `deallocate()` on the result.
    static func createCArguments(arguments: [String]) -> CStringArray {
        // Create C strings using strdup (must be freed later)
        let cStrings: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) } + [nil] // Null terminate

        // Allocate a buffer to hold the pointers themselves
        let buffer = UnsafeMutableBufferPointer<UnsafeMutablePointer<CChar>?>.allocate(capacity: cStrings.count)
        // Copy the pointers into the buffer
        _ = buffer.initialize(from: cStrings)

        return CStringArray(strdupPointers: cStrings, pointerBuffer: buffer)
    }

    /// Creates C environment array (char * const []). Caller must call `deallocate()` on the result.
    static func createCEnvironment(environment: [String: String]?) -> CStringArray? {
        guard let environment = environment, !environment.isEmpty else { return nil }

        let envStrings = environment.map { "\($0.key)=\($0.value)" }
        // Create C strings using strdup (must be freed later)
        let cStrings: [UnsafeMutablePointer<CChar>?] = envStrings.map { strdup($0) } + [nil] // Null terminate

        // Allocate buffer for the pointers
        let buffer = UnsafeMutableBufferPointer<UnsafeMutablePointer<CChar>?>.allocate(capacity: cStrings.count)
        // Copy pointers into the buffer
        _ = buffer.initialize(from: cStrings)

        return CStringArray(strdupPointers: cStrings, pointerBuffer: buffer)
    }

    /// Gets the global 'environ' variable. Use `createCEnvironment` for custom environments.
    static func getEnviron() -> UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>? {
        #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
            // On Darwin, use _NSGetEnviron() - Requires Foundation
            guard let environPtr = _NSGetEnviron() else { return nil }
            return environPtr.pointee // environ is char**
        #elseif os(Linux)
            // On Linux, Glibc provides 'environ' directly
            return Glibc.environ
        #else
            #warning("Retrieving default environment variables not implemented for this platform.")
            return nil
        #endif
    }
}


// MARK: - Process Class

/// Represents a child process launched via posix_spawn.
/// Manages the process lifecycle and provides access to standard streams if redirected.
/// Note: This class is not inherently thread-safe for concurrent operations on the same instance.
public class Process {
    public let processID: ProcessID

    /// File descriptor for writing to the child process's standard input.
    /// Only valid if `redirectStandardStreams` was true during initialization.
    /// The caller is responsible for closing this descriptor when done writing.
    public private(set) var standardInput: FileDescriptor? = nil

    /// File descriptor for reading from the child process's standard output.
    /// Only valid if `redirectStandardStreams` was true during initialization.
    /// The caller is responsible for closing this descriptor when done reading.
    public private(set) var standardOutput: FileDescriptor? = nil

    /// File descriptor for reading from the child process's standard error.
    /// Only valid if `redirectStandardStreams` was true during initialization.
    /// The caller is responsible for closing this descriptor when done reading.
    public private(set) var standardError: FileDescriptor? = nil

    // Keep track of the child-side pipe ends we need to close *in the parent* after spawn.
    private var childStdinReadEndToClose: FileDescriptor? = nil
    private var childStdoutWriteEndToClose: FileDescriptor? = nil
    private var childStderrWriteEndToClose: FileDescriptor? = nil

    private var hasWaited: Bool = false

    /// Launches a new process using `posix_spawn`.
    ///
    /// - Parameters:
    ///   - executablePath: Absolute or relative path to the executable.
    ///   - arguments: Arguments for the command. The first argument (`arguments[0]`)
    ///                should typically be the executable name itself (argv[0]).
    ///   - environment: A dictionary of environment variables for the child process.
    ///                  If `nil`, the child inherits the parent's environment.
    ///                  If empty `[:]`, the child has an empty environment.
    ///   - redirectStandardStreams: If true, pipes will be created and connected to the
    ///                              child's stdin, stdout, and stderr. Access these via
    ///                              `standardInput`, `standardOutput`, `standardError`.
    /// - Throws: `POSIXError` on failure to create pipes, set up actions, or spawn the process.
    public init(
        executablePath: String,
        arguments: [String],
        environment: [String: String]? = nil,
        redirectStandardStreams: Bool = true
    ) throws {

        // --- Prepare C arguments and environment ---
        let argv = CInterop.createCArguments(arguments: arguments)
        let envp = CInterop.createCEnvironment(environment: environment)
        // Ensure argv/envp are deallocated even if init throws later
        defer {
            argv.deallocate()
            envp?.deallocate()
        }

        // --- Resources to manage (file actions, attributes, pipe ends) ---
        var fileActions: posix_spawn_file_actions_t? = nil
        var attrs: posix_spawnattr_t? = nil

        // Defer cleanup of actions/attributes if they are initialized
        defer {
            if fileActions != nil { posix_spawn_file_actions_destroy(&fileActions) }
            if attrs != nil { posix_spawnattr_destroy(&attrs) }
        }

        // --- Setup Pipes and File Actions (if redirecting) ---
        if redirectStandardStreams {
            try POSIXError.CSuccess(posix_spawn_file_actions_init(&fileActions), function: "posix_spawn_file_actions_init")

            do {
                // Standard Input (Parent Write -> Child Read)
                let stdinPipe = try POSIXKit.pipe()
                self.standardInput = stdinPipe.writeEnd         // Parent keeps write end
                self.childStdinReadEndToClose = stdinPipe.readEnd // Parent closes child's read end after spawn
                // Child: Dup pipe's read end to stdin (0)
                try POSIXError.CSuccess(posix_spawn_file_actions_adddup2(&fileActions, stdinPipe.readEnd.rawValue, FileDescriptor.standardInput.rawValue), function: "adddup2 stdin")
                // Child: Close original pipe read end and the parent's write end
                try POSIXError.CSuccess(posix_spawn_file_actions_addclose(&fileActions, stdinPipe.readEnd.rawValue), function: "addclose stdin read")
                try POSIXError.CSuccess(posix_spawn_file_actions_addclose(&fileActions, stdinPipe.writeEnd.rawValue), function: "addclose stdin write")

                // Standard Output (Child Write -> Parent Read)
                let stdoutPipe = try POSIXKit.pipe()
                self.standardOutput = stdoutPipe.readEnd        // Parent keeps read end
                self.childStdoutWriteEndToClose = stdoutPipe.writeEnd // Parent closes child's write end after spawn
                // Child: Dup pipe's write end to stdout (1)
                try POSIXError.CSuccess(posix_spawn_file_actions_adddup2(&fileActions, stdoutPipe.writeEnd.rawValue, FileDescriptor.standardOutput.rawValue), function: "adddup2 stdout")
                // Child: Close original pipe write end and the parent's read end
                try POSIXError.CSuccess(posix_spawn_file_actions_addclose(&fileActions, stdoutPipe.writeEnd.rawValue), function: "addclose stdout write")
                try POSIXError.CSuccess(posix_spawn_file_actions_addclose(&fileActions, stdoutPipe.readEnd.rawValue), function: "addclose stdout read")


                // Standard Error (Child Write -> Parent Read)
                let stderrPipe = try POSIXKit.pipe()
                self.standardError = stderrPipe.readEnd         // Parent keeps read end
                self.childStderrWriteEndToClose = stderrPipe.writeEnd // Parent closes child's write end after spawn
                // Child: Dup pipe's write end to stderr (2)
                try POSIXError.CSuccess(posix_spawn_file_actions_adddup2(&fileActions, stderrPipe.writeEnd.rawValue, FileDescriptor.standardError.rawValue), function: "adddup2 stderr")
                // Child: Close original pipe write end and the parent's read end
                try POSIXError.CSuccess(posix_spawn_file_actions_addclose(&fileActions, stderrPipe.writeEnd.rawValue), function: "addclose stderr write")
                try POSIXError.CSuccess(posix_spawn_file_actions_addclose(&fileActions, stderrPipe.readEnd.rawValue), function: "addclose stderr read")

            } catch {
                // If pipe or file action setup fails, clean up any pipes already created
                cleanupPipeEnds() // Close parent ends (standardInput etc.)
                 // Close any child ends captured so far
                 try? childStdinReadEndToClose.map { try POSIXKit.close($0) }
                 try? childStdoutWriteEndToClose.map { try POSIXKit.close($0) }
                 try? childStderrWriteEndToClose.map { try POSIXKit.close($0) }
                throw error // Re-throw the error that occurred
            }
        }

        // --- Setup Attributes (Example placeholder) ---
        // try POSIXError.CSuccess(posix_spawnattr_init(&attrs), function: "posix_spawnattr_init")
        // var flags: Int16 = 0 // POSIX requires short for flags
        // flags |= POSIX_SPAWN_CLOEXEC_DEFAULT // Good practice on Linux if available
        // try POSIXError.CSuccess(posix_spawnattr_setflags(&attrs, flags), function: "posix_spawnattr_setflags")

        // --- Spawn the Process ---
        var spawnedPid: ProcessID = 0
        let spawnResult = try executablePath.withCString { cPath -> Int32 in
            // Determine envp pointer for spawn call
            // If envp is nil, use current environment. If envp is non-nil (even if empty), use it.
            let envpPtr = envp?.unsafeBaseAddress ?? CInterop.getEnviron()

            return Darwin.posix_spawn(
                &spawnedPid,                  // pid*
                cPath,                        // path
                &fileActions,                 // file_actions* (pass address of optional pointer)
                &attrs,                       // attrp* (pass address of optional pointer)
                argv.unsafeBaseAddress,       // argv (char* const*)
                envpPtr                       // envp (char* const*)
            )
             // On Linux: Glibc.posix_spawn(...)
        }
        try POSIXError.CSuccess(spawnResult, function: "posix_spawn")

        self.processID = spawnedPid

        // --- Post-Spawn Cleanup (Parent) ---
        // Close the child's ends of the pipes in the parent process.
        // These are no longer needed now that the child has inherited them (or not).
        try? childStdinReadEndToClose.map { try POSIXKit.close($0) }
        try? childStdoutWriteEndToClose.map { try POSIXKit.close($0) }
        try? childStderrWriteEndToClose.map { try POSIXKit.close($0) }
        // Note: Parent keeps standardInput(write), standardOutput(read), standardError(read) open.
    }

    /// Sends a signal to the process.
    /// - Parameter signal: The signal number (e.g., `SIGTERM`, `SIGKILL`). Constants defined in Darwin/Glibc.
    /// - Throws: `POSIXError` if `kill` fails (e.g., process doesn't exist, permissions error).
    public func sendSignal(_ signal: Int32) throws {
        let result = Darwin.kill(self.processID, signal)
        // On Linux: Glibc.kill(...)
        // Check for error (-1)
        try POSIXError.CResult(result, function: "kill(\(processID), \(signal))")
    }

    /// Sends the `SIGTERM` signal (request termination).
    /// Allows the process to perform cleanup if it handles the signal.
    public func terminate() throws {
        try sendSignal(SIGTERM)
    }

    /// Sends the `SIGKILL` signal (forceful termination).
    /// The process is terminated immediately by the kernel without chance for cleanup.
    public func kill() throws {
        try sendSignal(SIGKILL)
    }

    /// Waits synchronously for the process to terminate and returns its status.
    /// This should only be called once per Process instance.
    /// Calling it again will result in an error.
    ///
    /// - Returns: The `WaitStatus` containing exit code or signal information.
    /// - Throws: `POSIXError` if `waitpid` fails or if the process has already been waited for.
    public func waitUntilExit() throws -> WaitStatus {
        guard !hasWaited else {
            // ECHILD typically means "No child processes", but here we use it
            // to indicate we already waited for *this specific* child.
            throw POSIXError.errno(code: ECHILD, function: "waitUntilExit (already waited for pid \(processID))")
        }

        // Loop in case of interruption by a signal (EINTR)
        while true {
            var status: Int32 = 0
            let waitResult = Darwin.waitpid(self.processID, &status, 0) // Options = 0 for blocking wait
            // On Linux: Glibc.waitpid(...)

            if waitResult == -1 {
                let error = Darwin.errno // On Linux: Glibc.errno
                if error == EINTR {
                    continue // Interrupted by signal, retry waitpid
                }
                // Other error (e.g., ECHILD if process already reaped elsewhere, permissions)
                try POSIXError.throwFromErrno(function: "waitpid(\(processID))")
            }

            // waitpid succeeded
            guard waitResult == self.processID else {
                // Should not happen when waiting for a specific PID without WNOHANG
                throw POSIXError.errno(code: ECHILD, function: "waitpid returned unexpected pid \(waitResult) for \(processID)")
            }

            self.hasWaited = true
            // Important: Close parent's ends of pipes *after* process terminates,
            // otherwise the child might block indefinitely trying to read/write.
            self.cleanupPipeEnds()
            return WaitStatus(status) // Return the collected status
        }
    }

    /// Closes the parent's ends of the standard stream pipes.
    /// Called automatically after `waitUntilExit` or in `deinit`.
    /// Can be called manually if you are managing I/O asynchronously and know
    /// you are done with a particular stream.
    public func cleanupPipeEnds() {
        // Use map to attempt close only if descriptor is non-nil
        // Ignore errors during cleanup.
        try? standardInput.map { fd in
            try POSIXKit.close(fd)
            standardInput = nil // Set to nil after attempting close
        }
        try? standardOutput.map { fd in
            try POSIXKit.close(fd)
            standardOutput = nil
        }
        try? standardError.map { fd in
             try POSIXKit.close(fd)
             standardError = nil
        }
    }

    /// Ensures pipes are closed and warns if the process hasn't been waited for.
    deinit {
        // If the process object is destroyed before waitUntilExit is called,
        // the child process might become a zombie if not handled elsewhere.
        if !hasWaited {
            #if DEBUG // Only print warnings in debug builds
            print("Warning: Process \(processID) deinitialized without being waited for. Child process may become a zombie.")
            #endif
            // Optional: Attempt a non-blocking waitpid here to try and reap the zombie,
            // but it's generally better design for the creator to explicitly wait.
            // try? POSIXKit.waitpid(self.processID, options: .noHang)
        }
        // Ensure parent pipe ends are closed regardless.
        cleanupPipeEnds()
    }
}
