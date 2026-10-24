#!/usr/bin/env python3
"""App Store 크리에이티브 자산(제품 페이지 헤더 · 검색 결과) 생성: HTML → 헤드리스 Chrome.

사용법: python3 scripts/make_creative_assets.py [언어 ...]     (없으면 전부)

자리
  docs/screenshots/creative/<스토어 로케일>/header.png   3840x1646  제품 페이지 맨 위
  docs/screenshots/creative/<스토어 로케일>/search.png   3840x2560  검색 결과 (없으면 스크린샷이 대신 보인다)

기기 화면은 docs/screenshots/raw/creative/<앱언어>/ 의 시뮬레이터 캡처다(scripts/capture_raw_screenshots.sh).
영어(영국)은 영국식 화면(en-GB)을 따로 쓰고, 스페인어 화면 한 벌이 es-ES · es-MX 를 맡는다.

⚠️ 안전 영역 밖은 기기에 따라 잘린다. 글은 **반드시** 안전 영역 안에 둔다(배경 · 기기 그림은 넘쳐도 된다).
   수치는 Apple 공식 PSD 템플릿에서 잰 값이다(https://developer.apple.com/app-store/asset-best-practices/).
   아이폰에서 헤더는 가운데만 남고, 검색 결과는 약 385pt 폭으로 줄어 보인다. 그래서 글이 크다.

⚠️ 가격 · 할인 · 주소(URL) · 수상 · 다른 플랫폼 이름은 넣지 않는다(Apple 가이드).
"""
import shutil, subprocess, sys, pathlib, tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
RAW = ROOT / "docs" / "screenshots" / "raw" / "creative"
OUT = ROOT / "docs" / "screenshots" / "creative"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

# 문구 언어 → App Store Connect 로케일
STORE = {"en": "en-US", "de": "de-DE", "es": "es-ES", "es-MX": "es-MX", "fr": "fr-FR"}
# 문구 언어 → 기기 화면 캡처 폴더
SCREEN = {"ko": "ko", "en": "en", "ja": "ja", "de": "de", "es": "es", "es-MX": "es",
          "fr": "fr", "zh-Hans": "zh-Hans", "zh-Hant": "zh-Hant", "pt-BR": "pt-BR", "it": "it", "en-GB": "en-GB",
          "ru": "ru", "nl": "nl", "pl": "pl", "tr": "tr", "sv": "sv", "da": "da", "nb": "nb", "fi": "fi", "cs": "cs", "el": "el", "th": "th", "vi": "vi", "id": "id"}

# (가로, 세로, 안전 영역 left, top, right, bottom)
SPEC = {
    "header": (3840, 1646, (1097, 493, 2743, 1154)),
    "search": (3840, 2560, (836, 765, 3004, 1795)),
}

# 검색 결과: 눈썹글은 그 나라 사람이 검색창에 치는 말. 앱의 약속은 "손 대지 않고 말로 템포를 바꾼다".
# 음성 명령은 영어만 알아듣는다(VoiceController 의 en-US 인식기) — 한국어 글에도 영어 명령을 그대로 적는다.
SEARCH = {
    "ko": ("메트로놈", "템포는<br>말로 바꾸세요", "영어로 “start”, “faster” 한마디면 돼요"),
    "en": ("Metronome", "Change tempo<br>with your voice", "Say “start” or “faster” as you play"),
    "ja": ("メトロノーム", "テンポは<br>声で変えよう", "英語で「start」「faster」と言うだけ"),
    "de": ("Metronom", "Tempo ändern<br>per Stimme", "Sag beim Spielen „start“ oder „faster“"),
    "es": ("Metrónomo", "Cambia el tempo<br>con tu voz", "Di “start” o “faster” mientras tocas"),
    "es-MX": ("Metrónomo", "Cambia el tempo<br>con tu voz", "Di “start” o “faster” mientras tocas"),
    "fr": ("Métronome", "Change de tempo<br>à la voix", "Dis « start » ou « faster » en jouant"),
    "zh-Hans": ("节拍器", "速度<br>开口就能改", "用英文说“start”“faster”就行"),
    "pt-BR": ("Metrônomo", "Mude o andamento<br>com a voz", "Diga “start” ou “faster” enquanto toca"),
    "zh-Hant": ("節拍器", "速度<br>開口就能改", "用英文說「start」「faster」就行"),
    "it": ("Metronomo", "Cambia tempo<br>con la voce", "Dì “start” o “faster” mentre suoni"),
    "ru": ("Метроном", "Меняйте темп<br>голосом", "Скажите «start» или «faster» во время игры"),
    "nl": ("Metronoom", "Wijzig het tempo<br>met je stem", "Zeg “start” of “faster” terwijl je speelt"),
    "pl": ("Metronom", "Zmieniaj tempo<br>głosem", "Powiedz „start” lub „faster” podczas gry"),
    "tr": ("Metronom", "Temposu<br>sesinizle değiştirin", "Çalarken “start” veya “faster” deyin"),
    "sv": ("Metronom", "Byt tempo<br>med rösten", "Säg “start” eller “faster” medan du spelar"),
    "da": ("Metronom", "Skift tempo<br>med stemmen", "Sig “start” eller “faster”, mens du spiller"),
    "nb": ("Metronom", "Bytt tempo<br>med stemmen", "Si «start» eller «faster» mens du spiller"),
    "fi": ("Metronomi", "Vaihda tempoa<br>äänellä", "Sano “start” tai “faster” soittaessasi"),
    "cs": ("Metronom", "Měňte tempo<br>hlasem", "Řekněte „start“ nebo „faster“ za hraní"),
    "el": ("Μετρονόμος", "Αλλάξτε ταχύτητα<br>με τη φωνή σας", "Πείτε «start» ή «faster» ενώ παίζετε"),
    "th": ("เมโทรนอม", "เปลี่ยนความเร็ว<br>ด้วยเสียง", "พูดว่า “start” หรือ “faster” ขณะเล่น"),
    "vi": ("Máy gõ nhịp", "Đổi tốc độ<br>bằng giọng nói", "Nói “start” hoặc “faster” khi đang chơi"),
    "id": ("Metronom", "Ubah tempo<br>dengan suara", "Ucapkan “start” atau “faster” saat bermain"),
    "en-GB": ("Metronome", "Change tempo<br>with your voice", "Say “start” or “faster” as you play"),
}

# 헤더: 처음 온 사람에게 한 가지 약속. 연주하는 손을 떼지 않는다.
HEADER = {
    "ko": ("핸즈프리 메트로놈", "두 손은 악기에,<br>템포는 말로"),
    "en": ("Hands-free metronome", "Keep both hands playing.<br>Just say “faster.”"),
    "ja": ("ハンズフリーメトロノーム", "両手は楽器に、<br>テンポは声で"),
    "de": ("Freihändiges Metronom", "Beide Hände am Instrument.<br>Sag einfach „faster“."),
    "es": ("Metrónomo manos libres", "No sueltes el instrumento.<br>Solo di “faster”."),
    "es-MX": ("Metrónomo manos libres", "No sueltes el instrumento.<br>Solo di “faster”."),
    "fr": ("Métronome mains libres", "Joue des deux mains.<br>Dis juste « faster »."),
    "zh-Hans": ("免手动节拍器", "双手留在乐器上<br>速度开口就改"),
    "pt-BR": ("Metrônomo sem usar as mãos", "Mãos no instrumento.<br>É só dizer “faster”."),
    "zh-Hant": ("免手動節拍器", "雙手留在樂器上<br>速度開口就改"),
    "it": ("Metronomo a mani libere", "Le mani sullo strumento.<br>Tu dì solo “faster”."),
    "ru": ("Метроном без рук", "Руки на инструменте.<br>Просто скажите «faster»."),
    "nl": ("Handsfree metronoom", "Beide handen aan het spelen.<br>Zeg gewoon “faster”."),
    "pl": ("Metronom bez rąk", "Obie ręce przy grze.<br>Po prostu powiedz „faster”."),
    "tr": ("Eller serbest metronom", "İki el çalmaya devam.<br>Sadece “faster” deyin."),
    "sv": ("Metronom utan händer", "Båda händerna på spelet.<br>Säg bara “faster”."),
    "da": ("Håndfri metronom", "Begge hænder på instrumentet.<br>Sig bare “faster”."),
    "nb": ("Håndfri metronom", "Begge hendene på spillet.<br>Si bare «faster»."),
    "fi": ("Käsiä vapauttava metronomi", "Molemmat kädet soittamassa.<br>Sano vain “faster”."),
    "cs": ("Metronom bez rukou", "Obě ruce při hře.<br>Stačí říct „faster“."),
    "el": ("Μετρονόμος χωρίς χέρια", "Και τα δύο χέρια στο παίξιμο.<br>Πείτε απλώς «faster»."),
    "th": ("เมโทรนอมแบบไม่ใช้มือ", "มือทั้งสองข้างอยู่กับการเล่น<br>แค่พูดว่า “faster”"),
    "vi": ("Máy gõ nhịp rảnh tay", "Hai tay cứ chơi nhạc.<br>Chỉ cần nói “faster”."),
    "id": ("Metronom bebas tangan", "Kedua tangan tetap bermain.<br>Cukup ucapkan “faster”."),
    "en-GB": ("Hands-free metronome", "Keep both hands playing.<br>Just say “faster.”"),
}

# 바탕 · 글자색은 앱의 색이다: 다크 모드 화면(검정) + 키 색 청록(cue #22D3EE, Palette.swift 의
# 다크 모드 값) + 첫 박 빨강(beatRed).
BASE_CSS = """
* { margin:0; padding:0; box-sizing:border-box; }
html,body { width:%(W)dpx; height:%(H)dpx; overflow:hidden; }
body { background:#0a0d0f; position:relative;
  font-family:-apple-system, "SF Pro Display", "Apple SD Gothic Neo", "Hiragino Sans", "PingFang SC", sans-serif; }
.glow { position:absolute; border-radius:50%%; filter:blur(160px); pointer-events:none; }
.text { position:absolute; display:flex; flex-direction:column; justify-content:center; }
.eyebrow { font-weight:700; color:#22D3EE; letter-spacing:-0.01em; line-height:1.15; }
.headline { font-weight:800; color:#eef3f5; letter-spacing:-0.03em; line-height:1.12; text-wrap:balance; }
.sub { font-weight:500; color:#93a0a6; letter-spacing:-0.01em; line-height:1.35; text-wrap:balance; }
/* 한국어는 낱말 중간에서 끊지 않는다. */
:lang(ko) .headline, :lang(ko) .sub, :lang(ko) .eyebrow { word-break:keep-all; }
.phone { position:absolute; background:#17171a; border:6px solid #3a3a3e; padding:40px; border-radius:190px;
  box-shadow: 0 60px 160px rgba(0,0,0,.6), 0 0 0 2px #232327 inset; }
.phone img { width:100%%; display:block; border-radius:152px; }
.dot { position:absolute; border-radius:50%%; }
"""

# 글이 상자를 넘지 않을 때까지 줄인다. 잘리는 글은 없다 - 끝까지 안 맞으면 표시하고 멈춘다.
FIT_JS = """
<script>
// 문구에 적은 줄(<br>)보다 더 쪼개지면 "Rispondi / con un / tocco" 처럼 읽기가 끊긴다.
// 적은 줄 수를 지킬 때까지 줄인다.
function lines(el) {
  return Math.round(el.getBoundingClientRect().height / parseFloat(getComputedStyle(el).lineHeight));
}
function fit(box, el, max, min) {
  const want = el.querySelectorAll('br').length + 1;
  let size = max;
  el.style.fontSize = size + 'px';
  while (size > min && (box.scrollHeight > box.clientHeight + 1 || box.scrollWidth > box.clientWidth + 1 ||
         lines(el) > want)) {
    size -= 4; el.style.fontSize = size + 'px';
  }
  if (box.scrollHeight > box.clientHeight + 1 || box.scrollWidth > box.clientWidth + 1 || lines(el) > want)
    document.body.dataset.overflow = '1';
}
document.fonts.ready.then(() => {
  const box = document.querySelector('.text');
  const h = document.querySelector('.headline');
  fit(box, h, +h.dataset.max, +h.dataset.min);
  document.body.dataset.done = '1';
});
</script>
"""


def phone(img, left, top, width, rotate=0):
    return (f'<div class="phone" style="left:{left}px;top:{top}px;width:{width}px;'
            f'transform:rotate({rotate}deg)"><img src="{img}"></div>')


def beat_dots(x, y, size, gap, n, opacity):
    """앱의 박자 점(첫 박 빨강 + 청록 cue)을 장식으로. 안전 영역 바깥에만 둔다."""
    out = []
    for i in range(n):
        color = "#E63833" if i == 0 else "#22D3EE"
        out.append(f'<div class="dot" style="left:{x + i * (size + gap)}px;top:{y}px;width:{size}px;'
                   f'height:{size}px;background:{color};opacity:{opacity}"></div>')
    return "".join(out)


def shot(lang, name):
    return (RAW / SCREEN[lang] / name).as_uri()


def search_html(lang):
    W, H, (l, t, r, b) = SPEC["search"]
    eyebrow, headline, sub = SEARCH[lang]
    sw, sh = r - l, b - t
    col = int(sw * 0.56)
    ph_w = 1040
    ph_left = l + col + int(sw * 0.04)
    return f"""
<div class="glow" style="left:{ph_left - 300}px;top:500px;width:1700px;height:1700px;background:rgba(34,211,238,.20)"></div>
<div class="glow" style="left:{l - 700}px;top:{t - 500}px;width:1400px;height:1000px;background:rgba(34,211,238,.07)"></div>
{phone(shot(lang, "01-main.png"), ph_left, t - 360, ph_w, 0)}
<div class="text" style="left:{l}px;top:{t}px;width:{col}px;height:{sh}px">
  <div class="eyebrow" style="font-size:96px">{eyebrow}</div>
  <div class="headline" data-max="250" data-min="140" style="margin-top:36px">{headline}</div>
  <div class="sub" style="font-size:84px;margin-top:52px">{sub}</div>
</div>"""


def header_html(lang):
    W, H, (l, t, r, b) = SPEC["header"]
    eyebrow, headline = HEADER[lang]
    sw, sh = r - l, b - t
    dots = (beat_dots(1180, 250, 70, 46, 4, .55) + beat_dots(2330, 1330, 70, 46, 4, .35))
    return f"""
<div class="glow" style="left:{l - 200}px;top:{t - 400}px;width:{sw + 400}px;height:{sh + 800}px;background:rgba(34,211,238,.15)"></div>
{dots}
{phone(shot(lang, "02-number.png"), 300, 360, 640, -9)}
{phone(shot(lang, "01-main.png"), 2900, 360, 640, 9)}
<div class="text" style="left:{l}px;top:{t}px;width:{sw}px;height:{sh}px;align-items:center;text-align:center">
  <div class="eyebrow" style="font-size:76px">{eyebrow}</div>
  <div class="headline" data-max="210" data-min="110" style="margin-top:22px">{headline}</div>
</div>"""


def render(lang, kind):
    W, H, _ = SPEC[kind]
    body = search_html(lang) if kind == "search" else header_html(lang)
    page = (f'<!doctype html><html lang="{lang.split("-")[0] if lang == "es-MX" else lang}"><head><meta charset="utf-8"><style>'
            f'{BASE_CSS % {"W": W, "H": H}}</style></head><body>{body}{FIT_JS}</body></html>')
    html_path = pathlib.Path(tempfile.gettempdir()) / f"notmytempo-creative-{lang}-{kind}.html"
    html_path.write_text(page, encoding="utf-8")
    # 글이 끝까지 안 맞으면 그림을 만들지 않는다(잘린 글이 스토어에 올라가는 것보다 낫다).
    dom = subprocess.run([CHROME, "--headless=new", "--dump-dom", f"--window-size={W},{H}",
                          "--force-device-scale-factor=1", "--disable-gpu", "--virtual-time-budget=3000",
                          html_path.as_uri()], capture_output=True, text=True, timeout=90).stdout
    if 'data-done="1"' not in dom:
        raise SystemExit(f"글 맞추기가 끝나지 않았다: {lang} {kind}")
    if 'data-overflow="1"' in dom:
        raise SystemExit(f"글이 안전 영역을 넘는다: {lang} {kind} - 문구를 줄일 것")
    out_dir = OUT / STORE.get(lang, lang)
    out_dir.mkdir(parents=True, exist_ok=True)
    out_png = out_dir / f"{kind}.png"
    # ⚠️ Chrome 은 가끔 아무것도 안 그리고 끝나거나 멈춘다. 세 번까지 한다.
    for _ in range(3):
        try:
            r = subprocess.run([CHROME, "--headless=new", f"--screenshot={out_png}",
                                f"--window-size={W},{H}", "--force-device-scale-factor=1",
                                "--hide-scrollbars", "--disable-gpu", "--virtual-time-budget=3000",
                                "--allow-file-access-from-files", html_path.as_uri()],
                               capture_output=True, timeout=90)
        except subprocess.TimeoutExpired:
            continue
        if r.returncode == 0:
            break
    else:
        raise SystemExit(f"Chrome 이 그리지 못했다: {out_png}")
    print(f"rendered {out_png}")


if __name__ == "__main__":
    langs = sys.argv[1:] or list(SEARCH)
    for lang in langs:
        if lang not in SEARCH:
            raise SystemExit(f"모르는 언어: {lang} (아는 것: {', '.join(SEARCH)})")
        for kind in ("header", "search"):
            render(lang, kind)
