import Foundation
import AVFoundation
import os

private let engineLog = Logger(subsystem: "com.handsfree.metronome", category: "engine")

/// Sample-accurate metronome driven by AVAudioEngine.
/// Generates a short click programmatically — no audio assets required.
final class MetronomeEngine: ObservableObject {
    @Published private(set) var isPlaying = false
    // NOTE: never re-assign these inside their own didSet. They are bound directly
    // to a Slider / segmented Picker, so a self-assignment would publish a change
    // from within a SwiftUI view update ("undefined behavior" → crash/freeze).
    // Range clamping lives in the mutator methods below instead.
    @Published var bpm: Int = 100 {
        didSet {
            UserDefaults.standard.set(bpm, forKey: Self.bpmKey)
            if isPlaying { reschedule() }
        }
    }

    /// How many clicks per beat: 1 = quarter, 2 = eighth, 3 = triplet, 4 = sixteenth.
    @Published var subdivision: Int = 1 {
        didSet {
            UserDefaults.standard.set(subdivision, forKey: Self.subdivisionKey)
            if isPlaying { reschedule() }
        }
    }

    /// Beats per measure (the time-signature numerator). Beat 1 is accented.
    /// Do not re-assign inside didSet (it is bound to a Picker) — clamp in the setter.
    @Published var beatsPerMeasure = 4 {
        didSet {
            UserDefaults.standard.set(beatsPerMeasure, forKey: Self.beatsKey)
            if isPlaying { reschedule() }
        }
    }

    /// Output level for the click, 0…1. Bound to the volume slider; applied straight
    /// to the engine's main mixer so it takes effect immediately, even mid-play.
    /// Do not re-assign inside didSet (it is bound to a Slider) — clamp in the setter.
    @Published var volume: Float = 1.0 {
        didSet {
            UserDefaults.standard.set(volume, forKey: Self.volumeKey)
            engine.mainMixerNode.outputVolume = volume
        }
    }

    /// The largest time-signature numerator the app supports. Kept here so the UI and
    /// the engine agree on the same ceiling (the dot grid lays out up to this many).
    static let maxBeatsPerMeasure = 8

    // MARK: Speed trainer — automatically climb the tempo as you practise, so you
    // can drill a passage a little faster every few bars without touching anything.
    @Published private(set) var speedTrainerOn = false
    @Published var trainerStep = 5 {  // BPM added at each step
        didSet { UserDefaults.standard.set(trainerStep, forKey: Self.trainerStepKey) }
    }
    @Published var trainerBars = 4 {  // measures played between steps
        didSet { UserDefaults.standard.set(trainerBars, forKey: Self.trainerBarsKey) }
    }
    @Published var trainerTarget = 160 {  // stop climbing once we reach this BPM
        didSet { UserDefaults.standard.set(trainerTarget, forKey: Self.trainerTargetKey) }
    }
    /// Measures completed since the last automatic step. Only touched on `timerQueue`.
    private var measuresSinceStep = 0

    private static let bpmKey = "metronome.bpm"
    private static let subdivisionKey = "metronome.subdivision"
    private static let beatsKey = "metronome.beatsPerMeasure"
    private static let volumeKey = "metronome.volume"
    private static let trainerStepKey = "metronome.trainerStep"
    private static let trainerBarsKey = "metronome.trainerBars"
    private static let trainerTargetKey = "metronome.trainerTarget"

    /// Fires on the main thread on each beat (quarter note), passing the beat's
    /// index within the measure (0 = downbeat). Used to animate the UI.
    var onBeat: ((Int) -> Void)?

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var accentClick: AVAudioPCMBuffer?  // measure downbeat (beat 1)
    private var beatClick: AVAudioPCMBuffer?    // other beats
    private var subClick: AVAudioPCMBuffer?     // subdivisions between beats
    private let sampleRate: Double = 44_100
    private var beatTimer: DispatchSourceTimer?
    /// Serial queue so that when we swap timers (tempo/subdivision change) the old
    /// and new handlers never run concurrently and double-call the audio player.
    private let timerQueue = DispatchQueue(label: "com.handsfree.metronome.timer",
                                           qos: .userInteractive)
    private var tick = 0 // position counter — only touched on timerQueue

    init() {
        // Restore the last-used settings (default 100 BPM, 4/4, quarters on first run).
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.bpmKey) != nil {
            bpm = clampBPM(defaults.integer(forKey: Self.bpmKey))
        }
        if defaults.object(forKey: Self.subdivisionKey) != nil {
            subdivision = min(4, max(1, defaults.integer(forKey: Self.subdivisionKey)))
        }
        if defaults.object(forKey: Self.beatsKey) != nil {
            beatsPerMeasure = min(Self.maxBeatsPerMeasure, max(1, defaults.integer(forKey: Self.beatsKey)))
        }
        if defaults.object(forKey: Self.volumeKey) != nil {
            volume = min(1, max(0, defaults.float(forKey: Self.volumeKey)))
        }
        if defaults.object(forKey: Self.trainerStepKey) != nil {
            trainerStep = min(20, max(1, defaults.integer(forKey: Self.trainerStepKey)))
        }
        if defaults.object(forKey: Self.trainerBarsKey) != nil {
            trainerBars = min(16, max(1, defaults.integer(forKey: Self.trainerBarsKey)))
        }
        if defaults.object(forKey: Self.trainerTargetKey) != nil {
            trainerTarget = clampBPM(defaults.integer(forKey: Self.trainerTargetKey))
        }
        configureSession()
        // Clean, pure-tone clicks. Distinct pitches mark accent / beat / subdivision.
        accentClick = makeClick(freq: 2000, volume: 1.0)
        beatClick = makeClick(freq: 1500, volume: 0.9)
        subClick = makeClick(freq: 1000, volume: 0.7)
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: accentClick?.format)
        engine.mainMixerNode.outputVolume = volume   // honour the saved level
    }

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        // .playAndRecord lets the click coexist with speech recognition.
        do {
            try session.setCategory(.playAndRecord,
                                    mode: .default,
                                    options: [.mixWithOthers, .defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
        } catch {
            // Non-fatal: the click may be quieter or route oddly, but the app still
            // runs. Surface it in the log so a silent-metronome report is diagnosable.
            engineLog.error("Audio session setup failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// A clean pitched click: a pure sine with a smooth attack and a decay that
    /// fully settles to silence inside the buffer. The soft edges are what keep it
    /// "clean" — an abrupt onset or a tone cut off mid-swing adds an audible pop.
    private func makeClick(freq: Double, volume: Float) -> AVAudioPCMBuffer? {
        let duration = 0.040                         // 40 ms — room for the tone to die away
        let frames = AVAudioFrameCount(sampleRate * duration)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buffer.frameLength = frames
        let ptr = buffer.floatChannelData![0]
        let n = Int(frames)
        let attack = 0.0015 * sampleRate             // 1.5 ms fade-in kills the onset click
        let release = 0.004 * sampleRate             // 4 ms fade-out guarantees a silent tail
        for i in 0..<n {
            let t = Double(i) / sampleRate
            let atk = min(1.0, Double(i) / attack)                 // ramp up
            let rel = min(1.0, Double(n - i) / release)            // ramp down at the very end
            let decay = exp(-t * 150.0)                            // near-zero (~0.01) by ~30 ms
            let sample = sin(2 * .pi * freq * t) * atk * decay * rel
            ptr[i] = Float(sample) * volume
        }
        return buffer
    }

    func toggle() { isPlaying ? stop() : start() }

    func start() {
        guard !isPlaying else { return }
        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                // The graph couldn't start (e.g. an interruption is in flight).
                // Bail cleanly rather than flipping to a "playing" state with no sound.
                engineLog.error("Audio engine start failed: \(error.localizedDescription, privacy: .public)")
                return
            }
        }
        player.play()
        isPlaying = true
        tick = 0
        startTimer()
    }

    func stop() {
        guard isPlaying else { return }
        isPlaying = false
        beatTimer?.cancel()
        beatTimer = nil
        player.stop()
        // Release the audio render pipeline while paused so an idle metronome
        // doesn't keep the audio thread (and CPU) spinning. start() restarts it.
        engine.stop()
    }

    /// Tempo/subdivision changed mid-play: just retune the ONE running timer.
    /// We never create a second timer, so the audio player is only ever driven
    /// from a single serialized place — no concurrent access, no crash/freeze.
    private func reschedule() {
        guard let timer = beatTimer else { return }
        timer.schedule(deadline: .now(), repeating: currentInterval())
        timerQueue.async { [weak self] in self?.tick = 0 } // realign to a downbeat
    }

    private func currentInterval() -> Double {
        60.0 / Double(bpm) / Double(max(1, subdivision))
    }

    private func startTimer() {
        let timer = DispatchSource.makeTimerSource(queue: timerQueue)
        timer.schedule(deadline: .now(), repeating: currentInterval())
        timer.setEventHandler { [weak self] in self?.fireTick() }
        timer.resume()
        beatTimer = timer
    }

    /// Always runs on `timerQueue`.
    private func fireTick() {
        guard isPlaying else { return }
        let sub = max(1, subdivision)
        let ticksPerMeasure = beatsPerMeasure * sub
        let pos = tick % ticksPerMeasure
        let isBeat = pos % sub == 0          // a quarter-note pulse
        let isDownbeat = pos == 0            // beat 1 of the measure
        let buffer = isDownbeat ? accentClick
                   : isBeat     ? beatClick
                   :              subClick
        if let buffer {
            player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        }
        if isBeat {
            let beatIndex = pos / sub   // 0..<beatsPerMeasure
            DispatchQueue.main.async { [weak self] in self?.onBeat?(beatIndex) }
        }
        // Speed trainer: once a whole measure completes, count it; step the tempo
        // when enough bars have gone by. `tick != 0` skips the very first downbeat.
        if speedTrainerOn && isDownbeat && tick != 0 {
            measuresSinceStep += 1
            if measuresSinceStep >= max(1, trainerBars) {
                measuresSinceStep = 0
                DispatchQueue.main.async { [weak self] in self?.applyTrainerStep() }
            }
        }
        tick += 1
    }

    /// Raise (or lower) the tempo by one trainer step, stopping at the target.
    private func applyTrainerStep() {
        guard speedTrainerOn else { return }
        let next = clampBPM(bpm + trainerStep)
        let reached = trainerStep >= 0 ? next >= trainerTarget : next <= trainerTarget
        if reached {
            setTempo(trainerTarget)   // land exactly on the goal…
            speedTrainerOn = false    // …then stop climbing
        } else {
            setTempo(next)
        }
    }

    func setSpeedTrainer(_ on: Bool) {
        speedTrainerOn = on
        timerQueue.async { [weak self] in self?.measuresSinceStep = 0 }
    }
    func toggleSpeedTrainer() { setSpeedTrainer(!speedTrainerOn) }

    // MARK: Tempo helpers — clamp here so the @Published setters never re-assign.
    func nudge(_ delta: Int) { bpm = clampBPM(bpm + delta) }
    func setTempo(_ value: Int) { bpm = clampBPM(value) }
    func doubleTempo() { bpm = clampBPM(bpm * 2) }
    func halfTempo() { bpm = clampBPM(bpm / 2) }
    func setSubdivision(_ value: Int) { subdivision = min(4, max(1, value)) }
    func setBeatsPerMeasure(_ n: Int) { beatsPerMeasure = min(Self.maxBeatsPerMeasure, max(1, n)) }
    func setVolume(_ value: Float) { volume = min(1, max(0, value)) }

    private func clampBPM(_ value: Int) -> Int { min(260, max(30, value)) }

    static func subdivisionName(for value: Int) -> String {
        switch value {
        case 2: return "Eighths"
        case 3: return "Triplets"
        case 4: return "Sixteenths"
        default: return "Quarters"
        }
    }

    static func tempoName(for bpm: Int) -> String {
        switch bpm {
        case ..<40: return "Grave"
        case 40..<52: return "Largo"
        case 52..<66: return "Adagio"
        case 66..<76: return "Andante"
        case 76..<108: return "Moderato"
        case 108..<132: return "Allegro"
        case 132..<168: return "Vivace"
        case 168..<200: return "Presto"
        default: return "Prestissimo"
        }
    }
}

/// A short two-note chime ("뾰롱") played to confirm a recognized voice command.
/// The sound is generated in memory (no audio file) and played via AVAudioPlayer,
/// which mixes over the click and the mic without touching the metronome engine.
final class FeedbackSound {
    static let shared = FeedbackSound()
    private let player: AVAudioPlayer?

    private init() {
        if let data = FeedbackSound.makeChime() {
            player = try? AVAudioPlayer(data: data)
            player?.volume = 0.55
            player?.prepareToPlay()
        } else {
            player = nil
        }
    }

    func play() {
        guard let player else { return }
        player.currentTime = 0
        player.play()
    }

    /// Two quick ascending sine notes with a fast decay → a light "ploong".
    private static func makeChime() -> Data? {
        let sr = 44_100.0
        let notes: [(freq: Double, dur: Double, decay: Double)] = [
            (987.77, 0.07, 26),   // B5
            (1318.51, 0.16, 12)   // E6
        ]
        var samples: [Int16] = []
        for note in notes {
            let count = Int(note.dur * sr)
            for k in 0..<count {
                let t = Double(k) / sr
                let env = exp(-t * note.decay)
                let value = sin(2 * .pi * note.freq * t) * env * 0.5
                samples.append(Int16(max(-1, min(1, value)) * 32_767))
            }
        }
        return wav(samples: samples, sampleRate: Int(sr))
    }

    private static func wav(samples: [Int16], sampleRate: Int) -> Data {
        let channels = 1, bits = 16
        let dataSize = samples.count * bits / 8
        var d = Data()
        func str(_ s: String) { d.append(s.data(using: .ascii)!) }
        func u32(_ v: UInt32) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: UInt16) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 2)) }
        str("RIFF"); u32(UInt32(36 + dataSize)); str("WAVE")
        str("fmt "); u32(16); u16(1); u16(UInt16(channels))
        u32(UInt32(sampleRate)); u32(UInt32(sampleRate * channels * bits / 8))
        u16(UInt16(channels * bits / 8)); u16(UInt16(bits))
        str("data"); u32(UInt32(dataSize))
        samples.withUnsafeBufferPointer { d.append(Data(buffer: $0)) }
        return d
    }
}
