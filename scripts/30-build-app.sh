#!/usr/bin/env bash
# 앱을 이 보드용으로 빌드한다.
#
#   scripts/30-build-app.sh [앱경로] [코어]
#
#   앱경로  기본 apps/blinky
#   코어    cpu0 (기본) | cpu1..cpu5 | cpucs
#
# 굽는 건 여기서 하지 않는다. 벤더 보드 정의의 flash runner 가 winIDEA (상용/Windows) 라
# Linux 에서 `west flash` 가 안 된다 — docs/toolchain.md 참조.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${1:-apps/blinky}"
CORE="${2:-cpu0}"
WS="$REPO/ws"
TC="$REPO/toolchain/tricore-gcc-toolchain-11.3.0/INSTALL"

[ -d "$WS/zephyr" ] || { echo "!! 워크스페이스 없음 — scripts/20-init-workspace.sh 먼저"; exit 1; }

if [ -x "$TC/bin/tricore-elf-gcc" ]; then
	export ZEPHYR_TOOLCHAIN_VARIANT=cross-compile
	export CROSS_COMPILE="$TC/bin/tricore-elf-"
elif command -v tricore-elf-gcc >/dev/null 2>&1; then
	export ZEPHYR_TOOLCHAIN_VARIANT=cross-compile
	export CROSS_COMPILE="$(dirname "$(command -v tricore-elf-gcc)")/tricore-elf-"
else
	echo "!! tricore-elf-gcc 없음 — scripts/10-build-toolchain.sh 먼저"
	exit 1
fi

BOARD="kit_a3g_tc4d7_lite/tc4d7xp/$CORE"
BUILD="$REPO/build/$(basename "$APP")-$CORE"

echo "==> board      $BOARD"
echo "==> app        $APP"
echo "==> toolchain  $CROSS_COMPILE"
echo "==> build dir  $BUILD"

cd "$WS"
west build -b "$BOARD" -d "$BUILD" "$REPO/$APP" "${@:3}"

echo
ls -la "$BUILD/zephyr/zephyr.elf" 2>/dev/null && \
	"${CROSS_COMPILE}size" "$BUILD/zephyr/zephyr.elf"
