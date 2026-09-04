# Linux 툴체인 경로

## 결론 먼저

**prebuilt tricore-elf-gcc 배포본이 없다.** 확인한 것:

| 후보 | Linux 호스트 | prebuilt 바이너리 | 등록/라이선스 | 비고 |
|---|---|---|---|---|
| **Zephyr SDK 0.16.5** | ✅ | — | 불필요 | **tricore 타깃 자체가 없음** (arm 만) |
| **EEESlab/tricore-gcc-toolchain-11.3.0** | ✅ | ❌ (릴리스 없음) | 불필요 | Ubuntu 소스 빌드 스크립트 제공. **현재 유일한 무등록 경로** |
| shreyasifx/Tricore-GCC-Toolchain | ? | ❌ | ? | README 가 제목 한 줄뿐, 내용 없음 |
| Infineon GCC 11.3.1 | ❌ | Windows 인스톨러 | 불필요 | AURIX Development Studio 에 번들 |
| HighTec Free TriCore Entry Tool Chain | ? | ✅ | **필요** (폼 제출 → 라이선스 파일) | 유료 제품은 Windows/Linux 호스트 모두 지원. **무료 엔트리판의 Linux 지원은 미확인** |

Zephyr 업스트림 PR #107516 은 `tricore-elf-gcc` (Infineon GCC 11.3.1 / GCC 13.4) 로 빌드한다고
기술한다. GCC 13.4 쪽 배포처는 아직 확인하지 못했다.

## 선택: EEESlab 소스 빌드

`scripts/10-build-toolchain.sh` 가 이걸 한다.

```
binutils-gdb + gcc 11.3.0 + newlib  →  toolchain/tricore-gcc-11.3.0/bin/tricore-elf-*
```

**비용**: GNU 툴체인 3단 빌드. 시간·디스크·지속적인 CPU/IO 부하가 든다.

> ⚠️ **이 머신 주의**: 루트 NVMe 가 QLC 이고 과열로 하드 크래시를 낸 이력이 있다.
> 사용률이 97% (55 GB 여유) 다. 장시간 빌드 중 온도를 지켜보고, 필요하면 `-j` 를 낮춰라.
> 스크립트는 기본 `-j$(nproc)/2` 로 잡는다.

## Zephyr 에 커스텀 GCC 물리기

Zephyr SDK 가 아니므로 `cross-compile` 배리언트를 쓴다:

```bash
export ZEPHYR_TOOLCHAIN_VARIANT=cross-compile
export CROSS_COMPILE=/home/kim/aurix-tc4d7/toolchain/tricore-gcc-11.3.0/bin/tricore-elf-
```

`scripts/30-build-app.sh` 가 설정해준다.

## 미해결: 굽는 방법

빌드와 별개 문제다. 벤더 Zephyr 의 보드 정의:

```cmake
# boards/infineon/kit_a3g_tc4d7_lite/board.cmake
board_set_flasher_ifnset(winidea)
board_finalize_runner_args(winidea)
```

**flash runner 가 `winidea`** — iSYSTEM winIDEA, 상용 도구다. 즉 `west flash` 는 Linux 에서
바로 안 된다. **빌드는 되지만 굽는 건 안 된다.**

후보 (전부 미검증):

1. **Infineon TAS Tool Interface** — DAS 와 달리 Linux 서버 바이너리가 있다
   (`sudo TAS_V*/bin/tas_server`). 보고된 사례는 **TC3xx** 뿐, TC4x 미확인
2. **aurix-openocd** — TAS 와 조합한 TC3xx 사례가 블로그로 존재. TC4x 미확인
3. **ASC BSL (부트스트랩 로더)** — 보드가 `HWCFG[3..4]=00` 이면 P14.0/P14.1 의 generic BSL,
   `10` 이면 P15.2/3 의 ASC BSL 로 부팅한다. **ttyUSB0 가 곧 ASCLIN0** 이므로
   디버거 없이 UART 로 굽는 경로가 원리적으로 존재한다. 프로토콜 문서 확인 필요.
   → 순수 Linux + 케이블 없이 가능한 유일한 후보라 **우선 조사 대상**
4. **DAP over FT2232H** — miniWiggler 채널 A 를 직접 구동. DAS 프로토콜 리버싱 필요, 비용 큼

## 미해결: QEMU

벤더/업스트림에 `qemu_tc3x`, `qemu_tc4x` 보드가 있지만 **업스트림 QEMU 에는
`qemu-system-tricore` 타깃이 없다** (이 머신에도 없음). PR 설명이 외부 레포의 커스텀 빌드가
필요하고 업스트림 제출 예정이라고 밝힌다. → "하드웨어 없이 검증"은 공짜가 아니다.
