#!/usr/bin/env python3
"""App Store 마케팅 스크린샷: HTML → 헤드리스 Chrome (appstore-assets 스킬의 스크립트를 이 앱에 맞춘 것).

사용법: python3 scripts/make_marketing_screenshots.py [스토어로케일 ...]   (없으면 전부)

원본   docs/screenshots/raw/en/0N-….png         시뮬레이터 캡처 (앱 화면은 영어 한 벌)
제출본 docs/screenshots/marketing/<로케일>/0N-….png   1242×2688, 이 폴더를 DeployBar 가 올린다

바탕·글자색은 제품 페이지 헤더(make_creative_assets.py)와 같다: 검정 바탕 + 앱의 키 색 청록(cue, HandsFreeMetronome/Palette.swift).
"""
import subprocess, sys, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
RAW = ROOT / "docs" / "screenshots" / "raw" / "en"
OUT = ROOT / "docs" / "screenshots" / "marketing"
WORK = pathlib.Path("/tmp") / "nmt-marketing"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
W, H = 1242, 2688

# (파일, 레이아웃, 헤드라인, 서브카피) — 언어마다 따로 쓴다.
SHOTS = {
    "en-US": [
        ("01-playing.png", "hero",  "Keep both hands<br>on your instrument", "Say “start” or “faster” — no tapping"),
        ("02-orbit.png",   "left",  "See every beat<br>go around", "Orbit, bounce and ring views"),
        ("03-count.png",   "right", "Count the bar<br>at a glance", "Big numbers you can read from the stand"),
        ("04-voice.png",   "hero",  "Forgot a command?<br>Just say “help”", "Every word you can say, right on screen"),
        ("05-accents.png", "bottom","Make every<br>click your own", "Accent grid and per-song presets with Pro"),
    ],
    "ko": [
        ("01-playing.png", "hero",  "두 손은 악기에,<br>템포는 말로", "영어로 “start”, “faster” 한마디면 돼요"),
        ("02-orbit.png",   "left",  "박이 도는 게<br>눈에 보여요", "원 궤도, 튀는 공, 링 세 가지 화면"),
        ("03-count.png",   "right", "지금 몇 박인지<br>한눈에", "보면대 너머에서도 읽히는 큰 숫자"),
        ("04-voice.png",   "hero",  "명령이 생각 안 나면<br>“help”", "말할 수 있는 말을 화면에 바로 띄워 줘요"),
        ("05-accents.png", "bottom","강세를<br>마음대로", "Pro의 악센트 그리드와 곡별 프리셋"),
    ],
}

BASE_CSS = f"""
* {{ margin:0; padding:0; box-sizing:border-box; }}
html,body {{ width:{W}px; height:{H}px; overflow:hidden; }}
body {{ background:#0a0d0f; position:relative;
  font-family:-apple-system, "SF Pro Display", "Apple SD Gothic Neo", sans-serif; }}
.glow {{ position:absolute; width:1200px; height:1200px; border-radius:50%; filter:blur(200px);
  background:rgba(34,211,238,.22); }}
.headline {{ font-size:104px; font-weight:800; color:#eef3f5; letter-spacing:-3px; line-height:1.14; }}
.sub {{ font-size:50px; font-weight:500; color:#9aa6ac; letter-spacing:-1px; line-height:1.3; }}
:lang(ko) .headline, :lang(ko) .sub {{ word-break:keep-all; }}
.phone {{ position:absolute; background:#17171a; border-radius:112px; border:4px solid #3a3a3e; padding:24px;
  box-shadow: 0 60px 140px rgba(0,0,0,.6); }}
.phone img {{ width:100%; display:block; border-radius:90px; }}
.t {{ position:absolute; left:90px; right:90px; }}
"""

LAYOUTS = {
    "hero": """
.glow { left:20px; top:900px; }
.t { top:230px; text-align:center; }
.sub { margin-top:44px; }
.phone { width:820px; left:211px; top:740px; }
""",
    "left": """
.glow { left:300px; top:1100px; }
.t { top:250px; text-align:left; }
.sub { margin-top:44px; }
.phone { width:820px; left:330px; top:760px; transform:rotate(-4deg); }
""",
    "right": """
.glow { left:-300px; top:1000px; }
.t { top:250px; text-align:right; }
.sub { margin-top:44px; }
.phone { width:820px; left:90px; top:760px; transform:rotate(4deg); }
""",
    "bottom": """
.glow { left:20px; top:-200px; }
.phone { width:900px; left:171px; top:-760px; }
.t { top:2030px; text-align:center; }
.sub { margin-top:44px; }
""",
}

HTML = """<!doctype html><html lang="{lang}"><head><meta charset="utf-8"><style>{css}</style></head>
<body><div class="glow"></div><div class="phone"><img src="{img}"></div>
<div class="t"><div class="headline">{headline}</div><div class="sub">{sub}</div></div></body></html>"""

def main(only):
    WORK.mkdir(exist_ok=True)
    for loc, shots in SHOTS.items():
        if only and loc not in only:
            continue
        (OUT / loc).mkdir(parents=True, exist_ok=True)
        for fname, layout, headline, sub in shots:
            html = WORK / f"{loc}-{fname}.html"
            html.write_text(HTML.format(lang=loc.split("-")[0], css=BASE_CSS + LAYOUTS[layout],
                                        img=(RAW / fname).as_uri(), headline=headline, sub=sub), encoding="utf-8")
            out = OUT / loc / fname
            # 다른 세션의 Chrome 과 겹치면 가끔 실패한다 — 새 프로필로 몇 번 다시 시도한다.
            for attempt in range(4):
                out.unlink(missing_ok=True)
                prof = WORK / f"chrome-{attempt}"
                try:
                    subprocess.run([CHROME, "--headless=new", f"--screenshot={out}", f"--window-size={W},{H}",
                                    "--force-device-scale-factor=1", "--hide-scrollbars", "--disable-gpu",
                                    "--no-first-run", f"--user-data-dir={prof}", html.as_uri()],
                                   capture_output=True, timeout=40)
                except subprocess.TimeoutExpired:
                    pass
                if out.exists() and out.stat().st_size > 0:
                    break
            else:
                sys.exit(f"렌더 실패: {out}")
            print("rendered", out.relative_to(ROOT))

if __name__ == "__main__":
    main(sys.argv[1:])
