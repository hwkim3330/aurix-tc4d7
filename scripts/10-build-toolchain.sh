#!/usr/bin/env bash
# tricore-elf-gcc 를 소스에서 빌드한다 (EEESlab/tricore-gcc-toolchain-11.3.0).
#
# prebuilt 배포본이 없어서 이 경로를 쓴다 — docs/toolchain.md 참조.
# 단계: binutils-mcs -> binutils -> gcc-stage1 -> newlib -> gcc-stage2
#
# 산출물: toolchain/tricore-gcc-toolchain-11.3.0/INSTALL/bin/tricore-elf-*
#
# 환경변수:
#   JOBS=N   병렬 빌드 잡 수 (기본 nproc/2 — 이 머신 SSD 과열 이력 때문에 보수적)
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$REPO/toolchain/tricore-gcc-toolchain-11.3.0"
UPSTREAM="https://github.com/EEESlab/tricore-gcc-toolchain-11.3.0.git"
JOBS="${JOBS:-$(( $(nproc) / 2 ))}"
[ "$JOBS" -lt 1 ] && JOBS=1

echo "==> 병렬 잡: $JOBS (JOBS= 로 조절)"

# 호스트 빌드 의존성 확인 (설치는 하지 않는다 — sudo 를 조용히 쓰지 않기 위해)
missing=()
for c in gcc g++ make makeinfo flex bison texi2any; do
	command -v "$c" >/dev/null 2>&1 || missing+=("$c")
done
for h in /usr/include/gmp.h /usr/include/mpfr.h /usr/include/mpc.h; do
	[ -e "$h" ] || missing+=("$h")
done
if [ "${#missing[@]}" -gt 0 ]; then
	echo "!! 호스트 빌드 의존성 없음: ${missing[*]}"
	echo "   설치 명령 (직접 실행하라):"
	echo "   sudo apt install build-essential texinfo flex bison libgmp-dev libmpfr-dev libmpc-dev"
	exit 1
fi

if [ ! -d "$SRC/.git" ]; then
	echo "==> clone (submodule: gcc, binutils-gdb, newlib)"
	mkdir -p "$REPO/toolchain"
	git clone --recursive --depth 1 --shallow-submodules "$UPSTREAM" "$SRC"
else
	echo "==> 이미 clone 되어 있음: $SRC"
fi

# 상위 스크립트가 PARALLEL_JOBS=$(nproc) 를 하드코딩하므로 잡 수를 여기서 조절한다
if grep -q '^PARALLEL_JOBS=\$(nproc)$' "$SRC/build-toolchain"; then
	sed -i "s|^PARALLEL_JOBS=\$(nproc)\$|PARALLEL_JOBS=\${JOBS:-\$(nproc)}|" "$SRC/build-toolchain"
	echo "==> build-toolchain 의 PARALLEL_JOBS 를 JOBS 로 연결"
fi

echo "==> 빌드 시작 (오래 걸린다). 로그: $SRC/LOG/"
cd "$SRC"
JOBS="$JOBS" nice -n 10 ./build-toolchain --all

GCC="$SRC/INSTALL/bin/tricore-elf-gcc"
if [ -x "$GCC" ]; then
	echo
	echo "==> 완료: $("$GCC" --version | head -1)"
	echo "    $GCC"
else
	echo "!! tricore-elf-gcc 가 생성되지 않았다. $SRC/LOG/ 확인"
	exit 1
fi
