import Foundation
import SwiftUI

// MARK: - One timed practice run

/// The tempo over one practice-timer run: a point each time the tempo changed,
/// plus one at the very end. `second` counts playing time only — a pause stops
/// the clock just as it stops the countdown.
struct PracticeSession: Codable, Identifiable, Equatable {
    struct Point: Codable, Equatable {
        var second: Double
        var bpm: Int
    }

    var id = UUID()
    var date: Date
    var seconds: Double
    var points: [Point]

    var report: PracticeReport { PracticeReport(self) }
}

// MARK: - What the run says

/// Reads a run the way a teacher would: where it started and ended, the top speed
/// and how long it was held, where the climb got stuck or backed off, and a tempo
/// to start from next time. Pure — every rule is tested in `PracticeReportTests`.
struct PracticeReport: Equatable {
    /// A stretch at one tempo.
    struct Hold: Equatable {
        let bpm: Int
        let start: Double
        let seconds: Double
    }

    /// A tempo the climb didn't get past easily.
    struct Wall: Equatable, Identifiable {
        enum Kind: Equatable { case stuck, backedOff }
        let kind: Kind
        let hold: Hold
        var id: Double { hold.start }
    }

    /// Why `nextStart` is what it is.
    enum Advice: Equatable { case warmUpToWall, halfway, stepUp }

    let holds: [Hold]
    let startBPM: Int
    let endBPM: Int
    let peakBPM: Int
    /// Total time spent at `peakBPM`.
    let peakSeconds: Double
    let walls: [Wall]
    let nextStart: Int
    let advice: Advice

    /// A stretch must be held at least this long to count as stuck — and twice
    /// as long as a typical step of the run.
    static let stuckMinimum: Double = 60

    init(_ session: PracticeSession) {
        // Consecutive points at one tempo are one hold; the last point only marks the end.
        var holds: [Hold] = []
        let points = session.points.sorted { $0.second < $1.second }
        for (i, p) in points.enumerated() {
            let end = i + 1 < points.count ? points[i + 1].second : session.seconds
            let length = max(0, end - p.second)
            if let last = holds.last, last.bpm == p.bpm {
                holds[holds.count - 1] = Hold(bpm: last.bpm, start: last.start, seconds: last.seconds + length)
            } else if length > 0 || holds.isEmpty {
                holds.append(Hold(bpm: p.bpm, start: p.second, seconds: length))
            }
        }
        // Passing over a tempo while dragging the slider is not playing it.
        let played = holds.filter { $0.seconds >= 2 }
        let steps = played.isEmpty ? holds : played
        self.holds = holds

        startBPM = steps.first?.bpm ?? 0
        endBPM = steps.last?.bpm ?? 0
        let peak = steps.map(\.bpm).max() ?? 0
        peakBPM = peak
        peakSeconds = steps.filter { $0.bpm == peak }.reduce(0) { $0 + $1.seconds }

        // Stuck: far longer than a typical step, below the top speed (holding the top
        // speed is the goal, not a wall), and moved on from — the last stretch just
        // ends with the timer. Backed off: the next tempo was slower.
        let lengths = steps.map(\.seconds).sorted()
        let typical = lengths.isEmpty ? 0 : lengths[lengths.count / 2]
        var walls: [Wall] = []
        for (i, hold) in steps.enumerated() {
            if i + 1 < steps.count, steps[i + 1].bpm < hold.bpm {
                walls.append(Wall(kind: .backedOff, hold: hold))
            } else if steps.count >= 3, i + 1 < steps.count, hold.bpm < peak,
                      hold.seconds >= max(Self.stuckMinimum, typical * 2) {
                walls.append(Wall(kind: .stuck, hold: hold))
            }
        }
        self.walls = walls

        // Next time: warm up to the first wall; after a clean climb, start halfway
        // up it; after one steady tempo, one step faster.
        if let wall = walls.first {
            nextStart = Self.round5(max(steps.map(\.bpm).min() ?? wall.hold.bpm, wall.hold.bpm - 10))
            advice = .warmUpToWall
        } else if peak > startBPM {
            nextStart = Self.round5(startBPM + (peak - startBPM) / 2)
            advice = .halfway
        } else {
            nextStart = Self.round5(startBPM + 5)
            advice = .stepUp
        }
    }

    /// To the nearest 5 BPM — an easy number to remember — inside the metronome's range.
    static func round5(_ bpm: Int) -> Int {
        min(260, max(30, Int((Double(bpm) / 5).rounded()) * 5))
    }
}

// MARK: - Saved runs

/// The runs the player chose to keep, newest first. On this device only.
@MainActor
final class PracticeLog: ObservableObject {
    static let shared = PracticeLog()

    @Published private(set) var sessions: [PracticeSession] = []

    private static let key = "practice.log"
    /// Enough for a long history; each run is a few hundred bytes.
    private static let limit = 300

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([PracticeSession].self, from: data) {
            sessions = saved
        }
    }

    func isSaved(_ session: PracticeSession) -> Bool { sessions.contains { $0.id == session.id } }

    func save(_ session: PracticeSession) {
        guard !isSaved(session) else { return }
        sessions.insert(session, at: 0)
        if sessions.count > Self.limit { sessions.removeLast(sessions.count - Self.limit) }
        persist()
    }

    func delete(at offsets: IndexSet) {
        sessions.remove(atOffsets: offsets)
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(sessions) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
