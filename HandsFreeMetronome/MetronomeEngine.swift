import Foundation
import AVFoundation

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

    private static let bpmKey = "metronome.bpm"
    private static let subdivisionKey = "metronome.subdivision"
    private static let beatsKey = "metronome.beatsPerMeasure"

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
            beatsPerMeasure = min(12, max(1, defaults.integer(forKey: Self.beatsKey)))
        }
        configureSession()
        accentClick = makeClick(freq: 2000, volume: 1.0)
        beatClick = makeClick(freq: 1500, volume: 0.8)
        subClick = makeClick(freq: 1000, volume: 0.55)
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: accentClick?.format)
    }

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        // .playAndRecord lets the click coexist with speech recognition.
        try? session.setCategory(.playAndRecord,
                                 mode: .default,
                                 options: [.mixWithOthers, .defaultToSpeaker, .allowBluetooth])
        try? session.setActive(true)
    }

    /// A short pitched click. Higher freq + louder = stronger accent.
    private func makeClick(freq: Double, volume: Float) -> AVAudioPCMBuffer? {
        let frames = AVAudioFrameCount(sampleRate * 0.028) // 28 ms click — crisp even for fast 1/16
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buffer.frameLength = frames
        let ptr = buffer.floatChannelData![0]
        for i in 0..<Int(frames) {
            let t = Double(i) / sampleRate
            let envelope = exp(-t * 70.0)            // fast decay so clicks don't blur together
            ptr[i] = Float(sin(2 * .pi * freq * t) * envelope) * volume
        }
        return buffer
    }

    func toggle() { isPlaying ? stop() : start() }

    func start() {
        guard !isPlaying else { return }
        if !engine.isRunning { try? engine.start() }
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
        tick += 1
    }

    // MARK: Tempo helpers — clamp here so the @Published setters never re-assign.
    func nudge(_ delta: Int) { bpm = clampBPM(bpm + delta) }
    func setTempo(_ value: Int) { bpm = clampBPM(value) }
    func doubleTempo() { bpm = clampBPM(bpm * 2) }
    func halfTempo() { bpm = clampBPM(bpm / 2) }
    func setSubdivision(_ value: Int) { subdivision = min(4, max(1, value)) }
    func setBeatsPerMeasure(_ n: Int) { beatsPerMeasure = min(12, max(1, n)) }

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
