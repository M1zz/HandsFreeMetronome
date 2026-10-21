#!/bin/bash
# App Store 원본 캡처: 시뮬레이터에서 앱 언어마다 같은 장면을 찍는다.
#
# 사용법: scripts/capture_raw_screenshots.sh <시뮬레이터 UDID> <앱 경로(.app, Debug)> [앱언어 ...]
#   (언어를 안 주면 전부: en ja de es fr zh-Hans zh-Hant pt-BR)
#   ONLY="03-count 05-accents" 처럼 주면 그 파일만 다시 찍는다.
#
# 장면은 ContentView 의 -shot <scene> 훅(Debug 전용)이 스스로 차린다.
# 원본  docs/screenshots/raw/<앱언어>/0N-….png            스토어 스크린샷용
#       docs/screenshots/raw/creative/<앱언어>/0N-….png   헤더 · 검색 결과용
# 그다음 make_marketing_screenshots.py · make_creative_assets.py 로 제출본을 만든다.
#
# 처음 한 번: 이 시뮬레이터에서 앱을 열어 마이크 · 음성 인식 권한을 허용해 둔다
# (권한 팝업이 찍히면 안 된다). 모양은 라이트 모드, 상태 막대는 9:41 로 고정한다.
set -euo pipefail

UDID="$1"; APP="$2"; shift 2
LANGS=("$@"); [ ${#LANGS[@]} -eq 0 ] && LANGS=(en ja de es fr zh-Hans zh-Hant pt-BR)
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE=com.leeo.HandsFreeMetronome

SHOTS=(01-playing:playing 02-orbit:orbit 03-count:count 04-voice:voice 05-accents:accents)
CREATIVE=(01-main:main 02-number:number)

xcrun simctl install "$UDID" "$APP"
xcrun simctl privacy "$UDID" grant microphone "$BUNDLE" || true
xcrun simctl ui "$UDID" appearance light
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState charged --batteryLevel 100 \
    --cellularBars 4 --wifiBars 3

shoot() {   # <앱언어> <장면> <파일>
    local lang="$1" scene="$2" out="$3"
    if [ -n "${ONLY:-}" ] && [[ " $ONLY " != *" $(basename "$out" .png) "* ]]; then return; fi
    local region; case "$lang" in
        en) region=en_US;; ja) region=ja_JP;; de) region=de_DE;; es) region=es_ES;;
        fr) region=fr_FR;; zh-Hans) region=zh_CN;; zh-Hant) region=zh_TW;; pt-BR) region=pt_BR;; *) region=en_US;;
    esac
    xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
    xcrun simctl launch "$UDID" "$BUNDLE" -AppleLanguages "($lang)" -AppleLocale "$region" \
        -shot "$scene" >/dev/null
    sleep 7   # 장면 준비(1.5초) + 마이크가 켜지고 재생이 몇 박 돌 시간
    mkdir -p "$(dirname "$out")"
    xcrun simctl io "$UDID" screenshot "$out" >/dev/null 2>&1
    echo "captured ${out#$ROOT/}"
}

# 설치 직후 첫 실행은 느려서 장면이 늦게 차려진다 — 한 번 띄워 데워 둔다.
xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null; sleep 8

for lang in "${LANGS[@]}"; do
    for s in "${SHOTS[@]}"; do shoot "$lang" "${s#*:}" "$ROOT/docs/screenshots/raw/$lang/${s%%:*}.png"; done
    for s in "${CREATIVE[@]}"; do shoot "$lang" "${s#*:}" "$ROOT/docs/screenshots/raw/creative/$lang/${s%%:*}.png"; done
done
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
