import AppKit
import SwiftUI

/// A media app we know how to talk to.
enum MediaApp: String, CaseIterable, Sendable {
    case music, spotify

    var bundleID: String {
        switch self {
        case .music: "com.apple.Music"
        case .spotify: "com.spotify.client"
        }
    }
    var displayName: String {
        switch self {
        case .music: "Music"
        case .spotify: "Spotify"
        }
    }
    var symbol: String {
        switch self {
        case .music: "music.note"
        case .spotify: "music.note.list"
        }
    }
    var tint: Color {
        switch self {
        case .music: Color(red: 0.98, green: 0.20, blue: 0.35)
        case .spotify: Color(red: 0.11, green: 0.84, blue: 0.38)
        }
    }
    /// Distributed notification this app broadcasts when playback changes.
    var playerNotification: Notification.Name {
        switch self {
        case .music: Notification.Name("com.apple.Music.playerInfo")
        case .spotify: Notification.Name("com.spotify.client.PlaybackStateChanged")
        }
    }
}

/// What's playing right now, as the UI needs it.
struct NowPlayingSnapshot: Equatable {
    var source: MediaApp
    var title: String
    var artist: String
    var album: String
    var isPlaying: Bool
    var duration: TimeInterval
    /// Position at the moment `sampledAt` was taken; the UI extrapolates from there
    /// so the scrubber glides at 60fps instead of stepping once a second.
    var position: TimeInterval
    var sampledAt: Date
    var artwork: NSImage?
    /// Dominant colour pulled from the artwork, for the glow and the visualiser.
    var accent: Color

    var isEmpty: Bool { title.isEmpty && artist.isEmpty }

    /// Where the playhead actually is at `date`.
    func position(at date: Date = .now) -> TimeInterval {
        guard isPlaying else { return position }
        let drift = date.timeIntervalSince(sampledAt)
        return min(max(0, position + drift), duration > 0 ? duration : .greatestFiniteMagnitude)
    }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(0, position(at: .now) / duration), 1)
    }

    /// True when the snapshot differs in ways the *pill* can see — used to avoid
    /// re-animating the whole surface once a second for a moved playhead.
    func differsVisibly(from other: NowPlayingSnapshot) -> Bool {
        source != other.source || title != other.title || artist != other.artist
            || album != other.album || isPlaying != other.isPlaying || artwork != other.artwork
    }
}

/// Something the user asked the playing app to do.
enum MediaCommand: Equatable, Sendable {
    case playPause
    case next
    case previous
    /// Absolute position, in seconds.
    case seek(TimeInterval)
}
