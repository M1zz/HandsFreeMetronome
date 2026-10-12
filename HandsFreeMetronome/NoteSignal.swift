import Foundation
import AVFoundation

/// Start / stop the metronome by playing a short phrase on your own instrument
/// (e.g. E4 → C4). Like the tuner it does NOT open a microphone — it is fed the
/// buffers VoiceController already captures, so it works while Listen is on.
///
/// A note only counts once it has been HELD for `holdTime`, and consecutive notes
/// must start within `maxGap` of each other. Quick passing notes in a song never
/// qualify, which is what keeps ordinary playing from firing the signal.
final class NoteSignalDetector: ObservableObject {

    enum Mode: Equatable { case idle, recording }

    /// Signal on / off. Persisted.
    @Published var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
            sync()
        }
    }
    /// The saved phrase as MIDI note numbers (empty = not recorded yet). Persisted.
    @Published private(set) var pattern: [Int]
    @Published private(set) var mode: Mode = .idle
    /// Notes captured so far while recording.
    @Published private(set) var recorded: [Int] = []

    /// Fired on the main thread when the saved phrase is played.
    var onTrigger: (() -> Void)?

    static let holdTime = 0.3        // seconds a note must ring to count
    static let maxGap = 1.8          // onset → next onset (0.3 s hold + 1.5 s pause)
    static let minNotes = 2
    static let maxNotes = 5
    private static let finishAfter = 2.0   // recording ends after this much quiet
    private static let cooldown = 1.0      // ignore notes right after a trigger
    private static let enabledKey = "noteSignal.enabled"
    private static let patternKey = "noteSignal.pattern"

    private let analysisQueue = DispatchQueue(label: "com.handsfree.notesignal", qos: .userInitiated)
    private let frameSize = 2048

    // Everything below is touched only on analysisQueue.
    private var window: [Float] = []
    private var clock = 0.0                  // seconds of audio analysed so far
    private var candidate: Int?              // note currently ringing
    private var candidateStart = 0.0
    private var candidateEmitted = false
    private var missedFrames = 0             // tolerate a dropped frame inside a note
    private var heard: [(note: Int, onset: Double)] = []
    private var quietUntil = 0.0
    private var lastRecordedAt = 0.0
    private var target: [Int] = []           // mirror of `pattern`
    private var listening = false            // enabled && !suspended
    private var isRecording = false
    private var suspended = false

    init() {
        let defaults = UserDefaults.standard
        enabled = defaults.bool(forKey: Self.enabledKey)
        let stored = (defaults.array(forKey: Self.patternKey) as? [Int]) ?? []
        pattern = stored.count >= Self.minNotes ? stored : []
        sync()
    }

    // MARK: Control (main thread)

    /// Pause analysis while the tuner is open — tuning a string must not fire it.
    func setSuspended(_ value: Bool) {
        analysisQueue.async { [weak self] in
            self?.suspended = value
            self?.resetTracking()
        }
    }

    func startRecording() {
        recorded = []
        mode = .recording
        analysisQueue.async { [weak self] in
            guard let self else { return }
            self.isRecording = true
            self.lastRecordedAt = self.clock
            self.resetTracking()
        }
    }

    func cancelRecording() {
        mode = .idle
        recorded = []
        analysisQueue.async { [weak self] in
            self?.isRecording = false
            self?.resetTracking()
        }
    }

    /// Keep what was played (if long enough) and go back to listening.
    func finishRecording() {
        guard mode == .recording else { return }
        if recorded.count >= Self.minNotes {
            pattern = recorded
            UserDefaults.standard.set(pattern, forKey: Self.patternKey)
            if !enabled { enabled = true }   // recording one means you want it on
        }
        mode = .idle
        recorded = []
        analysisQueue.async { [weak self] in
            self?.isRecording = false
            self?.resetTracking()
        }
        sync()
    }

    private func sync() {
        let on = enabled && !pattern.isEmpty
        let notes = pattern
        analysisQueue.async { [weak self] in
            self?.listening = on
            self?.target = notes
            self?.resetTracking()
        }
    }

    // MARK: Analysis

    /// Fed from VoiceController's mic tap (runs on the audio thread).
    func process(_ buffer: AVAudioPCMBuffer) {
        guard let ch = buffer.floatChannelData?[0] else { return }
        let n = Int(buffer.frameLength)
        let sr = buffer.format.sampleRate
        guard n > 0, sr > 0 else { return }
        let samples = Array(UnsafeBufferPointer(start: ch, count: n))
        analysisQueue.async { [weak self] in
            guard let self, !self.suspended, self.listening || self.isRecording else { return }
            self.window.append(contentsOf: samples)
            while self.window.count >= self.frameSize {
                let frame = Array(self.window.prefix(self.frameSize))
                self.window.removeFirst(self.frameSize)
                self.clock += Double(self.frameSize) / sr
                self.analyse(frame, sampleRate: sr)
            }
        }
    }

    private func analyse(_ frame: [Float], sampleRate: Double) {
        let note = TunerEngine.detectPitch(frame, sampleRate: sampleRate).map(Self.midi)

        if isRecording, recorded.count >= Self.minNotes, clock - lastRecordedAt > Self.finishAfter {
            DispatchQueue.main.async { [weak self] in self?.finishRecording() }
            isRecording = false   // don't queue the finish twice
            return
        }

        guard let note else {
            // One empty frame (~45 ms) can be a dip inside a ringing note; two end it.
            missedFrames += 1
            if missedFrames > 1 { candidate = nil }
            return
        }
        missedFrames = 0
        if note != candidate {
            candidate = note
            candidateStart = clock
            candidateEmitted = false
            return
        }
        guard !candidateEmitted, clock - candidateStart >= Self.holdTime else { return }
        candidateEmitted = true
        held(note, onset: candidateStart)
    }

    private func held(_ note: Int, onset: Double) {
        if isRecording {
            lastRecordedAt = clock
            DispatchQueue.main.async { [weak self] in
                guard let self, self.mode == .recording, self.recorded.count < Self.maxNotes else { return }
                self.recorded.append(note)
                if self.recorded.count == Self.maxNotes { self.finishRecording() }
            }
            return
        }
        guard onset >= quietUntil, !target.isEmpty else { return }
        if let last = heard.last, onset - last.onset > Self.maxGap { heard.removeAll() }
        heard.append((note, onset))
        if heard.count > Self.maxNotes { heard.removeFirst() }
        guard heard.count >= target.count,
              heard.suffix(target.count).map(\.note) == target else { return }
        heard.removeAll()
        quietUntil = clock + Self.cooldown
        DispatchQueue.main.async { [weak self] in self?.onTrigger?() }
    }

    private func resetTracking() {
        window.removeAll(keepingCapacity: true)
        candidate = nil
        candidateEmitted = false
        missedFrames = 0
        heard.removeAll()
    }

    // MARK: Names

    private static func midi(_ freq: Double) -> Int {
        Int((69 + 12 * log2(freq / 440)).rounded())
    }

    /// "E4" for MIDI 64.
    static func name(_ note: Int) -> String {
        let names = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
        return "\(names[((note % 12) + 12) % 12])\(note / 12 - 1)"
    }

    static func phrase(_ notes: [Int]) -> String {
        notes.map(name).joined(separator: " → ")
    }
}
