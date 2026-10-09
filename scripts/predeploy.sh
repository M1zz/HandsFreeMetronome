#!/bin/sh
# 배포 전 게이트 — 여기서 실패하면 DeployBar 가 아카이브를 만들지 않는다.
#
# 이 앱에는 테스트 타겟이 없다. 대신 Release 빌드가 서는지 본다.
# (CODE_SIGNING_ALLOWED=NO 를 쓰지 않는다 — 실제 배포 경로와 같게 빌드한다.)
set -e
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

echo "▶︎ Release 빌드 (HandsFreeMetronome)"
xcodebuild -project HandsFreeMetronome.xcodeproj -scheme HandsFreeMetronome -configuration Release \
  -destination 'generic/platform=iOS Simulator' -quiet build

echo "✅ 게이트 통과 — 배포 가능"
