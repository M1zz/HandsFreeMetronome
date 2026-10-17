import Foundation
import os
import LeeoKit

// MARK: - Remote kill switch

/// Features that can be switched off from the CloudKit dashboard without an
/// App Review round-trip (record type `RemoteFlags`, record
/// `flags_com.leeo.HandsFreeMetronome`, one Int64 field per case: 1 on, 0 off).
///
/// ⚠️ The raw value IS the CloudKit field name — renaming a case silently
///    disconnects it from the dashboard. A missing field or a failed fetch
///    means "on", so the switch can never become the outage.
enum NotMyTempoFlag: String, LeeoRemoteFlag, CaseIterable {
    /// Anonymous usage statistics + crash diagnostics to FeedbackHub.
    /// Off → nothing leaves the device, same as the user's own opt-out.
    case usageStats
    /// "Start / stop with my instrument". The detector listens to the live mic
    /// feed during practice; if a release makes it misfire (stopping people
    /// mid-song) it can be turned off for everyone while a fix ships.
    case instrumentSignal

    var isEnabled: Bool { LeeoRemoteFlags.isEnabled(self) }
}

// MARK: - Crash-loop guard

/// Notices when the app dies before its first screen settles on two launches
/// in a row, and opens the next launch in **safe mode**: no TipKit datastore,
/// and the microphone / speech recognizer is not started automatically. Those
/// are the two pieces of start-up work that touch on-disk state and system
/// audio — the likely places for a launch-time crash to live.
///
/// A launch counts as successful once the main screen has stayed up for a few
/// seconds (`markLaunchSucceeded()` from `ContentView`). The launch after a
/// successful safe-mode launch is normal again.
enum LaunchGuard {
    static let crashGuard = LeeoCrashLoopGuard(name: "app", defaults: .standard)

    /// Decided once per process by `begin()`.
    private(set) static var isSafeMode = false

    /// Call first thing in `App.init()`.
    static func begin() {
        isSafeMode = crashGuard.beginLaunch()
        if isSafeMode {
            Log.app.error("Safe mode: the last launches did not finish — skipping tips and auto-listen")
        }
    }

    /// Call when the first screen is on display.
    static func markLaunchSucceeded() {
        crashGuard.markLaunchSucceededAfterSurvivalDelay()
    }
}

// MARK: - Logging & signposts

enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.leeo.HandsFreeMetronome"
    static let app = Logger(subsystem: subsystem, category: "app")
    static let audio = Logger(subsystem: subsystem, category: "audio")
}

/// Intervals for the work that has to keep up with real time — visible in
/// Instruments' "Points of Interest" lane, free when nobody is recording.
enum Perf {
    static let signposter = OSSignposter(subsystem: Bundle.main.bundleIdentifier ?? "com.leeo.HandsFreeMetronome",
                                         category: .pointsOfInterest)
}
