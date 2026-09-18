import AppKit
import Foundation

/// Serialised AppleScript execution off the main thread.
///
/// `NSAppleScript` is not thread-safe and a script can block for as long as the
/// target app takes to answer, so every call funnels through one utility queue.
/// Compiled scripts are cached: recompiling the same source once a second would
/// cost more than the event itself.
final class AppleScriptRunner: @unchecked Sendable {
    static let shared = AppleScriptRunner()

    private let queue = DispatchQueue(label: "com.sachi.DynamicNotch.applescript", qos: .utility)
    private var compiled: [String: NSAppleScript] = [:]

    enum ScriptError: Error {
        case compileFailed(String)
        case executionFailed(code: Int, message: String)
        case notPermitted
    }

    /// Runs `source` and hands the descriptor to `extract` on the script queue,
    /// returning only the Sendable value that comes back.
    func run<T: Sendable>(
        _ source: String,
        extract: @escaping @Sendable (NSAppleEventDescriptor) -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do {
                    let script: NSAppleScript
                    if let cached = compiled[source] {
                        script = cached
                    } else {
                        guard let fresh = NSAppleScript(source: source) else {
                            throw ScriptError.compileFailed(source)
                        }
                        var compileError: NSDictionary?
                        fresh.compileAndReturnError(&compileError)
                        if let compileError {
                            throw ScriptError.compileFailed(
                                compileError[NSAppleScript.errorMessage] as? String ?? "unknown"
                            )
                        }
                        compiled[source] = fresh
                        script = fresh
                    }

                    var error: NSDictionary?
                    let result = script.executeAndReturnError(&error)
                    if let error {
                        let code = error[NSAppleScript.errorNumber] as? Int ?? 0
                        // -1743: the user said no in the Automation prompt.
                        if code == -1743 { throw ScriptError.notPermitted }
                        throw ScriptError.executionFailed(
                            code: code,
                            message: error[NSAppleScript.errorMessage] as? String ?? "unknown"
                        )
                    }
                    continuation.resume(returning: extract(result))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func runString(_ source: String) async throws -> String {
        try await run(source) { $0.stringValue ?? "" }
    }

    func runData(_ source: String) async throws -> Data? {
        try await run(source) { descriptor in
            if let data = descriptor.data as Data?, !data.isEmpty { return data }
            return nil
        }
    }

    func runVoid(_ source: String) async throws {
        _ = try await run(source) { _ in true }
    }
}

/// Whether we're allowed to send Apple events to a particular app.
enum AutomationPermission: Sendable {
    case granted, denied, notRunning, unknown

    static func check(bundleID: String, askIfNeeded: Bool) -> AutomationPermission {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        guard let descriptor = target.aeDesc else { return .unknown }
        let status = AEDeterminePermissionToAutomateTarget(
            descriptor, typeWildCard, typeWildCard, askIfNeeded
        )
        switch status {
        case noErr: return .granted
        case OSStatus(-1743): return .denied
        case OSStatus(-600), OSStatus(procNotFound): return .notRunning
        default: return .unknown
        }
    }
}
