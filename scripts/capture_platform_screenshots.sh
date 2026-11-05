#!/bin/bash
# iPad · Apple Watch 스토어 스크린샷: 언어마다 같은 장면을 찍어 제출본으로 바로 둔다.
#
# 사용법:
#   scripts/capture_platform_screenshots.sh ipad  <iPad 13" 시뮬레이터 UDID> <앱 경로(.app, Debug)>  [스토어 로케일 ...]
#   scripts/capture_platform_screenshots.sh watch <Watch 46mm 시뮬레이터 UDID> <워치 앱 경로(.app, Debug)> [스토어 로케일 ...]
#
# 결과  iPad : docs/screenshots/marketing/<로케일>/ipad-0N-….png (2064×2752, 세로)
#       워치 : docs/screenshots/watch/<로케일>/0N-….png (416×496)
# 장면은 앱이 스스로 차린다: iPad 는 ContentView 의 -shot <장면>, 워치는 -wristDemo <장면> (둘 다 Debug 전용).
# 앱은 CODE_SIGN_IDENTITY=- 로 빌드한다(서명 없이 빌드하면 iCloud 권한이 없어 백업 금고가 시작하며 죽는다).
# 미리: iPad 시뮬레이터에서 마이크 · 음성 인식을 허용해 둔다(권한 창이 찍히면 안 된다).
#       워치는 아이폰 시뮬레이터와 짝지어 둔다(안 그러면 상태 막대에 '연결 끊김' 표시가 찍힌다).
set -euo pipefail
KIND="$1"; U="$2"; APP="$3"; shift 3
LOCS=("$@"); [ ${#LOCS[@]} -eq 0 ] && LOCS=(ko en-US en-GB ja de-DE es-ES es-MX fr-FR zh-Hans zh-Hant pt-BR it ru nl pl tr sv da nb fi cs el th vi id)
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

lang_of() { case "$1" in en-US) echo en;; de-DE) echo de;; es-ES|es-MX) echo es;; fr-FR) echo fr;; *) echo "$1";; esac; }
region_of() { case "$1" in
    en-US) echo en_US;; en-GB) echo en_GB;; ko) echo ko_KR;; ja) echo ja_JP;; de-DE) echo de_DE;; es-ES) echo es_ES;; es-MX) echo es_MX;;
    fr-FR) echo fr_FR;; zh-Hans) echo zh_CN;; zh-Hant) echo zh_TW;; pt-BR) echo pt_BR;; it) echo it_IT;; ru) echo ru_RU;; nl) echo nl_NL;;
    pl) echo pl_PL;; tr) echo tr_TR;; sv) echo sv_SE;; da) echo da_DK;; nb) echo nb_NO;; fi) echo fi_FI;; cs) echo cs_CZ;; el) echo el_GR;;
    th) echo th_TH;; vi) echo vi_VN;; id) echo id_ID;; *) echo en_US;; esac; }

if [ "$KIND" = ipad ]; then
    BUNDLE=com.leeo.HandsFreeMetronome
    SHOTS=(ipad-01-playing:playing ipad-02-count:count ipad-03-orbit:orbit ipad-04-setup:main)
else
    BUNDLE=com.leeo.HandsFreeMetronome.watchkitapp
    SHOTS=(01-playing:playing 02-meter:still)
fi

xcrun simctl install "$U" "$APP"
if [ "$KIND" = ipad ]; then
    xcrun simctl ui "$U" appearance light
    xcrun simctl status_bar "$U" override --time 9:41 --batteryState charged --batteryLevel 100 --wifiBars 3
fi

for loc in "${LOCS[@]}"; do
    lang=$(lang_of "$loc"); region=$(region_of "$loc")
    if [ "$KIND" = ipad ]; then
        OUT="$ROOT/docs/screenshots/marketing/$loc"
        # 상태 막대의 날짜는 SpringBoard 가 시스템 언어로 그린다 — 시스템 언어를 바꾸고 SpringBoard 만 다시 띄운다.
        xcrun simctl spawn "$U" defaults write -g AppleLanguages -array "$lang"
        xcrun simctl spawn "$U" defaults write -g AppleLocale "$region"
        xcrun simctl spawn "$U" launchctl kickstart -k system/com.apple.SpringBoard >/dev/null 2>&1 || true
        sleep 8
    else
        OUT="$ROOT/docs/screenshots/watch/$loc"
    fi
    mkdir -p "$OUT"
    for s in "${SHOTS[@]}"; do
        name="${s%%:*}"; scene="${s#*:}"
        if [ "$KIND" = ipad ]; then
            xcrun simctl terminate "$U" "$BUNDLE" >/dev/null 2>&1 || true
            sleep 2
            xcrun simctl launch --terminate-running-process "$U" "$BUNDLE" -AppleLanguages "($lang)" -AppleLocale "$region" -shot "$scene" >/dev/null
            sleep 9
            xcrun simctl io "$U" screenshot "$OUT/$name.png" >/dev/null 2>&1
        else
            # 연주 중이던 워치 앱은 끄면 시스템이 곧바로 (인자 없이) 다시 띄운다 — 한 번 더 끄고 새로 띄운다.
            # 템포 숫자가 1박 빨강으로 찍히면 다시 찍는다.
            for try in 1 2 3 4 5 6; do
                xcrun simctl terminate "$U" "$BUNDLE" >/dev/null 2>&1 || true; sleep 3
                xcrun simctl terminate "$U" "$BUNDLE" >/dev/null 2>&1 || true; sleep 1
                xcrun simctl launch --terminate-running-process "$U" "$BUNDLE" -AppleLanguages "($lang)" -AppleLocale "$region" -wristDemo "$scene" >/dev/null
                sleep 5
                xcrun simctl io "$U" screenshot "$OUT/$name.png" >/dev/null 2>&1
                python3 -c "
from PIL import Image; import sys
im = Image.open(sys.argv[1]).convert('RGB')
red = sum(1 for x in range(100, 316, 2) for y in range(120, 230, 2)
          if (lambda p: p[0] > 200 and p[1] < 110 and p[2] < 110)(im.getpixel((x, y))))
sys.exit(0 if red > 20 else 1)" "$OUT/$name.png" || break
            done
        fi
        echo "captured ${OUT#$ROOT/}/$name.png"
    done
done
xcrun simctl terminate "$U" "$BUNDLE" >/dev/null 2>&1 || true
