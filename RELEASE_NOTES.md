# Release Notes — Not My Tempo

## 1.0.4

안정성 업데이트입니다. 재생을 멈추는 순간 앱이 종료될 수 있던 문제를 비롯해,
드물게 앱을 종료시킬 수 있는 내부 원인들을 전수 점검해 수정했습니다.

A stability update: fixed a crash when stopping playback, and audited every
remaining path that could terminate the app.

### App Store (한국어)

- 재생을 멈추는 순간(특히 6/8·셋잇단처럼 느린 템포에서 음성으로 멈출 때) 앱이 종료되던 문제를 수정했습니다.
- 재생 중 악센트를 편집하거나 정지/시작을 빠르게 반복해도 안전하도록 오디오 내부 동작을 안정화했습니다.
- 전화·Siri·알람이 끼어들면 메트로놈이 깨끗하게 멈추도록 했습니다.
- 그 밖에 드물게 앱을 종료시킬 수 있는 원인들을 전수 점검해 수정했습니다.

### App Store (English)

- Fixed a crash when stopping playback — most likely at slow tempos with subdivisions (e.g. 6/8 triplets) and when stopping by voice.
- Hardened the audio internals so rapid start/stop and editing accents during playback are safe.
- A phone call, Siri, or an alarm now stops the metronome cleanly.
- Audited and fixed the remaining rare conditions that could terminate the app.

### Details (한국어)

- 정지 순간 크래시: 정지 직후 프레임에서 진자/링 스윕 뷰가 페이드아웃으로 아직
  화면에 남아 있는 동안 박 위상이 음수가 되어, 클릭 타깃 배열을 범위 밖
  인덱스로 접근했습니다. 애니메이션을 재생 상태로 게이트하고 위상을 0…1로
  클램프했습니다(진자·링 스윕 뷰).
- 동시성: 오디오 정리가 진행 중인 틱이 끝나길 기다립니다(버퍼 스케줄링과의
  경합 제거). 틱 스레드는 락으로 보호된 악센트 스냅샷을 읽고, 음성 인식
  request는 오디오 탭 스레드와의 경합을 락으로 차단합니다.
- 오디오 세션 인터럽션(전화·Siri·알람)은 깨끗한 정지로 처리하고, 모든
  play/schedule 호출 전에 엔진 상태를 확인합니다.
- 강제 언래핑을 제거하고 모든 Int(Double) 변환(BPM 슬라이더, 탭 템포, 튜너
  노트 매핑)에 NaN/무한대 가드를 넣었습니다.

### Details (English)

- Stop-time crash: on the frame after stopping, the beat phase could go negative
  while the pendulum/ring views were still fading out, indexing a click-target
  array out of bounds. The animation is now gated on the playing state and the
  phase clamped (pendulum and ring-sweep views).
- Concurrency: audio teardown now waits for any in-flight tick (no race with
  buffer scheduling); the tick thread reads a lock-guarded accent snapshot; the
  speech-recognition request is lock-guarded against the audio-tap thread.
- Audio-session interruptions (call/Siri/alarm) fold into a clean stop; the
  engine is checked before every play/schedule call.
- Removed force unwraps and guarded all Int(Double) conversions (BPM slider,
  tap tempo, tuner note mapping) against NaN/infinity.

## 1.0.3

이번 업데이트의 핵심은 **마디 전체 악센트 커스터마이징**과 **새로운 비트
시각화·타이밍 연습**입니다. 마디 안의 모든 클릭을 한 칸씩 설계하고, 새 진자·링
스윕 뷰로 박을 보고, 클릭에 맞춰 탭하며 타이밍을 연습할 수 있습니다. 보조접근
(Assistive Access) 지원과 iOS 음성 제어(Voice Control) 공존 모드도 함께
들어갔습니다.

The headline of this update: **full-measure accent customization** plus **new beat
visualizations and timing practice** — design every click in the measure, watch the
beat in the new pendulum and ring-sweep views, and tap along to train your timing.
Also: Assistive Access support and an iOS Voice Control coexistence mode.

### App Store (한국어)

- 악센트 커스터마이징: 분할 카드를 더블탭하면 마디 전체가 그리드로 펼쳐집니다. 4/4에 1/16이면 16칸 — 칸을 탭할 때마다 고음 → 저음 → 무음(쉼표)으로 순환합니다(예: 삑·비·비·삑, 쉼표 넣기도 가능).
- 패턴을 이름 붙여 프리셋으로 저장하고 곡마다 불러올 수 있습니다 — 불러오면 박자와 분할도 함께 복원됩니다.
- 패턴은 박자수×분할 조합별로 자동 저장되어 설정을 바꿔도 유지되고, Reset으로 기본 패턴에 돌아갑니다.
- 궤도(orbit) 화면의 분할 점이 고음 클릭에서 금색으로 커지고 무음은 흐려져, 듣는 패턴이 눈에도 보입니다.
- 보조접근(Assistive Access)을 완벽 지원합니다 — 큰 버튼과 핵심 기능만 남긴 단순 화면.
- iOS 음성 제어를 쓰신다면 앱 마이크를 끄고 "Tap Start"처럼 이름으로 조작하는 공존 모드를 켤 수 있습니다.
- 타이밍 연습: 궤도 화면에서 클릭에 맞춰 탭해 보세요 — Perfect / Good / Bad 판정과 함께, 돌던 점이 탭한 순간의 자리에 잔상을 남겨 얼마나 빠르거나 늦었는지 눈에 보입니다. 초록·금·빨강 원 카운터가 횟수를 세고, 1/8·1/16에서는 서브클릭 하나하나가 판정 대상입니다.
- 진자 뷰가 새로워졌습니다: 공이 던져 올린 듯한 중력 곡선으로 움직이고, 소리가 나는 접점의 점선 타깃을 통과하는 순간 팝 하고 터집니다. 빠른 분할에서도 스윙은 눈으로 따라가기 좋은 속도를 유지합니다.
- 새 링 스윕 뷰: 시계처럼 링이 한 박마다 12시부터 차오르고 박이 울리는 순간 12시에서 터지며, 중앙의 큰 숫자가 박을 카운트합니다. 뷰 버튼(또는 "switch view")으로 진자 → 궤도 → 링 스윕 순환.
- 박마다 화면 전체가 은은하게 번쩍입니다(다운비트 빨강, 나머지 금색) — 악보를 보면서도 곁눈으로 박이 들어옵니다.
- 가로모드가 한 화면에 매끄럽게 들어갑니다.
- 첫 실행 직후 마이크 권한을 허용하면 앱이 종료될 수 있던 문제를 수정했습니다.
- 첫 실행 온보딩 팁이 사용 환경(마이크/음성 제어)에 맞춰 표시되고, 숨은 기능들(악센트·빠르기말 전환·뷰 전환·스피드 트레이너·튜너)을 팁 투어가 하나씩 차례로 소개합니다.
- 템포 감지(음악 듣고 BPM 찾기) 기능은 제거했습니다 — 화면이 더 단순해졌습니다.

### App Store (English)

- Accent customization: double-tap the subdivision card to open the whole measure as a grid. 4/4 with sixteenths → 16 cells; each tap cycles a cell high → low → silent (rests welcome).
- Save patterns as named presets and recall them per song — a preset restores its meter and subdivision too.
- Patterns are auto-saved per meter × subdivision combination, and Reset restores the stock pattern.
- The orbit view now shows the pattern — high clicks appear as larger gold dots, silent ones fade out.
- Full Assistive Access support — a distilled layout with big, clear controls.
- Use iOS Voice Control? A coexistence mode turns the app's own mic off so the two recognizers never clash.
- Timing practice: tap along in orbit view — a Perfect / Good / Bad call flashes, and the travelling dot freezes a ghost right where it was, so you can see how early or late you landed. Green / gold / red bubbles keep count, and with subdivisions every click is a target.
- The pendulum view is new: the ball arcs like a thrown ball under gravity and pops through a dashed target ring at the exact instant of the click. At fast subdivisions the swing stays at a readable one arc per beat.
- New ring-sweep view: clock-style — the ring fills once per beat, bursts at 12 o'clock as the click lands, and a big centre number counts the beats. Cycle views with the button or "switch view".
- A subtle whole-screen flash marks every beat (red on the downbeat, gold elsewhere) — easy to catch in peripheral vision while reading a score.
- Landscape now fits everything on one screen.
- Fixed a crash that could occur right after granting the microphone permission on first launch.
- First-run tips adapt to how you control the app (mic vs. Voice Control), and a guided tip tour introduces the hidden gems one by one — accents, tempo terms, beat views, the speed trainer, and the tuner.
- Removed the listen-and-detect-BPM feature for a simpler screen.

### Details

**Accents**
- The engine keeps a measure-wide level array per (beats × subdivision) combination
  (up to 8×4 = 32 clicks); every tick is high (1500 Hz), low (1000 Hz), or a silent
  rest, and the downbeat's extra-high chime (2000 Hz) follows its own cell —
  nothing is hard-wired.
- Editor: a step-sequencer grid (one row per beat, one cell per click; tall bar =
  high, short = low, dashed empty = rest) presented as a sheet; opened by
  double-tapping the subdivision card, from Help, or via a VoiceOver "Edit
  accents" action. Reset restores the default; a first-run TipKit tip points out
  the double-tap.
- Presets: name and save the current pattern (meter + subdivision + levels,
  JSON in UserDefaults); applying one switches the metronome to match; delete
  in place.
- Patterns persist across launches and are reflected live while playing; the orbit
  view's minor ticks render the pattern in place (silent rests fade out).

**Accessibility**
- Assistive Access: full-screen opt-in plus a simplified layout (tempo, Slower /
  Faster, Start/Stop) when running inside the simplified system experience.
- Voice Control coexistence: a user toggle releases the app's mic and leans on
  control names; VoiceOver intro and first-run TipKit tips branch accordingly.

**Beat views & timing**
- Pendulum: gravity-curve (parabolic) arcs crossing the centre exactly on each
  click; a dashed target ring at the contact point pops (burst ring + ball scale)
  on contact, all phase-derived so it never drifts from the audio. Above 1/8 the
  swing caps at one arc per beat to stay readable; the amplitude adapts to the
  card height (landscape).
- Ring sweep: a radial progress ring fills over each beat, bursts at 12 o'clock,
  and shows a numeric centre count — third stop in the view cycle
  (bounce → orbit → sweep).
- Play-along timing: taps are judged against the click grid (within 10% of the
  click interval = Perfect, 25% = Good); the orbit dot drops a fading ghost at
  its tap-time position, and per-verdict bubbles tally the run (reset on start).
  VoiceOver announces each verdict and reads the running score.
- Whole-screen beat flash (subtle, skipped with Reduce Motion); the landscape
  layout now flexes so both columns always fit one screen.

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
