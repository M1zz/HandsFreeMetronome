import Foundation
import AVFoundation

/// Listens to music through the mic for a few seconds and estimates its tempo.
/// Approach: build an energy envelope from the input, derive an onset-strength
/// signal (half-wave rectified flux), then autocorrelate it to find the dominant
/// beat period. Octave ambiguity (half/double tempo) is folded into a musical range.
final class TempoDetector: ObservableObject {

    enum State: Equatable {
        case idle
        case listening
        case result(Int)
        case failed
        case denied
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var progress: Double = 0   // 0…1 while listening

    var isRunning: Bool { state == .listening }

    private let engine = AVAudioEngine()
    private let hop = 512                  // samples per envelope frame
    private let captureSeconds: Double = 8
    private var envelope: [Float] = []
    private var carry: [Float] = []        // leftover samples between buffers
    private var envelopeRate: Double = 0
    private var targetCount = 0
    private var capturing = false          // touched only on the audio tap thread

    // MARK: Control

    func toggle() { isRunning ? cancel() : start() }

    func start() {
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                guard let self else { return }
                granted ? self.begin() : (self.state = .denied)
            }
        }
    }

    func cancel() {
        teardown()
        state = .idle
        progress = 0
    }

    private func begin() {
        envelope.removeAll(keepingCapacity: true)
        carry.removeAll(keepingCapacity: true)
        progress = 0

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { state = .failed; return }
        envelopeRate = format.sampleRate / Double(hop)
        targetCount = Int(captureSeconds * envelopeRate)

        input.removeTap(onBus: 0)
        capturing = true
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            self?.process(buffer)
        }
        engine.prepare()
        do { try engine.start() } catch { capturing = false; state = .failed; return }
        state = .listening
    }

    private func teardown() {
        capturing = false
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
    }

    // MARK: Capture — runs on the audio tap thread (serialized).

    private func process(_ buffer: AVAudioPCMBuffer) {
        guard capturing, let channel = buffer.floatChannelData?[0] else { return }
        let n = Int(buffer.frameLength)
        var samples = carry
        samples.reserveCapacity(samples.count + n)
        for i in 0..<n { samples.append(channel[i]) }

        var idx = 0
        while idx + hop <= samples.count {
            var sum: Float = 0
            for j in idx..<(idx + hop) { sum += samples[j] * samples[j] }
            envelope.append(sqrtf(sum / Float(hop)))   // RMS energy of this frame
            idx += hop
        }
        carry = Array(samples[idx...])

        let p = min(1.0, Double(envelope.count) / Double(max(1, targetCount)))
        DispatchQueue.main.async { self.progress = p }

        if envelope.count >= targetCount {
            capturing = false                 // stop appending before we hand off
            let env = envelope                // copied here, on the tap thread
            let rate = envelopeRate
            DispatchQueue.main.async { [weak self] in self?.finish(env, rate) }
        }
    }

    private func finish(_ env: [Float], _ rate: Double) {
        guard state == .listening else { return }
        teardown()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let bpm = TempoDetector.estimateBPM(envelope: env, envelopeRate: rate)
            DispatchQueue.main.async {
                guard let self else { return }
                self.state = bpm.map { .result($0) } ?? .failed
                self.progress = 0
            }
        }
    }

    // MARK: DSP

    static func estimateBPM(envelope: [Float], envelopeRate: Double) -> Int? {
        guard envelope.count > 32, envelopeRate > 0 else { return nil }

        // Onset strength: positive energy changes only.
        var flux = [Float](repeating: 0, count: envelope.count)
        for i in 1..<envelope.count {
            let d = envelope[i] - envelope[i - 1]
            flux[i] = d > 0 ? d : 0
        }
        // Subtract mean to suppress the DC/constant component.
        let mean = flux.reduce(0, +) / Float(flux.count)
        for i in 0..<flux.count { flux[i] = max(0, flux[i] - mean) }

        let minBPM = 50.0, maxBPM = 200.0
        let minLag = max(1, Int(60.0 * envelopeRate / maxBPM))
        let maxLag = Int(60.0 * envelopeRate / minBPM)
        guard maxLag > minLag, maxLag < flux.count else { return nil }

        var bestLag = -1
        var bestScore: Float = 0
        for lag in minLag...maxLag {
            var sum: Float = 0
            var i = lag
            while i < flux.count { sum += flux[i] * flux[i - lag]; i += 1 }
            let score = sum / Float(flux.count - lag)
            if score > bestScore { bestScore = score; bestLag = lag }
        }
        guard bestLag > 0, bestScore > 0 else { return nil }

        var bpm = 60.0 * envelopeRate / Double(bestLag)
        while bpm < 60 { bpm *= 2 }      // fold octave errors into ~60–180
        while bpm >= 180 { bpm /= 2 }
        return Int(bpm.rounded())
    }
}
