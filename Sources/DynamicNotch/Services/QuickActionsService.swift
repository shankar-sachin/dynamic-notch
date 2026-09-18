import AppKit
import SwiftUI

/// The things you reach for often enough to want them one flick away.
@MainActor
@Observable
final class QuickActionsService {
    private let model: NotchViewModel
    private var caffeinate: Process?

    init(model: NotchViewModel) {
        self.model = model
    }

    // MARK: State the buttons reflect

    var isDarkMode: Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    }

    private(set) var isKeepingAwake = false

    // MARK: Actions

    func toggleDarkMode() {
        let wantsDark = !isDarkMode
        Task { [weak self] in
            do {
                try await AppleScriptRunner.shared.runVoid("""
                tell application id "com.apple.systemevents"
                	tell appearance preferences to set dark mode to \(wantsDark)
                end tell
                """)
                self?.toast(
                    symbol: wantsDark ? "moon.fill" : "sun.max.fill",
                    title: wantsDark ? "Dark Mode" : "Light Mode"
                )
            } catch {
                self?.toast(symbol: "exclamationmark.triangle.fill", title: "Couldn't switch appearance", tint: .orange)
            }
        }
    }

    /// Holds the Mac awake by parenting a `caffeinate` process — when we quit or
    /// crash, it dies with us, so the Mac can never get stuck awake.
    func toggleKeepAwake() {
        if let caffeinate {
            caffeinate.terminate()
            self.caffeinate = nil
            isKeepingAwake = false
            toast(symbol: "zzz", title: "Sleep allowed")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        process.arguments = ["-di"]
        do {
            try process.run()
            caffeinate = process
            isKeepingAwake = true
            toast(symbol: "cup.and.saucer.fill", title: "Staying awake")
        } catch {
            toast(symbol: "exclamationmark.triangle.fill", title: "Couldn't stay awake", tint: .orange)
        }
    }

    func lockScreen() {
        model.collapse()
        // Nothing can draw over the login window, so the padlock gets its
        // moment here instead — shown, then a beat, then the screen goes.
        model.present(.event(EventActivity(
            symbol: "lock.fill",
            tint: .white,
            title: "Locking"
        )))

        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(420))
            self?.performLock()
        }
    }

    private func performLock() {
        // The public API for this was retired; this is the call the login window
        // itself uses, and it still ships in macOS 27.
        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/login.framework/Versions/A/login",
            RTLD_LAZY
        ), let symbol = dlsym(handle, "SACLockScreenImmediate") else {
            run("/usr/bin/pmset", ["displaysleepnow"])
            return
        }
        typealias Lock = @convention(c) () -> Int32
        _ = unsafeBitCast(symbol, to: Lock.self)()
    }

    func sleepNow() {
        model.collapse()
        run("/usr/bin/pmset", ["sleepnow"])
    }

    func screenshot() {
        model.collapse()
        // Interactive selection, straight to the clipboard.
        run("/usr/sbin/screencapture", ["-i", "-c"])
    }

    func emptyTrashConfirmed() {
        Task { [weak self] in
            try? await AppleScriptRunner.shared.runVoid("""
            tell application id "com.apple.finder" to empty trash
            """)
            self?.toast(symbol: "trash", title: "Trash emptied")
        }
    }

    // MARK: Plumbing

    private func run(_ path: String, _ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        do {
            try process.run()
        } catch {
            Log.app.error("\(path, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func toast(symbol: String, title: String, tint: Color = .white) {
        model.present(.event(EventActivity(symbol: symbol, tint: tint, title: title)))
    }

    func stop() {
        caffeinate?.terminate()
        caffeinate = nil
    }
}
