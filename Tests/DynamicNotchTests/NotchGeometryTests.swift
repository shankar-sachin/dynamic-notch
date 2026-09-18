import Foundation
import Testing
@testable import DynamicNotch

@Suite("Notch geometry")
struct NotchGeometryTests {
    @Test("The body sits between the two flares")
    func bodyWidthExcludesFlares() {
        let presentation = NotchPresentation(
            bodySize: CGSize(width: 200, height: 32),
            topRadius: 12,
            bottomRadius: 20
        )
        #expect(presentation.outerWidth == 224)
    }

    @Test("Idle is exactly the hardware notch, so the app is invisible at rest")
    func idleMatchesHardware() {
        let notch = CGSize(width: 185, height: 32)
        let presentation = NotchPresentation.resolve(mode: .idle, notch: notch, accessories: 0)

        #expect(presentation.bodySize == notch)
        #expect(presentation.topRadius == 0)
        // Zero flare means the outer edge is the notch edge: nothing spills out.
        #expect(presentation.outerWidth == notch.width)
    }

    @Test("Each mode is at least as wide as the one before it")
    func modesGrowMonotonically() {
        let notch = CGSize(width: 185, height: 32)
        let widths = [NotchMode.idle, .ambient, .hinted, .expanded].map {
            NotchPresentation.resolve(mode: $0, notch: notch, accessories: 2).outerWidth
        }
        #expect(widths == widths.sorted())
    }

    @Test("A wide notch is never narrowed by the open panel")
    func expandedNeverShrinksBelowTheNotch() {
        let notch = CGSize(width: 900, height: 40)
        let presentation = NotchPresentation.resolve(mode: .expanded, notch: notch, accessories: 2)
        #expect(presentation.bodySize.width >= notch.width)
    }

    @Test("The silhouette fills its box exactly")
    func shapeFillsItsRect() {
        let rect = CGRect(x: 0, y: 0, width: 300, height: 120)
        let path = NotchShape(topRadius: 14, bottomRadius: 26).path(in: rect)
        let bounds = path.boundingRect

        #expect(abs(bounds.minX - rect.minX) < 0.5)
        #expect(abs(bounds.maxX - rect.maxX) < 0.5)
        #expect(abs(bounds.minY - rect.minY) < 0.5)
        #expect(abs(bounds.maxY - rect.maxY) < 0.5)
    }

    @Test("Radii survive sizes too small to hold them", arguments: [
        CGSize(width: 4, height: 3),
        CGSize(width: 40, height: 8),
        CGSize(width: 1, height: 1),
    ])
    func shapeSurvivesDegenerateSizes(size: CGSize) {
        let path = NotchShape(topRadius: 30, bottomRadius: 40)
            .path(in: CGRect(origin: .zero, size: size))
        #expect(!path.isEmpty)
        #expect(path.boundingRect.width <= size.width + 0.5)
    }

    @Test("Metrics hang the notch off the top edge of its screen")
    func notchRectHangsFromTheTop() {
        let metrics = NotchMetrics(
            screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            notchSize: CGSize(width: 185, height: 32),
            notchCenterX: 756,
            isPhysical: true
        )
        #expect(metrics.notchRect == CGRect(x: 663.5, y: 950, width: 185, height: 32))
    }
}

@Suite("Pill contents")
struct PillPlanTests {
    @MainActor
    private func model() -> NotchViewModel {
        NotchViewModel(metrics: NotchMetrics(
            screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            notchSize: CGSize(width: 185, height: 32),
            notchCenterX: 756,
            isPhysical: true
        ))
    }

    private var track: NowPlayingSnapshot {
        NowPlayingSnapshot(
            source: .spotify, title: "Kanave Nee Naan", artist: "Sooraj Santhosh",
            album: "Kannum Kannum Kollaiyadithaal (Original Motion Picture Soundtrack)",
            isPlaying: false, duration: 240, position: 76,
            sampledAt: .now, artwork: nil, accent: .white
        )
    }

    @Test("Playing music takes both ears")
    @MainActor
    func musicFillsThePill() {
        let model = model()
        model.nowPlaying = track

        #expect(model.pill.units == 2)
        #expect(model.mode == .ambient)
    }

    @Test("Music paused long enough hands the notch back")
    @MainActor
    func dormantMusicReleasesThePill() {
        let model = model()
        model.nowPlaying = track
        model.musicDormant = true

        // Bare hardware again: nothing drawn, nothing sticking out.
        #expect(model.pill.units == 0)
        #expect(model.mode == .idle)
        #expect(model.presentation.bodySize == model.metrics.notchSize)

        // But the track is still there for whoever opens the panel.
        #expect(model.nowPlaying != nil)
    }

    @Test("A timer still shows even while the music is dormant")
    @MainActor
    func dormantMusicDoesNotSilenceTimers() {
        let model = model()
        model.nowPlaying = track
        model.musicDormant = true
        model.timer = TimerState(total: 300, endDate: .now.addingTimeInterval(120))

        #expect(model.mode == .ambient)
        if case .timerCountdown = model.pill.trailing {} else {
            Issue.record("the timer should have the trailing ear")
        }
    }

    @Test("The pill never spreads past the menu bar icons")
    @MainActor
    func pillRespectsTheMenuBar() {
        let model = model()
        model.nowPlaying = track
        let unbounded = model.presentation.outerWidth

        // Icons sitting close to the notch leave less room to grow into.
        model.menuBarLeftEdge = 880
        #expect(model.presentation.outerWidth < unbounded)
        #expect(model.presentation.outerWidth / 2 + model.metrics.notchCenterX <= 880)
    }
}
