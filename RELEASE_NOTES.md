# Release Notes — Not My Tempo

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
