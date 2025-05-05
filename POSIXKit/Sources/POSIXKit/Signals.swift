//
//  File.swift
//  POSIXKit
//
//  Created by 이지안 on 5/5/25.
//

// Sources/POSIXKit/Signals.swift (New File) - USE WITH EXTREME CAUTION

// Typealias for a Swift signal handler closure.
// WARNING: Code in this closure MUST be async-signal-safe!
// This usually means NO allocation, NO locking, NO complex Swift features.
// public typealias SignalHandler = @convention(c) (Int32) -> Void

// WARNING: Global state for handlers is problematic for complex apps.
// private var signalHandlers: [Int32: SignalHandler] = [:]

// private func swiftSignalTrampoline(signal: Int32) {
//     // LOOK UP and CALL the registered Swift handler for 'signal'
//     // VERY DANGEROUS - the Swift handler MUST be async-signal-safe.
//     signalHandlers[signal]?(signal)
// }

/// Sets a signal handler using sigaction (Simplified Example - Potentially Unsafe).
/// - Parameters:
///   - signal: The signal number (e.g., `SIGINT`).
///   - handler: The C function pointer to handle the signal.
///              MUST point to an async-signal-safe function.
/// - Throws: `POSIXError` on failure.
// public func setSignalHandler(_ signal: Int32, handler: SignalHandler) throws {
//     // Store the Swift closure (Problematic global state)
//     // signalHandlers[signal] = handler
//
//     var action = sigaction()
//     // Set the C trampoline function as the handler
//     action.sa_handler = swiftSignalTrampoline // This assumes the trampoline exists and is safe
//
//     // Block other signals during handler execution (recommended)
//     sigfillset(&action.sa_mask)
//     action.sa_flags = SA_RESTART // Or other flags as needed
//
//     let result = Darwin.sigaction(signal, &action, nil)
//     try POSIXError.CResult(result, function: "sigaction")
// }
