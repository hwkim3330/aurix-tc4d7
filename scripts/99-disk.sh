#!/usr/bin/env bash
# 이 프로젝트가 쓰는 용량을 보고한다. 기본은 읽기 전용이다.
#
#   scripts/99-disk.sh              리포트만
#   scripts/99-disk.sh --purge-ws   ws/ 를 지운다 (확인을 묻는다)
#
# ws/ 는 gitignore 되어 있고 scripts/20-init-workspace.sh 로 재생성된다.
# 지워도 조사 결과(docs/, scripts/)는 손실되지 않는다.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

hdr() { printf '\n\033[1m%s\033[0m\n' "$1"; }

hdr "이 프로젝트"
for p in ws/modules ws/zephyr ws/tools ws/bootloader toolchain build; do
	[ -e "$REPO/$p" ] && printf '  %-16s %s\n' "$p" "$(du -sh "$REPO/$p" 2>/dev/null | cut -f1)"
done
printf '  %-16s %s   <- 실제 산출물 (문서 + 스크립트)\n' "레포 본체" \
	"$(du -sh --exclude=ws --exclude=toolchain --exclude=build "$REPO" 2>/dev/null | cut -f1)"

hdr "이 머신의 다른 Zephyr (별개 트리, 건드리지 않는다)"
for p in "$HOME/zephyrproject" "$HOME/zephyr-sdk-0.16.5" "$HOME/zephyr-sdk-0.16.5_linux-x86_64.tar.xz"; do
	[ -e "$p" ] && printf '  %-46s %s\n' "$(basename "$p")" "$(du -sh "$p" 2>/dev/null | cut -f1)"
done
if [ -e "$HOME/zephyr-sdk-0.16.5_linux-x86_64.tar.xz" ] && [ -d "$HOME/zephyr-sdk-0.16.5" ]; then
	echo "  ! SDK tarball 이 이미 압축 해제되어 있다 — 회수 가능한 용량이다 (직접 판단하라)"
fi

hdr "디스크"
df -h "$REPO" | tail -1 | sed 's/^/  /'

if [ "${1:-}" = "--purge-ws" ]; then
	hdr "ws/ 삭제"
	if [ ! -d "$REPO/ws" ]; then
		echo "  ws/ 가 없다."
		exit 0
	fi
	echo "  대상: $REPO/ws  ($(du -sh "$REPO/ws" 2>/dev/null | cut -f1))"
	echo "  재생성: scripts/20-init-workspace.sh"
	printf '  지울까? [y/N] '
	read -r ans
	case "$ans" in
		y|Y)
			rm -rf "$REPO/ws"
			echo "  삭제했다."
			df -h "$REPO" | tail -1 | sed 's/^/  /'
			;;
		*)
			echo "  취소."
			;;
	esac
fi
