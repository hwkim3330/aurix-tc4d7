#!/usr/bin/env bash
# 전제조건과 보드 연결 상태 확인. 아무것도 설치하거나 변경하지 않는다.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0

hdr() { printf '\n\033[1m%s\033[0m\n' "$1"; }
ok()  { printf '  \033[32mOK\033[0m    %s\n' "$1"; }
bad() { printf '  \033[31mMISS\033[0m  %s\n' "$1"; fail=1; }
note(){ printf '  \033[33m..\033[0m    %s\n' "$1"; }

hdr "빌드 도구"
for c in west cmake ninja dtc gperf python3 git; do
	if command -v "$c" >/dev/null 2>&1; then
		ok "$c ($("$c" --version 2>&1 | head -1))"
	else
		bad "$c"
	fi
done

hdr "tricore 툴체인"
if [ -x "$REPO/toolchain/tricore-gcc-toolchain-11.3.0/INSTALL/bin/tricore-elf-gcc" ]; then
	ok "$("$REPO/toolchain/tricore-gcc-toolchain-11.3.0/INSTALL/bin/tricore-elf-gcc" --version | head -1)"
elif command -v tricore-elf-gcc >/dev/null 2>&1; then
	ok "PATH 에 있음: $(tricore-elf-gcc --version | head -1)"
else
	bad "tricore-elf-gcc — scripts/10-build-toolchain.sh 실행 필요"
fi

hdr "Zephyr 워크스페이스"
if [ -d "$REPO/ws/zephyr" ]; then
	ok "ws/zephyr 존재"
	if [ -d "$REPO/ws/zephyr/boards/infineon/kit_a3g_tc4d7_lite" ]; then
		ok "보드 정의 kit_a3g_tc4d7_lite 존재"
	else
		bad "보드 정의 없음 — 잘못된 브랜치? (aurix 브랜치가 필요)"
	fi
else
	bad "ws/ — scripts/20-init-workspace.sh 실행 필요"
fi

hdr "보드 연결"
if lsusb 2>/dev/null | grep -q '058b:0043'; then
	ok "$(lsusb | grep '058b:0043')"
else
	note "058b:0043 (AURIX Lite Kit) 안 보임 — USB-C 연결 확인"
fi
if [ -e /dev/ttyUSB0 ]; then
	drv=$(udevadm info -q property -n /dev/ttyUSB0 2>/dev/null | sed -n 's/^ID_USB_DRIVER=//p')
	mdl=$(udevadm info -q property -n /dev/ttyUSB0 2>/dev/null | sed -n 's/^ID_MODEL=//p')
	ok "/dev/ttyUSB0 driver=$drv model=$mdl"
	# ttyUSB0 는 이 보드가 아닐 수도 있다 (다른 FTDI/CP210x 보드가 먼저 잡힐 수 있음)
	case "$mdl" in
		*TC4D7*) ok "ttyUSB0 = 이 보드의 ASCLIN0" ;;
		*)       note "ttyUSB0 가 이 보드가 아니다 — /dev/serial/by-id 확인" ;;
	esac
else
	note "/dev/ttyUSB0 없음"
fi
if id -nG | tr ' ' '\n' | grep -qx dialout; then
	ok "dialout 그룹 소속"
else
	bad "dialout 그룹 아님 — sudo usermod -aG dialout \$USER 후 재로그인"
fi

hdr "디스크"
avail_k=$(df -Pk "$REPO" | awk 'NR==2{print $4}')
avail_g=$(( avail_k / 1024 / 1024 ))
if [ "$avail_g" -ge 20 ]; then
	ok "${avail_g} GB 여유"
else
	bad "${avail_g} GB 여유 — 툴체인+워크스페이스에 약 8~10 GB 필요"
fi
df -h "$REPO" | tail -1 | sed 's/^/  /'

printf '\n'
[ "$fail" -eq 0 ] && echo "전부 통과." || echo "위의 MISS 항목을 먼저 해결하라."
exit "$fail"
