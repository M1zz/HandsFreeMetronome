# Not My Tempo — Hands-Free Metronome (iOS)

A metronome you control entirely by voice while playing an instrument — no screen
taps, and **no need to enable iOS system Voice Control or any Accessibility setting**.
The app listens through its own microphone using on-device speech recognition.

## Open & run
1. Unzip, then open `HandsFreeMetronome.xcodeproj` in Xcode 15+.
2. Select your team under Signing & Capabilities (Automatic signing).
3. Run on a real device (the simulator's mic/speech support is limited).
4. Tap **Listen** once and grant Microphone + Speech permission.

## Voice commands
- "start" / "stop" — play / pause
- "faster" / "slower" — ±5 BPM
- "up" / "down" — ±1 BPM
- "tempo 120" (or just a number) — set the value
- "double" / "half" — ×2 / ÷2
- "quarter" / "eighth" / "triplet" / "sixteenth" — subdivision per beat (1/2/3/4 clicks)
- "tune" — open the tuner; "help" — show commands; "close" / "done" — close a panel

Some Korean words are also recognized: 시작, 정지, 빠르게, 느리게, 16분, 8분, 셋잇단, 4분, 튜너, 닫아.

The last-used tempo, time signature, and subdivision are saved and restored on the
next launch.

## Time signatures
Pick the meter in the TIME SIGNATURE row (2/4 – 7/4). The beat dots adapt to the
count and beat 1 of every measure gets the loud accent + a stronger haptic.

## Detect tempo from music
Tap the waveform button (top-right of the tempo card). The app stops the click,
listens to nearby music for ~8 seconds, estimates the BPM (onset detection +
autocorrelation) and applies it. Accuracy varies with the source; very quiet or
beat-less music may fail, and half/double-tempo results are possible — tap "half"
/ "double" (or the ± buttons) to correct.

## Practicing 16th notes (4/4)
Pick **1/16** in the SUBDIVISION row (or say "sixteenth"). Each beat is split into
four evenly-spaced clicks; beat 1 of every measure is the loudest accent, the other
three beats are a medium click, and the in-between 16ths are quieter — so you always
hear where the beat is while playing all sixteen notes per measure.

## How it works
- `MetronomeEngine` — AVAudioEngine plays a programmatically generated click
  (no audio files needed); a high-priority dispatch timer keeps the beat. The timer
  ticks at the subdivision rate and picks one of three accent levels (measure
  downbeat / beat / subdivision) based on the position within the 4/4 measure.
- `VoiceController` — SFSpeechRecognizer with `requiresOnDeviceRecognition = true`,
  continuously re-listens so it keeps working between songs.
- Audio session uses `.playAndRecord` + `.mixWithOthers` so the click and the mic
  coexist. Use earphones to keep the click out of the mic for best accuracy.

Deployment target: iOS 16.0.

## Support & Privacy
- **Support:** https://m1zz.github.io/HandsFreeMetronome/
- **Privacy Policy:** https://m1zz.github.io/HandsFreeMetronome/privacy.html

The pages live in [`docs/`](docs/) ([support](docs/index.html) · [privacy](docs/privacy.html))
and are served via GitHub Pages.

### Publishing the pages (GitHub Pages)
This project isn't a git repo yet. To publish the support/privacy pages:

1. `git init && git add . && git commit -m "Initial commit"`
2. Create a GitHub repo named `HandsFreeMetronome` and push to it.
3. On GitHub: **Settings → Pages → Source: Deploy from a branch**, pick
   `main` and folder **`/docs`**, then save.
4. The pages go live at `https://<your-username>.github.io/HandsFreeMetronome/`
   (support) and `/privacy.html`. Update the two links above with your username.
