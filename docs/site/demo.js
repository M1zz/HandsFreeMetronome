// 낫마템포 웹 데모: 앱의 음성 명령을 브라우저에서 그대로 해 본다.
// 규칙은 앱과 같다 — 템포 30~260 (MetronomeEngine.clampBPM), 이름은 tempoName, 명령은 VoiceController.
(() => {
  const root = document.getElementById("demo");
  if (!root) return;
  const T = JSON.parse(root.dataset.text);

  const state = { bpm: 100, beats: 4, playing: false, beat: -1 };
  const clamp = v => Math.min(260, Math.max(30, Math.round(v)));
  const tempoName = b => b < 40 ? "Grave" : b < 52 ? "Largo" : b < 66 ? "Adagio" : b < 76 ? "Andante"
    : b < 108 ? "Moderato" : b < 132 ? "Allegro" : b < 168 ? "Vivace" : b < 200 ? "Presto" : "Prestissimo";

  root.innerHTML = `
    <div class="demo-stage">
      <div class="demo-dots" aria-hidden="true"></div>
      <div class="demo-name">${tempoName(state.bpm)}</div>
      <div class="demo-bpm"><span>${state.bpm}</span> BPM</div>
      <div class="demo-bubble" aria-live="polite"></div>
    </div>
    <div class="demo-controls">
    <div class="demo-chips">
      ${["start", "stop", "faster", "slower", "tempo 120", "double", "half", "three beats", "four beats"]
        .map(c => `<button type="button" class="chip" data-say="${c}">“${c}”</button>`).join("")}
    </div>
    <div class="demo-mic">
      <button type="button" class="mic" aria-pressed="false">
        <svg viewBox="0 0 24 24" width="20" height="20" aria-hidden="true"><path fill="currentColor" d="M12 15a4 4 0 0 0 4-4V6a4 4 0 1 0-8 0v5a4 4 0 0 0 4 4Zm7-4a1 1 0 1 0-2 0 5 5 0 0 1-10 0 1 1 0 1 0-2 0 7 7 0 0 0 6 6.92V21a1 1 0 1 0 2 0v-3.08A7 7 0 0 0 19 11Z"/></svg>
        <span>${T.mic}</span>
      </button>
      <p class="muted small demo-note">${T.note}</p>
    </div>
    </div>`;

  const $ = s => root.querySelector(s);
  const dots = $(".demo-dots"), nameEl = $(".demo-name"), bpmEl = $(".demo-bpm span"), bubble = $(".demo-bubble");

  function render() {
    if (dots.children.length !== state.beats)
      dots.innerHTML = Array.from({ length: state.beats }, (_, i) => `<i class="${i ? "" : "first"}"></i>`).join("");
    [...dots.children].forEach((d, i) => d.classList.toggle("on", state.playing && i === state.beat));
    nameEl.textContent = tempoName(state.bpm);
    bpmEl.textContent = state.bpm;
    root.querySelector('[data-say="start"]').classList.toggle("hint", !state.playing && !root.dataset.used);
  }

  // 클릭 소리: Web Audio 로 미리 예약해 두어야 박이 흔들리지 않는다.
  let ctx, next = 0, count = 0, timer;
  function click(time, first) {
    const o = ctx.createOscillator(), g = ctx.createGain();
    o.frequency.value = first ? 1600 : 1000;
    g.gain.setValueAtTime(0.0001, time);
    g.gain.exponentialRampToValueAtTime(first ? 0.5 : 0.3, time + 0.002);
    g.gain.exponentialRampToValueAtTime(0.0001, time + 0.05);
    o.connect(g).connect(ctx.destination);
    o.start(time); o.stop(time + 0.06);
  }
  function schedule() {
    while (next < ctx.currentTime + 0.1) {
      const beat = count++ % state.beats, at = next;
      click(at, beat === 0);
      setTimeout(() => { if (state.playing) { state.beat = beat; render(); } }, Math.max(0, (at - ctx.currentTime) * 1000));
      next += 60 / state.bpm;
    }
  }
  function play() {
    ctx = ctx || new (window.AudioContext || window.webkitAudioContext)();
    ctx.resume();
    if (state.playing) return;
    state.playing = true; state.beat = -1; count = 0; next = ctx.currentTime + 0.05;
    timer = setInterval(schedule, 25); schedule();
  }
  function stop() { state.playing = false; clearInterval(timer); state.beat = -1; }

  const WORDS = { one: 1, two: 2, three: 3, four: 4, five: 5, six: 6, seven: 7, eight: 8 };
  // 앱의 VoiceController 처럼 문장 어디에 있든 명령 하나를 찾는다. 긴 것을 먼저 본다.
  function command(text) {
    const t = ` ${text.toLowerCase()} `;
    const has = w => w.some(x => t.includes(` ${x} `) || t.includes(` ${x}.`));
    const beat = t.match(/\b(one|two|three|four|five|six|seven|eight|[1-8])\s+beats?\b/);
    if (beat) return () => { state.beats = WORDS[beat[1]] || +beat[1]; state.beat = -1; count = 0; };
    const num = t.match(/\b(\d{2,3})\b/);
    if (num) return () => { state.bpm = clamp(+num[1]); };
    if (has(["double"])) return () => { state.bpm = clamp(state.bpm * 2); };
    if (has(["half"])) return () => { state.bpm = clamp(state.bpm / 2); };
    if (has(["faster", "speed up"])) return () => { state.bpm = clamp(state.bpm + 5); };
    if (has(["slower", "slow down"])) return () => { state.bpm = clamp(state.bpm - 5); };
    if (has(["stop", "pause"])) return stop;
    if (has(["start", "play", "go"])) return play;
    if (has(["up"])) return () => { state.bpm = clamp(state.bpm + 1); };
    if (has(["down"])) return () => { state.bpm = clamp(state.bpm - 1); };
    return null;
  }

  let bubbleTimer;
  function say(text) {
    const run = command(text);
    bubble.textContent = `“${text}”`;
    bubble.classList.toggle("miss", !run);
    bubble.classList.add("show");
    clearTimeout(bubbleTimer);
    bubbleTimer = setTimeout(() => bubble.classList.remove("show"), 1400);
    if (!run) return;
    root.dataset.used = "1";
    run();
    nameEl.classList.remove("bump"); void nameEl.offsetWidth; nameEl.classList.add("bump");
    render();
  }

  root.addEventListener("click", e => {
    const chip = e.target.closest("[data-say]");
    if (chip) say(chip.dataset.say);
  });

  // 마이크: 앱처럼 영어(미국)로 듣는다. 지원하지 않는 브라우저면 버튼으로만 해 본다.
  const Rec = window.SpeechRecognition || window.webkitSpeechRecognition;
  const mic = $(".mic"), micLabel = mic.querySelector("span");
  if (!Rec) { mic.disabled = true; micLabel.textContent = T.micNone; }
  let rec;
  mic.addEventListener("click", () => {
    if (rec) { rec.stop(); return; }
    rec = new Rec();
    rec.lang = "en-US"; rec.continuous = true; rec.interimResults = false;
    rec.onresult = e => say(e.results[e.results.length - 1][0].transcript.trim());
    rec.onend = () => { rec = null; mic.setAttribute("aria-pressed", "false"); micLabel.textContent = T.mic; };
    rec.start();
    mic.setAttribute("aria-pressed", "true"); micLabel.textContent = T.micOn;
  });

  render();
})();
