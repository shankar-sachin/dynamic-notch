import AppKit
import SwiftUI

/// Watches Music and Spotify and keeps `NotchViewModel.nowPlaying` honest.
///
/// Two channels feed this:
///  * **Distributed notifications** — both apps broadcast on every play, pause
///    and track change. They need no permission and arrive instantly, so they
///    drive the *reactions*.
///  * **Apple events** — the only way to get playhead position, artwork and to
///    send commands. Rate-limited to once a second while playing, less when not.
///
/// Apps that aren't running are never touched, so polling can't resurrect a
/// music app you deliberately quit.
@MainActor
final class MediaService {
    private let model: NotchViewModel
    private let runner = AppleScriptRunner.shared

    private var pollTask: Task<Void, Never>?
    private var nudgeTask: Task<Void, Never>?
    private var artworkTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    private var artwork: (key: String, image: NSImage?, accent: Color)?
    private var denied: Set<MediaApp> = []
    /// Last app we saw actually playing — wins ties when both are open.
    private var preferred: MediaApp?

    init(model: NotchViewModel) {
        self.model = model
    }

    // MARK: Lifecycle

    func start() {
        model.onMediaCommand = { [weak self] command in
            self?.send(command)
        }

        let center = DistributedNotificationCenter.default()
        for app in MediaApp.allCases {
            observers.append(
                center.addObserver(forName: app.playerNotification, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.preferred = app
                        self?.refreshSoon()
                    }
                }
            )
        }

        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(
                workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.refreshSoon() }
                }
            )
        }

        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                let interval = await self?.pollInterval ?? .seconds(3)
                try? await Task.sleep(for: interval)
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        nudgeTask?.cancel()
        artworkTask?.cancel()
        let center = DistributedNotificationCenter.default()
        observers.forEach(center.removeObserver)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        observers.removeAll()
    }

    /// Fast while playing (the scrubber needs it), lazy otherwise.
    private var pollInterval: Duration {
        guard let track = model.nowPlaying else { return .seconds(3) }
        return track.isPlaying ? .milliseconds(900) : .milliseconds(2400)
    }

    /// Coalesce the burst of notifications apps fire around a track change.
    private func refreshSoon() {
        nudgeTask?.cancel()
        nudgeTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(90))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    // MARK: Polling

    private var runningPlayers: [MediaApp] {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        return MediaApp.allCases.filter { running.contains($0.bundleID) && !denied.contains($0) }
    }

    private func refresh() async {
        let candidates = runningPlayers
        Log.media.debug("candidates=\(candidates.map(\.rawValue).joined(separator: ","), privacy: .public)")
        guard !candidates.isEmpty else {
            apply(nil)
            return
        }

        var readings: [PlayerReading] = []
        for app in candidates {
            if let reading = await read(app) { readings.append(reading) }
        }

        // A player that is actually playing always wins; otherwise fall back to
        // the one we heard from last, so a paused track stays on screen.
        let chosen = readings.first { $0.isPlaying && $0.app == preferred }
            ?? readings.first { $0.isPlaying }
            ?? readings.first { $0.app == preferred && !$0.isStopped }
            ?? readings.first { !$0.isStopped }

        guard let chosen else {
            apply(nil)
            return
        }
        Log.media.debug("read \(candidates.count) player(s), chose \(chosen.app.rawValue, privacy: .public) playing=\(chosen.isPlaying)")
        if chosen.isPlaying { preferred = chosen.app }
        apply(chosen)
    }

    private func read(_ app: MediaApp) async -> PlayerReading? {
        do {
            let raw = try await runner.runString(MediaScripts.state(for: app))
            return PlayerReading.parse(raw, app: app)
        } catch AppleScriptRunner.ScriptError.notPermitted {
            noteDenied(app)
            return nil
        } catch {
            // App quit mid-query, or is busy launching. Nothing to do but retry.
            Log.media.info("query \(app.rawValue, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: Applying

    private func apply(_ reading: PlayerReading?) {
        guard let reading, !reading.isStopped, !reading.title.isEmpty, model.settings.showNowPlaying else {
            if model.nowPlaying != nil {
                withAnimation(Motion.pill) { model.nowPlaying = nil }
            }
            return
        }

        let key = reading.artworkKey
        if artwork?.key != key {
            artwork = (key: key, image: nil, accent: reading.app.tint)
            loadArtwork(for: reading)
        }

        let snapshot = NowPlayingSnapshot(
            source: reading.app,
            title: reading.title,
            artist: reading.artist,
            album: reading.album,
            isPlaying: reading.isPlaying,
            duration: reading.duration,
            position: reading.position,
            sampledAt: .now,
            artwork: artwork?.image,
            accent: artwork?.accent ?? reading.app.tint
        )

        // Only animate when something a human can see has changed — otherwise
        // the once-a-second position sample would re-animate the whole pill.
        if let current = model.nowPlaying, !current.differsVisibly(from: snapshot) {
            model.nowPlaying = snapshot
        } else {
            withAnimation(Motion.pill) { model.nowPlaying = snapshot }
        }
    }

    private func loadArtwork(for reading: PlayerReading) {
        let key = reading.artworkKey
        artworkTask?.cancel()
        artworkTask = Task { [weak self] in
            guard let self else { return }
            let image: NSImage?

            switch reading.app {
            case .music:
                image = await musicArtwork()
            case .spotify:
                image = await remoteArtwork(reading.artworkURL)
            }

            guard !Task.isCancelled, let image else { return }
            let accent = ArtworkAnalyzer.accent(for: image, fallback: reading.app.tint)
            guard artwork?.key == key else { return }

            artwork = (key: key, image: image, accent: accent)
            if var snapshot = model.nowPlaying {
                snapshot.artwork = image
                snapshot.accent = accent
                withAnimation(Motion.content) { model.nowPlaying = snapshot }
            }
        }
    }

    private func musicArtwork() async -> NSImage? {
        guard let data = try? await runner.runData(MediaScripts.musicArtwork) else { return nil }
        if let image = NSImage(data: data) { return image }
        // Older Music builds wrap artwork in a classic PICT header.
        if data.count > 512, let image = NSImage(data: data.dropFirst(512)) { return image }
        return nil
    }

    private func remoteArtwork(_ url: URL?) async -> NSImage? {
        guard let url else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return NSImage(data: data)
    }

    // MARK: Commands

    private func send(_ command: MediaCommand) {
        guard let app = model.nowPlaying?.source ?? preferred else { return }

        // Reflect the tap immediately; the next poll confirms it.
        if case .playPause = command, var snapshot = model.nowPlaying {
            snapshot.isPlaying.toggle()
            snapshot.position = snapshot.position(at: .now)
            snapshot.sampledAt = .now
            withAnimation(Motion.pill) { model.nowPlaying = snapshot }
        }
        if case .seek(let position) = command, var snapshot = model.nowPlaying {
            snapshot.position = position
            snapshot.sampledAt = .now
            model.nowPlaying = snapshot
        }

        Task { [weak self] in
            guard let self else { return }
            do {
                try await runner.runVoid(MediaScripts.command(command, for: app))
            } catch AppleScriptRunner.ScriptError.notPermitted {
                noteDenied(app)
            } catch {
                // Ignore: the app may have quit between the tap and the event.
            }
            try? await Task.sleep(for: .milliseconds(180))
            await refresh()
        }
    }

    // MARK: Permission

    private func noteDenied(_ app: MediaApp) {
        guard !denied.contains(app) else { return }
        denied.insert(app)
        Log.media.error("automation denied for \(app.bundleID, privacy: .public)")
        model.mediaAccessDenied = true
        if model.nowPlaying?.source == app {
            withAnimation(Motion.pill) { model.nowPlaying = nil }
        }
    }

    /// Called from the UI when the user asks to fix permissions.
    func requestAccess() {
        let apps = denied
        denied.removeAll()
        model.mediaAccessDenied = false
        Task.detached(priority: .userInitiated) {
            for app in apps {
                _ = AutomationPermission.check(bundleID: app.bundleID, askIfNeeded: true)
            }
        }
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!
        )
    }
}
