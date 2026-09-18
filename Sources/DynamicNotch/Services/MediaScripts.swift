import Foundation

/// The AppleScript we send to Music and Spotify.
///
/// One round trip returns the whole player state as unit-separated fields —
/// cheaper and far less racy than asking for six properties one at a time.
/// (`st` is a reserved token in AppleScript, hence the wordy variable names.)
enum MediaScripts {
    static let separator = "\u{1F}"

    static func state(for app: MediaApp) -> String {
        switch app {
        case .music:
            """
            set sep to (ASCII character 31)
            tell application id "com.apple.Music"
            	set theState to (player state as text)
            	if theState is "stopped" then return "stopped"
            	set theTrack to current track
            	set theID to ""
            	try
            		set theID to (persistent ID of theTrack) as text
            	end try
            	return theState & sep & (name of theTrack) & sep & (artist of theTrack) & sep & (album of theTrack) & sep & ((duration of theTrack) as text) & sep & ((player position) as text) & sep & theID
            end tell
            """
        case .spotify:
            """
            set sep to (ASCII character 31)
            tell application id "com.spotify.client"
            	set theState to (player state as text)
            	if theState is "stopped" then return "stopped"
            	set theTrack to current track
            	return theState & sep & (name of theTrack) & sep & (artist of theTrack) & sep & (album of theTrack) & sep & ((duration of theTrack) as text) & sep & ((player position) as text) & sep & (id of theTrack as text) & sep & (artwork url of theTrack as text)
            end tell
            """
        }
    }

    /// Music hands back raw image bytes; Spotify only gives a URL, fetched over HTTP.
    static let musicArtwork = """
    tell application id "com.apple.Music"
    	try
    		set theTrack to current track
    		if (count of artworks of theTrack) is 0 then return missing value
    		return data of item 1 of artworks of theTrack
    	on error
    		return missing value
    	end try
    end tell
    """

    static func command(_ command: MediaCommand, for app: MediaApp) -> String {
        let verb: String
        switch command {
        case .playPause: verb = "playpause"
        case .next: verb = "next track"
        case .previous: verb = "previous track"
        case .seek(let position): verb = "set player position to \(String(format: "%.2f", position))"
        }
        return """
        tell application id "\(app.bundleID)"
        	\(verb)
        end tell
        """
    }
}

/// One player's answer, parsed but not yet turned into UI state.
struct PlayerReading: Sendable, Equatable {
    var app: MediaApp
    var isPlaying: Bool
    var isStopped: Bool
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval
    var position: TimeInterval
    var trackID: String
    var artworkURL: URL?

    /// Identity of the *track*, so artwork is only refetched when it truly changes.
    var artworkKey: String {
        trackID.isEmpty ? "\(app.rawValue):\(title)|\(artist)|\(album)" : "\(app.rawValue):\(trackID)"
    }

    static func parse(_ raw: String, app: MediaApp) -> PlayerReading? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed == "stopped" {
            return PlayerReading(
                app: app, isPlaying: false, isStopped: true,
                title: "", artist: "", album: "",
                duration: 0, position: 0, trackID: "", artworkURL: nil
            )
        }

        let fields = trimmed.components(separatedBy: MediaScripts.separator)
        guard fields.count >= 7 else { return nil }

        // Music reports duration in seconds, Spotify in milliseconds.
        let rawDuration = Double(fields[4]) ?? 0
        let duration = app == .spotify ? rawDuration / 1000 : rawDuration

        return PlayerReading(
            app: app,
            isPlaying: fields[0] == "playing",
            isStopped: false,
            title: fields[1],
            artist: fields[2],
            album: fields[3],
            duration: duration,
            position: Double(fields[5]) ?? 0,
            trackID: fields[6],
            artworkURL: fields.count > 7 ? URL(string: fields[7]) : nil
        )
    }
}
