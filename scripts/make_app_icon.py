#!/usr/bin/env python3
"""앱 아이콘 생성: SVG → 헤드리스 Chrome → AppIcon.png (1024×1024, 알파 없음).

사용법: python3 scripts/make_app_icon.py

색은 앱의 색과 같다 (HandsFreeMetronome/Palette.swift):
  바탕   청록 cue — 위는 다크 모드 값 #22D3EE, 아래는 라이트 모드 값 #0A7EA4 로 내려간다
  추     첫 박 빨강 beatRed #E63833
  진자   곁눈에도 잡히는 신호처럼 은은하게 빛나는 크림색
모양은 처음 아이콘(태엽 메트로놈)을 그대로 따른다 — 바뀐 것은 색뿐이다.
"""
import pathlib, subprocess, tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "HandsFreeMetronome" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon.png"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

SVG = """<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#3FDDF3"/>
      <stop offset="0.55" stop-color="#16A9CB"/>
      <stop offset="1" stop-color="#0A7EA4"/>
    </linearGradient>
    <radialGradient id="halo" cx="0.5" cy="0.5" r="0.5">
      <stop offset="0" stop-color="#22D3EE" stop-opacity="0.55"/>
      <stop offset="1" stop-color="#22D3EE" stop-opacity="0"/>
    </radialGradient>
    <filter id="shadow" x="-30%" y="-30%" width="160%" height="160%">
      <feDropShadow dx="0" dy="18" stdDeviation="22" flood-color="#04303F" flood-opacity="0.55"/>
    </filter>
    <filter id="glow" x="-50%" y="-50%" width="200%" height="200%">
      <feGaussianBlur stdDeviation="9" result="b"/>
      <feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge>
    </filter>
  </defs>
  <rect width="1024" height="1024" fill="url(#bg)"/>
  <g filter="url(#shadow)">
    <circle cx="512" cy="208" r="18" fill="#0E3A47"/>
    <rect x="432" y="224" width="160" height="40" rx="14" fill="#1E2428"/>
    <polygon points="422,252 602,252 724,866 300,866" fill="#1A1F23"/>
  </g>
  <polygon points="446,284 578,284 672,834 352,834" fill="#0B0F12"/>
  <ellipse cx="545" cy="560" rx="150" ry="260" fill="url(#halo)" opacity="0.6"/>
  <g filter="url(#glow)">
    <line x1="512" y1="774" x2="590" y2="370" stroke="#F3F7F8" stroke-width="16" stroke-linecap="round"/>
  </g>
  <rect x="512" y="508" width="92" height="60" rx="11" fill="#E63833" transform="rotate(10.9 558 538)"/>
  <circle cx="512" cy="774" r="22" fill="#22D3EE" filter="url(#glow)"/>
</svg>
"""


def main():
    with tempfile.TemporaryDirectory() as tmp:
        tmp = pathlib.Path(tmp)
        page = tmp / "icon.html"
        page.write_text("<!doctype html><html><head><style>html,body{margin:0;width:1024px;height:1024px;"
                        "overflow:hidden;background:#0A7EA4}</style></head><body>" + SVG + "</body></html>")
        shot = tmp / "icon.png"
        # Chrome 은 그림을 쓴 뒤에도 가끔 끝나지 않는다 — 시간이 지나면 끊고, 그림이 생겼는지로 판단한다.
        for attempt in range(4):
            try:
                subprocess.run([CHROME, "--headless=new", f"--screenshot={shot}", "--window-size=1024,1024",
                                "--hide-scrollbars", "--force-device-scale-factor=1", "--disable-gpu",
                                "--no-first-run", f"--user-data-dir={tmp / f'prof-{attempt}'}", page.as_uri()],
                               capture_output=True, timeout=40)
            except subprocess.TimeoutExpired:
                pass
            if shot.exists() and shot.stat().st_size > 0:
                break
        else:
            raise SystemExit("아이콘 렌더 실패")
        # App Store 는 알파 채널이 있는 아이콘을 거절한다 — JPEG 를 거쳐 알파를 확실히 없앤다.
        jpg = tmp / "icon.jpg"
        subprocess.run(["sips", "-s", "format", "jpeg", "-s", "formatOptions", "100", str(shot), "--out", str(jpg)],
                       check=True, capture_output=True)
        subprocess.run(["sips", "-s", "format", "png", str(jpg), "--out", str(OUT)], check=True, capture_output=True)
    print("rendered", OUT)


if __name__ == "__main__":
    main()
