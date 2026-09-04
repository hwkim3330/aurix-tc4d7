#!/usr/bin/env python3
"""AURIX ASC BSL 이 /dev/ttyUSB0 에서 응답하는지 찔러본다.

배경
----
부트스트랩 로더(BSL)는 칩에 공장에서 들어있는 작은 프로그램이다. 부트 모드가 그렇게
잡혀 있거나 BMHD 가 프로그램되지 않았으면 SSW 가 BSL 로 폴백하고, BSL 은 UART 로
호스트가 보내주는 코드를 받아 RAM 에 올려 실행한다.

이 보드에서 그 UART 는 P14.0/P14.1 = ASCLIN0 = FT2232H 채널 B = /dev/ttyUSB0 다.
즉 디버거(winIDEA/DAS) 없이 케이블만으로 굽는 경로가 원리적으로 존재한다.
→ docs/flashing.md

동작 원리
--------
ASC BSL 은 보레이트를 자동 검출한다. 호스트가 알려진 바이트를 보내면 BSL 이 그 비트
타이밍으로 보레이트를 재고, 검출이 끝나면 **ACK 바이트를 돌려보낸다**. 따라서
수동 청취로는 아무것도 안 나오는 게 정상이고, 먼저 말을 걸어야 한다.

한계
----
BSL 은 **리셋 직후에만** 살아 있다. 이미 부팅해 버렸으면 응답하지 않는다.
리셋은 /PORST 이고 보드에서 다음으로 걸 수 있다:
  - RESET 푸시버튼 (사람이 눌러야 함)
  - miniWiggler FT2232HL **ACBUS1** — 채널 A 쪽이라 ttyUSB0(채널 B)에서 못 건드린다
  - DAP 커넥터 pin 10, Arduino X302.3, 핀헤더 X1.30
→ 그래서 이 스크립트는 계속 프로브를 반복하고, 그 사이에 **사람이 리셋 버튼을 누르면**
   그 순간을 잡는다.

사용법
------
  python3 scripts/40-bsl-probe.py              # 한 바퀴 (지금 BSL 에 앉아 있는지 확인)
  python3 scripts/40-bsl-probe.py --watch 60   # 60초간 반복 — 도는 동안 RESET 을 눌러라
"""

import argparse
import sys
import time

try:
    import serial
except ImportError:
    sys.exit("pyserial 없음: pip3 install --break-system-packages pyserial")

PORT = "/dev/ttyUSB0"

# ASC BSL 보레이트 검출용 후보. 전통적으로 0x00 (start bit + 8 zero bits = 최장 low
# 구간이라 비트 타이밍을 재기 쉽다). 0x55 는 교대 패턴으로 흔한 대안.
PROBES = [b"\x00", b"\x55", b"\xaa", b"\x00\x00"]

BAUDS = [9600, 19200, 38400, 57600, 115200, 230400, 460800, 500000]


def probe_once(verbose=True):
    """모든 (보레이트, 프로브) 조합을 한 바퀴 돈다. 응답을 받으면 그 목록을 돌려준다."""
    hits = []
    for baud in BAUDS:
        try:
            s = serial.Serial(PORT, baud, timeout=0.25,
                              bytesize=8, parity="N", stopbits=1)
        except Exception as exc:  # noqa: BLE001
            if verbose:
                print(f"  {baud:>7} 열기 실패: {exc}")
            continue
        try:
            for probe in PROBES:
                s.reset_input_buffer()
                s.reset_output_buffer()
                s.write(probe)
                s.flush()
                resp = s.read(64)
                if resp:
                    hits.append((baud, probe, resp))
                    print(f"  \033[32m응답\033[0m {baud} baud  보냄={probe.hex()} "
                          f"받음={resp.hex()} ({len(resp)}바이트)")
        finally:
            s.close()
    return hits


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--watch", type=int, default=0, metavar="SEC",
                    help="SEC 초간 반복한다. 도는 동안 보드 RESET 버튼을 눌러라.")
    args = ap.parse_args()

    print(f"포트 {PORT}")
    print(f"보레이트 {BAUDS}")
    print(f"프로브 {[p.hex() for p in PROBES]}")

    if not args.watch:
        print("\n한 바퀴 (지금 BSL 에 앉아 있는지 확인):")
        hits = probe_once()
        if not hits:
            print("  응답 없음.")
            print("\n  → 이미 부팅해버렸거나, 부트 모드가 BSL 이 아니거나, 프로토콜이 다르다.")
            print("     --watch 로 돌리고 RESET 버튼을 눌러 리셋 직후를 잡아라.")
        return 0 if hits else 1

    deadline = time.time() + args.watch
    print(f"\n{args.watch}초간 반복한다. \033[1m지금 보드의 RESET 버튼을 눌러라.\033[0m")
    rounds = 0
    while time.time() < deadline:
        rounds += 1
        hits = probe_once(verbose=False)
        if hits:
            print(f"\n\033[32m잡았다\033[0m ({rounds}번째 바퀴)")
            return 0
        left = int(deadline - time.time())
        print(f"  {rounds}바퀴 무응답, {left}초 남음", end="\r", flush=True)
    print(f"\n{rounds}바퀴 전부 무응답.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
