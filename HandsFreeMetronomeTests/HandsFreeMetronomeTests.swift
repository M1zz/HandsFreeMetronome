import XCTest
import LeeoKit
@testable import HandsFreeMetronome

/// The app's contract with LeeoKit: paywall reachable, restore present, policy
/// URLs https, analytics sink set… The bootstrap runs the same audit in DEBUG,
/// but only a test fails the build when it regresses.
final class SpecPreflightTests: XCTestCase {
    func testSpecIsReleasable() {
        let issues = LeeoPreflight.audit(HandsFreeMetronomeSpec.self)
        XCTAssertTrue(issues.isReleasable, issues.errors.map(\.message).joined(separator: "\n"))
    }

    func testEveryProFeatureIsGatedAndTheCoreStaysFree() {
        let policy = HandsFreeMetronomeSpec.monetization.gate
        let free = LeeoGate(policy: policy, hasPro: false, isTrialActive: false)
        for feature in ProFeature.allCases {
            XCTAssertFalse(free.allows(feature.rawValue), "\(feature) must need Pro")
        }
        XCTAssertTrue(free.allows("metronome"))
        let pro = LeeoGate(policy: policy, hasPro: true, isTrialActive: false)
        XCTAssertTrue(ProFeature.allCases.allSatisfy { pro.allows($0.rawValue) })
        // The paywall is reachable, so the contract audit has nothing to warn about.
        XCTAssertFalse(LeeoPreflight.audit(HandsFreeMetronomeSpec.self).contains { $0.code == "gate.noPath" })
    }

    func testProductIDsMatchTheStoreKitConfiguration() throws {
        // The StoreKit test file must sell exactly what the Spec declares, or
        // the paywall is tested against products that don't exist.
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Products", withExtension: "storekit")
            ?? Bundle.main.url(forResource: "Products", withExtension: "storekit")
            ?? sourceStoreKitURL())
        let text = try String(contentsOf: url, encoding: .utf8)
        for id in [ProStore.yearlyID, ProStore.lifetimeID] {
            XCTAssertTrue(text.contains("\"\(id)\""), "\(id) missing from Products.storekit")
        }
    }

    private func sourceStoreKitURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("HandsFreeMetronome/Products.storekit")
    }
}

/// Pitch detection is what the tuner and the instrument signal both stand on.
final class PitchDetectionTests: XCTestCase {
    private func sine(_ freq: Double, sampleRate: Double = 44_100, count: Int = 4096,
                      amplitude: Float = 0.5) -> [Float] {
        (0..<count).map { amplitude * Float(sin(2 * .pi * freq * Double($0) / sampleRate)) }
    }

    func testDetectsConcertA() throws {
        let f = try XCTUnwrap(TunerEngine.detectPitch(sine(440), sampleRate: 44_100))
        XCTAssertEqual(f, 440, accuracy: 1.0)
    }

    func testDetectsLowEString() throws {
        let f = try XCTUnwrap(TunerEngine.detectPitch(sine(82.41), sampleRate: 44_100))
        XCTAssertEqual(f, 82.41, accuracy: 0.5)
    }

    func testSilenceIsNotANote() {
        XCTAssertNil(TunerEngine.detectPitch([Float](repeating: 0, count: 4096), sampleRate: 44_100))
        XCTAssertNil(TunerEngine.detectPitch(sine(440, amplitude: 0.001), sampleRate: 44_100))
    }

    func testRejectsTooShortOrInvalidInput() {
        XCTAssertNil(TunerEngine.detectPitch(sine(440, count: 512), sampleRate: 44_100))
        XCTAssertNil(TunerEngine.detectPitch(sine(440), sampleRate: 0))
    }

    func testNoteNamesAndCents() {
        let (a4, c0) = TunerEngine.noteInfo(440)
        XCTAssertEqual(a4, "A4")
        XCTAssertEqual(c0, 0, accuracy: 0.01)

        let (c4, _) = TunerEngine.noteInfo(261.63)
        XCTAssertEqual(c4, "C4")

        // 10 cents sharp of A4.
        let (name, cents) = TunerEngine.noteInfo(440 * pow(2, 10.0 / 1200))
        XCTAssertEqual(name, "A4")
        XCTAssertEqual(cents, 10, accuracy: 0.01)
    }

    func testReferencePitchShiftsTheReading() {
        // An orchestra tuned to A = 442: a 440 Hz A reads flat.
        let (name, cents) = TunerEngine.noteInfo(440, referenceA: 442)
        XCTAssertEqual(name, "A4")
        XCTAssertLessThan(cents, -7)
    }

    func testGarbageFrequencyNeverTraps() {
        XCTAssertEqual(TunerEngine.noteInfo(0).0, "—")
        XCTAssertEqual(TunerEngine.noteInfo(-5).0, "—")
        XCTAssertEqual(TunerEngine.noteInfo(.nan).0, "—")
        XCTAssertEqual(TunerEngine.noteInfo(.infinity).0, "—")
    }

    func testSignalPhraseNames() {
        XCTAssertEqual(NoteSignalDetector.name(60), "C4")
        XCTAssertEqual(NoteSignalDetector.name(64), "E4")
        XCTAssertEqual(NoteSignalDetector.phrase([64, 60]), "E4 → C4")
    }
}

final class MetronomeModelTests: XCTestCase {
    func testTempoNamesCoverTheWholeRange() {
        XCTAssertEqual(MetronomeEngine.tempoName(for: 30), "Grave")
        XCTAssertEqual(MetronomeEngine.tempoName(for: 40), "Largo")
        XCTAssertEqual(MetronomeEngine.tempoName(for: 100), "Moderato")
        XCTAssertEqual(MetronomeEngine.tempoName(for: 120), "Allegro")
        XCTAssertEqual(MetronomeEngine.tempoName(for: 260), "Prestissimo")
    }

    func testDefaultAccentsStressEachBeat() {
        let high = MetronomeEngine.ClickLevel.high.rawValue, low = MetronomeEngine.ClickLevel.low.rawValue
        XCTAssertEqual(MetronomeEngine.defaultAccentLevels(beats: 4, sub: 1), [high, high, high, high])
        XCTAssertEqual(MetronomeEngine.defaultAccentLevels(beats: 2, sub: 3), [high, low, low, high, low, low])
        // A nonsense subdivision falls back to one click per beat.
        XCTAssertEqual(MetronomeEngine.defaultAccentLevels(beats: 3, sub: 0).count, 3)
    }
}

/// Who gets the introduction and who gets "What's new" — a newcomer must never
/// be told what changed, and someone who updated must never be re-onboarded.
final class LaunchAudienceTests: XCTestCase {
    private let current = WhatsNewContent.version

    func testFirstLaunchIsANewcomer() {
        XCTAssertEqual(LaunchAudience.resolve(launchCount: 1, hasCompletedOnboarding: false,
                                              lastSeenWhatsNewVersion: nil), .newcomer)
    }

    func testQuittingMidIntroductionShowsItAgain() {
        // First launch marked the card seen silently, but the introduction wasn't finished.
        XCTAssertEqual(LaunchAudience.resolve(launchCount: 2, hasCompletedOnboarding: false,
                                              lastSeenWhatsNewVersion: current), .newcomer)
    }

    func testUpdaterFromBeforeTheIntroductionGetsWhatsNew() {
        XCTAssertEqual(LaunchAudience.resolve(launchCount: 40, hasCompletedOnboarding: false,
                                              lastSeenWhatsNewVersion: nil), .returningNeedsWhatsNew)
    }

    func testUpdaterWithAnOlderCardGetsTheNewOne() {
        XCTAssertEqual(LaunchAudience.resolve(launchCount: 40, hasCompletedOnboarding: true,
                                              lastSeenWhatsNewVersion: "1.0.0"), .returningNeedsWhatsNew)
    }

    func testSeenEverythingGoesStraightIn() {
        XCTAssertEqual(LaunchAudience.resolve(launchCount: 40, hasCompletedOnboarding: true,
                                              lastSeenWhatsNewVersion: current), .returning)
    }

    func testWhatsNewHasContent() {
        XCTAssertFalse(WhatsNewContent.rows.isEmpty)
        XCTAssertEqual(Set(WhatsNewContent.rows.map(\.id)).count, WhatsNewContent.rows.count)
    }
}

final class OperationsTests: XCTestCase {
    func testKillSwitchesDefaultToOn() {
        // A flag the dashboard never set (or a fetch that failed) must read as on.
        let key = "leeo.flag." + NotMyTempoFlag.instrumentSignal.rawValue
        let saved = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(saved, forKey: key) }
        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertTrue(NotMyTempoFlag.instrumentSignal.isEnabled)
        XCTAssertTrue(NoteSignalDetector.isAvailable)

        UserDefaults.standard.set(false, forKey: key)
        XCTAssertFalse(NoteSignalDetector.isAvailable, "the remote switch turns the instrument signal off")
    }

    func testFlagNamesAreStable() {
        // These raw values are CloudKit field names; renaming one disconnects it.
        XCTAssertEqual(NotMyTempoFlag.usageStats.rawValue, "usageStats")
        XCTAssertEqual(NotMyTempoFlag.instrumentSignal.rawValue, "instrumentSignal")
    }
}
