import Foundation
import Testing
@testable import DynamicNotch

/// These fixtures are the real records `mobiletimerd` wrote on macOS 27, copied
/// out of the live preference domain. If Apple changes the schema these tests
/// fail, which is the point — the mirror is reading someone else's private
/// state, so the shape it depends on should be written down and checked.
@Suite("Clock bridge")
struct ClockBridgeTests {
    private func running(firingIn seconds: TimeInterval, duration: Double = 900) -> [String: Any] {
        [
            "MTTimerDataVersion": "1.6",
            "MTTimerDuration": duration,
            "MTTimerFireTime": [
                "$MTTimerDate": ["MTTimerTimeDate": Date().addingTimeInterval(seconds)],
            ],
            "MTTimerFireTimerClass": "MTTimerDate",
            "MTTimerID": "F45D7341-7FEE-4126-8C76-7C94E617D0DE",
            "MTTimerState": 3,
            "MTTimerTitle": "",
        ]
    }

    private var dormant: [String: Any] {
        [
            "MTTimerDuration": 900.0,
            "MTTimerFireTime": [
                "$MTTimerTimeInterval": ["MTTimerTimeInterval": 900.0],
            ],
            "MTTimerFireTimerClass": "MTTimerTimeInterval",
            "MTTimerState": 1,
            "MTTimerTitle": "CURRENT_TIMER",
        ]
    }

    @Test("A running Clock timer is mirrored, with its own end date")
    func runningTimerIsRead() throws {
        let state = try #require(ClockBridge.state(from: running(firingIn: 787)))

        #expect(state.source == .clock)
        #expect(!state.isPaused)
        #expect(abs(state.total - 900) < 0.001)
        #expect(abs(state.remaining() - 787) < 2)
    }

    @Test("Clock's dormant record is not a running timer")
    func dormantRecordIsIgnored() {
        // Clock always keeps this one around holding the duration its UI shows.
        // Treating it as running would park a phantom 15:00 in the notch forever.
        #expect(ClockBridge.state(from: dormant) == nil)
    }

    @Test("A timer that already fired is not resurrected")
    func expiredTimerIsIgnored() {
        #expect(ClockBridge.state(from: running(firingIn: -30)) == nil)
    }

    @Test("CURRENT_TIMER is plumbing, not a label the user typed")
    func placeholderTitleIsDropped() throws {
        var record = running(firingIn: 120)
        record["MTTimerTitle"] = "CURRENT_TIMER"
        let state = try #require(ClockBridge.state(from: record))
        #expect(state.label == nil)
    }

    @Test("A real title survives")
    func realTitleIsKept() throws {
        var record = running(firingIn: 120)
        record["MTTimerTitle"] = "Pasta"
        let state = try #require(ClockBridge.state(from: record))
        #expect(state.label == "Pasta")
    }

    @Test("A paused Clock timer reports the time it has left")
    func pausedTimerIsRead() throws {
        // Paused, Clock holds a remaining interval shorter than the duration.
        let record: [String: Any] = [
            "MTTimerDuration": 600.0,
            "MTTimerFireTime": ["$MTTimerTimeInterval": ["MTTimerTimeInterval": 240.0]],
            "MTTimerFireTimerClass": "MTTimerTimeInterval",
            "MTTimerState": 2,
            "MTTimerTitle": "",
        ]
        let state = try #require(ClockBridge.state(from: record))
        #expect(state.isPaused)
        #expect(abs(state.remaining() - 240) < 0.001)
    }

    @Test("Junk records are skipped rather than guessed at")
    func malformedRecordsAreIgnored() {
        // Plist dictionaries aren't Sendable, so these live inline rather than
        // as test arguments.
        #expect(ClockBridge.state(from: [:]) == nil)
        #expect(ClockBridge.state(from: ["MTTimerDuration": 0.0]) == nil)
        // A duration with no fire time at all.
        #expect(ClockBridge.state(from: ["MTTimerDuration": 900.0]) == nil)
        // A fire time holding nothing usable.
        #expect(ClockBridge.state(from: [
            "MTTimerDuration": 900.0,
            "MTTimerFireTime": ["$MTTimerDate": [:] as [String: Any]],
        ]) == nil)
    }

    @Test("The date is found wherever in the record it is nested")
    func dateSearchIsResilient() throws {
        // If Apple renames the wrapper key, a depth-first search still finds it.
        let nested: [String: Any] = ["$SomethingNew": ["WhateverTheyCallIt": Date()]]
        #expect(ClockBridge.firstDate(in: nested) != nil)
    }
}
