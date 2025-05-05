//
//  File.swift
//  POSIXKit
//
//  Created by 이지안 on 5/5/25.
//

import Darwin // or Glibc

// MARK: - Direct Syscall Wrapper (Discouraged & Problematic) -

/*
 NOTE: The standard C `syscall(2)` function is variadic (takes `...` arguments).
 Swift's Clang importer cannot directly import or call variadic C functions.
 Therefore, a direct wrapper like the one attempted below is NOT feasible in pure Swift.

 The recommended approach is ALWAYS to use the higher-level C library functions
 provided by Darwin/Glibc (e.g., `getpid()`, `open()`, `read()`, `write()`, `stat()`, etc.)
 which handle the underlying syscalls correctly.

 If you absolutely need to perform a syscall not exposed by a standard library function,
 the correct method is to write a small C "shim" function that takes a fixed number
 of arguments and calls the syscall internally. You would then import that C shim
 into your Swift code.

 The following code is commented out because it will not compile due to the
 variadic function import limitation.
*/

/*
 /// ### Warning: Unsafe & Uncompilable ###
 /// Direct wrapper attempt for the syscall function. Use with extreme caution.
 /// Prefer higher-level C library functions. THIS WILL NOT COMPILE DIRECTLY.
 ///
 /// The number and type of arguments MUST match the requirements of the
 /// specific system call number being used. Incorrect usage can lead to crashes
 /// or undefined behavior.
 ///
 /// - Parameters:
 ///   - number: The system call number (e.g., `SYS_getpid`). Check `<sys/syscall.h>`.
 ///   - arg1, ... arg6: Arguments for the system call. Type-punned as Int.
 /// - Returns: The return value of the system call. Typically -1 on error.
 /// - Throws: `POSIXError` if the syscall returns -1.
 public func unsafeSyscall(
     _ number: Int32, // Or Int, depending on platform definition
     _ arg1: Int = 0,
     _ arg2: Int = 0,
     _ arg3: Int = 0,
     _ arg4: Int = 0,
     _ arg5: Int = 0,
     _ arg6: Int = 0
 ) throws -> Int { // Return type mismatch: C syscall often returns CInt (Int32)

     #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
         // ERROR: 'syscall' is unavailable: Variadic function is unavailable
         // ERROR: Cannot convert return expression of type 'Int32' to return type 'Int' (if it could be called)
         let result = Darwin.syscall(Int32(number), arg1, arg2, arg3, arg4, arg5, arg6)
     #elseif os(Linux)
         // ERROR: 'syscall' is unavailable: Variadic function is unavailable (likely)
         let result = Glibc.syscall(Int(number), arg1, arg2, arg3, arg4, arg5, arg6)
     #else
         #error("Platform not supported")
     #endif

     // syscall returns -1 on error and sets errno
     // Need to cast result to Int if C func returns Int32
     if Int(result) == -1 { // Example cast if result was CInt/Int32
         try POSIXError.throwFromErrno(function: "syscall(\(number))")
     }
     return Int(result) // Example cast
 }
 */

// Example usage (also commented out as it depends on unsafeSyscall)
/*
 import Darwin
 public func getProcessIDViaSyscall() throws -> ProcessID {
     #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
     // Will fail because unsafeSyscall cannot be called
     // let pid = try unsafeSyscall(SYS_getpid)
     // return ProcessID(pid)
     fatalError("unsafeSyscall is unavailable") // Or return a default/error
     #elseif os(Linux)
     // Will fail because unsafeSyscall cannot be called
     // let pid = try unsafeSyscall(Int32(SYS_getpid)) // Cast needed on Linux for number? Depends on SYS_* def
     // return ProcessID(pid)
      fatalError("unsafeSyscall is unavailable") // Or return a default/error
     #endif
 }
 */
