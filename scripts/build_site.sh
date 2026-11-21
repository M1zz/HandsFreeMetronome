#!/bin/sh
# 소개 페이지 다시 만들기 (docs/index.html · docs/<언어>/index.html).
# 공용 생성기(DeployBar 의 scripts/sitegen)를 돌린 뒤, 오른쪽에서 왼쪽으로 쓰는 언어(아랍어)에 dir 을 단다.
# 생성기는 글 방향을 모른다. 뒤집는 스타일은 docs/site/demo.css 의 [dir="rtl"] 에 있다.
#
# 사용법: scripts/build_site.sh        (생성기 자리가 다르면 SITEGEN=<sitegen.py 경로>)
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SITEGEN="${SITEGEN:-$HOME/Documents/workspace/개발중/DeployBar/scripts/sitegen/sitegen.py}"
python3 "$SITEGEN" "$ROOT"
for lang in ar; do
  page="$ROOT/docs/$lang/index.html"
  [ -f "$page" ] && sed -i '' "s/<html lang=\"$lang\">/<html lang=\"$lang\" dir=\"rtl\">/" "$page"
done
echo "완료: docs/<언어>/index.html"
