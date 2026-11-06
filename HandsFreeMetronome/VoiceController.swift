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
        case setBeats(Int)       // time-signature numerator, 1…8
        case volumeUp, volumeDown, mute
        case setVolume(Int)      // 0…100 percent
        case toggleView, bounceView, orbitView   // beat visualization
        case help, tuner, dismiss, scrollUp, scrollDown, practice
        case timer                // open the practice-timer panel
        case setTimer(Int)        // minutes, "timer 5 minutes"
        case timerOff
    }

    /// Mic buffers, broadcast so features like the tuner can share the input
    /// instead of opening a second audio engine.
    var onAudioBuffer: ((AVAudioPCMBuffer) -> Void)?

    /// Increments whenever the inactivity window resets (start / any command), so
    /// the UI can restart the Listen-button auto-mute countdown.
    @Published private(set) var activityToken = 0

    /// Smoothed mic input level (0…1) that drives the live waveform.
    @Published private(set) var audioLevel: Float = 0

    /// The words the mic listens for, and the recognizer that hears them.
    /// Swapped by `setLanguage` — English, or the app language's own words.
    private(set) var vocabulary = VoiceVocabulary.current
    private var recognizer = SFSpeechRecognizer(locale: VoiceVocabulary.current.recognizerLocale)
    private let audioEngine = AVAudioEngine()
    /// The live recognition request. Swapped on the main thread (refresh) while
    /// the mic tap reads it on the audio thread — an unguarded strong-property
    /// race there can over-release and crash, so ALL access goes through
    /// `requestLock` (see `currentRequest`/`setRequest`).
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private let requestLock = NSLock()
    private var task: SFSpeechRecognitionTask?
    private var awaitingRestart = false   // ignore late results after a command fires
    private var sessionGeneration = 0     // invalidates stale auto-refresh timers
    private var inactivityGeneration = 0  // invalidates stale auto-mute timers
    let autoMuteAfter: TimeInterval = 180  // mute after 3 min with no command (battery)
    private var smoothedLevel: Float = 0
    private var lastPublishedLevel: Float = -1
    private var levelTick = 0

    var isListening: Bool { status == .listening }

    /// Thread-safe access to `request` — read on the audio (tap) thread,
    /// swapped on the main thread.
    private var currentRequest: SFSpeechAudioBufferRecognitionRequest? {
        requestLock.lock(); defer { requestLock.unlock() }
        return request
    }

    private func setRequest(_ newValue: SFSpeechAudioBufferRecognitionRequest?) {
        requestLock.lock()
        request = newValue
        requestLock.unlock()
    }

    func toggle() { isListening ? stop() : requestAndStart() }

    /// Switch the command language. A running mic restarts with the new recognizer.
    func setLanguage(_ language: VoiceLanguage) {
        let next = language == .native ? (VoiceVocabulary.native ?? .english) : .english
        guard next.id != vocabulary.id else { return }
        vocabulary = next
        recognizer = SFSpeechRecognizer(locale: next.recognizerLocale)
        DispatchQueue.main.async { self.lastHeard = "" }
        if isListening {
            stop()
            start()
        }
    }

    private func requestAndStart() {
        SFSpeechRecognizer.requestAuthorization { [weak self] speechAuth in
            AVAudioApplication.requestRecordPermission { micAuth in
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
        // Re-assert a record-capable session HERE, not only at metronome-engine
        // init: on a first launch that init runs before the mic permission exists,
        // and its early setActive can fail — leaving recording illegal even after
        // the user grants both permissions.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default,
                                 options: [.mixWithOthers, .defaultToSpeaker, .allowBluetoothHFP])
        try? session.setActive(true)
        // Set up the mic + tap ONCE and keep them running for the whole listening
        // session. Only the lightweight recognition request/task is recycled after
        // this (see refresh). Repeatedly stopping/starting the audio engine while
        // the metronome's engine also runs is what made recognition die over time.
        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        // A dead input reports 0 Hz / 0 channels, and installTap raises an
        // uncatchable Objective-C exception on such a format — the app dies on the
        // spot. Bail to a visible "unavailable" state instead; the metronome
        // itself keeps working without the mic.
        guard format.sampleRate > 0, format.channelCount > 0 else {
            status = .unavailable
            return
        }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.currentRequest?.append(buffer)
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

    /// Something other than speech (the instrument signal) used the mic — treat
    /// it as activity so listening doesn't auto-mute in the middle of practice.
    func keepAlive() {
        guard status == .listening else { return }
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
        currentRequest?.endAudio()
        task?.cancel()

        // Bump the generation BEFORE creating the new task. Callbacks from the task
        // we just cancelled arrive as cancellation "errors"; without this guard each
        // one would trigger another refresh, an endless cancel→recreate loop that
        // stopped recognition working after the very first command.
        sessionGeneration += 1
        let generation = sessionGeneration

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Only force on-device recognition when the language's model is actually present.
        // On devices without it, forcing it makes recognition return no result and
        // no error — the mic appears dead. Fall back to server recognition instead.
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        setRequest(request)
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
        currentRequest?.endAudio()
        task?.cancel()
        task = nil
        setRequest(nil)
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
        let lower = full.lowercased(with: Locale(identifier: vocabulary.defaultLocale))
        DispatchQueue.main.async { self.lastHeard = lower }

        guard let cmd = command(in: lower) else { return }

        // Fire once, then recycle recognition so the same word isn't re-detected
        // and the next command starts from a clean transcription.
        awaitingRestart = true
        bumpInactivityTimer()   // a command means the user is active
        DispatchQueue.main.async { self.onCommand?(cmd) }
        refresh()
    }

    /// The current language's parser (→ VoiceVocabulary.swift).
    private func command(in text: String) -> Command? {
        VoiceCommandParser(vocabulary: vocabulary).command(in: text)
    }
}
