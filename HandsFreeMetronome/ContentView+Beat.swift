import SwiftUI
import UIKit
import AppIntents
import TipKit
import LeeoKit

/// The beat card: the editable grid and the three playing views (bounce, orbit, sweep).
/// Part of `ContentView`, split by area so an edit recompiles one small file.
extension ContentView {
    // MARK: Beat visualization — two selectable modes.
    //  • bounce: a pendulum ball arcs up/down and meets a dashed target ring at
    //    its centre resting point on every click — the contact "pops" (burst ring
    //    + scale) exactly as the sound fires.
    //  • orbit:  a dot circles a ring of beat markers (4/4 → 0/90/180/270°),
    //    landing on each marker on the beat at constant angular velocity.
    // While stopped, both fall back to the editable dot grid so the time signature
    // can still be tapped in.

    var vizMode: BeatVizMode { BeatVizMode(rawValue: vizModeRaw) ?? .bounce }

    var beatDots: some View {
        let playing = metronome.isPlaying
        return ZStack {
            if playing {
                switch vizMode {
                case .bounce: bounceViz.transition(.opacity)
                case .orbit:  orbitViz.transition(.opacity)
                case .sweep:  sweepViz.transition(.opacity)
                }
            } else {
                editableBeatGrid.transition(.opacity)
            }
        }
        // Cross-fade between the editable grid, bounce and orbit rather than snapping.
        .animation(.easeInOut(duration: 0.35), value: playing)
        .animation(.easeInOut(duration: 0.3), value: vizModeRaw)
        // Once playing, the setup cards fade out and the pendulum grows to fill the
        // screen — a clear switch to a focused "performance" view. In landscape
        // (compact height) the card flexes to whatever the column has left instead,
        // so the tempo card below it is never pushed off screen.
        // Unfolded it has a whole pane of its own, so it fills that too.
        .frame(height: beatFillsPane ? nil : (playing ? 340 : 200))
        .frame(maxHeight: beatFillsPane ? .infinity : nil)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(card)
        .overlay(alignment: .topTrailing) { vizModeButton.padding(12) }
        // Hint sits at the bottom edge as an overlay so it never nudges the content.
        .overlay(alignment: .bottom) {
            Text("\(metronome.beatsPerMeasure)/4  ·  tap dots to set beats")
                .font(.caption)
                // Small print needs 4.5:1 — system grey at this size falls just
                // short (accessibility audit), so a darker ink of the label colour.
                .foregroundStyle(Color(.label).opacity(0.7))
                // Grows with the text size: wraps onto a second line instead of clipping.
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .opacity(!hintDismissed && !playing ? 1 : 0)
                .accessibilityHidden(hintDismissed || playing)   // don't read the invisible hint
                .padding(.bottom, 6)
        }
        .coachAnchor("beat")
    }

    /// The beat card flexes to its space instead of a fixed height: landscape, or its own pane on an unfolded Duo.
    var beatFillsPane: Bool { vSizeClass == .compact || fold.isUnfolded || isStand }

    /// Small toggle that cycles bounce → orbit → sweep; its icon previews the NEXT view.
    var vizModeButton: some View {
        Button {
            vizModeRaw = vizMode.next.rawValue
            haptic.impactOccurred(intensity: 0.5)
            VizModeTip().invalidate(reason: .actionPerformed)
        } label: {
            Image(systemName: vizMode.next == .orbit ? "circle.circle"
                            : vizMode.next == .sweep ? "clock"
                            : "arrow.up.arrow.down")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .popoverTip(featureTips.currentTip as? VizModeTip)
        .accessibilityLabel(vizMode.next == .orbit ? "Switch to orbit view"
                          : vizMode.next == .sweep ? "Switch to ring sweep view"
                          : "Switch to bounce view")
        .accessibilityInputLabels(["Change view", "Metronome mode", "Switch view"])
    }

    /// The editable dot grid shown while stopped — tap a dot to set the meter.
    var editableBeatGrid: some View {
        let rows = dotRows(total: maxBeats)
        return VStack(spacing: 12) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 12) {
                    ForEach(rows[r], id: \.self) { i in
                        beatDot(i, active: i < metronome.beatsPerMeasure)
                    }
                }
            }
        }
    }

    /// Continuous phase (beats since the measure's beat 0) interpolated between the
    /// audio-accurate beat callbacks, so motion stays glued to the click.
    /// The beat views only move while the click plays (`beatPhase` is 0 otherwise), so
    /// the frame clock stops with it — an idle screen no longer redraws at 120 Hz.
    var vizPaused: Bool { reduceMotion || showHelpMarks || !metronome.isPlaying }

    func beatPhase(now: Date) -> Double {
        guard metronome.isPlaying, currentBeat >= 0 else { return 0 }
        let beatDuration = 60.0 / Double(metronome.bpm)
        let progress = min(1, max(0, now.timeIntervalSince(beatAnchor) / beatDuration))
        return Double(currentBeat) + progress
    }

    // MARK: Bounce visualization — a row of circles (one per beat) that rise and
    // fall separately, so a crest travels across them like a stadium wave (파도타기).

    var bounceViz: some View {
        let beats = metronome.beatsPerMeasure
        let sub = max(1, metronome.subdivision)
        // Beyond 1/8 a per-click swing blurs into jitter, so cap the pendulum at
        // one swing per beat — the ear still gets every click.
        let swings = sub <= 2 ? sub : 1
        return GeometryReader { geo in
            // Swing as wide as the card allows — the full ±110 in portrait, tighter in
            // landscape — keeping the popped ball (~55pt) inside the card's bounds.
            let amp = min(110, max(36, geo.size.height / 2 - 34))
            TimelineView(.animation(paused: vizPaused)) { timeline in
                let phase = beatPhase(now: timeline.date)
                // Gate on isPlaying too: right after a stop this view lingers for its
                // fade-out while `currentBeat` still holds the last beat but the phase
                // has already collapsed to 0 — without the gate `f` goes negative and
                // the click index below would subscript clickYs out of bounds (crash).
                let started = metronome.isPlaying && currentBeat >= 0
                let f = started ? min(1, max(0, phase - Double(currentBeat))) : 0   // 0…1 progress in the beat
                ZStack {
                    HStack(spacing: 8) {
                        ForEach(0..<beats, id: \.self) { i in
                            let base = i == 0 ? beatRed : cue          // downbeat is red
                            let active = started && i == currentBeat
                            // The active beat's ball crosses the centre ON each click and
                            // arcs out to an alternating extreme in between. Idle circles
                            // WAIT at the centre — where every swing begins and ends — so
                            // the hand-off from one beat to the next never jumps; only
                            // brightness/scale cross-fade.
                            let y = (active && !reduceMotion)
                                ? pendulumY(f, sub: swings, beat: i, amp: amp) : 0
                            // Pop on every CLICK: progress within the current click,
                            // 1 → 0 right after it fires — phase-derived, so it stays
                            // glued to the audio even when one swing spans four clicks.
                            let g = (f * Double(sub)).truncatingRemainder(dividingBy: 1)
                            let pop = (active && !reduceMotion && g < 0.3)
                                ? CGFloat(1 - g / 0.3) : 0
                            // Where the ball sits at the moment of each click — the
                            // sounding spots along the swing. Several clicks can share
                            // a spot (at 1/16 the ¾ point is struck on the way up AND
                            // down), so dedupe to one crisp dashed ring per height.
                            let clickYs = (0..<sub).map { k in
                                pendulumY(Double(k) / Double(sub), sub: swings, beat: i, amp: amp)
                            }
                            let targetYs = Array(Set(clickYs.map { ($0 * 2).rounded() / 2 })).sorted()
                            ZStack {
                                if active && !reduceMotion {
                                    // Dashed targets where the sound lives: the ball
                                    // meeting a ring IS a click, made visible — at 1/16
                                    // that's the centre, the ¾ point and the apex.
                                    ForEach(targetYs, id: \.self) { ty in
                                        Circle()
                                            .strokeBorder(base.opacity(0.55),
                                                          style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                                            .frame(width: 46, height: 46)
                                            .offset(y: ty)
                                    }
                                    // The pop: a ring bursts outward from whichever
                                    // target the ball is passing as its click fires.
                                    if pop > 0 {
                                        let k = max(0, min(sub - 1, Int(f * Double(sub))))
                                        Circle()
                                            .stroke(base, lineWidth: 2.5)
                                            .frame(width: 46, height: 46)
                                            .scaleEffect(1 + (1 - pop) * 1.2)
                                            .opacity(Double(pop))
                                            .offset(y: clickYs[k])
                                    }
                                }
                                Circle()
                                    .fill(base.opacity(active ? 1.0 : 0.4))
                                    .frame(width: 34, height: 34)
                                    // The ball itself pops too — a burst of scale on contact.
                                    .scaleEffect(active && !reduceMotion ? 1.3 + 0.25 * pop : 1.0)
                                    .offset(y: y)
                                    .shadow(color: active ? base.opacity(0.6) : .clear, radius: active ? 12 : 0)
                            }
                            .frame(width: 34, height: 34)   // ring overflow shouldn't widen the row
                            .animation(.easeInOut(duration: 0.16), value: currentBeat)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(width: geo.size.width, height: geo.size.height)   // centre in the card
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Beat \(max(1, currentBeat + 1)) of \(beats), \(MetronomeEngine.subdivisionName(for: sub))")
    }

    /// Ball height for progress `f` (0…1) through beat `beat`: a thrown-ball arc.
    /// The ball leaves the centre at full speed, decelerates under "gravity" to
    /// float at the apex, then accelerates back to cross the centre exactly ON the
    /// next click — so the contact moment is the fastest, sharpest point of the
    /// motion and easy to anticipate. Extremes alternate top/bottom per click.
    func pendulumY(_ f: Double, sub: Int, beat: Int, amp: CGFloat) -> CGFloat {
        let x = min(0.99999, max(0, f))
        let seg = x * Double(sub)
        let j = Int(seg)                            // which click within the beat
        let g = seg - Double(j)                     // 0…1 progress within the click
        let up = (beat * sub + j) % 2 == 0          // alternate extremes click by click
        let t = 2 * g - 1                           // -1 → 1 across the click
        let reach = CGFloat(1 - t * t)              // parabola: gravity ease in/out
        return (up ? -amp : amp) * reach
    }

    // MARK: Orbit visualization

    var orbitViz: some View {
        let beats = metronome.beatsPerMeasure
        let sub = max(1, metronome.subdivision)
        return TimelineView(.animation(paused: vizPaused)) { timeline in
            let phase = beatPhase(now: timeline.date)
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)
                let radius = side / 2 - 10
                let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                ZStack {
                    Circle()                              // the track
                        .stroke(Color(.systemGray4), lineWidth: 2.5)
                        .frame(width: radius * 2, height: radius * 2)
                        .position(center)
                    // Subdivision minor ticks between the beats — one extra dot per
                    // click, so 1/8 shows a midpoint, 1/16 shows three per beat.
                    // Each tick mirrors its click level: high = cue and larger,
                    // low = grey, a silent rest = barely-there.
                    if sub > 1 {
                        ForEach(0..<(beats * sub), id: \.self) { m in
                            if m % sub != 0 {
                                let level = metronome.clickLevel(at: m)
                                let pp = orbitPoint(beat: Double(m) / Double(sub), beats: beats, radius: radius, center: center)
                                Circle().fill(level == .high ? cue : Color(.systemGray2))
                                    .frame(width: level == .high ? 11 : 7,
                                           height: level == .high ? 11 : 7)
                                    .opacity(level == .mute ? 0.25 : 1)
                                    .position(pp)
                            }
                        }
                    }
                    // Fixed beat markers at equal angles, beat 1 at the top.
                    ForEach(0..<beats, id: \.self) { i in
                        let p = orbitPoint(beat: Double(i), beats: beats, radius: radius, center: center)
                        let lit = i == currentBeat
                        Circle()
                            .fill(lit ? (i == 0 ? beatRed : cue)
                                      : (i == 0 ? beatRed.opacity(0.45) : cue.opacity(0.4)))
                            .frame(width: 20, height: 20)
                            .scaleEffect(lit ? 1.5 : 1.0)     // grow via scale so it eases cleanly
                            .position(p)
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: currentBeat)
                    }
                    // The travelling dot.
                    let p = orbitPoint(beat: reduceMotion ? Double(max(0, currentBeat)) : phase,
                                       beats: beats, radius: radius, center: center)
                    let dotColor = currentBeat == 0 ? beatRed : cue
                    Circle()
                        .fill(dotColor)
                        .frame(width: 24, height: 24)
                        .shadow(color: dotColor.opacity(0.6), radius: 10)
                        .position(p)
                    // Timing verdict from tapping along — flashes in the ring's
                    // empty centre, then fades.
                    if let verdict = timingVerdict {
                        Text(verdict.label)
                            .font(.system(size: 36, weight: .heavy, design: .rounded))
                            .foregroundStyle(verdict.color(cue: cue, red: beatRed))
                            .position(center)
                            .transition(reduceMotion ? .opacity
                                        : .scale(scale: 0.6).combined(with: .opacity))
                    }
                    // Running tally of this run's taps, resting below the flash.
                    if timingStats.total > 0 {
                        timingStatsReadout
                            .position(x: center.x, y: center.y + 52)
                            .transition(.opacity)
                    }
                    // Afterimages: each tap freezes a ghost of the travelling dot
                    // where it was at that instant — how far it sits from a beat
                    // marker is your timing error, made visible on the ring.
                    ForEach(tapGhosts) { ghost in
                        GhostCircle(color: ghost.verdict.color(cue: cue, red: beatRed),
                                    reduceMotion: reduceMotion)
                            .position(orbitPoint(beat: ghost.phase, beats: beats,
                                                 radius: radius, center: center))
                    }
                }
            }
        }
        .contentShape(Rectangle())
        // Tap along with the click: the gap to the nearest click becomes a verdict.
        .onTapGesture { judgeTimingTap() }
        .accessibilityElement()
        .accessibilityLabel("Beat \(max(1, currentBeat + 1)) of \(beats), \(MetronomeEngine.subdivisionName(for: sub))")
        .accessibilityValue(timingStats.total == 0 ? ""
            : "\(timingStats.perfect) perfect, \(timingStats.good) good, \(timingStats.bad) bad")
        .accessibilityHint("Tap in rhythm to check your timing")
        .accessibilityAction(named: "Check timing") { judgeTimingTap() }
    }

    /// Wordless tally: one bubble per verdict colour with its tap count inside.
    var timingStatsReadout: some View {
        HStack(spacing: 10) {
            statBubble(timingStats.perfect, color: .green, symbol: "checkmark")
            statBubble(timingStats.good, color: cue, symbol: "circle")
            statBubble(timingStats.bad, color: beatRed, symbol: "xmark")
        }
        .accessibilityHidden(true)   // spoken via the orbit view's accessibilityValue
    }

    /// Text on a solid fill: bright cyan in dark mode needs black, everything else white.
    func ink(on fill: Color) -> Color {
        fill == cue ? .onCue : .white
    }

    func statBubble(_ count: Int, color: Color, symbol: String) -> some View {
        Text("\(count)")
            .font(.system(.headline, design: .rounded).weight(.bold))
            .monospacedDigit()
            .minimumScaleFactor(0.5)   // three-digit counts shrink to stay inside
            .foregroundStyle(ink(on: color))
            .frame(width: 34, height: 34)
            .background(Circle().fill(color))
            // Differentiate Without Color: perfect / good / bad also differ by mark.
            .overlay(alignment: .topTrailing) {
                if differentiateWithoutColor {
                    Image(systemName: symbol)
                        .font(.caption2.weight(.heavy))
                        .foregroundStyle(color)
                        .padding(3)
                        .background(Circle().fill(Color(.systemBackground)))
                        .offset(x: 6, y: -6)
                }
            }
    }

    /// Grade a tap by its distance to the nearest CLICK — the subdivision grid, so
    /// at 1/8 a full orbit offers 8 chances at a Perfect, at 1/16 sixteen. Within
    /// 10% of the click interval = Perfect, 25% = Good, anything worse = Bad. The
    /// travelling dot drops a fading ghost at the spot it held when the tap landed.
    func judgeTimingTap() {
        guard metronome.isPlaying, currentBeat >= 0 else { return }
        let clickDuration = 60.0 / Double(metronome.bpm) / Double(max(1, metronome.subdivision))
        let offset = Date().timeIntervalSince(beatAnchor)
            .truncatingRemainder(dividingBy: clickDuration)
        let error = min(offset, clickDuration - offset) / clickDuration
        let verdict: TimingVerdict = error <= 0.10 ? .perfect
                                   : error <= 0.25 ? .good
                                   : .bad
        timingToken += 1
        let token = timingToken
        withAnimation(.spring(duration: 0.25)) {
            timingVerdict = verdict
            timingStats.record(verdict)
        }
        let ghost = TapGhost(phase: beatPhase(now: Date()), verdict: verdict)
        tapGhosts.append(ghost)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            tapGhosts.removeAll { $0.id == ghost.id }
        }
        haptic.impactOccurred(intensity: verdict == .perfect ? 1.0 : 0.5)
        UIAccessibility.post(notification: .announcement, argument: verdict.label)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            guard timingToken == token else { return }   // a newer tap took over
            withAnimation(.easeOut(duration: 0.3)) { timingVerdict = nil }
        }
    }

    // MARK: Sweep visualization — a radial progress ring that fills over exactly
    // one beat (clock metaphor: zero learning curve) and "bursts" at 12 o'clock as
    // the click lands, with the beat number counting in the centre.

    var sweepViz: some View {
        let beats = metronome.beatsPerMeasure
        return TimelineView(.animation(paused: vizPaused)) { timeline in
            let phase = beatPhase(now: timeline.date)
            // Same guard as the bounce view: while fading out after a stop the phase
            // is already 0 but `currentBeat` isn't reset yet, so an unclamped `f`
            // would go negative for a frame (negative trim/scale glitches).
            let started = metronome.isPlaying && currentBeat >= 0
            let f = started ? min(1, max(0, phase - Double(currentBeat))) : 0   // 0…1 through the beat
            let color = currentBeat == 0 ? beatRed : cue        // downbeat sweeps red
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)
                let radius = side / 2 - 16
                let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                ZStack {
                    Circle()                                      // the track
                        .stroke(Color(.systemGray5), lineWidth: 10)
                        .frame(width: radius * 2, height: radius * 2)
                        .position(center)
                    Circle()                                      // this beat's fill
                        .trim(from: 0, to: reduceMotion ? 1 : CGFloat(f))
                        .stroke(color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))            // start/burst at 12 o'clock
                        .frame(width: radius * 2, height: radius * 2)
                        .position(center)
                    // The burst: right after the click a dot at 12 o'clock swells and
                    // fades — driven purely by the beat phase, so it stays glued to
                    // the audio with no extra state.
                    if started && !reduceMotion && f < 0.25 {
                        let b = CGFloat(f / 0.25)                 // 0…1 through the burst
                        Circle()
                            .fill(color)
                            .frame(width: 18, height: 18)
                            .scaleEffect(1 + b * 2.4)
                            .opacity(Double(1 - b))
                            .position(x: center.x, y: center.y - radius)
                    }
                    // Centre count-off, big enough to read from across the room.
                    Text("\(max(1, currentBeat + 1))")
                        .font(.system(size: 88, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(color)
                        .contentTransition(.numericText())
                        .position(center)
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Beat \(max(1, currentBeat + 1)) of \(beats)")
    }

    /// Position on the orbit ring for a (possibly fractional) beat index, with beat 0
    /// at 12 o'clock and advancing clockwise.
    func orbitPoint(beat: Double, beats: Int, radius: CGFloat, center: CGPoint) -> CGPoint {
        let angle = -Double.pi / 2 + (beat / Double(max(1, beats))) * 2 * .pi
        return CGPoint(x: center.x + radius * CGFloat(cos(angle)),
                       y: center.y + radius * CGFloat(sin(angle)))
    }

    /// One row up to 6 dots; 7+ split into two balanced rows (8 → 4 + 4).
    func dotRows(total: Int) -> [[Int]] {
        let all = Array(0..<total)
        guard total > 6 else { return [all] }
        let first = (total + 1) / 2
        return [Array(all[0..<first]), Array(all[first...])]
    }

    func beatDot(_ i: Int, active: Bool) -> some View {
        let sounding = isActive(i)
        // While playing, the resting dots sit low and the sounding one rises to the
        // top — so the wave swings through the full height (top ↔ bottom), not just
        // upward. A wide ±34 travel makes the swing read clearly across the room.
        // Idle (or Reduce Motion): centred, no motion.
        let lift: CGFloat = (reduceMotion || !metronome.isPlaying) ? 0 : (sounding ? -34 : 34)
        return Circle()
            .fill(active ? dotFill(i) : Color.clear)
            .overlay(Circle().strokeBorder(active ? .clear : inactiveOutline,
                                           lineWidth: contrast == .increased ? 2 : 1.5))
            .frame(width: 30, height: 30)
            // As the beat advances the crest travels across the row → stadium wave (파도타기).
            .offset(y: lift)
            .scaleEffect(sounding && !reduceMotion ? 1.3 : 1.0)   // Reduce Motion: no grow, brightness still marks the beat
            .shadow(color: sounding ? dotFill(i).opacity(0.6) : .clear, radius: sounding ? 9 : 0)
            // Linear over exactly one beat → constant speed, no spring accel/bounce.
            // Each beat one dot rises while its predecessor falls, so the crest
            // glides across at a steady pace (a constant-velocity 파도타기).
            .animation(.linear(duration: 60.0 / Double(metronome.bpm)), value: currentBeat)
            .animation(.easeOut(duration: 0.2), value: metronome.beatsPerMeasure)
            .animation(.easeInOut(duration: 0.25), value: metronome.isPlaying)  // settle on start/stop
            .contentShape(Circle())
            .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
            .onTapGesture {
                metronome.setBeatsPerMeasure(i + 1)
                haptic.impactOccurred(intensity: 0.5)
                withAnimation(.easeInOut(duration: 0.4)) { hintDismissed = true }
            }
            // Voice Control: say "Tap N beats" to set the time signature.
            .accessibilityLabel(Text("\(i + 1) beats"))
            .accessibilityInputLabels(["\(i + 1) beats", "Beat \(i + 1)", "\(i + 1)"])
            // VoiceOver: announce as a button, mark the current time signature selected.
            .accessibilityAddTraits(i + 1 == metronome.beatsPerMeasure ? [.isButton, .isSelected] : .isButton)
            .accessibilityHint("Sets \(i + 1)/4 time")
    }

    /// Outline of an unused beat — a hairline normally, a firm line with Increase Contrast.
    var inactiveOutline: Color {
        contrast == .increased ? Color(.systemGray) : Color(.systemGray3)
    }

    func isActive(_ i: Int) -> Bool { metronome.isPlaying && i == currentBeat }

    /// Fill for an active beat: the currently sounding one is bright
    /// (downbeat red, others cue); the rest keep their hue but dimmed, so the
    /// downbeat "1" still reads as red even while stopped.
    func dotFill(_ i: Int) -> Color {
        let hue = i == 0 ? beatRed : cue
        return isActive(i) ? hue : hue.opacity(contrast == .increased ? 0.8 : 0.5)
    }
}
