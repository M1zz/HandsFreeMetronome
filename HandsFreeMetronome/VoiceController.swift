import Foundation
import Speech
import AVFoundation

/// In-app continuous speech recognition. This is the app's OWN microphone
/// listener — it does NOT require the user to turn on iOS system Voice Control
/// or any Accessibility setting. The app drives everything itself.
final class VoiceController: ObservableObject {

    enum Status: Equatable {
        case idle
        case listening
        case denied
        case unavailable
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var lastHeard: String = ""

    /// Called with a normalized command string ("start", "stop", "faster", …)
    /// or ("tempo", value).
    var onCommand: ((Command) -> Void)?

    enum Command: Equatable {
        case start, stop, faster, slower, up, down, double, half
        case setTempo(Int)
        case setSubdivision(Int) // 1 quarter, 2 eighth, 3 triplet, 4 sixteenth
        case help, tuner, dismiss
    }

    /// Mic buffers, broadcast so features like the tuner can share the input
    /// instead of opening a second audio engine.
    var onAudioBuffer: ((AVAudioPCMBuffer) -> Void)?

    /// Increments whenever the inactivity window resets (start / any command), so
    /// the UI can restart the Listen-button auto-mute countdown.
    @Published private(set) var activityToken = 0

    /// Smoothed mic input level (0…1) that drives the live waveform.
    @Published private(set) var audioLevel: Float = 0

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var awaitingRestart = false   // ignore late results after a command fires
    private var sessionGeneration = 0     // invalidates stale auto-refresh timers
    private var inactivityGeneration = 0  // invalidates stale auto-mute timers
    let autoMuteAfter: TimeInterval = 180  // mute after 3 min with no command (battery)
    private var smoothedLevel: Float = 0
    private var lastPublishedLevel: Float = -1
    private var levelTick = 0

    var isListening: Bool { status == .listening }

    func toggle() { isListening ? stop() : requestAndStart() }

    private func requestAndStart() {
        SFSpeechRecognizer.requestAuthorization { [weak self] speechAuth in
            AVAudioSession.sharedInstance().requestRecordPermission { micAuth in
                DispatchQueue.main.async {
                    guard speechAuth == .authorized, micAuth else {
                        self?.status = .denied
                        return
                    }
                    self?.start()
                }
            }
        }
    }

    private func start() {
        guard let recognizer, recognizer.isAvailable else {
            status = .unavailable
            return
        }
        // Set up the mic + tap ONCE and keep them running for the whole listening
        // session. Only the lightweight recognition request/task is recycled after
        // this (see refresh). Repeatedly stopping/starting the audio engine while
        // the metronome's engine also runs is what made recognition die over time.
        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
            self?.onAudioBuffer?(buffer)
            self?.updateLevel(buffer)
        }
        audioEngine.prepare()
        do { try audioEngine.start() } catch {
            status = .unavailable
            return
        }
        status = .listening
        beginRecognition()
        bumpInactivityTimer()
    }

    /// Auto-mute after a stretch with no commands, to save battery. Reset on each
    /// command; listening resumes when the user taps Listen again.
    private func bumpInactivityTimer() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.inactivityGeneration += 1
            self.activityToken += 1
            let generation = self.inactivityGeneration
            DispatchQueue.main.asyncAfter(deadline: .now() + self.autoMuteAfter) { [weak self] in
                guard let self, self.status == .listening, self.inactivityGeneration == generation else { return }
                self.stop()
            }
        }
    }

    /// Start a fresh recognition request + task. The already-running tap feeds the
    /// new request immediately, so recognition is swapped without touching the engine.
    private func beginRecognition() {
        guard status == .listening, let recognizer else { return }
        request?.endAudio()
        task?.cancel()

        // Bump the generation BEFORE creating the new task. Callbacks from the task
        // we just cancelled arrive as cancellation "errors"; without this guard each
        // one would trigger another refresh, an endless cancel→recreate loop that
        // stopped recognition working after the very first command.
        sessionGeneration += 1
        let generation = sessionGeneration

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if #available(iOS 13, *) { request.requiresOnDeviceRecognition = true }
        self.request = request
        awaitingRestart = false

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self, generation == self.sessionGeneration else { return }  // ignore stale task
            if let result {
                self.parse(result.bestTranscription.formattedString)
                if result.isFinal { self.refresh() }   // keep listening between songs
            }
            if error != nil { self.refresh() }
        }
        scheduleAutoRefresh(generation)
    }

    /// SFSpeechRecognizer caps a single recognition at ~1 minute. Refresh well
    /// before that so listening never silently dies during a long song.
    private func scheduleAutoRefresh(_ generation: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 40) { [weak self] in
            guard let self, self.status == .listening, self.sessionGeneration == generation else { return }
            self.refresh()
        }
    }

    /// Recycle recognition (after a command, at the time limit, or on error)
    /// WITHOUT tearing down the audio engine. Dispatched to main to avoid
    /// re-entrancy from inside a task's completion handler.
    private func refresh() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.status == .listening else { return }
            self.beginRecognition()
        }
    }

    func stop() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        smoothedLevel = 0
        lastPublishedLevel = -1
        audioLevel = 0
        if status == .listening { status = .idle }
    }

    /// Smoothed RMS of the mic input → 0…1, published (throttled) for the waveform.
    private func updateLevel(_ buffer: AVAudioPCMBuffer) {
        guard let ch = buffer.floatChannelData?[0] else { return }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return }
        var sum: Float = 0
        for i in 0..<n { sum += ch[i] * ch[i] }
        let rms = sqrtf(sum / Float(n))
        let target = min(1, rms * 12)
        // Fast attack, slow release so the bars linger briefly after a word.
        smoothedLevel += (target > smoothedLevel ? 0.6 : 0.12) * (target - smoothedLevel)

        levelTick &+= 1
        guard levelTick % 2 == 0 else { return }   // ~20 Hz
        let level = smoothedLevel
        // Publish only on meaningful change (no churn while silent).
        if abs(level - lastPublishedLevel) > 0.02 || (level < 0.03 && lastPublishedLevel >= 0.03) {
            lastPublishedLevel = level
            DispatchQueue.main.async { self.audioLevel = level }
        }
    }

    // MARK: Parsing

    private func parse(_ full: String) {
        guard !awaitingRestart else { return }   // a command already fired this utterance
        let lower = full.lowercased()
        DispatchQueue.main.async { self.lastHeard = lower }

        guard let cmd = command(in: lower) else { return }

        // Fire once, then recycle recognition so the same word isn't re-detected
        // and the next command starts from a clean transcription.
        awaitingRestart = true
        bumpInactivityTimer()   // a command means the user is active
        DispatchQueue.main.async { self.onCommand?(cmd) }
        refresh()
    }

    /// Match a command anywhere in the current transcription. Longer/compound
    /// phrases ("speed up") are checked before short ones ("up").
    private func command(in text: String) -> Command? {
        if contains(text, ["help", "헬프", "도움말"]) { return .help }
        if contains(text, ["tune", "tuner", "튜너", "튜닝"]) { return .tuner }
        // Closes whichever panel is open. "done" is easily misheard as "down",
        // so offer clearer alternatives too.
        if contains(text, ["done", "close", "okay", "exit", "dismiss",
                           "닫아", "닫기", "완료", "그만"]) { return .dismiss }
        if contains(text, ["double", "두배"]) { return .double }
        if contains(text, ["half", "절반"]) { return .half }
        if contains(text, ["faster", "speed up", "빠르게", "빨리"]) { return .faster }
        if contains(text, ["slower", "slow down", "느리게", "천천히"]) { return .slower }
        if contains(text, ["sixteenth", "16th", "십육분", "16분"]) { return .setSubdivision(4) }
        if contains(text, ["triplet", "셋잇단", "삼연음"]) { return .setSubdivision(3) }
        if contains(text, ["eighth", "8th", "팔분", "8분"]) { return .setSubdivision(2) }
        if contains(text, ["quarter", "사분", "4분"]) { return .setSubdivision(1) }
        if contains(text, ["start", "play", "go", "begin", "시작"]) { return .start }
        if contains(text, ["stop", "pause", "halt", "정지", "멈춰"]) { return .stop }
        if contains(text, ["up", "higher", "위로"]) { return .up }
        if contains(text, ["down", "lower", "아래로"]) { return .down }
        if let n = firstNumber(in: text) { return .setTempo(n) }
        return nil
    }

    private func contains(_ text: String, _ words: [String]) -> Bool {
        words.contains { text.contains($0) }
    }

    private func firstNumber(in text: String) -> Int? {
        let pattern = "\\d{2,3}"
        guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
        return Int(text[range])
    }
}
