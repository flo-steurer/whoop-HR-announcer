import Testing
#if SWIFT_PACKAGE
@testable import WhoopHRAnnouncerCore
#else
@testable import HR_Announcer
#endif

struct AnnouncementEngineTests {
    private let configuration = AnnouncementConfiguration(
        minimumBPM: 135,
        maximumBPM: 155,
        normalInterval: 60,
        warningInterval: 10,
        confirmationDelay: 5
    )

    @Test func waitsForStableInitialReadingThenAnnounces() {
        var engine = AnnouncementEngine()

        #expect(engine.ingest(bpm: 145, at: 0, configuration: configuration) == nil)
        #expect(engine.ingest(bpm: 145, at: 4.9, configuration: configuration) == nil)
        let event = engine.ingest(bpm: 146, at: 5, configuration: configuration)

        #expect(event == AnnouncementEvent(bpm: 146, state: .inRange, reason: .initial))
        #expect(event?.spokenText == "Heart rate 146, in range")
    }

    @Test func announcesPeriodicallyAtNormalInterval() {
        var engine = startedInRangeEngine()

        #expect(engine.ingest(bpm: 146, at: 64.9, configuration: configuration) == nil)
        #expect(engine.ingest(bpm: 147, at: 65, configuration: configuration)
            == AnnouncementEvent(bpm: 147, state: .inRange, reason: .periodic))
    }

    @Test func confirmsOutsideRangeAndUsesWarningInterval() {
        var engine = startedInRangeEngine()

        #expect(engine.ingest(bpm: 160, at: 10, configuration: configuration) == nil)
        #expect(engine.ingest(bpm: 162, at: 14.9, configuration: configuration) == nil)
        let transition = engine.ingest(bpm: 161, at: 15, configuration: configuration)
        #expect(transition == AnnouncementEvent(bpm: 161, state: .aboveRange, reason: .rangeChanged))
        #expect(transition?.spokenText == "Heart rate 161, above range")

        #expect(engine.ingest(bpm: 163, at: 24.9, configuration: configuration) == nil)
        #expect(engine.ingest(bpm: 164, at: 25, configuration: configuration)
            == AnnouncementEvent(bpm: 164, state: .aboveRange, reason: .periodic))
    }

    @Test func ignoresBriefBoundaryBounce() {
        var engine = startedInRangeEngine()

        #expect(engine.ingest(bpm: 160, at: 10, configuration: configuration) == nil)
        #expect(engine.ingest(bpm: 150, at: 14, configuration: configuration) == nil)
        #expect(engine.stableState == .inRange)

        #expect(engine.ingest(bpm: 160, at: 15, configuration: configuration) == nil)
        #expect(engine.ingest(bpm: 161, at: 19.9, configuration: configuration) == nil)
        #expect(engine.ingest(bpm: 162, at: 20, configuration: configuration)?.state == .aboveRange)
    }

    @Test func announcesReturnAndResumesNormalSchedule() {
        var engine = startedAboveRangeEngine()

        #expect(engine.ingest(bpm: 150, at: 20, configuration: configuration) == nil)
        let returned = engine.ingest(bpm: 149, at: 25, configuration: configuration)
        #expect(returned == AnnouncementEvent(bpm: 149, state: .inRange, reason: .returnedToRange))
        #expect(returned?.spokenText == "Heart rate 149, back in range")

        #expect(engine.ingest(bpm: 148, at: 84.9, configuration: configuration) == nil)
        #expect(engine.ingest(bpm: 147, at: 85, configuration: configuration)?.reason == .periodic)
    }

    @Test func endpointsAreInsideRange() {
        #expect(AnnouncementEngine.classify(bpm: 134, configuration: configuration) == .belowRange)
        #expect(AnnouncementEngine.classify(bpm: 135, configuration: configuration) == .inRange)
        #expect(AnnouncementEngine.classify(bpm: 155, configuration: configuration) == .inRange)
        #expect(AnnouncementEngine.classify(bpm: 156, configuration: configuration) == .aboveRange)
    }

    @Test func appliesChangedSettingsThroughTheSameDebounce() {
        var engine = startedInRangeEngine()
        var changed = configuration
        changed.maximumBPM = 140

        #expect(engine.ingest(bpm: 145, at: 10, configuration: changed) == nil)
        #expect(engine.ingest(bpm: 145, at: 15, configuration: changed)?.state == .aboveRange)
    }

    private func startedInRangeEngine() -> AnnouncementEngine {
        var engine = AnnouncementEngine()
        _ = engine.ingest(bpm: 145, at: 0, configuration: configuration)
        _ = engine.ingest(bpm: 145, at: 5, configuration: configuration)
        return engine
    }

    private func startedAboveRangeEngine() -> AnnouncementEngine {
        var engine = startedInRangeEngine()
        _ = engine.ingest(bpm: 160, at: 10, configuration: configuration)
        _ = engine.ingest(bpm: 160, at: 15, configuration: configuration)
        return engine
    }
}
