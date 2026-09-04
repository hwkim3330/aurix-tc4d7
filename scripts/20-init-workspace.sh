#!/usr/bin/env bash
# Infineon 의 Zephyr 포크로 west 워크스페이스를 만든다.
#
# 업스트림 Zephyr 에는 TriCore 지원이 아직 머지되지 않았다 (PR #107516, open).
# 벤더 브랜치 Infineon/zephyr-aurix@aurix 가 업스트림 PR 보다 앞서 있고
# 이 보드용 devicetree (LED/버튼/CAN FD/I2C/ASCLIN) 가 이미 들어 있다.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WS="$REPO/ws"
MANIFEST_URL="https://github.com/Infineon/zephyr-aurix"
MANIFEST_REV="aurix"

command -v west >/dev/null 2>&1 || { echo "!! west 없음: pip3 install --break-system-packages west"; exit 1; }

if [ ! -d "$WS/.west" ]; then
	echo "==> west init ($MANIFEST_URL @ $MANIFEST_REV)"
	west init -m "$MANIFEST_URL" --mr "$MANIFEST_REV" "$WS"
else
	echo "==> 워크스페이스 이미 있음: $WS"
fi

cd "$WS"

# 안 쓰는 모듈 그룹을 빼서 다운로드/디스크를 줄인다 (이 머신 디스크가 빠듯하다)
west config manifest.group-filter -- -babblesim,-optional,-testing

echo "==> west update (수 GB 다운로드)"
west update --narrow -o=--depth=1

echo "==> Zephyr Python 의존성"
if ! python3 -c "import pyelftools" 2>/dev/null; then
	echo "   pip3 install --break-system-packages -r $WS/zephyr/scripts/requirements.txt"
	echo "   (직접 실행하라 — 시스템 파이썬을 조용히 건드리지 않는다)"
fi

echo
echo "==> 보드 정의 확인"
if [ -d "$WS/zephyr/boards/infineon/kit_a3g_tc4d7_lite" ]; then
	echo "OK: kit_a3g_tc4d7_lite"
	ls "$WS/zephyr/boards/infineon/kit_a3g_tc4d7_lite" | sed 's/^/    /'
else
	echo "!! 보드 정의 없음 — 브랜치가 aurix 인지 확인하라"
	exit 1
fi
