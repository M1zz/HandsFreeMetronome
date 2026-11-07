import SwiftUI
import UIKit
import AppIntents
import TipKit
import LeeoKit

/// Tempo, subdivision, accents, the voice strip, the transport and the help marks.
/// Part of `ContentView`, split by area so an edit recompiles one small file.
extension ContentView {
    // MARK: Tempo

    var tempoCard: some View {
        VStack(spacing: 10) {
            // The big display shows the Italian tempo term (Largo, Moderato…) by
            // default; tap to flip it to the raw BPM number and back.
            Text(tempoAsNumber ? "\(metronome.bpm)" : MetronomeEngine.tempoName(for: metronome.bpm))
                .font(.system(size: isStand ? standTempoSize : bpmFontSize, weight: .bold, design: .rounded))
                .lineLimit(1)
                .allowsTightening(true)   // "Prestissimo" tightens before it shrinks
                .minimumScaleFactor(0.5)
                .foregroundStyle(beatScale > 1.0 ? cue : Color.primary)
                .scaleEffect(beatScale)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) { tempoAsNumber.toggle() }
                    TempoDisplayTip().invalidate(reason: .actionPerformed)
                }
                .popoverTip(featureTips.currentTip as? TempoDisplayTip)
                .accessibilityLabel("Tempo")
                .accessibilityValue("\(metronome.bpm) BPM, \(MetronomeEngine.tempoName(for: metronome.bpm))")
                .accessibilityHint("Tap to switch between the tempo name and BPM")
                .accessibilityAddTraits(.isButton)
                .accessibilityInputLabels(["Tempo"])
                .accessibilityAction(named: "Tap tempo") { tapTempo() }   // VoiceOver keeps tap-tempo
            Text(tempoSubtitle)
                .font(isStand ? .system(size: standTempoSize * 0.3, weight: .semibold, design: .rounded) : .subheadline)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                // Readable grey: the system secondary colour misses 4.5:1 at this size.
                .foregroundStyle(metronome.speedTrainerOn ? cue : Color(.label).opacity(0.7))
            HStack(spacing: 16) {
                stepButton(systemName: "minus.circle.fill", delta: -1)
                Slider(value: bpmBinding, in: 30...260, step: 1)
                    .tint(cue)
                    .accessibilityLabel("Tempo")
                    .accessibilityValue("\(metronome.bpm) BPM")
                    .accessibilityInputLabels(["Tempo", "Tempo slider", "BPM"])
                stepButton(systemName: "plus.circle.fill", delta: 1)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(card)
        // The speed trainer has no button of its own (voice / Help launcher only),
        // so its tip anchors to the tempo card whose subtitle shows its status.
        .popoverTip(featureTips.currentTip as? PracticeTip)
        .coachAnchor("tempo")
    }

    var tempoSubtitle: String {
        // Trainer status takes over the subtitle when it's running.
        if metronome.speedTrainerOn {
            return String(localized: "Speed trainer · +\(metronome.trainerStep) every \(metronome.trainerBars) bars → \(metronome.trainerTarget)")
        }
        // Show whichever representation the big display isn't showing, so the BPM
        // number is always visible somewhere.
        return tempoAsNumber
            ? MetronomeEngine.tempoName(for: metronome.bpm)
            : String(localized: "\(metronome.bpm) BPM")
    }

    // MARK: Subdivision — tap a ring that shows how the beat is divided

    var subdivisionCard: some View {
        let options: [(seg: Int, value: Int, label: String, name: String)] =
            [(1, 1, "1/4", String(localized: "Quarter notes")), (2, 2, "1/8", String(localized: "Eighth notes")),
             (3, 3, "Trip", String(localized: "Triplets")), (4, 4, "1/16", String(localized: "Sixteenth notes"))]
        return HStack(spacing: 8) {
            ForEach(options, id: \.value) { opt in
                let selected = metronome.subdivision == opt.value
                Button {
                    metronome.setSubdivision(opt.value)
                    haptic.impactOccurred(intensity: 0.5)
                } label: {
                    SegmentedRing(segments: opt.seg,
                                  color: selected ? cue : Color(.systemGray3))
                        .frame(width: 40, height: 40)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 12)
                            .fill(selected ? cue.opacity(0.14) : .clear))
                        // Differentiate Without Color / Increase Contrast: the faint tint
                        // alone is too weak a "selected" cue — outline it as well.
                        .overlay {
                            if selected && (differentiateWithoutColor || contrast == .increased) {
                                RoundedRectangle(cornerRadius: 12).strokeBorder(cue, lineWidth: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(opt.name)
                .accessibilityInputLabels([opt.name, opt.label])
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                // No on-screen Accents button — VoiceOver reaches the editor here.
                .accessibilityAction(named: "Edit accents") { openAccents() }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(card)
        // Double-tap the card to open the accent grid (documented in Help — there is
        // no separate button). Simultaneous, so the first tap still selects normally.
        // Quarters are editable too: each beat of the measure is its own cell.
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            haptic.impactOccurred(intensity: 0.6)
            openAccents()
        })
        // First-run hint — the double-tap is otherwise invisible.
        .popoverTip(featureTips.currentTip as? AccentGridTip)
        .coachAnchor("sub")
    }

    // MARK: Accent grid modal — the WHOLE measure as a step-sequencer grid: one row
    // per beat, one cell per click, so 4/4 with sixteenths shows all 16 clicks as
    // individually tappable cells cycling high → low → silent.

    var accentsSheet: some View {
        let sub = max(1, metronome.subdivision)
        let beats = metronome.beatsPerMeasure
        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Every click of the measure is its own cell — \(beats * sub) clicks in all. Tap a cell to cycle it: high → low → silent.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if sub == 1 {
                        // Undivided: a single row, one cell per beat, numbered below.
                        HStack(spacing: 6) {
                            ForEach(0..<beats, id: \.self) { b in
                                VStack(spacing: 4) {
                                    accentCell(tick: b, sub: sub)
                                    Text("\(b + 1)")
                                        .font(.caption2.weight(.semibold))
                                        .monospacedDigit()
                                        .foregroundStyle(b == 0 ? beatRed : .secondary)
                                }
                            }
                        }
                    } else {
                        VStack(spacing: 8) {
                            ForEach(0..<beats, id: \.self) { b in
                                HStack(spacing: 12) {
                                    Text("\(b + 1)")
                                        .font(.subheadline.weight(.semibold))
                                        .monospacedDigit()
                                        .foregroundStyle(b == 0 ? beatRed : .secondary)
                                        .frame(width: 22, alignment: .center)
                                    HStack(spacing: 6) {
                                        ForEach(0..<sub, id: \.self) { i in
                                            accentCell(tick: b * sub + i, sub: sub)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    presetsSection
                }
                .padding(20)
                .animation(.easeInOut(duration: 0.15), value: metronome.accentLevels)
            }
            .navigationTitle("Accents")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { metronome.resetAccents() } label: {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                    }
                        .accessibilityHint("Restores the default pattern for this meter")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { panel = nil } label: { Label("Done", systemImage: "checkmark") }
                }
            }
            .alert("Save preset", isPresented: $showSavePreset) {
                TextField("Name (e.g. Bossa intro)", text: $presetNameDraft)
                    .submitLabel(.done)
                    .onSubmit { savePresetDraft() }
                Button("Save") { savePresetDraft() }
                Button("Cancel", role: .cancel) { presetNameDraft = "" }
            } message: {
                Text("Saves this pattern with its meter and subdivision, so you can recall it per song.")
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// Saves the pattern on screen under the typed name (Save button or Return).
    func savePresetDraft() {
        let before = metronome.accentPresets.count
        metronome.saveAccentPreset(named: presetNameDraft)
        presetNameDraft = ""
        showSavePreset = false
        guard metronome.accentPresets.count > before else { return }   // blank name: nothing saved
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        AccessibilityNotification.Announcement(String(localized: "Preset saved")).post()
        // Building a pattern for a song is real investment in the app.
        LeeoEngagement.shared.registerSignificantEvent()
    }

    /// One cell of the accent grid. Each tap cycles high → low → silent. A tall bar
    /// marks a high click, a short one low, none a rest — reads at a glance,
    /// colorblind-safe.
    func accentCell(tick: Int, sub: Int) -> some View {
        let level = metronome.clickLevel(at: tick)
        return Button {
            metronome.cycleClickLevel(at: tick)
            haptic.impactOccurred(intensity: 0.4)
        } label: {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(level == .high ? cue
                    : level == .low ? Color(.systemGray5)
                    : Color(.systemGray6))
                .frame(height: 44)
                .frame(maxWidth: .infinity)
                .overlay {
                    if level == .mute {
                        // A rest: an empty, dashed cell.
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color(.systemGray3),
                                          style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                    } else {
                        Capsule()
                            .fill(level == .high ? Color.onCue : Color(.systemGray2))
                            .frame(width: 4, height: level == .high ? 22 : 10)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Beat \(tick / sub + 1), click \(tick % sub + 1)")
        .accessibilityValue(level == .high ? "High tone" : level == .low ? "Low tone" : "Silent")
        .accessibilityHint("Cycles between high, low, and silent")
        .accessibilityInputLabels(["Beat \(tick / sub + 1) click \(tick % sub + 1)"])
    }

    /// Saved patterns: recall one per song (it restores its meter + subdivision too),
    /// or snapshot the pattern on screen under a new name.
    var presetsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Presets")
                .font(.subheadline.weight(.semibold))
            if metronome.accentPresets.isEmpty {
                // Empty state with its own way out: the save button lives inside it.
                ContentUnavailableView {
                    Label("No presets yet", systemImage: "square.stack")
                        .font(.headline)
                } description: {
                    Text("Save a pattern per song — recalling it also restores its meter and subdivision.")
                        .font(.footnote)
                } actions: {
                    savePresetButton
                }
                .padding(.vertical, -12)   // sits inside a sheet; drop the full-screen padding
            }
            ForEach(metronome.accentPresets) { preset in
                HStack(spacing: 10) {
                    Button {
                        metronome.applyAccentPreset(preset)
                        haptic.impactOccurred(intensity: 0.5)
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(preset.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                // Long song names keep their start and end ("Bossa … outro").
                                .lineLimit(2)
                                .truncationMode(.middle)
                            Text("\(preset.beats)/4 · \(MetronomeEngine.subdivisionName(for: preset.sub))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Preset \(preset.name)")
                    .accessibilityHint("Applies this pattern, meter, and subdivision")
                    .accessibilityInputLabels([preset.name])
                    Button {
                        metronome.deleteAccentPreset(preset)
                        haptic.impactOccurred(intensity: 0.4)
                    } label: {
                        Image(systemName: "trash")
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Delete preset \(preset.name)")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.tertiarySystemGroupedBackground)))
            }
            if !metronome.accentPresets.isEmpty { savePresetButton }
        }
        .padding(.top, 4)
    }

    var savePresetButton: some View {
        Button {
            showSavePreset = true
        } label: {
            Label("Save current pattern…", systemImage: "plus.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(cue)
        }
        .accessibilityInputLabels(["Save pattern", "Save preset"])
    }

    // MARK: Voice status + help

    /// A slim, elegant voice strip: a small live waveform + one line that reads
    /// "Listening…" (or the last command in gold), with the help button trailing.
    var voiceCard: some View {
        HStack(spacing: 10) {
            if voice.isListening {
                VoiceWaveform(level: voice.level, color: cue).frame(width: 40, height: 16)
            } else {
                Image(systemName: "mic.slash.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            Text(voice.isListening
                 ? (lastCommandText.isEmpty ? String(localized: "Listening…") : lastCommandText)
                 : micMessage)
                .font(.subheadline.weight(voice.isListening && !lastCommandText.isEmpty ? .semibold : .regular))
                // Mic off: this line is the instruction for turning it back on,
                // so it reads at full contrast (the audit flagged grey-on-card).
                .foregroundStyle(voice.isListening
                                 ? (lastCommandText.isEmpty ? Color.secondary : cue)
                                 : .primary)
                // Wraps at large text sizes instead of shrinking out of reach.
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button { showHelp() } label: {
                Image(systemName: "questionmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Help")
            .accessibilityInputLabels(["Help", "Tips", "Voice commands"])
            .popoverTip(HelpVoiceTip())
            Button { present(.settings) } label: {
                Image(systemName: "gearshape.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Settings")
            .accessibilityInputLabels(["Settings", "Pro", "Unlock Pro"])
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity)
        // This strip is far shorter than the other cards, where the shared 16pt
        // radius reads as a capsule; a tighter radius keeps the same rectangular
        // look as every other box on screen.
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground)))
        // The tuner is voice-first ("tune"), so its tip sits on the voice strip.
        .popoverTip(featureTips.currentTip as? TunerTip)
        .coachAnchor("voice")
    }

    // MARK: Transport

    var transportBar: some View {
        HStack(spacing: 12) {
            Button { voice.toggle() } label: {
                // When listening, this is the Mute control (speaker symbol). As each
                // command lands, its name flashes here for a moment, then it settles
                // back to "Mute" — press again to toggle listening.
                let flashing = flashingCommand && voice.isListening && !lastCommandText.isEmpty
                transportLabel(flashing ? lastCommandText
                                        : (voice.isListening ? String(localized: "Mute") : String(localized: "Listen")),
                               icon: flashing ? "checkmark.circle.fill"
                                     : (voice.isListening ? "speaker.wave.2.fill" : "mic"),
                               // Off state: muted, but dark enough to read (4.5:1) —
                               // system grey on its own tinted fill fell short in the audit.
                               color: voice.isListening ? cue : Color(.label).opacity(0.7),
                               filled: false,
                               // At accessibility text sizes three labelled buttons can't
                               // share a row — this one goes icon-only so Start keeps its word.
                               iconOnly: dynamicTypeSize.isAccessibilitySize)
                    .overlay {
                        // Border countdown: drains toward the auto-mute moment.
                        if voice.isListening {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .trim(from: 0, to: muteProgress)
                                .stroke(cue, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                                .allowsHitTesting(false)
                        }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(voice.isListening ? "Mute voice control" : "Listen for voice")
            .accessibilityInputLabels(voice.isListening
                ? ["Mute", "Stop listening"]
                : ["Listen", "Start listening"])
            .popoverTip(MicListeningTip())   // first-run guidance for plain mic users

            Button { metronome.toggle() } label: {
                transportLabel(metronome.isPlaying ? String(localized: "Stop") : String(localized: "Start"),
                               icon: metronome.isPlaying ? "stop.fill" : "play.fill",
                               color: metronome.isPlaying ? .red : cue,
                               filled: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(metronome.isPlaying ? "Stop metronome" : "Start metronome")
            .accessibilityInputLabels(metronome.isPlaying
                ? ["Stop", "Stop metronome", "Pause"]
                : ["Start", "Start metronome", "Play"])
            .popoverTip(VoiceControlTip())   // first-run guidance for Voice Control users
            .coachAnchor("start")
        }
    }

    /// Practice timer: a card just above the transport, styled like the tempo and
    /// subdivision cards. The time left is large enough to read from the music stand
    /// while playing. Tap to set it up.
    var timerRow: some View {
        let on = metronome.practiceTimerOn
        return Button { openTimer() } label: {
            HStack(spacing: 12) {
                Image(systemName: "timer")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(on ? cue : Color(.label).opacity(0.7))
                    .accessibilityHidden(true)
                Text("Practice timer")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 8)
                Text(on ? timerText(metronome.practiceTimerRemaining) : String(localized: "Off"))
                    // Running: big enough to read at a glance. Off: just a quiet word.
                    .font(on ? .system(size: isStand ? 56 : 36, weight: .bold, design: .rounded)
                             : .headline.weight(.regular))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    .foregroundStyle(on ? cue : Color(.label).opacity(0.7))
                    .minimumScaleFactor(0.6)
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .lineLimit(1)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(card)
            .contentShape(Rectangle())
            .animation(.default, value: metronome.practiceTimerRemaining)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Practice timer")
        .accessibilityValue(on ? timerSpokenValue : String(localized: "Off"))
        .accessibilityAddTraits(.isButton)
        .accessibilityInputLabels(["Timer", "Practice timer"])
        .coachAnchor("timer")
    }

    /// "4:05" — minutes are not padded, so up to 120:00 stays compact.
    func timerText(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    var timerSpokenValue: String {
        let left = Duration.seconds(metronome.practiceTimerRemaining)
        return String(localized: "\(left.formatted(.units(allowed: [.minutes, .seconds], width: .wide))) left")
    }

    /// Button outlines: soft by default, solid enough to see with Increase Contrast.
    var outlineOpacity: Double { contrast == .increased ? 0.85 : 0.35 }

    func transportLabel(_ title: String, icon: String, color: Color, filled: Bool,
                                iconOnly: Bool = false) -> some View {
        Label(title, systemImage: icon)
            .labelStyle(TransportLabelStyle(iconOnly: iconOnly))
            .font(.headline)
            // A flashed command name may be longer, and text may be large:
            // wrap to a second line rather than shrink.
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .foregroundStyle(filled ? ink(on: color) : color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(filled ? color : color.opacity(0.15)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(color.opacity(filled ? 0 : outlineOpacity), lineWidth: 1.5))
    }

    // MARK: Help marks ("help" → highlight every on-screen control + its command)

    /// The voice phrase shown beside each highlighted control. Only controls that are
    /// actually on screen (have a captured anchor) get a mark, so it always matches
    /// the current screen.
    func helpPhrase(for id: String) -> String {
        switch id {
        case "beat":  return "\u{201C}\(voiceWord(.bounce))\u{201D} / \u{201C}\(voiceWord(.orbit))\u{201D}"
        case "tempo": return "\u{201C}\(voiceWord(.faster))\u{201D} · \u{201C}\(voiceWord(.tempo120))\u{201D}"
        case "sub":   return "\u{201C}\(voiceWord(.quarter))\u{201D} · \u{201C}\(voiceWord(.eighth))\u{201D} · \u{201C}\(voiceWord(.triplet))\u{201D} · \u{201C}\(voiceWord(.sixteenth))\u{201D}"
        case "voice": return "\u{201C}\(voiceWord(.help))\u{201D} · \u{201C}\(voiceWord(.close))\u{201D}"
        case "start": return metronome.isPlaying ? "\u{201C}\(voiceWord(.stop))\u{201D}" : "\u{201C}\(voiceWord(.start))\u{201D}"
        case "timer": return "\u{201C}\(voiceWord(.timer5))\u{201D}"
        default:      return ""
        }
    }

    func helpMarksOverlay(_ anchors: [String: Anchor<CGRect>], _ proxy: GeometryProxy) -> some View {
        let ids = ["beat", "tempo", "sub", "voice", "timer", "start"].filter { anchors[$0] != nil }
        return ZStack(alignment: .topLeading) {
            // Reduce Transparency: a near-solid scrim, so the busy screen behind
            // never shows through the callouts.
            Color.black.opacity(reduceTransparency ? 0.92 : 0.6).ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { dismissHelpMarks() }
                .accessibilityLabel("Dismiss help")
                .accessibilityAction { dismissHelpMarks() }
            // A ring + a "say …" pill on every visible control. The pill sits at the
            // centre of its own control, so pills never overlap each other (each stays
            // within its control's bounds).
            ForEach(ids, id: \.self) { id in
                // `ids` is filtered on this dictionary, but never force-unwrap in
                // a view body — a stale re-evaluation must degrade, not crash.
                if let anchor = anchors[id] {
                    let rect = proxy[anchor]
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(cue, lineWidth: 2.5)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .allowsHitTesting(false)
                    helpPill(helpPhrase(for: id))
                        .frame(maxWidth: max(140, rect.width - 24))
                        .fixedSize(horizontal: false, vertical: true)
                        .position(x: rect.midX, y: rect.midY)
                }
            }
            // Persistent instructions + escape hatches, pinned near the TOP edge.
            VStack {
                HStack(spacing: 12) {
                    Label("Say \u{201C}\(voiceWord(.close))\u{201D} or tap to dismiss", systemImage: "xmark.circle")
                        .font(.footnote.weight(.medium)).foregroundStyle(.white)
                        .lineLimit(2).minimumScaleFactor(0.8)
                    Spacer(minLength: 8)
                    Button { dismissHelpMarks(); present(.commands) } label: {
                        Text("All commands")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(Color.onCue)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Capsule().fill(cue))
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(reduceTransparency ? Color.black : Color.black.opacity(0.45)))
                .padding(.horizontal, 16)
                .padding(.top, 52)   // clear the status bar / notch
                Spacer()
            }
        }
    }

    /// A small "say …" callout tag placed next to a highlighted control.
    func helpPill(_ phrase: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("say").font(.caption2.weight(.bold)).foregroundStyle(cue)
            Text(phrase).font(.footnote.weight(.semibold)).foregroundStyle(.primary)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(.systemBackground))
            .shadow(color: .black.opacity(0.3), radius: 8, y: 2))
        .overlay {
            if contrast == .increased {
                RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(cue, lineWidth: 1.5)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
