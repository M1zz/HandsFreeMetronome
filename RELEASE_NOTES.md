# Release Notes — Not My Tempo

## 1.0.2

이번 업데이트는 **비트 시각화와 핸즈프리 조작**을 대폭 개선했습니다. 진자를 두 가지
모드로 새로 만들고, 거의 모든 기능을 음성으로 제어할 수 있게 했습니다.

This update reimagines the **beat visualization and hands-free control** — two new
pendulum modes, plus voice control for nearly everything.

### App Store (한국어)

- 두 가지 진자 모드: 위아래로 등속 왕복하는 **진자(파형)** 와 원을 도는 **오빗(원형)**. 탭 또는 음성으로 전환합니다.
- 분할(1/8·트리플렛·1/16)을 진자가 위·아래 지점을 등속으로 왕복하며 타격해 시각적으로 보여줍니다.
- 재생을 시작하면 화면이 **진자와 템포만 남는 집중(퍼포먼스) 모드**로 전환되고, 진자가 커집니다.
- 음성 명령을 대폭 확장했습니다 — 볼륨("louder"/"quieter"/"mute"), 박자수("three beats"), 화면 전환("bounce"/"orbit"), 연습 모드("practice").
- "help"라고 하면 지금 화면에서 조작할 수 있는 **모든 컨트롤이 한 번에 강조**되고, 각 옆에 말할 명령이 표시됩니다.
- 템포를 이탈리아어 빠르기말(Largo·Moderato…)로 표시하고, 탭하면 BPM 숫자로 바뀝니다.
- 명령을 인식하면 버튼에 인식된 명령이 잠깐 표시됩니다.
- 연습 중 화면이 꺼지지 않도록 했고, 색상을 더 또렷하게 다듬었습니다.

### App Store (English)

- Two pendulum modes: a constant-speed **bounce (waveform)** and an **orbit (circular)** dot. Switch by tap or voice.
- Subdivisions (1/8, triplets, 1/16) are shown by the ball striking fixed top/bottom marks at a steady pace.
- Starting playback switches to a **focused performance view — just the pendulum and tempo** — and the pendulum grows.
- Greatly expanded voice control — volume ("louder"/"quieter"/"mute"), time signature ("three beats"), view ("bounce"/"orbit"), and practice mode ("practice").
- Say "help" to **highlight every control on screen at once**, each tagged with the command that drives it.
- Tempo shows as an Italian term (Largo, Moderato…); tap to flip to the BPM number.
- Recognized commands flash on the button for a moment.
- The screen no longer sleeps while playing, and colors are crisper.

### Details

**Beat visualization**
- New **bounce** and **orbit** modes (choice persisted), driven by a continuous phase interpolated from the audio-accurate beat callbacks for smooth, constant-velocity motion.
- Subdivision is visualized by the active beat's ball swinging to strike fixed top/bottom hit-markers (1/8 = top & bottom, 1/16 = two round-trips); each marker flashes on contact. Orbit shows subdivision minor ticks.
- Smoother beat hand-off (idle circles wait on the top line — no position jump; brightness/scale cross-fade), larger pendulum, and a more saturated gold / vivid downbeat red.

**Performance view**
- On play, the setup cards fade out and the beat area grows so only the pendulum and tempo remain; stopping restores the full layout.

**Voice & help**
- New commands: `louder` / `quieter` / `mute` / `volume 60`, `three beats`, `bounce` / `orbit`, and `practice`.
- Help redesigned as **all-at-once coach marks** — every on-screen control is ringed and tagged with its voice command (via anchor preferences); the full command & settings sheet sits behind an "All commands" button.
- Listen/Mute button shows a speaker symbol and briefly flashes the recognized command; the voice status is now a slim strip.

**Other**
- Practice (speed trainer) moved into its own modal.
- Tempo term ↔ BPM tap toggle; screen stays awake while playing; the volume slider was removed (control it by voice).
- The app is now English-only.

## 1.0.1

이번 업데이트는 **접근성**에 집중했습니다. 눈이 보이지 않거나 손을 쓰기 어려운
분도 메트로놈과 튜너를 온전히 사용할 수 있도록 했고, 가로모드도 새로 지원합니다.

This update is all about **accessibility** — so the metronome and tuner work
fully whether you rely on the screen reader, your voice, or just one hand — plus
new landscape support.

### App Store (한국어)

- 가로모드를 지원합니다. 화면을 돌려도 모든 기능이 한 화면에 보이도록 2단으로 재배치됩니다.
- VoiceOver를 완벽 지원합니다. 템포·튜너 값을 음성으로 읽어주고, 선택 상태를 알려주며, 장식 요소는 건너뜁니다.
- 처음 실행할 때 VoiceOver가 켜져 있으면, 음성 조작 방법을 음성으로 안내합니다.
- 보이스 컨트롤(음성 제어)로 모든 버튼을 이름으로 부를 수 있습니다.
- "동작 줄이기"를 켜면 박자 애니메이션이 차분해집니다(박자는 점의 밝기로 계속 표시).
- "색상 구분 없이"를 켜면 튜너가 색 대신 기호로 음정을 표시합니다.
- 박자 점을 카드 가운데에 정렬하고, 안내 문구가 잠시 후 자연스럽게 사라지도록 다듬었습니다.

### App Store (English)

- Landscape support — rotate your device and everything stays on one screen with a new two-column layout.
- Full VoiceOver support — tempo and tuner values are spoken, selection states are announced, and decorative visuals are skipped.
- On first launch with VoiceOver on, the app speaks a quick guide to using it by voice.
- Voice Control — every button can be addressed by name.
- Reduce Motion — beat animations calm down (the beat is still shown by the lit dot).
- Differentiate Without Color — the tuner shows pitch with a symbol, not just color.
- Polished the beat dots to sit centered in their card, and the hint now fades away on its own.

### Details

**Accessibility**
- VoiceOver: meaningful labels, `isSelected` traits on the current time signature and
  subdivision, spoken tempo ("120 beats per minute") and tuner pitch
  ("A4, 12 cents sharp" / "in tune"), decorative meters (waveform, cents) hidden,
  combined sheet rows, and a fix so the hidden hint is no longer read aloud.
- VoiceOver onboarding: a one-time, high-priority spoken announcement on first launch
  (also fires if VoiceOver is turned on right after opening).
- Voice Control: `accessibilityInputLabels` on beat dots, tempo steppers/slider,
  subdivisions, transport, and the detect/help buttons — including easy-to-say
  aliases (e.g. "Quarter" for 1/4).
- Reduce Motion: beat-pulse and dot-scale bounces are dropped; transitions fall back
  to opacity.
- Differentiate Without Color: checkmark / up / down glyphs for the tuner's
  in-tune / sharp / flat states.

**Layout**
- Landscape (left/right) enabled; compact-height screens use a two-column layout
  (beats + tempo on the left; subdivision, voice status, and transport on the right).
- Beat dots centered within their card; the "tap dots to set beats" hint auto-fades
  after a few seconds.

**Other**
- Version bumped to 1.0.1.
</content>
</invoke>
