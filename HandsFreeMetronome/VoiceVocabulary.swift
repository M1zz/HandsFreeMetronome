import Foundation
import Speech
import SwiftUI

// MARK: - Which words the mic listens for

/// The user's choice: the short English words every language has always used,
/// or the words of the language the app is shown in.
///
/// ⚠️ English stays the default — people who already learned the commands keep them.
///    The switch is in Settings and Voice Commands, and only appears when the app's language has
///    its own words here (`VoiceVocabulary.native`).
enum VoiceLanguage: String {
    case english, native

    static let storageKey = "voice.language"

    static var current: VoiceLanguage {
        VoiceLanguage(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .english
    }
}

// MARK: - The words of one language

/// Everything a language needs for voice control: the words the parser listens for
/// and the phrases the screens show (`Phrase`). One table per language, so adding a
/// language is adding a table — the parser itself never changes.
///
/// Matching is "does the transcript contain this word", lower-cased, the same way
/// the English parser always worked. That keeps inflected languages simple (a stem
/// like "прокрут" catches every form) and works for languages without spaces.
/// ⚠️ Order matters, not the lists: `VoiceCommandParser` checks compound phrases
///    before short words. A word must not contain a word of a slot checked earlier —
///    `VoiceVocabularyTests` parses every shown phrase back to prove it.
struct VoiceVocabulary {

    enum Slot: CaseIterable {
        case help, tuner, timer, minute, timerOff, practice, orbit, bounce, view
        case mute, volume, louder, quieter, beat, scroll, close
        case sixteenth, triplet, eighth, quarter, double, half, faster, slower
        case start, stop, up, down, hour, halfHour
    }

    /// What the screens quote ("Say “help”…"). Each one parses back to its command.
    enum Phrase: CaseIterable {
        case help, close, done, practice, louder, quieter, mute, volume60
        case scrollDown, scrollUp, start, stop, faster, slower, tempo120, tune
        case timer5, timerOff, bounce, orbit, up, down, double, half, threeBeats
        case quarter, eighth, triplet, sixteenth
    }

    /// App localization this table belongs to ("ko", "zh-Hans", "pt-BR" …).
    let id: String
    /// Recognizer locale when the device's own region isn't one the recognizer knows.
    let defaultLocale: String
    let words: [Slot: [String]]
    /// Number words 1…8 for "three beats", plus a few for "timer five minutes".
    let numbers: [String: Int]
    /// "twenty" + "five" — only languages that build numbers from separate words.
    var tens: [String: Int] = [:]
    let phrases: [Phrase: String]

    func words(_ slot: Slot) -> [String] { words[slot] ?? [] }
    func say(_ phrase: Phrase) -> String { phrases[phrase] ?? VoiceVocabulary.english.phrases[phrase] ?? "" }

    // MARK: Picking a table

    /// The language the app is shown in, as the bundle resolved it.
    static var appLanguage: String { Bundle.main.preferredLocalizations.first ?? "en" }

    /// The app language's own words, if it has any (English has none — it IS English).
    static var native: VoiceVocabulary? {
        let language = appLanguage
        guard !language.hasPrefix("en") else { return nil }
        return all.first { $0.id == language }
            ?? all.first { $0.id == String(language.prefix(2)) }
    }

    /// What the mic listens for right now.
    static var current: VoiceVocabulary {
        VoiceLanguage.current == .native ? (native ?? english) : english
    }

    /// The name to show for the native choice, in that language ("한국어", "Deutsch").
    var displayName: String {
        let locale = Locale(identifier: id)
        let name = locale.localizedString(forIdentifier: id) ?? id
        return name.prefix(1).uppercased(with: locale) + name.dropFirst()
    }

    /// Recognizer locale: the device's region when the recognizer knows it (es-MX,
    /// pt-PT…), otherwise this table's default.
    var recognizerLocale: Locale {
        if id == "en" { return Locale(identifier: "en-US") }
        let supported = Set(SFSpeechRecognizer.supportedLocales().map(\.identifier))
        if let region = Locale.current.region?.identifier,
           !id.contains("-") {   // zh-Hans / zh-Hant / pt-BR pin their own region
            let candidate = "\(id)-\(region)"
            if supported.contains(candidate) || supported.contains(candidate.replacingOccurrences(of: "-", with: "_")) {
                return Locale(identifier: candidate)
            }
        }
        return Locale(identifier: defaultLocale)
    }
}

// MARK: - Parser

/// Turns a transcript into a command with one language's words.
/// Pure — no mic, no audio — so every language is checked by unit tests.
struct VoiceCommandParser {
    typealias Command = VoiceController.Command
    let vocabulary: VoiceVocabulary

    /// Match a command anywhere in the transcription. Longer/compound phrases
    /// ("speed up") are checked before short ones ("up").
    func command(in raw: String) -> Command? {
        let text = raw.lowercased(with: Locale(identifier: vocabulary.defaultLocale))
        func has(_ slot: VoiceVocabulary.Slot) -> Bool {
            vocabulary.words(slot).contains { text.contains($0) }
        }

        if has(.help) { return .help }
        if has(.tuner) { return .tuner }
        // Practice timer — "timer 5 minutes", "timer off". Checked before "practice"
        // ("practice timer") and before start/stop ("stop timer").
        if has(.timer) || has(.minute) {
            if has(.timerOff) { return .timerOff }
            if let n = minutes(in: text) { return .setTimer(n) }
            if has(.timer) { return .timer }
        }
        // Open the practice-mode modal (auto tempo climb). Checked before "up"/numbers.
        if has(.practice) { return .practice }
        // Beat visualization. Specific styles before the generic "view" toggle.
        if has(.orbit) { return .orbitView }
        if has(.bounce) { return .bounceView }
        if has(.view) { return .toggleView }
        // Volume. "volume 60" sets a percent; louder/quieter nudge; mute silences.
        if has(.mute) { return .mute }
        if has(.volume) || has(.louder) || has(.quieter) {
            if has(.volume), let n = firstNumber(in: text) { return .setVolume(n) }
            if has(.louder) || (has(.volume) && has(.up)) { return .volumeUp }
            if has(.quieter) || (has(.volume) && has(.down)) { return .volumeDown }
        }
        // Time signature — "three beats". Requires the beat word so it never
        // collides with tempo numbers or subdivisions.
        if has(.beat), let n = beatsCount(in: text) { return .setBeats(n) }
        // Scroll the help list — before up/down (tempo) and before close words.
        if has(.scroll) { return has(.up) ? .scrollUp : .scrollDown }
        // Closes whichever panel is open.
        if has(.close) { return .dismiss }
        // Subdivisions before double/half: "double croche" is a sixteenth in French.
        if has(.sixteenth) { return .setSubdivision(4) }
        if has(.triplet) { return .setSubdivision(3) }
        if has(.eighth) { return .setSubdivision(2) }
        if has(.quarter) { return .setSubdivision(1) }
        if has(.double) { return .double }
        if has(.half) { return .half }
        if has(.faster) { return .faster }
        if has(.slower) { return .slower }
        if has(.start) { return .start }
        if has(.stop) { return .stop }
        if has(.up) { return .up }
        if has(.down) { return .down }
        if let n = firstNumber(in: text) { return .setTempo(n) }
        return nil
    }

    /// A time-signature count (1…8): a lone digit, or a number word — longest first,
    /// so "seven" is never read as a shorter word inside it.
    private func beatsCount(in text: String) -> Int? {
        if let r = text.range(of: "(?<!\\d)[1-8](?!\\d)", options: .regularExpression) { return Int(text[r]) }
        let words = vocabulary.numbers.filter { (1...8).contains($0.value) }
            .sorted { $0.key.count > $1.key.count }
        return words.first { text.contains($0.key) }?.value
    }

    /// A practice length in minutes: digits, "half an hour", or whole number words
    /// ("fifteen" never reads as "five").
    private func minutes(in text: String) -> Int? {
        if let r = text.range(of: "\\d{1,3}", options: .regularExpression), let n = Int(text[r]), n > 0 {
            return n
        }
        if vocabulary.words(.halfHour).contains(where: text.contains) { return 30 }
        if vocabulary.words(.hour).contains(where: text.contains) { return 60 }
        let tokens = text.split { !$0.isLetter }.map(String.init)
        for (i, word) in tokens.enumerated() {
            if let t = vocabulary.tens[word] {
                if i + 1 < tokens.count, let u = vocabulary.numbers[tokens[i + 1]], u < 10 { return t + u }
                return t
            }
            if let u = vocabulary.numbers[word] { return u }
        }
        return nil
    }

    private func firstNumber(in text: String) -> Int? {
        guard let range = text.range(of: "\\d{2,3}", options: .regularExpression) else { return nil }
        return Int(text[range])
    }
}

// MARK: - Tables

extension VoiceVocabulary {

    static let all: [VoiceVocabulary] = [
        english, korean, japanese, german, spanish, french, chineseSimplified, chineseTraditional,
        portuguese, italian, russian, dutch, polish, turkish, swedish, danish, norwegian,
        finnish, czech, indonesian, vietnamese, greek, thai,
    ]

    static let english = VoiceVocabulary(
        id: "en", defaultLocale: "en-US",
        words: [
            .help: ["help"], .tuner: ["tune", "tuner"],
            .timer: ["timer"], .minute: ["minute"],
            .timerOff: ["off", "cancel", "clear", "no timer", "stop timer"],
            .practice: ["practice", "trainer"],
            .orbit: ["orbit", "circle", "circular"], .bounce: ["bounce", "vertical"],
            .view: ["switch view", "change view", "view", "visual"],
            .mute: ["mute", "silent", "silence"],
            .volume: ["volume"], .louder: ["louder"], .quieter: ["quieter", "softer"],
            .beat: ["beat"], .scroll: ["scroll"],
            .close: ["done", "close", "okay", "exit", "dismiss"],
            .sixteenth: ["sixteenth", "16th"], .triplet: ["triplet"],
            .eighth: ["eighth", "8th"], .quarter: ["quarter"],
            .double: ["double"], .half: ["half"],
            .faster: ["faster", "speed up"], .slower: ["slower", "slow down"],
            .start: ["start", "play", "go", "begin"], .stop: ["stop", "pause", "halt"],
            .up: ["up", "higher"], .down: ["down", "lower"],
            .hour: ["an hour", "one hour"], .halfHour: ["half an hour"],
        ],
        numbers: ["one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
                  "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12,
                  "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16,
                  "seventeen": 17, "eighteen": 18, "nineteen": 19],
        tens: ["twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60],
        phrases: [
            .help: "help", .close: "close", .done: "done", .practice: "practice",
            .louder: "louder", .quieter: "quieter", .mute: "mute", .volume60: "volume 60",
            .scrollDown: "scroll down", .scrollUp: "scroll up", .start: "start", .stop: "stop",
            .faster: "faster", .slower: "slower", .tempo120: "tempo 120", .tune: "tune",
            .timer5: "timer 5 minutes", .timerOff: "timer off", .bounce: "bounce", .orbit: "orbit",
            .up: "up", .down: "down", .double: "double", .half: "half", .threeBeats: "three beats",
            .quarter: "quarter", .eighth: "eighth", .triplet: "triplet", .sixteenth: "sixteenth",
        ])

    // ⚠️ Korean: no bare "분" (minute) — "16분음표" is a sixteenth note. Timers need "타이머".
    static let korean = VoiceVocabulary(
        id: "ko", defaultLocale: "ko-KR",
        words: [
            .help: ["도움말", "도와줘", "명령어"], .tuner: ["튜너", "조율"],
            .timer: ["타이머"], .timerOff: ["꺼", "끄기", "취소", "없애"],
            .practice: ["연습", "트레이너"],
            .orbit: ["궤도", "원형", "동그라미"], .bounce: ["바운스", "통통"],
            .view: ["화면 전환", "화면 바꿔", "보기 바꿔"],
            .mute: ["음소거", "조용히"],
            .volume: ["볼륨", "음량", "소리"], .louder: ["크게", "키워"], .quieter: ["작게", "줄여"],
            .beat: ["박자", "박"], .scroll: ["스크롤"],
            .close: ["닫아", "닫기", "완료"],
            .sixteenth: ["16분음표", "십육분"], .triplet: ["셋잇단", "트리플렛"],
            .eighth: ["8분음표", "팔분음표"], .quarter: ["4분음표", "사분음표"],
            .double: ["두 배", "두배"], .half: ["절반", "반으로"],
            .faster: ["빠르게", "빨리"], .slower: ["느리게", "천천히"],
            .start: ["시작", "출발", "재생"], .stop: ["정지", "멈춰", "멈춤", "그만"],
            .up: ["올려", "위로"], .down: ["내려", "아래로"],
            .hour: ["한 시간", "1시간"], .halfHour: ["30분", "삼십 분", "반 시간"],
        ],
        numbers: ["하나": 1, "한": 1, "둘": 2, "두": 2, "셋": 3, "세": 3, "넷": 4, "네": 4,
                  "다섯": 5, "여섯": 6, "일곱": 7, "여덟": 8],
        phrases: [
            .help: "도움말", .close: "닫아", .done: "완료", .practice: "연습",
            .louder: "크게", .quieter: "작게", .mute: "음소거", .volume60: "볼륨 60",
            .scrollDown: "스크롤 내려", .scrollUp: "스크롤 올려", .start: "시작", .stop: "정지",
            .faster: "빠르게", .slower: "느리게", .tempo120: "템포 120", .tune: "튜너",
            .timer5: "타이머 5분", .timerOff: "타이머 꺼", .bounce: "바운스", .orbit: "궤도",
            .up: "올려", .down: "내려", .double: "두 배", .half: "절반", .threeBeats: "세 박자",
            .quarter: "4분음표", .eighth: "8분음표", .triplet: "셋잇단음표", .sixteenth: "16분음표",
        ])

    // ⚠️ Japanese: no bare "分" — "16分音符" is a sixteenth note.
    static let japanese = VoiceVocabulary(
        id: "ja", defaultLocale: "ja-JP",
        words: [
            .help: ["ヘルプ", "助けて", "コマンド"], .tuner: ["チューナー", "チューニング"],
            .timer: ["タイマー"], .timerOff: ["オフ", "解除", "キャンセル", "消して", "止め"],
            .practice: ["練習", "トレーナー"],
            .orbit: ["軌道", "オービット", "サークル"], .bounce: ["バウンド", "バウンス", "ボール"],
            .view: ["表示切り替え", "表示を切り替え", "ビュー"],
            .mute: ["ミュート", "消音"],
            .volume: ["音量", "ボリューム"], .louder: ["大きく"], .quieter: ["小さく"],
            .beat: ["拍"], .scroll: ["スクロール"],
            .close: ["閉じて", "閉じる", "完了"],
            .sixteenth: ["16分音符", "十六分"], .triplet: ["三連符", "3連符"],
            .eighth: ["8分音符", "八分音符"], .quarter: ["4分音符", "四分音符"],
            .double: ["2倍", "二倍", "倍に"], .half: ["半分"],
            .faster: ["速く", "早く", "速めて"], .slower: ["遅く", "ゆっくり"],
            .start: ["スタート", "開始", "始め", "はじめ", "再生"],
            .stop: ["ストップ", "停止", "止め", "止まれ"],
            .up: ["上げ", "アップ"], .down: ["下げ", "ダウン"],
            .hour: ["1時間", "一時間"], .halfHour: ["30分", "三十分", "半時間"],
        ],
        numbers: ["一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8],
        phrases: [
            .help: "ヘルプ", .close: "閉じて", .done: "完了", .practice: "練習",
            .louder: "大きく", .quieter: "小さく", .mute: "ミュート", .volume60: "音量60",
            .scrollDown: "スクロールダウン", .scrollUp: "スクロールアップ", .start: "スタート", .stop: "ストップ",
            .faster: "速く", .slower: "遅く", .tempo120: "テンポ120", .tune: "チューナー",
            .timer5: "タイマー5分", .timerOff: "タイマーオフ", .bounce: "バウンド", .orbit: "軌道",
            .up: "上げて", .down: "下げて", .double: "2倍", .half: "半分", .threeBeats: "3拍子",
            .quarter: "4分音符", .eighth: "8分音符", .triplet: "三連符", .sixteenth: "16分音符",
        ])

    static let german = VoiceVocabulary(
        id: "de", defaultLocale: "de-DE",
        words: [
            .help: ["hilfe"], .tuner: ["stimmgerät", "stimmen", "tuner"],
            .timer: ["timer"], .minute: ["minute"],
            .timerOff: ["aus", "abbrechen", "stopp timer"],
            .practice: ["üben", "übung", "trainer"],
            .orbit: ["orbit", "kreis"], .bounce: ["ball", "hüpf"],
            .view: ["ansicht wechseln", "ansicht", "anzeige"],
            .mute: ["stumm", "ton aus"],
            .volume: ["lautstärke"], .louder: ["lauter"], .quieter: ["leiser"],
            .beat: ["schlag", "schläge"], .scroll: ["scroll"],
            .close: ["fertig", "schließ", "okay", "beenden"],
            .sixteenth: ["sechzehntel"], .triplet: ["triole"], .eighth: ["achtel"], .quarter: ["viertel"],
            .double: ["doppelt"], .half: ["halb"],
            .faster: ["schneller"], .slower: ["langsamer"],
            .start: ["start", "los", "spiel"], .stop: ["stopp", "stop", "pause", "halt"],
            .up: ["höher", "hoch", "rauf", "oben"], .down: ["tiefer", "runter", "unten"],
            .hour: ["eine stunde"], .halfHour: ["halbe stunde"],
        ],
        numbers: ["eins": 1, "ein": 1, "zwei": 2, "drei": 3, "vier": 4, "fünf": 5, "sechs": 6,
                  "sieben": 7, "acht": 8, "zehn": 10, "fünfzehn": 15, "zwanzig": 20, "dreißig": 30],
        phrases: [
            .help: "Hilfe", .close: "schließen", .done: "fertig", .practice: "üben",
            .louder: "lauter", .quieter: "leiser", .mute: "stumm", .volume60: "Lautstärke 60",
            .scrollDown: "nach unten scrollen", .scrollUp: "nach oben scrollen", .start: "Start", .stop: "Stopp",
            .faster: "schneller", .slower: "langsamer", .tempo120: "Tempo 120", .tune: "Stimmgerät",
            .timer5: "Timer 5 Minuten", .timerOff: "Timer aus", .bounce: "Ball", .orbit: "Kreis",
            .up: "höher", .down: "tiefer", .double: "doppelt", .half: "halb", .threeBeats: "drei Schläge",
            .quarter: "Viertel", .eighth: "Achtel", .triplet: "Triole", .sixteenth: "Sechzehntel",
        ])

    static let spanish = VoiceVocabulary(
        id: "es", defaultLocale: "es-ES",
        words: [
            .help: ["ayuda"], .tuner: ["afinador", "afinar"],
            .timer: ["temporizador", "cronómetro"], .minute: ["minuto"],
            .timerOff: ["apaga", "quita", "cancela", "sin temporizador"],
            .practice: ["práctica", "practicar", "entrenador"],
            .orbit: ["órbita", "círculo"], .bounce: ["rebote", "pelota", "rebota"],
            .view: ["cambiar vista", "cambia la vista", "vista"],
            .mute: ["silencio", "silencia", "mudo"],
            .volume: ["volumen"], .louder: ["más fuerte"], .quieter: ["más bajo", "más suave"],
            .beat: ["tiempos", "pulsos"], .scroll: ["desplaza", "desliza"],
            .close: ["cierra", "cerrar", "listo", "vale", "salir"],
            .sixteenth: ["semicorchea"], .triplet: ["tresillo"], .eighth: ["corchea"], .quarter: ["negra"],
            .double: ["doble"], .half: ["mitad"],
            .faster: ["más rápido", "acelera"], .slower: ["más lento", "despacio"],
            .start: ["empieza", "empezar", "inicia", "comienza", "arranca", "dale"],
            .stop: ["para", "detén", "detener", "pausa", "alto"],
            .up: ["sube", "subir", "arriba"], .down: ["baja", "bajar", "abajo"],
            .hour: ["una hora"], .halfHour: ["media hora"],
        ],
        numbers: ["uno": 1, "dos": 2, "tres": 3, "cuatro": 4, "cinco": 5, "seis": 6, "siete": 7,
                  "ocho": 8, "diez": 10, "quince": 15, "veinte": 20, "treinta": 30],
        phrases: [
            .help: "ayuda", .close: "cierra", .done: "listo", .practice: "práctica",
            .louder: "más fuerte", .quieter: "más bajo", .mute: "silencio", .volume60: "volumen 60",
            .scrollDown: "desplaza abajo", .scrollUp: "desplaza arriba", .start: "empieza", .stop: "para",
            .faster: "más rápido", .slower: "más lento", .tempo120: "tempo 120", .tune: "afinador",
            .timer5: "temporizador 5 minutos", .timerOff: "apaga el temporizador", .bounce: "rebote", .orbit: "órbita",
            .up: "sube", .down: "baja", .double: "doble", .half: "mitad", .threeBeats: "tres tiempos",
            .quarter: "negra", .eighth: "corchea", .triplet: "tresillo", .sixteenth: "semicorchea",
        ])

    static let french = VoiceVocabulary(
        id: "fr", defaultLocale: "fr-FR",
        words: [
            .help: ["aide"], .tuner: ["accordeur", "accorder"],
            .timer: ["minuteur", "chrono"], .minute: ["minute"],
            .timerOff: ["arrête", "coupe", "annule", "désactive", "sans minuteur"],
            .practice: ["entraînement", "entraîne", "pratique", "exercice"],
            .orbit: ["orbite", "cercle"], .bounce: ["rebond", "balle"],
            .view: ["changer de vue", "change de vue", "affichage"],
            .mute: ["muet", "silence", "coupe le son"],
            .volume: ["volume"], .louder: ["plus fort"], .quieter: ["moins fort", "plus doux"],
            .beat: ["temps", "battements"], .scroll: ["défile", "défiler"],
            .close: ["ferme", "fermer", "terminé", "c'est bon"],
            .sixteenth: ["double croche", "double-croche"], .triplet: ["triolet"],
            .eighth: ["croche"], .quarter: ["noire"],
            .double: ["double"], .half: ["moitié"],
            .faster: ["plus vite", "accélère", "plus rapide"], .slower: ["moins vite", "ralentis", "plus lent"],
            .start: ["démarre", "commence", "lance", "joue", "c'est parti"], .stop: ["stop", "arrête", "pause"],
            .up: ["monte", "haut"], .down: ["descends", "baisse", "bas"],
            .hour: ["une heure"], .halfHour: ["demi-heure", "demi heure"],
        ],
        numbers: ["un": 1, "une": 1, "deux": 2, "trois": 3, "quatre": 4, "cinq": 5, "six": 6,
                  "sept": 7, "huit": 8, "dix": 10, "quinze": 15, "vingt": 20, "trente": 30],
        phrases: [
            .help: "aide", .close: "ferme", .done: "terminé", .practice: "entraînement",
            .louder: "plus fort", .quieter: "moins fort", .mute: "muet", .volume60: "volume 60",
            .scrollDown: "défile vers le bas", .scrollUp: "défile vers le haut", .start: "démarre", .stop: "stop",
            .faster: "plus vite", .slower: "moins vite", .tempo120: "tempo 120", .tune: "accordeur",
            .timer5: "minuteur 5 minutes", .timerOff: "arrête le minuteur", .bounce: "rebond", .orbit: "orbite",
            .up: "monte", .down: "baisse", .double: "double", .half: "moitié", .threeBeats: "trois temps",
            .quarter: "noire", .eighth: "croche", .triplet: "triolet", .sixteenth: "double croche",
        ])

    // ⚠️ Chinese: no bare "分" — "十六分音符" is a sixteenth note.
    static let chineseSimplified = VoiceVocabulary(
        id: "zh-Hans", defaultLocale: "zh-CN",
        words: [
            .help: ["帮助", "命令"], .tuner: ["调音"],
            .timer: ["计时", "定时"], .timerOff: ["关", "取消"],
            .practice: ["练习", "训练"],
            .orbit: ["轨道", "圆圈", "环形"], .bounce: ["弹跳", "小球", "弹球"],
            .view: ["切换视图", "切换显示", "视图"],
            .mute: ["静音"],
            .volume: ["音量"], .louder: ["大声", "大一点"], .quieter: ["小声", "小一点"],
            .beat: ["拍"], .scroll: ["滚动"],
            .close: ["关闭", "完成", "好了", "退出"],
            .sixteenth: ["十六分", "16分"], .triplet: ["三连音"], .eighth: ["八分", "8分"], .quarter: ["四分", "4分"],
            .double: ["加倍", "两倍", "翻倍"], .half: ["减半", "一半"],
            .faster: ["快一点", "加快", "快点", "更快"], .slower: ["慢一点", "减慢", "慢点", "更慢"],
            .start: ["开始", "播放", "启动"], .stop: ["停止", "暂停", "停"],
            .up: ["上调", "加一", "向上", "往上", "高一点"], .down: ["下调", "减一", "向下", "往下", "低一点"],
            .hour: ["一小时", "一个小时"], .halfHour: ["半小时", "半个小时"],
        ],
        numbers: ["一": 1, "二": 2, "两": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8],
        phrases: [
            .help: "帮助", .close: "关闭", .done: "完成", .practice: "练习",
            .louder: "大声", .quieter: "小声", .mute: "静音", .volume60: "音量60",
            .scrollDown: "向下滚动", .scrollUp: "向上滚动", .start: "开始", .stop: "停止",
            .faster: "快一点", .slower: "慢一点", .tempo120: "速度120", .tune: "调音",
            .timer5: "计时5分钟", .timerOff: "关闭计时", .bounce: "弹跳", .orbit: "轨道",
            .up: "上调", .down: "下调", .double: "加倍", .half: "减半", .threeBeats: "三拍",
            .quarter: "四分音符", .eighth: "八分音符", .triplet: "三连音", .sixteenth: "十六分音符",
        ])

    static let chineseTraditional = VoiceVocabulary(
        id: "zh-Hant", defaultLocale: "zh-TW",
        words: [
            .help: ["幫助", "說明", "指令"], .tuner: ["調音"],
            .timer: ["計時", "定時"], .timerOff: ["關", "取消"],
            .practice: ["練習", "訓練"],
            .orbit: ["軌道", "圓圈", "環形"], .bounce: ["彈跳", "小球", "彈球"],
            .view: ["切換檢視", "切換顯示", "檢視"],
            .mute: ["靜音"],
            .volume: ["音量"], .louder: ["大聲", "大一點"], .quieter: ["小聲", "小一點"],
            .beat: ["拍"], .scroll: ["捲動", "滾動"],
            .close: ["關閉", "完成", "好了", "退出"],
            .sixteenth: ["十六分", "16分"], .triplet: ["三連音"], .eighth: ["八分", "8分"], .quarter: ["四分", "4分"],
            .double: ["加倍", "兩倍", "翻倍"], .half: ["減半", "一半"],
            .faster: ["快一點", "加快", "快點", "更快"], .slower: ["慢一點", "減慢", "慢點", "更慢"],
            .start: ["開始", "播放", "啟動"], .stop: ["停止", "暫停", "停"],
            .up: ["調高", "加一", "向上", "往上", "高一點"], .down: ["調低", "減一", "向下", "往下", "低一點"],
            .hour: ["一小時", "一個小時"], .halfHour: ["半小時", "半個小時"],
        ],
        numbers: ["一": 1, "二": 2, "兩": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8],
        phrases: [
            .help: "幫助", .close: "關閉", .done: "完成", .practice: "練習",
            .louder: "大聲", .quieter: "小聲", .mute: "靜音", .volume60: "音量60",
            .scrollDown: "向下捲動", .scrollUp: "向上捲動", .start: "開始", .stop: "停止",
            .faster: "快一點", .slower: "慢一點", .tempo120: "速度120", .tune: "調音",
            .timer5: "計時5分鐘", .timerOff: "關閉計時", .bounce: "彈跳", .orbit: "軌道",
            .up: "調高", .down: "調低", .double: "加倍", .half: "減半", .threeBeats: "三拍",
            .quarter: "四分音符", .eighth: "八分音符", .triplet: "三連音", .sixteenth: "十六分音符",
        ])

    static let portuguese = VoiceVocabulary(
        id: "pt-BR", defaultLocale: "pt-BR",
        words: [
            .help: ["ajuda"], .tuner: ["afinador", "afinar"],
            .timer: ["temporizador", "cronômetro"], .minute: ["minuto"],
            .timerOff: ["desliga", "cancela", "sem temporizador"],
            .practice: ["prática", "praticar", "treino"],
            .orbit: ["órbita", "círculo"], .bounce: ["quique", "quicar", "bola"],
            .view: ["trocar visualização", "mudar visualização", "visualização"],
            .mute: ["mudo", "silêncio", "silencia"],
            .volume: ["volume"], .louder: ["mais alto"], .quieter: ["mais baixo"],
            .beat: ["tempos", "batidas"], .scroll: ["rolar", "rola", "desliza"],
            .close: ["fecha", "fechar", "pronto", "sair"],
            .sixteenth: ["semicolcheia"], .triplet: ["quiáltera", "tercina"],
            .eighth: ["colcheia"], .quarter: ["semínima"],
            .double: ["dobro", "dobra"], .half: ["metade"],
            .faster: ["mais rápido", "acelera"], .slower: ["mais devagar", "mais lento", "desacelera"],
            .start: ["começa", "começar", "inicia", "iniciar", "toca"], .stop: ["para", "pare", "pausa"],
            .up: ["sobe", "subir", "aumenta", "cima"], .down: ["desce", "descer", "abaixa", "baixo"],
            .hour: ["uma hora"], .halfHour: ["meia hora"],
        ],
        numbers: ["um": 1, "uma": 1, "dois": 2, "duas": 2, "três": 3, "quatro": 4, "cinco": 5,
                  "seis": 6, "sete": 7, "oito": 8, "dez": 10, "quinze": 15, "vinte": 20, "trinta": 30],
        phrases: [
            .help: "ajuda", .close: "fecha", .done: "pronto", .practice: "prática",
            .louder: "mais alto", .quieter: "mais baixo", .mute: "mudo", .volume60: "volume 60",
            .scrollDown: "rolar para baixo", .scrollUp: "rolar para cima", .start: "começa", .stop: "para",
            .faster: "mais rápido", .slower: "mais devagar", .tempo120: "tempo 120", .tune: "afinador",
            .timer5: "temporizador 5 minutos", .timerOff: "desliga o temporizador", .bounce: "quique", .orbit: "órbita",
            .up: "sobe", .down: "desce", .double: "dobro", .half: "metade", .threeBeats: "três tempos",
            .quarter: "semínima", .eighth: "colcheia", .triplet: "quiáltera", .sixteenth: "semicolcheia",
        ])

    static let italian = VoiceVocabulary(
        id: "it", defaultLocale: "it-IT",
        words: [
            .help: ["aiuto"], .tuner: ["accordatore", "accorda"],
            .timer: ["timer"], .minute: ["minut"],
            .timerOff: ["spegni", "annulla", "togli"],
            .practice: ["esercizio", "allenamento", "pratica"],
            .orbit: ["orbita", "cerchio"], .bounce: ["rimbalzo", "pallina", "palla"],
            .view: ["cambia vista", "vista", "visualizzazione"],
            .mute: ["muto", "silenzio"],
            .volume: ["volume"], .louder: ["più forte"], .quieter: ["più piano", "più basso"],
            .beat: ["battiti", "tempi", "battute"], .scroll: ["scorri"],
            .close: ["chiudi", "fatto", "esci", "finito"],
            .sixteenth: ["semicroma", "sedicesimi"], .triplet: ["terzina"],
            .eighth: ["croma", "ottavi"], .quarter: ["semiminima", "quarti"],
            .double: ["doppio", "raddoppia"], .half: ["metà", "dimezza"],
            .faster: ["più veloce", "accelera"], .slower: ["più lento", "rallenta"],
            .start: ["inizia", "avvia", "parti", "suona"], .stop: ["stop", "ferma", "pausa", "basta"],
            .up: ["alza", "sali", "in alto", "in su"], .down: ["abbassa", "scendi", "in basso", "giù"],
            .hour: ["un'ora", "un ora"], .halfHour: ["mezz'ora", "mezzora", "mezza ora"],
        ],
        numbers: ["uno": 1, "due": 2, "tre": 3, "quattro": 4, "cinque": 5, "sei": 6, "sette": 7,
                  "otto": 8, "dieci": 10, "quindici": 15, "venti": 20, "trenta": 30],
        phrases: [
            .help: "aiuto", .close: "chiudi", .done: "fatto", .practice: "esercizio",
            .louder: "più forte", .quieter: "più piano", .mute: "muto", .volume60: "volume 60",
            .scrollDown: "scorri in basso", .scrollUp: "scorri in alto", .start: "inizia", .stop: "ferma",
            .faster: "più veloce", .slower: "più lento", .tempo120: "tempo 120", .tune: "accordatore",
            .timer5: "timer 5 minuti", .timerOff: "spegni il timer", .bounce: "rimbalzo", .orbit: "orbita",
            .up: "alza", .down: "abbassa", .double: "doppio", .half: "metà", .threeBeats: "tre battiti",
            .quarter: "semiminima", .eighth: "croma", .triplet: "terzina", .sixteenth: "semicroma",
        ])

    static let russian = VoiceVocabulary(
        id: "ru", defaultLocale: "ru-RU",
        words: [
            .help: ["помощь", "справка", "команды"], .tuner: ["тюнер", "настро"],
            .timer: ["таймер"], .minute: ["минут"],
            .timerOff: ["выключи", "отмени", "убери", "сбрось"],
            .practice: ["тренировк", "тренаж", "практик", "упражнени"],
            .orbit: ["орбит", "круг"], .bounce: ["мяч", "прыж"],
            .view: ["смени вид", "сменить вид", "вид"],
            .mute: ["без звука", "выключи звук", "тишина"],
            .volume: ["громкость"], .louder: ["громче"], .quieter: ["тише"],
            .beat: ["доли", "долей", "доля"], .scroll: ["прокрут", "листай"],
            .close: ["закрой", "закрыть", "готово"],
            .sixteenth: ["шестнадцат"], .triplet: ["триол"], .eighth: ["восьм"], .quarter: ["четверт"],
            .double: ["удвой", "вдвое быстрее", "в два раза быстрее"],
            .half: ["половин", "вдвое медленнее", "в два раза медленнее"],
            .faster: ["быстрее"], .slower: ["медленнее"],
            .start: ["старт", "начни", "начать", "поехали", "играй", "запуск"],
            .stop: ["стоп", "останов", "пауза", "хватит"],
            .up: ["выше", "вверх", "повысь"], .down: ["ниже", "вниз", "понизь"],
            .hour: ["час"], .halfHour: ["полчаса"],
        ],
        numbers: ["один": 1, "одна": 1, "два": 2, "две": 2, "три": 3, "четыре": 4, "пять": 5,
                  "шесть": 6, "семь": 7, "восемь": 8, "десять": 10, "пятнадцать": 15,
                  "двадцать": 20, "тридцать": 30],
        phrases: [
            .help: "помощь", .close: "закрой", .done: "готово", .practice: "тренировка",
            .louder: "громче", .quieter: "тише", .mute: "без звука", .volume60: "громкость 60",
            .scrollDown: "прокрути вниз", .scrollUp: "прокрути вверх", .start: "старт", .stop: "стоп",
            .faster: "быстрее", .slower: "медленнее", .tempo120: "темп 120", .tune: "тюнер",
            .timer5: "таймер 5 минут", .timerOff: "выключи таймер", .bounce: "мяч", .orbit: "орбита",
            .up: "выше", .down: "ниже", .double: "удвой", .half: "половина", .threeBeats: "три доли",
            .quarter: "четверти", .eighth: "восьмые", .triplet: "триоли", .sixteenth: "шестнадцатые",
        ])

    static let dutch = VoiceVocabulary(
        id: "nl", defaultLocale: "nl-NL",
        words: [
            .help: ["help", "hulp"], .tuner: ["stemapparaat", "stemmen", "tuner"],
            .timer: ["timer", "wekker"], .minute: ["minu"],
            .timerOff: ["uit", "annuleer", "stop timer"],
            .practice: ["oefen", "trainer"],
            .orbit: ["baan", "cirkel", "rondje"], .bounce: ["stuiter", "bal"],
            .view: ["wissel weergave", "weergave"],
            .mute: ["dempen", "stil", "geluid uit"],
            .volume: ["volume"], .louder: ["harder", "luider"], .quieter: ["zachter"],
            .beat: ["tellen", "slagen"], .scroll: ["scroll"],
            .close: ["sluit", "klaar", "oké"],
            .sixteenth: ["zestiende"], .triplet: ["triool"], .eighth: ["achtste"], .quarter: ["kwart"],
            .double: ["dubbel", "verdubbel"], .half: ["half", "halveer"],
            .faster: ["sneller"], .slower: ["langzamer"],
            .start: ["start", "begin", "speel"], .stop: ["stop", "pauze", "halt"],
            .up: ["hoger", "omhoog"], .down: ["lager", "omlaag"],
            .hour: ["een uur"], .halfHour: ["half uur"],
        ],
        numbers: ["een": 1, "één": 1, "twee": 2, "drie": 3, "vier": 4, "vijf": 5, "zes": 6,
                  "zeven": 7, "acht": 8, "tien": 10, "vijftien": 15, "twintig": 20, "dertig": 30],
        phrases: [
            .help: "help", .close: "sluit", .done: "klaar", .practice: "oefenen",
            .louder: "harder", .quieter: "zachter", .mute: "dempen", .volume60: "volume 60",
            .scrollDown: "scroll omlaag", .scrollUp: "scroll omhoog", .start: "start", .stop: "stop",
            .faster: "sneller", .slower: "langzamer", .tempo120: "tempo 120", .tune: "stemapparaat",
            .timer5: "timer 5 minuten", .timerOff: "timer uit", .bounce: "stuiter", .orbit: "cirkel",
            .up: "hoger", .down: "lager", .double: "dubbel", .half: "half", .threeBeats: "drie tellen",
            .quarter: "kwart", .eighth: "achtste", .triplet: "triool", .sixteenth: "zestiende",
        ])

    static let polish = VoiceVocabulary(
        id: "pl", defaultLocale: "pl-PL",
        words: [
            .help: ["pomoc", "komendy"], .tuner: ["stroik", "strojenie", "tuner"],
            .timer: ["minutnik", "timer"], .minute: ["minut"],
            .timerOff: ["wyłącz", "anuluj", "usuń"],
            .practice: ["ćwicz", "trening"],
            .orbit: ["orbit", "okrąg", "koło"], .bounce: ["piłk", "piłeczk", "odbij"],
            .view: ["zmień widok", "widok"],
            .mute: ["wycisz", "bez dźwięku"],
            .volume: ["głośność"], .louder: ["głośniej"], .quieter: ["ciszej"],
            .beat: ["miar", "uderze"], .scroll: ["przewiń"],
            .close: ["zamknij", "gotowe", "okej"],
            .sixteenth: ["szesnast"], .triplet: ["triol"], .eighth: ["ósemk"], .quarter: ["ćwierć"],
            .double: ["podwój", "dwa razy szybciej"], .half: ["o połowę", "połowa", "dwa razy wolniej"],
            .faster: ["szybciej"], .slower: ["wolniej"],
            .start: ["start", "zacznij", "graj", "ruszaj"], .stop: ["stop", "zatrzymaj", "pauza", "przestań"],
            .up: ["wyżej", "w górę", "podnieś"], .down: ["niżej", "w dół", "obniż"],
            .hour: ["godzin"], .halfHour: ["pół godziny"],
        ],
        numbers: ["jeden": 1, "jedna": 1, "dwa": 2, "dwie": 2, "trzy": 3, "cztery": 4, "pięć": 5,
                  "sześć": 6, "siedem": 7, "osiem": 8, "dziesięć": 10, "piętnaście": 15,
                  "dwadzieścia": 20, "trzydzieści": 30],
        phrases: [
            .help: "pomoc", .close: "zamknij", .done: "gotowe", .practice: "trening",
            .louder: "głośniej", .quieter: "ciszej", .mute: "wycisz", .volume60: "głośność 60",
            .scrollDown: "przewiń w dół", .scrollUp: "przewiń w górę", .start: "start", .stop: "stop",
            .faster: "szybciej", .slower: "wolniej", .tempo120: "tempo 120", .tune: "stroik",
            .timer5: "minutnik 5 minut", .timerOff: "wyłącz minutnik", .bounce: "piłka", .orbit: "orbita",
            .up: "wyżej", .down: "niżej", .double: "podwój", .half: "o połowę", .threeBeats: "trzy miary",
            .quarter: "ćwierćnuty", .eighth: "ósemki", .triplet: "triole", .sixteenth: "szesnastki",
        ])

    static let turkish = VoiceVocabulary(
        id: "tr", defaultLocale: "tr-TR",
        words: [
            .help: ["yardım", "komutlar"], .tuner: ["akort", "tuner"],
            .timer: ["zamanlayıcı", "sayaç"], .minute: ["dakika"],
            .timerOff: ["kapat", "iptal", "durdur"],
            .practice: ["pratik", "alıştırma", "antrenman"],
            .orbit: ["yörünge", "daire", "çember"], .bounce: ["zıpla", "sekme"],
            .view: ["görünümü değiştir", "görünüm"],
            .mute: ["sessiz", "sesi kapat"],
            .volume: ["ses"], .louder: ["sesi aç", "sesli", "yükselt"], .quieter: ["kıs", "alçalt"],
            .beat: ["vuruş"], .scroll: ["kaydır"],
            .close: ["kapat", "tamam", "bitti"],
            .sixteenth: ["onaltılık", "on altılık"], .triplet: ["üçleme", "triole"],
            .eighth: ["sekizlik"], .quarter: ["dörtlük"],
            .double: ["iki katı", "ikiye katla"], .half: ["yarıya", "yarım hız"],
            .faster: ["hızlı", "hızlandır"], .slower: ["yavaş"],
            .start: ["başla", "çal"], .stop: ["dur", "duraklat"],
            .up: ["yukarı", "artır"], .down: ["aşağı", "azalt"],
            .hour: ["bir saat"], .halfHour: ["yarım saat"],
        ],
        numbers: ["bir": 1, "iki": 2, "üç": 3, "dört": 4, "beş": 5, "altı": 6, "yedi": 7, "sekiz": 8],
        tens: ["on": 10, "yirmi": 20, "otuz": 30, "kırk": 40, "elli": 50, "altmış": 60],
        phrases: [
            .help: "yardım", .close: "kapat", .done: "tamam", .practice: "pratik",
            .louder: "sesi aç", .quieter: "sesi kıs", .mute: "sessiz", .volume60: "ses 60",
            .scrollDown: "aşağı kaydır", .scrollUp: "yukarı kaydır", .start: "başla", .stop: "dur",
            .faster: "daha hızlı", .slower: "daha yavaş", .tempo120: "tempo 120", .tune: "akort",
            .timer5: "zamanlayıcı 5 dakika", .timerOff: "zamanlayıcıyı kapat", .bounce: "zıpla", .orbit: "yörünge",
            .up: "artır", .down: "azalt", .double: "iki katı", .half: "yarıya", .threeBeats: "üç vuruş",
            .quarter: "dörtlük", .eighth: "sekizlik", .triplet: "üçleme", .sixteenth: "onaltılık",
        ])

    static let swedish = VoiceVocabulary(
        id: "sv", defaultLocale: "sv-SE",
        words: [
            .help: ["hjälp"], .tuner: ["stämapparat", "stämma", "tuner"],
            .timer: ["timer", "nedräkning"], .minute: ["minut"],
            .timerOff: ["stäng av", "avbryt", "av"],
            .practice: ["öva", "övning", "träning"],
            .orbit: ["omloppsbana", "cirkel"], .bounce: ["studs", "boll"],
            .view: ["byt vy", "visning"],
            .mute: ["ljud av", "stäng av ljudet"],
            .volume: ["volym"], .louder: ["starkare", "högre ljud"], .quieter: ["tystare", "svagare"],
            .beat: ["slag"], .scroll: ["scrolla", "rulla"],
            .close: ["stäng", "klar", "färdig", "okej"],
            .sixteenth: ["sextondel"], .triplet: ["triol"], .eighth: ["åttondel"], .quarter: ["fjärdedel"],
            .double: ["dubbla", "dubbel"], .half: ["halvera", "halva"],
            .faster: ["snabbare"], .slower: ["långsammare"],
            .start: ["starta", "börja", "spela", "kör"], .stop: ["stopp", "stoppa", "paus", "sluta"],
            .up: ["upp", "högre", "öka"], .down: ["ner", "lägre", "sänk"],
            .hour: ["en timme"], .halfHour: ["halvtimme", "halv timme"],
        ],
        numbers: ["en": 1, "ett": 1, "två": 2, "tre": 3, "fyra": 4, "fem": 5, "sex": 6, "sju": 7,
                  "åtta": 8, "tio": 10, "femton": 15, "tjugo": 20, "trettio": 30],
        phrases: [
            .help: "hjälp", .close: "stäng", .done: "klar", .practice: "öva",
            .louder: "starkare", .quieter: "tystare", .mute: "ljud av", .volume60: "volym 60",
            .scrollDown: "scrolla ner", .scrollUp: "scrolla upp", .start: "starta", .stop: "stopp",
            .faster: "snabbare", .slower: "långsammare", .tempo120: "tempo 120", .tune: "stämapparat",
            .timer5: "timer 5 minuter", .timerOff: "stäng av timern", .bounce: "boll", .orbit: "cirkel",
            .up: "högre", .down: "lägre", .double: "dubbla", .half: "halvera", .threeBeats: "tre slag",
            .quarter: "fjärdedel", .eighth: "åttondel", .triplet: "triol", .sixteenth: "sextondel",
        ])

    static let danish = VoiceVocabulary(
        id: "da", defaultLocale: "da-DK",
        words: [
            .help: ["hjælp"], .tuner: ["stemmeapparat", "stem", "tuner"],
            .timer: ["timer", "nedtælling"], .minute: ["minut"],
            .timerOff: ["sluk", "annuller", "fjern"],
            .practice: ["øvelse", "øv", "træning"],
            .orbit: ["kredsløb", "cirkel"], .bounce: ["hop", "bold"],
            .view: ["skift visning", "visning"],
            .mute: ["lydløs", "slå lyden fra"],
            .volume: ["lydstyrke"], .louder: ["højere", "skru op"], .quieter: ["lavere", "skru ned"],
            .beat: ["slag"], .scroll: ["rul"],
            .close: ["luk", "færdig", "okay"],
            .sixteenth: ["sekstendedel"], .triplet: ["triol"], .eighth: ["ottendedel"], .quarter: ["fjerdedel"],
            .double: ["dobbelt", "fordobl"], .half: ["halver", "halvt"],
            .faster: ["hurtigere"], .slower: ["langsommere"],
            .start: ["start", "begynd", "spil"], .stop: ["stop", "pause"],
            .up: ["op"], .down: ["ned"],
            .hour: ["en time"], .halfHour: ["halv time", "halvtime"],
        ],
        numbers: ["en": 1, "et": 1, "to": 2, "tre": 3, "fire": 4, "fem": 5, "seks": 6, "syv": 7,
                  "otte": 8, "ti": 10, "femten": 15, "tyve": 20, "tredive": 30],
        phrases: [
            .help: "hjælp", .close: "luk", .done: "færdig", .practice: "øv",
            .louder: "højere", .quieter: "lavere", .mute: "lydløs", .volume60: "lydstyrke 60",
            .scrollDown: "rul ned", .scrollUp: "rul op", .start: "start", .stop: "stop",
            .faster: "hurtigere", .slower: "langsommere", .tempo120: "tempo 120", .tune: "stemmeapparat",
            .timer5: "timer 5 minutter", .timerOff: "sluk timeren", .bounce: "bold", .orbit: "cirkel",
            .up: "op", .down: "ned", .double: "fordobl", .half: "halver", .threeBeats: "tre slag",
            .quarter: "fjerdedel", .eighth: "ottendedel", .triplet: "triol", .sixteenth: "sekstendedel",
        ])

    static let norwegian = VoiceVocabulary(
        id: "nb", defaultLocale: "nb-NO",
        words: [
            .help: ["hjelp"], .tuner: ["stemmeapparat", "stemming", "tuner"],
            .timer: ["timer", "nedtelling"], .minute: ["minutt"],
            .timerOff: ["slå av", "avbryt", "fjern"],
            .practice: ["øving", "øv", "trening"],
            .orbit: ["bane", "sirkel"], .bounce: ["sprett", "ball"],
            .view: ["bytt visning", "visning"],
            .mute: ["lydløs", "demp", "stille"],
            .volume: ["volum"], .louder: ["høyere", "skru opp"], .quieter: ["lavere", "skru ned"],
            .beat: ["slag"], .scroll: ["rull"],
            .close: ["lukk", "ferdig", "greit"],
            .sixteenth: ["sekstendedel"], .triplet: ["triol"], .eighth: ["åttendedel"], .quarter: ["firedel", "kvart"],
            .double: ["doble", "dobbel"], .half: ["halver", "halv"],
            .faster: ["raskere", "fortere"], .slower: ["saktere", "langsommere"],
            .start: ["start", "begynn", "spill"], .stop: ["stopp", "pause"],
            .up: ["opp"], .down: ["ned"],
            .hour: ["en time"], .halfHour: ["halvtime", "halv time"],
        ],
        numbers: ["en": 1, "ett": 1, "to": 2, "tre": 3, "fire": 4, "fem": 5, "seks": 6, "sju": 7,
                  "syv": 7, "åtte": 8, "ti": 10, "femten": 15, "tjue": 20, "tretti": 30],
        phrases: [
            .help: "hjelp", .close: "lukk", .done: "ferdig", .practice: "øv",
            .louder: "høyere", .quieter: "lavere", .mute: "lydløs", .volume60: "volum 60",
            .scrollDown: "rull ned", .scrollUp: "rull opp", .start: "start", .stop: "stopp",
            .faster: "raskere", .slower: "saktere", .tempo120: "tempo 120", .tune: "stemmeapparat",
            .timer5: "timer 5 minutter", .timerOff: "slå av timeren", .bounce: "ball", .orbit: "sirkel",
            .up: "opp", .down: "ned", .double: "doble", .half: "halver", .threeBeats: "tre slag",
            .quarter: "firedel", .eighth: "åttendedel", .triplet: "triol", .sixteenth: "sekstendedel",
        ])

    static let finnish = VoiceVocabulary(
        id: "fi", defaultLocale: "fi-FI",
        words: [
            .help: ["apua", "ohje", "komennot"], .tuner: ["viritin", "viritys"],
            .timer: ["ajastin"], .minute: ["minuut"],
            .timerOff: ["pois", "peruuta", "sammuta"],
            .practice: ["harjoit", "treeni"],
            .orbit: ["kiertorata", "ympyrä"], .bounce: ["pomppu", "pallo"],
            .view: ["vaihda näkymä", "näkymä"],
            .mute: ["mykistä", "hiljaa"],
            .volume: ["ään"], .louder: ["kovemmalle", "kovempaa", "lujempaa"],
            .quieter: ["hiljemmälle", "hiljempää", "hiljemmäksi"],
            .beat: ["isku"], .scroll: ["vieritä"],
            .close: ["sulje", "valmis", "selvä"],
            .sixteenth: ["kuudestoistaosa"], .triplet: ["trioli"], .eighth: ["kahdeksasosa"], .quarter: ["neljäsosa"],
            .double: ["tuplaa", "kaksinkertai"], .half: ["puolita", "puoleen"],
            .faster: ["nopeammin", "nopeampaa"], .slower: ["hitaammin", "hitaampaa"],
            .start: ["aloita", "käynnistä", "soita"], .stop: ["seis", "lopeta", "pysäytä", "tauko"],
            .up: ["ylös", "nosta", "korkeammalle"], .down: ["alas", "laske", "matalammalle"],
            .hour: ["tunti"], .halfHour: ["puoli tuntia"],
        ],
        numbers: ["yksi": 1, "kaksi": 2, "kolme": 3, "neljä": 4, "viisi": 5, "kuusi": 6,
                  "seitsemän": 7, "kahdeksan": 8, "kymmenen": 10, "viisitoista": 15,
                  "kaksikymmentä": 20, "kolmekymmentä": 30],
        phrases: [
            .help: "apua", .close: "sulje", .done: "valmis", .practice: "harjoittele",
            .louder: "kovemmalle", .quieter: "hiljemmälle", .mute: "mykistä", .volume60: "äänenvoimakkuus 60",
            .scrollDown: "vieritä alas", .scrollUp: "vieritä ylös", .start: "aloita", .stop: "seis",
            .faster: "nopeammin", .slower: "hitaammin", .tempo120: "tempo 120", .tune: "viritin",
            .timer5: "ajastin 5 minuuttia", .timerOff: "ajastin pois", .bounce: "pallo", .orbit: "ympyrä",
            .up: "ylös", .down: "alas", .double: "tuplaa", .half: "puolita", .threeBeats: "kolme iskua",
            .quarter: "neljäsosa", .eighth: "kahdeksasosa", .triplet: "trioli", .sixteenth: "kuudestoistaosa",
        ])

    static let czech = VoiceVocabulary(
        id: "cs", defaultLocale: "cs-CZ",
        words: [
            .help: ["nápověda", "pomoc", "příkazy"], .tuner: ["ladička", "ladit"],
            .timer: ["časovač", "minutka"], .minute: ["minut"],
            .timerOff: ["vypni", "zruš", "odstraň"],
            .practice: ["cvič", "trénink"],
            .orbit: ["oběžn", "kruh"], .bounce: ["míček", "odraz"],
            .view: ["změň zobrazení", "zobrazení"],
            .mute: ["ztlum", "bez zvuku", "ticho"],
            .volume: ["hlasitost"], .louder: ["hlasitěji", "nahlas"], .quieter: ["tišeji", "potichu"],
            .beat: ["dob"], .scroll: ["posuň", "posunout", "rolovat"],
            .close: ["zavři", "zavřít", "hotovo"],
            .sixteenth: ["šestnáctin"], .triplet: ["triol"], .eighth: ["osmin"], .quarter: ["čtvrť", "čtvrtin"],
            .double: ["zdvojnásob", "dvojnásob"], .half: ["napůl", "polovin"],
            .faster: ["rychleji"], .slower: ["pomaleji"],
            .start: ["start", "spusť", "začni", "hraj"], .stop: ["stop", "zastav", "pauza"],
            .up: ["výš", "nahoru", "zvyš"], .down: ["níž", "dolů", "sniž"],
            .hour: ["hodin"], .halfHour: ["půl hodiny"],
        ],
        numbers: ["jedna": 1, "jeden": 1, "dva": 2, "dvě": 2, "tři": 3, "čtyři": 4, "pět": 5,
                  "šest": 6, "sedm": 7, "osm": 8, "deset": 10, "patnáct": 15, "dvacet": 20, "třicet": 30],
        phrases: [
            .help: "nápověda", .close: "zavři", .done: "hotovo", .practice: "cvičení",
            .louder: "hlasitěji", .quieter: "tišeji", .mute: "ztlum", .volume60: "hlasitost 60",
            .scrollDown: "posuň dolů", .scrollUp: "posuň nahoru", .start: "spusť", .stop: "stop",
            .faster: "rychleji", .slower: "pomaleji", .tempo120: "tempo 120", .tune: "ladička",
            .timer5: "časovač 5 minut", .timerOff: "vypni časovač", .bounce: "míček", .orbit: "kruh",
            .up: "výš", .down: "níž", .double: "zdvojnásob", .half: "napůl", .threeBeats: "tři doby",
            .quarter: "čtvrťové", .eighth: "osminy", .triplet: "trioly", .sixteenth: "šestnáctiny",
        ])

    static let indonesian = VoiceVocabulary(
        id: "id", defaultLocale: "id-ID",
        words: [
            .help: ["bantuan", "tolong"], .tuner: ["penyetel", "setem", "tuner"],
            .timer: ["timer", "pengatur waktu"], .minute: ["menit"],
            .timerOff: ["matikan", "batalkan", "hapus"],
            .practice: ["latihan"],
            .orbit: ["orbit", "lingkaran"], .bounce: ["pantul", "bola"],
            .view: ["ganti tampilan", "tampilan"],
            .mute: ["bisukan", "senyap", "bisu"],
            .volume: ["volume"], .louder: ["keraskan", "lebih keras", "besarkan"], .quieter: ["kecilkan", "lebih lirih"],
            .beat: ["ketukan"], .scroll: ["gulir"],
            .close: ["tutup", "selesai", "oke"],
            .sixteenth: ["seperenambelas"], .triplet: ["triol"], .eighth: ["seperdelapan"], .quarter: ["seperempat"],
            .double: ["gandakan", "dua kali lipat"], .half: ["setengah"],
            .faster: ["lebih cepat", "percepat", "cepat"], .slower: ["lebih lambat", "perlambat", "lambat"],
            .start: ["mulai", "putar", "jalankan"], .stop: ["berhenti", "stop", "jeda"],
            .up: ["naik", "atas"], .down: ["turun", "bawah"],
            .hour: ["satu jam"], .halfHour: ["setengah jam"],
        ],
        numbers: ["satu": 1, "dua": 2, "tiga": 3, "empat": 4, "lima": 5, "enam": 6, "tujuh": 7,
                  "delapan": 8, "sepuluh": 10],
        phrases: [
            .help: "bantuan", .close: "tutup", .done: "selesai", .practice: "latihan",
            .louder: "keraskan", .quieter: "kecilkan", .mute: "bisukan", .volume60: "volume 60",
            .scrollDown: "gulir ke bawah", .scrollUp: "gulir ke atas", .start: "mulai", .stop: "berhenti",
            .faster: "lebih cepat", .slower: "lebih lambat", .tempo120: "tempo 120", .tune: "penyetel",
            .timer5: "timer 5 menit", .timerOff: "matikan timer", .bounce: "bola", .orbit: "lingkaran",
            .up: "naik", .down: "turun", .double: "gandakan", .half: "setengah", .threeBeats: "tiga ketukan",
            .quarter: "seperempat", .eighth: "seperdelapan", .triplet: "triol", .sixteenth: "seperenambelas",
        ])

    static let vietnamese = VoiceVocabulary(
        id: "vi", defaultLocale: "vi-VN",
        words: [
            .help: ["trợ giúp", "giúp"], .tuner: ["chỉnh dây", "lên dây", "chỉnh âm"],
            .timer: ["hẹn giờ", "bộ đếm"], .minute: ["phút"],
            .timerOff: ["tắt", "hủy"],
            .practice: ["luyện tập", "tập luyện"],
            .orbit: ["quỹ đạo", "vòng tròn"], .bounce: ["nảy", "bóng"],
            .view: ["đổi chế độ xem", "chế độ xem"],
            .mute: ["tắt tiếng", "im lặng"],
            .volume: ["âm lượng"], .louder: ["to hơn", "lớn hơn"], .quieter: ["nhỏ hơn"],
            .beat: ["phách"], .scroll: ["cuộn"],
            .close: ["đóng", "xong", "được rồi"],
            .sixteenth: ["móc kép"], .triplet: ["liên ba", "chùm ba"], .eighth: ["móc đơn"], .quarter: ["nốt đen"],
            .double: ["gấp đôi"], .half: ["một nửa", "giảm nửa"],
            .faster: ["nhanh hơn", "nhanh lên"], .slower: ["chậm hơn", "chậm lại"],
            .start: ["bắt đầu", "chạy", "phát"], .stop: ["dừng", "ngừng"],
            .up: ["lên", "tăng"], .down: ["xuống", "giảm"],
            .hour: ["một tiếng", "một giờ"], .halfHour: ["nửa tiếng", "nửa giờ"],
        ],
        numbers: ["một": 1, "hai": 2, "ba": 3, "bốn": 4, "năm": 5, "sáu": 6, "bảy": 7, "tám": 8],
        phrases: [
            .help: "trợ giúp", .close: "đóng", .done: "xong", .practice: "luyện tập",
            .louder: "to hơn", .quieter: "nhỏ hơn", .mute: "tắt tiếng", .volume60: "âm lượng 60",
            .scrollDown: "cuộn xuống", .scrollUp: "cuộn lên", .start: "bắt đầu", .stop: "dừng",
            .faster: "nhanh hơn", .slower: "chậm hơn", .tempo120: "nhịp độ 120", .tune: "chỉnh dây",
            .timer5: "hẹn giờ 5 phút", .timerOff: "tắt hẹn giờ", .bounce: "bóng", .orbit: "quỹ đạo",
            .up: "lên", .down: "xuống", .double: "gấp đôi", .half: "một nửa", .threeBeats: "ba phách",
            .quarter: "nốt đen", .eighth: "móc đơn", .triplet: "liên ba", .sixteenth: "móc kép",
        ])

    static let greek = VoiceVocabulary(
        id: "el", defaultLocale: "el-GR",
        words: [
            .help: ["βοήθεια"], .tuner: ["κουρδιστήρι", "κούρδισμα"],
            .timer: ["χρονόμετρο", "χρονοδιακόπτ"], .minute: ["λεπτ"],
            .timerOff: ["κλείσε", "απενεργοποίη", "ακύρωσε", "σβήσε"],
            .practice: ["εξάσκηση", "προπόνηση"],
            .orbit: ["τροχιά", "κύκλος"], .bounce: ["αναπήδηση", "μπάλα"],
            .view: ["αλλαγή προβολής", "προβολή"],
            .mute: ["σίγαση", "σιωπή"],
            .volume: ["ένταση"], .louder: ["πιο δυνατά", "δυνάμωσε"], .quieter: ["πιο σιγά", "χαμήλωσε"],
            .beat: ["χτύπ", "χτυπ"], .scroll: ["κύλισε", "κύλιση"],
            .close: ["κλείσε", "κλείσιμο", "έτοιμο", "εντάξει"],
            .sixteenth: ["δέκατα έκτα", "δέκατο έκτο"], .triplet: ["τρίηχ"],
            .eighth: ["όγδοα", "όγδοο"], .quarter: ["τέταρτα", "τέταρτο"],
            .double: ["διπλάσια", "διπλασίασε"], .half: ["μισό"],
            .faster: ["πιο γρήγορα", "γρηγορότερα"], .slower: ["πιο αργά", "αργότερα"],
            .start: ["ξεκίνα", "έναρξη", "παίξε"], .stop: ["σταμάτα", "στοπ", "παύση"],
            .up: ["πάνω", "ανέβασε"], .down: ["κάτω", "κατέβασε"],
            .hour: ["μία ώρα", "μια ώρα"], .halfHour: ["μισή ώρα"],
        ],
        numbers: ["ένα": 1, "μία": 1, "δύο": 2, "τρία": 3, "τρεις": 3, "τέσσερα": 4, "πέντε": 5,
                  "έξι": 6, "επτά": 7, "εφτά": 7, "οκτώ": 8, "οχτώ": 8, "δέκα": 10,
                  "δεκαπέντε": 15, "είκοσι": 20, "τριάντα": 30],
        phrases: [
            .help: "βοήθεια", .close: "κλείσε", .done: "έτοιμο", .practice: "εξάσκηση",
            .louder: "πιο δυνατά", .quieter: "πιο σιγά", .mute: "σίγαση", .volume60: "ένταση 60",
            .scrollDown: "κύλισε κάτω", .scrollUp: "κύλισε πάνω", .start: "ξεκίνα", .stop: "σταμάτα",
            .faster: "πιο γρήγορα", .slower: "πιο αργά", .tempo120: "τέμπο 120", .tune: "κουρδιστήρι",
            .timer5: "χρονόμετρο 5 λεπτά", .timerOff: "κλείσε το χρονόμετρο", .bounce: "μπάλα", .orbit: "τροχιά",
            .up: "ανέβασε", .down: "κατέβασε", .double: "διπλάσια", .half: "μισό", .threeBeats: "τρία χτυπήματα",
            .quarter: "τέταρτα", .eighth: "όγδοα", .triplet: "τρίηχα", .sixteenth: "δέκατα έκτα",
        ])

    static let thai = VoiceVocabulary(
        id: "th", defaultLocale: "th-TH",
        words: [
            .help: ["ช่วยเหลือ", "วิธีใช้", "คำสั่ง"], .tuner: ["จูน", "ตั้งสาย"],
            .timer: ["จับเวลา", "ตั้งเวลา"], .minute: ["นาที"],
            .timerOff: ["ปิด", "ยกเลิก"],
            .practice: ["ฝึก", "ซ้อม"],
            .orbit: ["วงโคจร", "วงกลม"], .bounce: ["เด้ง", "ลูกบอล"],
            .view: ["เปลี่ยนมุมมอง", "มุมมอง"],
            .mute: ["ปิดเสียง", "เงียบ"],
            .volume: ["เสียง"], .louder: ["ดังขึ้น", "ดังกว่า"], .quieter: ["เบาลง", "ค่อยลง"],
            .beat: ["จังหวะ"], .scroll: ["เลื่อน"],
            .close: ["ปิด", "เสร็จ", "ตกลง"],
            .sixteenth: ["เขบ็ตสองชั้น"], .triplet: ["ทริปเล็ต", "สามพยางค์"],
            .eighth: ["เขบ็ตหนึ่งชั้น"], .quarter: ["ตัวดำ"],
            .double: ["สองเท่า"], .half: ["ครึ่ง"],
            .faster: ["เร็วขึ้น"], .slower: ["ช้าลง"],
            .start: ["เริ่ม", "เล่น"], .stop: ["หยุด"],
            .up: ["ขึ้น", "เพิ่ม"], .down: ["ลง", "ลด"],
            .hour: ["ชั่วโมง"], .halfHour: ["ครึ่งชั่วโมง"],
        ],
        numbers: ["หนึ่ง": 1, "สอง": 2, "สาม": 3, "สี่": 4, "ห้า": 5, "หก": 6, "เจ็ด": 7, "แปด": 8],
        phrases: [
            .help: "ช่วยเหลือ", .close: "ปิด", .done: "เสร็จ", .practice: "ฝึก",
            .louder: "ดังขึ้น", .quieter: "เบาลง", .mute: "ปิดเสียง", .volume60: "เสียง 60",
            .scrollDown: "เลื่อนลง", .scrollUp: "เลื่อนขึ้น", .start: "เริ่ม", .stop: "หยุด",
            .faster: "เร็วขึ้น", .slower: "ช้าลง", .tempo120: "เทมโป 120", .tune: "จูนเสียง",
            .timer5: "จับเวลา 5 นาที", .timerOff: "ปิดจับเวลา", .bounce: "เด้ง", .orbit: "วงโคจร",
            .up: "ขึ้น", .down: "ลง", .double: "สองเท่า", .half: "ครึ่ง", .threeBeats: "3 จังหวะ",
            .quarter: "ตัวดำ", .eighth: "เขบ็ตหนึ่งชั้น", .triplet: "ทริปเล็ต", .sixteenth: "เขบ็ตสองชั้น",
        ])
}

/// A command word as the screens quote it, in the language the mic listens for —
/// `Text("Say “\(voiceWord(.help))”…")`. The localized sentence around it keeps its
/// own quotes and grammar; only the word changes.
func voiceWord(_ phrase: VoiceVocabulary.Phrase) -> String {
    VoiceVocabulary.current.say(phrase)
}

// MARK: - The switch

/// English or the app language's own words — the same switch on the first-run page
/// and in Voice Commands. Each choice is written in its own language ("English | 한국어"),
/// so it needs no translation. Draws nothing when the app language has no table.
struct VoiceLanguagePicker: View {
    @AppStorage(VoiceLanguage.storageKey) private var language = VoiceLanguage.english.rawValue

    var body: some View {
        if let native = VoiceVocabulary.native {
            Picker("Command language", selection: $language) {
                Text(verbatim: "English").tag(VoiceLanguage.english.rawValue)
                Text(verbatim: native.displayName).tag(VoiceLanguage.native.rawValue)
            }
            .pickerStyle(.segmented)
        }
    }
}
