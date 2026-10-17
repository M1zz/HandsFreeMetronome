import Foundation
import AVFoundation

/// Chromatic tuner. It does NOT open its own microphone — it is fed the mic
/// buffers that VoiceController already captures, then estimates pitch (YIN-style
/// difference function) and maps it to the nearest note + cents offset.
final class TunerEngine: ObservableObject {

    @Published private(set) var active = false
    @Published private(set) var noteName = "—"
    @Published private(set) var cents = 0.0
    @Published private(set) var frequency = 0.0

    /// Concert-pitch reference for A4 (440 standard; 442 for many orchestras,
    /// 432 for some players). Persisted; the analysis queue reads its own copy.
    static let referenceRange = 430...450
    private static let referenceKey = "tunerReferenceA"
    @Published var referenceA: Int {
        didSet {
            let clamped = min(max(referenceA, Self.referenceRange.lowerBound), Self.referenceRange.upperBound)
            if clamped != referenceA { referenceA = clamped; return }
            UserDefaults.standard.set(referenceA, forKey: Self.referenceKey)
            let ref = Double(referenceA)
            analysisQueue.async { [weak self] in self?.analysisRef = ref }
        }
    }
    private var analysisRef: Double       // touched only on analysisQueue

    private let analysisQueue = DispatchQueue(label: "com.handsfree.tuner", qos: .userInitiated)
    private var window: [Float] = []
    private let windowSize = 4096        // larger window = steadier pitch, calmer readout
    private var smoothedFreq: Double = 0 // touched only on analysisQueue

    init() {
        let saved = UserDefaults.standard.integer(forKey: Self.referenceKey)
        let ref = Self.referenceRange.contains(saved) ? saved : 440
        referenceA = ref
        analysisRef = Double(ref)
    }

    func start() {
        active = true
        noteName = "—"; cents = 0; frequency = 0
        analysisQueue.async { [weak self] in
            self?.window.removeAll(keepingCapacity: true)
            self?.smoothedFreq = 0
        }
    }

    func stop() {
        active = false
        analysisQueue.async { [weak self] in
            self?.window.removeAll(keepingCapacity: true)
            self?.smoothedFreq = 0
        }
    }

    /// Fed from VoiceController's mic tap (runs on the audio thread).
    func process(_ buffer: AVAudioPCMBuffer) {
        guard active, let ch = buffer.floatChannelData?[0] else { return }
        let n = Int(buffer.frameLength)
        let sr = buffer.format.sampleRate
        var samples = [Float](repeating: 0, count: n)
        for i in 0..<n { samples[i] = ch[i] }

        analysisQueue.async { [weak self] in
            guard let self, self.active else { return }
            self.window.append(contentsOf: samples)
            guard self.window.count >= self.windowSize else { return }
            let frame = Array(self.window.suffix(self.windowSize))
            self.window.removeAll(keepingCapacity: true)

            // The YIN pass is the tuner's hot loop — it must finish well inside
            // one window (~93 ms at 44.1 kHz) or the readout starts to lag.
            let state = Perf.signposter.beginInterval("Tuner pitch")
            let detected = TunerEngine.detectPitch(frame, sampleRate: sr)
            Perf.signposter.endInterval("Tuner pitch", state)
            guard let f = detected else { return }
            // Smooth within a note for a calm readout, but jump when the note
            // changes (more than ~半음 away) so switching strings is responsive.
            if self.smoothedFreq <= 0 || abs(1200 * log2(f / self.smoothedFreq)) > 80 {
                self.smoothedFreq = f
            } else {
                self.smoothedFreq += 0.18 * (f - self.smoothedFreq)
            }
            let sf = self.smoothedFreq
            let (name, cents) = TunerEngine.noteInfo(sf, referenceA: self.analysisRef)
            DispatchQueue.main.async {
                guard self.active else { return }
                self.frequency = sf; self.noteName = name; self.cents = cents
            }
        }
    }

    // MARK: Pitch detection (simplified YIN)

    static func detectPitch(_ x: [Float], sampleRate: Double) -> Double? {
        let n = x.count
        guard n > 1024, sampleRate > 0 else { return nil }

        // Ignore silence.
        var energy: Float = 0
        for v in x { energy += v * v }
        if sqrtf(energy / Float(n)) < 0.012 { return nil }

        let minF = 50.0, maxF = 1000.0
        let minLag = max(2, Int(sampleRate / maxF))
        let maxLag = min(n - 1, Int(sampleRate / minF))
        guard maxLag > minLag else { return nil }

        // Difference function d(lag).
        let m = n - maxLag
        var d = [Float](repeating: 0, count: maxLag + 1)
        for lag in minLag...maxLag {
            var sum: Float = 0
            var i = 0
            while i < m { let diff = x[i] - x[i + lag]; sum += diff * diff; i += 1 }
            d[lag] = sum
        }

        // Cumulative mean normalized difference.
        var cmnd = [Float](repeating: 1, count: maxLag + 1)
        var running: Float = 0
        for lag in minLag...maxLag {
            running += d[lag]
            cmnd[lag] = running > 0 ? d[lag] * Float(lag - minLag + 1) / running : 1
        }

        // First dip below threshold (refined to a local minimum); else global min.
        let threshold: Float = 0.15
        var tau = -1
        var lag = minLag
        while lag <= maxLag {
            if cmnd[lag] < threshold {
                while lag + 1 <= maxLag && cmnd[lag + 1] < cmnd[lag] { lag += 1 }
                tau = lag; break
            }
            lag += 1
        }
        if tau < 0 {
            var best: Float = .greatestFiniteMagnitude
            for l in minLag...maxLag where cmnd[l] < best { best = cmnd[l]; tau = l }
        }
        guard tau > 0 else { return nil }

        // Parabolic interpolation around tau for sub-sample accuracy.
        var period = Double(tau)
        if tau > minLag && tau < maxLag {
            let a = d[tau - 1], b = d[tau], c = d[tau + 1]
            let denom = a + c - 2 * b
            if denom != 0 { period += Double((a - c) / (2 * denom)) }
        }

        let freq = sampleRate / period
        return (freq.isFinite && freq > minF && freq < maxF) ? freq : nil
    }

    static func noteInfo(_ freq: Double, referenceA: Double = 440) -> (String, Double) {
        // log2 of a non-positive frequency is NaN/-inf, and Int(NaN) below would
        // trap. detectPitch already filters, but never trust the input here.
        guard freq.isFinite, freq > 0, referenceA > 0 else { return ("—", 0) }
        let names = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
        let midi = 69 + 12 * log2(freq / referenceA)
        guard midi.isFinite else { return ("—", 0) }
        let nearest = midi.rounded()
        let cents = (midi - nearest) * 100
        let idx = ((Int(nearest) % 12) + 12) % 12
        let octave = Int(nearest) / 12 - 1
        return ("\(names[idx])\(octave)", cents)
    }
}
