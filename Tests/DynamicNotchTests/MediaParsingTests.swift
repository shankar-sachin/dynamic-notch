import Foundation
import Testing
@testable import DynamicNotch

@Suite("Media parsing")
struct MediaParsingTests {
    private func line(_ fields: [String]) -> String {
        fields.joined(separator: MediaScripts.separator)
    }

    @Test("Spotify reports milliseconds; we store seconds")
    func spotifyDurationIsConverted() throws {
        let raw = line(["playing", "Monica", "Anirudh", "Coolie", "217000", "31.5", "spotify:track:2t1", "https://i.scdn.co/image/abc"])
        let reading = try #require(PlayerReading.parse(raw, app: .spotify))

        #expect(reading.isPlaying)
        #expect(reading.title == "Monica")
        #expect(abs(reading.duration - 217) < 0.001)
        #expect(abs(reading.position - 31.5) < 0.001)
        #expect(reading.artworkURL?.host() == "i.scdn.co")
    }

    @Test("Music already reports seconds and has no artwork URL")
    func musicDurationIsUntouched() throws {
        let raw = line(["paused", "Everything In Its Right Place", "Radiohead", "Kid A", "251.3", "64", "A1B2C3"])
        let reading = try #require(PlayerReading.parse(raw, app: .music))

        #expect(!reading.isPlaying)
        #expect(abs(reading.duration - 251.3) < 0.001)
        #expect(reading.artworkURL == nil)
    }

    @Test("A stopped player parses, but carries no track")
    func stoppedIsRecognised() throws {
        let reading = try #require(PlayerReading.parse("stopped", app: .music))
        #expect(reading.isStopped)
        #expect(reading.title.isEmpty)
    }

    @Test("Junk and short rows are rejected rather than half-read", arguments: [
        "", "   ", "playing\u{1F}only\u{1F}three",
    ])
    func malformedInputIsRejected(raw: String) {
        #expect(PlayerReading.parse(raw, app: .spotify) == nil)
    }

    @Test("Titles containing the usual punctuation survive intact")
    func awkwardTitlesSurvive() throws {
        let raw = line(["playing", "Monica (From \"Coolie\") — Tamil", "A|B", "C", "1000", "0", "id"])
        let reading = try #require(PlayerReading.parse(raw, app: .spotify))
        #expect(reading.title == "Monica (From \"Coolie\") — Tamil")
        #expect(reading.artist == "A|B")
    }

    @Test("Artwork is keyed by track, so it isn't refetched every poll")
    func artworkKeyFollowsTheTrack() throws {
        let first = try #require(PlayerReading.parse(line(["playing", "A", "B", "C", "1000", "0", "id-1"]), app: .spotify))
        let later = try #require(PlayerReading.parse(line(["playing", "A", "B", "C", "1000", "42", "id-1"]), app: .spotify))
        let other = try #require(PlayerReading.parse(line(["playing", "Z", "B", "C", "1000", "0", "id-2"]), app: .spotify))

        #expect(first.artworkKey == later.artworkKey)
        #expect(first.artworkKey != other.artworkKey)
    }
}

@Suite("Playhead")
struct PlayheadTests {
    private func snapshot(playing: Bool, position: TimeInterval, duration: TimeInterval) -> NowPlayingSnapshot {
        NowPlayingSnapshot(
            source: .spotify, title: "T", artist: "A", album: "B",
            isPlaying: playing, duration: duration, position: position,
            sampledAt: Date(timeIntervalSinceReferenceDate: 1000),
            artwork: nil, accent: .white
        )
    }

    @Test("A playing track's position is extrapolated between samples")
    func positionAdvancesWhilePlaying() {
        let track = snapshot(playing: true, position: 30, duration: 200)
        let later = Date(timeIntervalSinceReferenceDate: 1005)
        #expect(abs(track.position(at: later) - 35) < 0.001)
    }

    @Test("A paused track's position stays put")
    func positionHoldsWhilePaused() {
        let track = snapshot(playing: false, position: 30, duration: 200)
        let later = Date(timeIntervalSinceReferenceDate: 1090)
        #expect(abs(track.position(at: later) - 30) < 0.001)
    }

    @Test("Extrapolation never runs past the end of the track")
    func positionClampsToDuration() {
        let track = snapshot(playing: true, position: 195, duration: 200)
        let later = Date(timeIntervalSinceReferenceDate: 1600)
        #expect(track.position(at: later) == 200)
        #expect(track.progress == 1)
    }

    @Test("A moved playhead alone doesn't count as a visible change")
    func positionAloneIsNotVisible() {
        let track = snapshot(playing: true, position: 30, duration: 200)
        var moved = track
        moved.position = 44

        #expect(!track.differsVisibly(from: moved))

        var paused = track
        paused.isPlaying = false
        #expect(track.differsVisibly(from: paused))
    }

    @Test("Clock formatting", arguments: [
        (0.0, "0:00"), (9.0, "0:09"), (61.0, "1:01"), (599.0, "9:59"), (3661.0, "1:01:01"), (-5.0, "0:00"),
    ])
    func clockFormatsSensibly(seconds: TimeInterval, expected: String) {
        #expect(Scrubber.clock(seconds) == expected)
    }

    @Test("The volume glyph follows the level down to silence")
    func volumeSymbolTracksLevel() {
        #expect(LevelKind.volume.symbol(value: 0.9, muted: false) == "speaker.wave.3.fill")
        #expect(LevelKind.volume.symbol(value: 0.5, muted: false) == "speaker.wave.2.fill")
        #expect(LevelKind.volume.symbol(value: 0.1, muted: false) == "speaker.wave.1.fill")
        #expect(LevelKind.volume.symbol(value: 0.0, muted: false) == "speaker.slash.fill")
        #expect(LevelKind.volume.symbol(value: 0.8, muted: true) == "speaker.slash.fill")
        // Brightness has one glyph whatever the level.
        #expect(LevelKind.brightness.symbol(value: 0.1, muted: false) == "sun.max.fill")
    }
}
